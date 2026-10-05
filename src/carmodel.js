// Procedural low-poly car models built from side-profile extrusions.
import * as THREE from 'three';
import { colorize, mergeGeometries } from './utils.js';
import { STYLES } from './config.js';
import * as TX from './textures.js';

let shared = null;
function getShared() {
  if (shared) return shared;
  shared = {
    envMap: makeEnvMap(),
    glass: null,
    trim: new THREE.MeshLambertMaterial({ vertexColors: true }),
    wheel: new THREE.MeshLambertMaterial({ vertexColors: true }),
    head: new THREE.MeshBasicMaterial({ color: 0xfff6e0, toneMapped: false }),
    shadowTex: TX.glowTexture('rgba(0,0,0,0.75)', 'rgba(0,0,0,0)'),
    beamTex: TX.beamTexture(),
    flameMat: new THREE.MeshBasicMaterial({ color: 0x66aaff, transparent: true, opacity: 0.85, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false }),
    geoCache: new Map(),
  };
  shared.glass = new THREE.MeshPhongMaterial({
    color: 0x0b0f14, specular: 0xffffff, shininess: 120, envMap: shared.envMap.texture,
    reflectivity: 0.38, combine: THREE.MixOperation,
  });
  return shared;
}

// Small cube env map painted from sky colours; repainted on day/night change.
function makeEnvMap() {
  const size = 32;
  const canvases = [];
  for (let i = 0; i < 6; i++) {
    const c = document.createElement('canvas');
    c.width = c.height = size;
    canvases.push(c);
  }
  const texture = new THREE.CubeTexture(canvases);
  texture.colorSpace = THREE.SRGBColorSpace;
  const paint = (top, horizon, ground) => {
    canvases.forEach((c, i) => {
      const ctx = c.getContext('2d');
      if (i === 2) { ctx.fillStyle = top; ctx.fillRect(0, 0, size, size); return; }
      if (i === 3) { ctx.fillStyle = ground; ctx.fillRect(0, 0, size, size); return; }
      const g = ctx.createLinearGradient(0, 0, 0, size);
      g.addColorStop(0, top);
      g.addColorStop(0.5, horizon);
      g.addColorStop(0.56, ground);
      g.addColorStop(1, ground);
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, size, size);
      // Fake skyline / light streaks for reflections
      ctx.fillStyle = 'rgba(255,255,255,0.25)';
      for (let k = 0; k < 4; k++) ctx.fillRect((k * 9 + i * 5) % size, size * 0.3, 3, size * 0.2);
    });
    texture.needsUpdate = true;
  };
  paint('#5d8fd6', '#cfe3f5', '#3a3f45');
  return { texture, paint };
}

export function paintEnvironment(top, horizon, ground) {
  getShared().envMap.paint(top, horizon, ground);
}

function extrudeProfile(points, width, bevel, taper) {
  const shape = new THREE.Shape(points.map(([z, y]) => new THREE.Vector2(z, y)));
  const depth = width - bevel * 2;
  const geo = new THREE.ExtrudeGeometry(shape, {
    depth, bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 2, curveSegments: 1,
  });
  geo.rotateY(-Math.PI / 2);
  geo.translate(depth / 2, 0, 0);
  // Taper the upper part inward for a more rounded body.
  const pos = geo.attributes.position;
  let ymin = Infinity, ymax = -Infinity;
  for (let i = 0; i < pos.count; i++) { ymin = Math.min(ymin, pos.getY(i)); ymax = Math.max(ymax, pos.getY(i)); }
  for (let i = 0; i < pos.count; i++) {
    const t = (pos.getY(i) - ymin) / (ymax - ymin);
    pos.setX(i, pos.getX(i) * (1 - taper * t * t));
  }
  geo.computeVertexNormals();
  return geo;
}

