// Sky dome, sun/moon lighting, fog and the day/night cycle.
import * as THREE from 'three';
import { clamp, lerp, smoothstep } from './utils.js';
import { paintEnvironment } from './carmodel.js';

const KEYS = [
  // hour, top, horizon, sunColor, sunIntensity, hemiSky, hemiGround, hemiIntensity
  [0, '#02040b', '#0b1530', '#9fb4ff', 0.55, '#3a4c86', '#16141a', 0.95],
  [5, '#0a1430', '#3a2f4a', '#ffb070', 0.5, '#3f4c78', '#1a1612', 0.85],
  [6.5, '#3d6cb0', '#f2a46a', '#ffc58a', 1.4, '#9ab6e0', '#5a4a3a', 0.85],
  [9, '#3f7fd6', '#bcd8f0', '#fff3e0', 2.6, '#bcd6ff', '#5e5a4c', 1.0],
  [15, '#3a7ad4', '#c4dcf2', '#fff1dc', 2.6, '#bcd6ff', '#5e5a4c', 1.0],
  [18, '#2f5aa0', '#f09a5a', '#ffa860', 1.6, '#a0a8d0', '#5a4a3a', 0.85],
  [19.5, '#141c3f', '#6a3f5a', '#ff7a50', 0.6, '#454a78', '#1a1612', 0.85],
  [21, '#02040b', '#0b1530', '#9fb4ff', 0.55, '#3a4c86', '#16141a', 0.95],
  [24, '#02040b', '#0b1530', '#9fb4ff', 0.55, '#3a4c86', '#16141a', 0.95],
];

export class Sky {
  constructor(scene, renderer, quality) {
    this.scene = scene;
    this.uniforms = {
      top: { value: new THREE.Color() },
      horizon: { value: new THREE.Color() },
      sunDir: { value: new THREE.Vector3(0, 1, 0) },
      sunCol: { value: new THREE.Color() },
      night: { value: 0 },
    };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.uniforms,
      side: THREE.BackSide,
      depthWrite: false,
      fog: false,
      vertexShader: `varying vec3 vDir; void main(){ vDir = normalize(position); vec4 p = projectionMatrix * modelViewMatrix * vec4(position,1.0); gl_Position = p.xyww; }`,
      fragmentShader: `
        uniform vec3 top; uniform vec3 horizon; uniform vec3 sunDir; uniform vec3 sunCol; uniform float night;
        varying vec3 vDir;
        float h3(vec3 p){ return fract(sin(dot(p, vec3(12.9898,78.233,37.719))) * 43758.5453); }
        void main(){
          vec3 d = normalize(vDir);
          float t = clamp(d.y, 0.0, 1.0);
          vec3 col = mix(horizon, top, pow(t, 0.55));
          if (d.y < 0.0) col = horizon * (1.0 + d.y * 0.6);
          float sd = max(dot(d, sunDir), 0.0);
          col += sunCol * (pow(sd, 900.0) * 6.0 + pow(sd, 12.0) * 0.35) * (1.0 - night * 0.5);
          if (night > 0.0 && d.y > 0.0) {
            vec3 cell = floor(d * 260.0);
            float s = step(0.9965, h3(cell));
            col += vec3(s) * night * smoothstep(0.0, 0.25, d.y) * (0.6 + 0.4 * h3(cell + 1.0));
          }
          gl_FragColor = vec4(col, 1.0);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    });
    this.dome = new THREE.Mesh(new THREE.SphereGeometry(100, 24, 12), mat);
    this.dome.frustumCulled = false;
    this.dome.renderOrder = -10;
    scene.add(this.dome);

    this.sun = new THREE.DirectionalLight(0xffffff, 2);
    this.sun.castShadow = quality.shadows;
    if (quality.shadows) {
      this.sun.shadow.mapSize.set(quality.shadowSize, quality.shadowSize);
      const c = this.sun.shadow.camera;
      c.left = -45; c.right = 45; c.top = 45; c.bottom = -45; c.near = 1; c.far = 400;
      this.sun.shadow.bias = -0.0006;
      this.sun.shadow.normalBias = 0.04;
    }
    scene.add(this.sun, this.sun.target);
    this.hemi = new THREE.HemisphereLight(0xbcd6ff, 0x5e5a4c, 1);
    scene.add(this.hemi);
    scene.fog = new THREE.Fog(0xbcd8f0, 200, quality.draw);
    this.fogFar = quality.draw;
    this.hour = 14;
    this.night = 0;
    this.lastPaint = -1;
  }

  sample(hour) {
    let i = 0;
    while (i < KEYS.length - 2 && KEYS[i + 1][0] <= hour) i++;
    const a = KEYS[i], b = KEYS[i + 1];
    const t = clamp((hour - a[0]) / (b[0] - a[0]), 0, 1);
    const c = (k) => new THREE.Color(a[k]).lerp(new THREE.Color(b[k]), t);
    return { top: c(1), horizon: c(2), sun: c(3), sunI: lerp(a[4], b[4], t), hs: c(5), hg: c(6), hi: lerp(a[7], b[7], t) };
  }

  update(hour, focus, camera) {
    this.hour = hour;
    const s = this.sample(hour);
    // Sun travels east->west; at night the "sun" light becomes moonlight.
    const ang = ((hour - 6) / 12) * Math.PI;
    const elev = Math.sin(ang);
    this.night = 1 - smoothstep(-0.12, 0.18, elev);
    const dir = new THREE.Vector3(Math.cos(ang) * 0.8, Math.max(Math.abs(elev), 0.25), 0.45).normalize();
    if (elev < 0) dir.set(-0.4, 0.7, -0.5).normalize(); // moon
    this.uniforms.top.value.copy(s.top);
    this.uniforms.horizon.value.copy(s.horizon);
    this.uniforms.sunCol.value.copy(s.sun);
    this.uniforms.sunDir.value.copy(elev >= 0 ? dir : new THREE.Vector3(0.3, 0.6, -0.7).normalize());
    this.uniforms.night.value = this.night;
    this.sun.color.copy(s.sun);
    this.sun.intensity = s.sunI;
    this.hemi.color.copy(s.hs);
    this.hemi.groundColor.copy(s.hg);
    this.hemi.intensity = s.hi;
    this.scene.fog.color.copy(s.horizon);
    this.scene.fog.near = lerp(this.fogFar * 0.25, this.fogFar * 0.12, this.night);
    this.scene.fog.far = lerp(this.fogFar, this.fogFar * 0.8, this.night);
    // Shadow camera follows the focus point.
    this.sun.position.set(focus.x + dir.x * 150, focus.y + dir.y * 150, focus.z + dir.z * 150);
    this.sun.target.position.copy(focus);
    this.dome.position.copy(camera.position);
    const scale = camera.far * 0.9 / 100;
    this.dome.scale.setScalar(scale);
    // Repaint reflections occasionally.
    const key = Math.round(hour * 2);
    if (key !== this.lastPaint) {
      this.lastPaint = key;
      paintEnvironment('#' + s.top.getHexString(), '#' + s.horizon.getHexString(), this.night > 0.5 ? '#08090c' : '#3a3f45');
    }
  }
}
