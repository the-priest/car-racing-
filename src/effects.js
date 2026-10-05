// Tire smoke, skid marks, and the chase camera rig.
import * as THREE from 'three';
import { smokeTexture } from './textures.js';
import { clamp, damp, lerp, wrapAngle } from './utils.js';

export class Smoke {
  constructor(scene, max = 260) {
    this.max = max;
    this.pos = new Float32Array(max * 3);
    this.vel = new Float32Array(max * 3);
    this.life = new Float32Array(max);
    this.maxLife = new Float32Array(max);
    this.size = new Float32Array(max);
    this.alpha = new Float32Array(max);
    this.tint = new Float32Array(max * 3);
    this.next = 0;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('size', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('alpha', new THREE.BufferAttribute(this.alpha, 1).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('tint', new THREE.BufferAttribute(this.tint, 3).setUsage(THREE.DynamicDrawUsage));
    this.mat = new THREE.ShaderMaterial({
      uniforms: { map: { value: smokeTexture() }, scale: { value: 600 }, light: { value: 1 } },
      transparent: true,
      depthWrite: false,
      vertexShader: `attribute float size; attribute float alpha; attribute vec3 tint; varying float vA; varying vec3 vT; uniform float scale;
        void main(){ vA = alpha; vT = tint; vec4 mv = modelViewMatrix * vec4(position,1.0); gl_PointSize = size * scale / -mv.z; gl_Position = projectionMatrix * mv; }`,
      fragmentShader: `uniform sampler2D map; uniform float light; varying float vA; varying vec3 vT;
        void main(){ vec4 t = texture2D(map, gl_PointCoord); gl_FragColor = vec4(vT * light, t.a * vA); }`,
    });
    this.points = new THREE.Points(g, this.mat);
    this.points.frustumCulled = false;
    scene.add(this.points);
    this.geo = g;
  }

  emit(x, y, z, vx, vy, vz, size, life, r = 0.85, gc = 0.85, b = 0.85) {
    const i = this.next;
    this.next = (this.next + 1) % this.max;
    this.pos[i * 3] = x; this.pos[i * 3 + 1] = y; this.pos[i * 3 + 2] = z;
    this.vel[i * 3] = vx; this.vel[i * 3 + 1] = vy; this.vel[i * 3 + 2] = vz;
    this.life[i] = life; this.maxLife[i] = life;
    this.size[i] = size;
    this.tint[i * 3] = r; this.tint[i * 3 + 1] = gc; this.tint[i * 3 + 2] = b;
  }

  update(dt, light, viewportH) {
    this.mat.uniforms.light.value = light;
    this.mat.uniforms.scale.value = viewportH * 0.9;
    for (let i = 0; i < this.max; i++) {
      if (this.life[i] <= 0) { this.alpha[i] = 0; continue; }
      this.life[i] -= dt;
      const t = 1 - this.life[i] / this.maxLife[i];
      this.pos[i * 3] += this.vel[i * 3] * dt;
      this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt;
      this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
      const f = Math.exp(-2.2 * dt);
      this.vel[i * 3] *= f; this.vel[i * 3 + 2] *= f;
      this.size[i] += dt * 4.5;
      this.alpha[i] = Math.sin(Math.min(t * 4, 1) * Math.PI * 0.5) * (1 - t) * 0.8;
    }
    this.geo.attributes.position.needsUpdate = true;
    this.geo.attributes.size.needsUpdate = true;
    this.geo.attributes.alpha.needsUpdate = true;
    this.geo.attributes.tint.needsUpdate = true;
  }
}

export class Skids {
  constructor(scene, max = 900) {
    this.max = max;
    const g = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);
    this.mat = new THREE.MeshBasicMaterial({
      color: 0x000000, transparent: true, opacity: 0.55, depthWrite: false,
      polygonOffset: true, polygonOffsetFactor: -6, polygonOffsetUnits: -12,
    });
    this.mesh = new THREE.InstancedMesh(g, this.mat, max);
    this.mesh.frustumCulled = false;
    this.mesh.count = 0;
    this.mesh.renderOrder = 1;
    scene.add(this.mesh);
    this.next = 0;
    this.m4 = new THREE.Matrix4();
    this.q = new THREE.Quaternion();
    this.up = new THREE.Vector3(0, 1, 0);
    this.last = new Map();
  }

  // key identifies a wheel so consecutive marks connect.
  mark(key, x, y, z, on) {
    const prev = this.last.get(key);
    if (!on) { this.last.delete(key); return; }
    if (prev) {
      const dx = x - prev.x, dz = z - prev.z;
      const len = Math.hypot(dx, dz);
      if (len < 0.6) return;
      if (len < 6) {
        this.q.setFromAxisAngle(this.up, Math.atan2(dx, dz));
        this.m4.compose(new THREE.Vector3((x + prev.x) / 2, (y + prev.y) / 2 + 0.05, (z + prev.z) / 2), this.q, new THREE.Vector3(0.3, 1, len + 0.05));
        this.mesh.setMatrixAt(this.next, this.m4);
        this.next = (this.next + 1) % this.max;
        this.mesh.count = Math.max(this.mesh.count, this.next === 0 ? this.max : this.next);
        this.mesh.instanceMatrix.needsUpdate = true;
      }
    }
    this.last.set(key, { x, y, z });
  }

  clear() {
    this.mesh.count = 0;
    this.next = 0;
    this.last.clear();
  }
}

export class CameraRig {
  constructor(camera, world) {
    this.cam = camera;
    this.world = world;
    this.mode = 0; // 0 chase, 1 far chase, 2 hood, 3 bumper
    this.pos = new THREE.Vector3();
    this.look = new THREE.Vector3();
    this.yaw = 0;
    this.snap = true;
    this.shake = 0;
    this.fov = 65;
    this.orbit = 0;
  }