function wheelGeometry(r) {
  const key = 'wheel' + r;
  const S = getShared();
  if (S.geoCache.has(key)) return S.geoCache.get(key);
  const tire = colorize(new THREE.CylinderGeometry(r, r, 0.3, 18).rotateZ(Math.PI / 2), 0x141414);
  const rim = colorize(new THREE.CylinderGeometry(r * 0.66, r * 0.66, 0.31, 14).rotateZ(Math.PI / 2), 0xb9bec6);
  const hub = colorize(new THREE.CylinderGeometry(r * 0.18, r * 0.18, 0.33, 8).rotateZ(Math.PI / 2), 0x30343a);
  const spokes = [];
  for (let i = 0; i < 5; i++) {
    const s = new THREE.BoxGeometry(0.322, r * 1.1, 0.07);
    s.rotateX((i / 5) * Math.PI);
    spokes.push(colorize(s, 0x5a5f66));
  }
  const g = mergeGeometries([tire, rim, hub, ...spokes]);
  S.geoCache.set(key, g);
  return g;
}

// Full detail car used for the player and rivals.
export function buildCar(styleName, color, opts = {}) {
  const S = getShared();
  const st = STYLES[styleName];
  const root = new THREE.Group();
  const body = new THREE.Group(); // chassis that pitches/rolls on suspension
  root.add(body);

  const paint = new THREE.MeshPhongMaterial({
    color, specular: 0xb0b0b0, shininess: 110, envMap: S.envMap.texture, reflectivity: 0.16, combine: THREE.MixOperation,
  });
  const bodyMesh = new THREE.Mesh(extrudeProfile(st.body, st.W, 0.07, 0.08), paint);
  bodyMesh.castShadow = true;
  body.add(bodyMesh);
  const cabin = new THREE.Mesh(extrudeProfile(st.cabin, st.W * 0.84, 0.05, 0.22), S.glass);
  cabin.castShadow = true;
  body.add(cabin);

  const front = st.body.reduce((m, p) => Math.max(m, p[0]), -9);
  const rear = st.body.reduce((m, p) => Math.min(m, p[0]), 9);
  // Trim: splitter, skirts, diffuser, mirrors, wing, exhausts
  const dark = 0x15171a, trimParts = [];
  const L = st.L, W = st.W;
  trimParts.push(colorize(new THREE.BoxGeometry(W * 0.98, 0.08, 0.4).translate(0, 0.3, front - 0.05), dark));
  trimParts.push(colorize(new THREE.BoxGeometry(0.08, 0.12, L * 0.55).translate(W / 2 - 0.02, 0.36, 0), dark));
  trimParts.push(colorize(new THREE.BoxGeometry(0.08, 0.12, L * 0.55).translate(-W / 2 + 0.02, 0.36, 0), dark));
  trimParts.push(colorize(new THREE.BoxGeometry(W * 0.8, 0.16, 0.25).translate(0, 0.36, rear - 0.02), 0x0c0d0f));
  // Grille
  trimParts.push(colorize(new THREE.BoxGeometry(W * 0.5, 0.14, 0.05).translate(0, 0.46, front + 0.06), 0x0a0a0a));
  for (const sx of [-1, 1]) {
    trimParts.push(colorize(new THREE.BoxGeometry(0.22, 0.1, 0.14).translate(sx * (W / 2 + 0.06), 0.95, 0.55), dark));
    trimParts.push(colorize(new THREE.CylinderGeometry(0.06, 0.06, 0.2, 8).rotateX(Math.PI / 2).translate(sx * 0.35, 0.38, rear - 0.1), 0x8d9299));
  }
  if (st.wing) {
    const wz = st.wingZ, wh = st.wingH;
    trimParts.push(colorize(new THREE.BoxGeometry(W * 0.9, 0.05, 0.42).translate(0, wh, wz), dark));
    for (const sx of [-0.55, 0.55]) trimParts.push(colorize(new THREE.BoxGeometry(0.05, wh - 0.85, 0.12).translate(sx, (wh + 0.85) / 2, wz + 0.05), dark));
    for (const sx of [-1, 1]) trimParts.push(colorize(new THREE.BoxGeometry(0.04, 0.18, 0.46).translate(sx * W * 0.45, wh + 0.06, wz), dark));
  }
  if (st.scoop) trimParts.push(colorize(new THREE.BoxGeometry(0.6, 0.12, 0.7).translate(0, 1.02, 1.3), 0x0d0d0d));
  if (st.fin) trimParts.push(colorize(new THREE.BoxGeometry(0.04, 0.3, 1.1).translate(0, 1.0, -1.4), dark));
  const trim = new THREE.Mesh(mergeGeometries(trimParts), S.trim);
  body.add(trim);

  // Lights
  const headGeo = mergeGeometries([
    new THREE.BoxGeometry(0.46, 0.1, 0.06).translate(W / 2 - 0.38, 0.6, front + 0.06),
    new THREE.BoxGeometry(0.46, 0.1, 0.06).translate(-W / 2 + 0.38, 0.6, front + 0.06),
  ].map((g) => g.toNonIndexed()));
  body.add(new THREE.Mesh(headGeo, S.head));
  const tailMat = new THREE.MeshBasicMaterial({ color: 0x550000, toneMapped: false });
  const tailGeo = mergeGeometries([
    new THREE.BoxGeometry(W * 0.8, 0.06, 0.05).translate(0, 0.72, rear - 0.08),
    new THREE.BoxGeometry(0.36, 0.13, 0.05).translate(W / 2 - 0.28, 0.66, rear - 0.08),
    new THREE.BoxGeometry(0.36, 0.13, 0.05).translate(-W / 2 + 0.28, 0.66, rear - 0.08),
  ].map((g) => g.toNonIndexed()));
  body.add(new THREE.Mesh(tailGeo, tailMat));

  // Wheels
  const wheels = [];
  const wg = wheelGeometry(st.wheelR);
  for (const [sx, sz] of [[1, 1], [-1, 1], [1, -1], [-1, -1]]) {
    const pivot = new THREE.Group();
    pivot.position.set(sx * (W / 2 - 0.06), st.wheelR, sz * st.wheelZ);
    const wm = new THREE.Mesh(wg, S.wheel);
    wm.castShadow = true;
    pivot.add(wm);
    root.add(pivot);
    wheels.push({ pivot, mesh: wm, front: sz > 0, baseY: st.wheelR });
  }

  // Contact shadow blob
  const blob = new THREE.Mesh(
    new THREE.PlaneGeometry(W * 1.5, L * 1.25).rotateX(-Math.PI / 2),
    new THREE.MeshBasicMaterial({ map: S.shadowTex, transparent: true, depthWrite: false, opacity: 0.85 })
  );
  blob.position.y = 0.04;
  blob.renderOrder = 1;
  root.add(blob);

  // Headlight beams on the road (night only)
  const beam = new THREE.Mesh(
    new THREE.PlaneGeometry(9, 30).rotateX(-Math.PI / 2).translate(0, 0, 15 + front),
    new THREE.MeshBasicMaterial({ map: S.beamTex, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, opacity: 0.0, toneMapped: false })
  );
  beam.position.y = 0.12;
  beam.renderOrder = 2;
  beam.visible = false;
  root.add(beam);

  // Nitro flames
  const flames = new THREE.Group();
  for (const sx of [-0.35, 0.35]) {
    const f = new THREE.Mesh(new THREE.ConeGeometry(0.11, 0.9, 8).rotateX(-Math.PI / 2), S.flameMat);
    f.position.set(sx, 0.38, rear - 0.55);
    flames.add(f);
  }
  flames.visible = false;
  body.add(flames);

  // Police light bar
  let lightbar = null;
  if (opts.police) {
    const red = new THREE.MeshBasicMaterial({ color: 0xff0020, toneMapped: false });
    const blue = new THREE.MeshBasicMaterial({ color: 0x0040ff, toneMapped: false });
    const roofY = st.cabin.reduce((m, p) => Math.max(m, p[1]), 0);
    const roofZ = st.cabin.reduce((s, p) => s + p[0], 0) / st.cabin.length;
    const r = new THREE.Mesh(new THREE.BoxGeometry(0.55, 0.13, 0.25), red);
    const b = new THREE.Mesh(new THREE.BoxGeometry(0.55, 0.13, 0.25), blue);
    r.position.set(0.3, roofY + 0.07, roofZ);
    b.position.set(-0.3, roofY + 0.07, roofZ);
    body.add(r, b);
    lightbar = { red, blue };
  }

  root.userData = { body, wheels, paint, tailMat, beam, flames, lightbar, style: st, blob };
  return root;
}

// Animate a car model from its vehicle state.
export function poseCar(model, v, night, t) {
  const d = model.userData;
  model.position.set(v.x, v.y, v.z);
  // Align to terrain slope + suspension motion
  const fx = Math.sin(v.yaw), fz = Math.cos(v.yaw);
  const slopePitch = Math.atan(v.groundNx * fx + v.groundNz * fz);
  const slopeRoll = Math.atan(v.groundNx * Math.cos(v.yaw) - v.groundNz * Math.sin(v.yaw));
  model.rotation.set(0, v.yaw, 0, 'YXZ');
  model.rotation.x = v.onGround ? -slopePitch : model.rotation.x;
  model.rotation.z = v.onGround ? slopeRoll : model.rotation.z;
  d.body.rotation.x = v.pitch;
  d.body.rotation.z = v.roll;
  d.body.position.y = 0.02 + Math.abs(v.roll) * 0.2;
  for (const w of d.wheels) {
    w.mesh.rotation.x = v.wheelRot;
    if (w.front) w.pivot.rotation.y = v.steerAngle;
  }
  const braking = v.brake > 0.1 && !v.reverse;
  d.tailMat.color.setRGB(braking ? 3.5 : 0.6 + night * 1.0, braking ? 0.15 : 0.02, braking ? 0.15 : 0.02);
  d.beam.visible = night > 0.15;
  d.beam.material.opacity = night * 0.75;
  d.flames.visible = v.nitroOn;
  if (v.nitroOn) d.flames.scale.setScalar(0.8 + Math.random() * 0.5);
  d.blob.visible = v.onGround || v.airTime < 0.4;
  if (d.lightbar) {
    const on = Math.floor(t * 6) % 2 === 0;
    d.lightbar.red.color.setScalar(0).r = on ? 4 : 0.2;
    d.lightbar.blue.color.setScalar(0).b = on ? 0.2 : 4;
  }
}