  cycle() { this.mode = (this.mode + 1) % 4; this.snap = true; }

  update(dt, v, lookBack, lookX, nitroOn) {
    const cam = this.cam;
    // Camera heading follows the velocity direction during slides for a dramatic drift view.
    const velYaw = v.speed > 4 ? Math.atan2(v.vx, v.vz) : v.yaw;
    const reversing = v.u < -1;
    const blend = clamp(v.speed / 25, 0, 1) * (reversing ? 0 : 0.55);
    const target = v.yaw + wrapAngle(velYaw - v.yaw) * blend;
    if (this.snap) this.yaw = target;
    this.yaw += wrapAngle(target - this.yaw) * (1 - Math.exp(-(this.mode >= 2 ? 30 : 6) * dt));
    this.orbit = damp(this.orbit, lookX * 2.6, 6, dt);
    let yaw = this.yaw + this.orbit + (lookBack ? Math.PI : 0);
    const fx = Math.sin(yaw), fz = Math.cos(yaw);
    const sp = clamp(v.speed / 80, 0, 1);
    let desired, lookAt;
    if (this.mode <= 1) {
      const far = this.mode === 1;
      const dist = (far ? 9.5 : 6.6) + sp * (far ? 2.5 : 1.6);
      const height = (far ? 3.4 : 2.2) - sp * 0.3;
      desired = new THREE.Vector3(v.x - fx * dist, v.y + height, v.z - fz * dist);
      lookAt = new THREE.Vector3(v.x + fx * 4, v.y + 1.1, v.z + fz * 4);
      // Keep the camera above terrain and out of buildings.
      const gh = this.world.ground(desired.x, desired.z) + 0.8;
      if (desired.y < gh) desired.y = gh;
      for (let k = 1; k <= 4; k++) {
        const t = k / 4;
        const px = lerp(v.x, desired.x, t), pz = lerp(v.z, desired.z, t);
        if (this.world.collideCircle(px, pz, 0.4)) {
          const tt = Math.max(0.15, t - 0.25);
          desired.x = lerp(v.x, desired.x, tt);
          desired.z = lerp(v.z, desired.z, tt);
          desired.y += 1.5;
          break;
        }
      }
    } else {
      // Hood / bumper cams are rigidly attached.
      const up = this.mode === 2 ? 1.35 : 0.65;
      const fwd = this.mode === 2 ? 0.2 : 2.3;
      const cf = Math.sin(v.yaw + (lookBack ? Math.PI : 0)), cz = Math.cos(v.yaw + (lookBack ? Math.PI : 0));
      desired = new THREE.Vector3(v.x + cf * fwd, v.y + up + v.pitch * 0.5, v.z + cz * fwd);
      lookAt = new THREE.Vector3(v.x + cf * 30, v.y + up - 0.2, v.z + cz * 30);
    }
    if (this.snap || this.mode >= 2) {
      this.pos.copy(desired);
      this.look.copy(lookAt);
      this.snap = false;
    } else {
      const k = 1 - Math.exp(-12 * dt);
      this.pos.lerp(desired, k);
      this.look.lerp(lookAt, 1 - Math.exp(-20 * dt));
    }
    cam.position.copy(this.pos);
    // Speed + impact shake
    this.shake = Math.max(0, this.shake - dt * 3);
    const s = this.shake * 0.35 + Math.pow(sp, 3) * 0.04 + (nitroOn ? 0.03 : 0);
    if (s > 0.001) cam.position.add(new THREE.Vector3((Math.random() - 0.5) * s, (Math.random() - 0.5) * s, (Math.random() - 0.5) * s));
    cam.lookAt(this.look);
    if (this.mode >= 2) cam.rotateZ(-v.roll * 0.6);
    // FOV widens with speed for a sense of velocity.
    const tf = 62 + sp * 18 + (nitroOn ? 8 : 0) + (this.mode >= 2 ? 6 : 0);
    this.fov = damp(this.fov, tf, 3, dt);
    if (Math.abs(cam.fov - this.fov) > 0.05) { cam.fov = this.fov; cam.updateProjectionMatrix(); }
  }
}