// Cheap single-draw traffic car (plus one draw for lights).
const trafficCache = new Map();
export function buildTrafficCar(styleName, color) {
  const S = getShared();
  const key = styleName + color;
  let geo = trafficCache.get(key);
  if (!geo) {
    const st = STYLES[styleName];
    const parts = [
      colorize(extrudeProfile(st.body, st.W, 0.05, 0.06), color),
      colorize(extrudeProfile(st.cabin, st.W * 0.86, 0.04, 0.18), 0x1a2028),
    ];
    for (const [sx, sz] of [[1, 1], [-1, 1], [1, -1], [-1, -1]]) {
      parts.push(colorize(new THREE.CylinderGeometry(st.wheelR, st.wheelR, 0.26, 10).rotateZ(Math.PI / 2)
        .translate(sx * (st.W / 2 - 0.14), st.wheelR, sz * st.wheelZ), 0x151515));
    }
    const lights = mergeGeometries([
      colorize(new THREE.BoxGeometry(st.W * 0.75, 0.1, 0.05).translate(0, 0.72, -st.L / 2 - 0.02), 0xff1010),
      colorize(new THREE.BoxGeometry(0.4, 0.1, 0.05).translate(st.W / 2 - 0.35, 0.62, st.L / 2 + 0.03), 0xfff0d0),
      colorize(new THREE.BoxGeometry(0.4, 0.1, 0.05).translate(-st.W / 2 + 0.35, 0.62, st.L / 2 + 0.03), 0xfff0d0),
    ]);
    geo = { body: mergeGeometries(parts), lights };
    trafficCache.set(key, geo);
  }
  if (!S.trafficMat) {
    S.trafficMat = new THREE.MeshPhongMaterial({ vertexColors: true, shininess: 60, specular: 0x444444 });
    S.trafficLightMat = new THREE.MeshBasicMaterial({ vertexColors: true, toneMapped: false });
  }
  const g = new THREE.Group();
  const m = new THREE.Mesh(geo.body, S.trafficMat);
  m.castShadow = false;
  g.add(m);
  g.add(new THREE.Mesh(geo.lights, S.trafficLightMat));
  const blob = new THREE.Mesh(
    new THREE.PlaneGeometry(2.8, 5.6).rotateX(-Math.PI / 2),
    new THREE.MeshBasicMaterial({ map: S.shadowTex, transparent: true, depthWrite: false, opacity: 0.8 })
  );
  blob.position.y = 0.05;
  g.add(blob);
  return g;
}

export function setTrafficLightLevel(n) {
  const S = getShared();
  if (S.trafficLightMat) S.trafficLightMat.color.setScalar(0.6 + n * 2.2);
}
