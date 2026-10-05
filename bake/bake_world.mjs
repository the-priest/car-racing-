// Offline world baker. Produces the terrain heightmap, road network, city
// layout, vegetation and navigation graph consumed by the Godot game.
// Run: node bake/bake_world.mjs   (deterministic; output in assets/world/)
import fs from 'node:fs';
import path from 'node:path';

const OUT = path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'assets', 'world');
export const HALF = 3072, CELL = 8, N = HALF * 2 / CELL + 1; // 769
const STREETS = []; for (let k = 0; k <= 10; k++) STREETS.push(-600 + k * 120);
const STREET_HW = 10, CITY_EDGE = 610, CITY_FLAT = 680;
const WATER_Y = 0;

// ---------------------------------------------------------------- math
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;
const smoothstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hash2(ix, iz) {
  let h = Math.imul(ix, 374761393) + Math.imul(iz, 668265263);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}
function vnoise(x, z) {
  const ix = Math.floor(x), iz = Math.floor(z), fx = x - ix, fz = z - iz;
  const ux = fx * fx * (3 - 2 * fx), uz = fz * fz * (3 - 2 * fz);
  return lerp(lerp(hash2(ix, iz), hash2(ix + 1, iz), ux), lerp(hash2(ix, iz + 1), hash2(ix + 1, iz + 1), ux), uz) * 2 - 1;
}
function fbm(x, z, o = 4) {
  let s = 0, a = 0.5, f = 1;
  for (let i = 0; i < o; i++) { s += vnoise(x * f + i * 17.3, z * f - i * 9.1) * a; f *= 2.03; a *= 0.5; }
  return s;
}
function ridged(x, z, o = 4) {
  let s = 0, a = 0.5, f = 1;
  for (let i = 0; i < o; i++) { const n = 1 - Math.abs(vnoise(x * f + i * 31.7, z * f + i * 7.7)); s += n * n * a; f *= 2.1; a *= 0.5; }
  return s;
}
function segDist(px, pz, ax, az, bx, bz) {
  const dx = bx - ax, dz = bz - az, l2 = dx * dx + dz * dz;
  const t = l2 > 0 ? clamp(((px - ax) * dx + (pz - az) * dz) / l2, 0, 1) : 0;
  const cx = ax + dx * t, cz = az + dz * t;
  return { d: Math.hypot(px - cx, pz - cz), t };
}

// ---------------------------------------------------------------- terrain shape
const AIR = { x0: 2080, x1: 2520, z0: -1350, z1: 1350, h: 14 };
function baseHeight(x, z) {
  const d = Math.max(Math.abs(x), Math.abs(z));
  const cityMask = smoothstep(CITY_FLAT, 1000, d);
  let h = 12 + fbm(x * 0.0011, z * 0.0011, 5) * 75 + fbm(x * 0.0042 + 3, z * 0.0042, 3) * 9;
  const mx = (x - 250) / 1150, mz = (z + 2350) / 720;
  h += Math.exp(-(mx * mx + mz * mz)) * (170 + ridged(x * 0.0021, z * 0.0021, 5) * 380);
  const rim = Math.min(1, smoothstep(2350, 3000, Math.max(-x, -z)) + smoothstep(2700, 3050, x));
  h += rim * (120 + ridged(x * 0.0035 + 9, z * 0.0035, 4) * 230);
  h = Math.max(h, 2);
  h = lerp(0, h, cityMask);
  // Airfield plateau
  const ax = Math.max(AIR.x0 - x, x - AIR.x1, 0), az = Math.max(AIR.z0 - z, z - AIR.z1, 0);
  h = lerp(AIR.h, h, smoothstep(0, 220, Math.hypot(ax, az)));
  // Southern coast
  const coast = smoothstep(1850, 2250, z + fbm(x * 0.0015, 7.3, 3) * 220);
  return lerp(h, -30, coast);
}

// ---------------------------------------------------------------- roads
function catmullRom(ctl, closed, spacing) {
  // Centripetal Catmull-Rom sampled densely, then resampled at fixed spacing.
  const P = ctl.map(([x, z]) => ({ x, z }));
  const n = P.length;
  const get = (i) => (closed ? P[(i + n) % n] : P[clamp(i, 0, n - 1)]);
  const dense = [];
  const segs = closed ? n : n - 1;
  for (let i = 0; i < segs; i++) {
    const p0 = get(i - 1), p1 = get(i), p2 = get(i + 1), p3 = get(i + 2);
    const tj = (a, b) => Math.pow(Math.hypot(b.x - a.x, b.z - a.z), 0.5) || 1e-4;
    const t0 = 0, t1 = t0 + tj(p0, p1), t2 = t1 + tj(p1, p2), t3 = t2 + tj(p2, p3);
    for (let s = 0; s < 40; s++) {
      const t = lerp(t1, t2, s / 40);
      const A1 = mix(p0, p1, (t1 - t) / (t1 - t0), (t - t0) / (t1 - t0));
      const A2 = mix(p1, p2, (t2 - t) / (t2 - t1), (t - t1) / (t2 - t1));
      const A3 = mix(p2, p3, (t3 - t) / (t3 - t2), (t - t2) / (t3 - t2));
      const B1 = mix(A1, A2, (t2 - t) / (t2 - t0), (t - t0) / (t2 - t0));
      const B2 = mix(A2, A3, (t3 - t) / (t3 - t1), (t - t1) / (t3 - t1));
      dense.push(mix(B1, B2, (t2 - t) / (t2 - t1), (t - t1) / (t2 - t1)));
    }
  }
  if (!closed) dense.push({ ...P[n - 1] });
  return resample(dense, spacing, closed);
}
const mix = (a, b, wa, wb) => ({ x: a.x * wa + b.x * wb, z: a.z * wa + b.z * wb });

function resample(pts, step, closed) {
  const src = closed ? [...pts, pts[0]] : pts;
  const out = [{ x: src[0].x, z: src[0].z }];
  let carry = 0;
  for (let i = 0; i < src.length - 1; i++) {
    const a = src[i], b = src[i + 1], L = Math.hypot(b.x - a.x, b.z - a.z);
    if (L < 1e-6) continue;
    let t = step - carry;
    while (t <= L) { out.push({ x: lerp(a.x, b.x, t / L), z: lerp(a.z, b.z, t / L) }); t += step; }
    carry = L - (t - step);
  }
  if (closed) { if (Math.hypot(out.at(-1).x - out[0].x, out.at(-1).z - out[0].z) < step * 0.5) out.pop(); }
  else { const l = src.at(-1); if (Math.hypot(out.at(-1).x - l.x, out.at(-1).z - l.z) > 1) out.push({ x: l.x, z: l.z }); }
  return out;
}

function smoothHeights(pts, closed, h0, h1, minH = 3) {
  const n = pts.length;
  let h = pts.map((p) => Math.max(baseHeight(p.x, p.z), minH));
  for (let pass = 0; pass < 5; pass++) {
    const o = new Array(n);
    for (let i = 0; i < n; i++) {
      let s = 0, c = 0;
      for (let k = -14; k <= 14; k++) {
        let j = i + k;
        if (closed) j = (j + n) % n; else if (j < 0 || j >= n) continue;
        s += h[j]; c++;
      }
      o[i] = s / c;
    }
    h = o;
  }
  const g = 0.075 * 8;
  for (let it = 0; it < 3; it++) {
    for (let i = 1; i < n; i++) h[i] = clamp(h[i], h[i - 1] - g, h[i - 1] + g);
    if (closed) h[0] = clamp(h[0], h[n - 1] - g, h[n - 1] + g);
    for (let i = n - 2; i >= 0; i--) h[i] = clamp(h[i], h[i + 1] - g, h[i + 1] + g);
  }
  if (!closed && h0 !== undefined) {
    const d0 = h0 - h[0], d1 = (h1 ?? h[n - 1]) - h[n - 1];
    for (let i = 0; i < n; i++) h[i] += lerp(d0, d1, i / (n - 1));
  }
  pts.forEach((p, i) => (p.h = Math.max(h[i], minH * 0.5)));
}

const roads = [];
const addRoad = (name, type, hw, closed, pts) => { const r = { name, type, hw, closed, pts }; roads.push(r); return r; };

const ring = catmullRom([
  [0, -1500], [800, -1420], [1350, -1050], [1600, -350], [1580, 400], [1350, 1050], [750, 1450],
  [0, 1560], [-750, 1500], [-1350, 1150], [-1620, 450], [-1600, -350], [-1350, -1050], [-750, -1450],
], true, 8);
smoothHeights(ring, true);
addRoad('Coastal Highway', 'hwy', 12, true, ring);
const ringNear = (x, z) => ring.reduce((b, p) => ((p.x - x) ** 2 + (p.z - z) ** 2 < (b.x - x) ** 2 + (b.z - z) ** 2 ? p : b), ring[0]);

function straight(ax, az, end, type, hw, name, h0 = 0) {
  const L = Math.hypot(end.x - ax, end.z - az), n = Math.ceil(L / 8);
  const pts = [];
  for (let i = 0; i <= n; i++) pts.push({ x: lerp(ax, end.x, i / n), z: lerp(az, end.z, i / n) });
  smoothHeights(pts, false, h0, end.h);
  return addRoad(name, type, hw, false, pts);
}
straight(0, -CITY_EDGE, ringNear(0, -1500), 'link', STREET_HW, 'North Expressway');
straight(0, CITY_EDGE, ringNear(0, 1560), 'link', STREET_HW, 'Harbor Expressway');
straight(CITY_EDGE, 0, ringNear(1600, 0), 'link', STREET_HW, 'East Expressway');
straight(-CITY_EDGE, 0, ringNear(-1610, 0), 'link', STREET_HW, 'West Expressway');

{
  const a = ringNear(800, -1420), b = ringNear(-750, -1450);
  const pass = catmullRom([
    [a.x, a.z], [950, -1650], [1250, -1850], [1350, -2150], [1150, -2400], [850, -2300], [650, -2550], [350, -2700],
    [150, -2500], [300, -2250], [50, -2050], [-300, -2200], [-650, -2400], [-950, -2200], [-1050, -1900], [-900, -1650], [b.x, b.z],
  ], false, 8);
  smoothHeights(pass, false, a.h, b.h);
  addRoad('Summit Pass', 'pass', 6, false, pass);
}
{
  const a = ringNear(-1620, 450), b = ringNear(-1600, -350);
  const c = catmullRom([
    [a.x, a.z], [-1900, 650], [-2200, 900], [-2520, 720], [-2680, 300], [-2550, -200], [-2250, -520], [-1950, -380], [b.x, b.z],
  ], false, 8);
  smoothHeights(c, false, a.h, b.h);
  addRoad('Valley Road', 'country', 5.5, false, c);
}
{
  const pts = [];
  for (let z = AIR.z0 + 60; z <= AIR.z1 - 60; z += 8) pts.push({ x: 2300, z, h: AIR.h });
  addRoad('Airfield Runway', 'runway', 24, false, pts);
  const a = ringNear(1580, 400);
  const taxi = [];
  const L = Math.hypot(2276 - a.x, 400 - a.z), n = Math.ceil(L / 8);
  for (let i = 0; i <= n; i++) taxi.push({ x: lerp(a.x, 2276, i / n), z: lerp(a.z, 400, i / n) });
  smoothHeights(taxi, false, a.h, AIR.h);
  addRoad('Airfield Access', 'link', 8, false, taxi);
}

// Flattened segment list + spatial grid for distance queries
const segs = [];
for (const s of STREETS) {
  segs.push({ ax: s, az: -CITY_EDGE, bx: s, bz: CITY_EDGE, ha: 0, hb: 0, hw: STREET_HW, type: 'city' });
  segs.push({ ax: -CITY_EDGE, az: s, bx: CITY_EDGE, bz: s, ha: 0, hb: 0, hw: STREET_HW, type: 'city' });
}
for (const r of roads) {
  const n = r.pts.length, last = r.closed ? n : n - 1;
  for (let i = 0; i < last; i++) {
    const p = r.pts[i], q = r.pts[(i + 1) % n];
    segs.push({ ax: p.x, az: p.z, bx: q.x, bz: q.z, ha: p.h, hb: q.h, hw: r.hw, type: r.type });
  }
}
const G = 64, grid = new Map();
segs.forEach((s, i) => {
  const m = 90;
  for (let gx = Math.floor((Math.min(s.ax, s.bx) - m + HALF) / G); gx <= Math.floor((Math.max(s.ax, s.bx) + m + HALF) / G); gx++)
    for (let gz = Math.floor((Math.min(s.az, s.bz) - m + HALF) / G); gz <= Math.floor((Math.max(s.az, s.bz) + m + HALF) / G); gz++) {
      const k = gx * 10000 + gz;
      if (!grid.has(k)) grid.set(k, []);
      grid.get(k).push(i);
    }
});
function roadQuery(x, z) {
  const arr = grid.get(Math.floor((x + HALF) / G) * 10000 + Math.floor((z + HALF) / G));
  if (!arr) return null;
  let best = null;
  for (const i of arr) {
    const s = segs[i], r = segDist(x, z, s.ax, s.az, s.bx, s.bz), e = r.d - s.hw;
    if (!best || e < best.edge) best = { edge: e, h: lerp(s.ha, s.hb, r.t), type: s.type, hw: s.hw };
  }
  return best;
}

// ---------------------------------------------------------------- heightmap
console.time('heightmap');
const hm = new Float32Array(N * N);
const mask = new Uint8Array(N * N * 2); // R: road proximity, G: urban
for (let j = 0; j < N; j++) {
  for (let i = 0; i < N; i++) {
    const x = -HALF + i * CELL, z = -HALF + j * CELL;
    let h = baseHeight(x, z);
    let road = 0;
    const q = roadQuery(x, z);
    if (q && q.type !== 'city') {
      h = lerp(q.h, h, smoothstep(5, 60, q.edge));
      road = 1 - smoothstep(0, 14, q.edge);
    }
    const urban = 1 - smoothstep(640, 700, Math.max(Math.abs(x), Math.abs(z)));
    if (urban > 0.999) h = 0;
    hm[j * N + i] = h;
    mask[(j * N + i) * 2] = Math.round(road * 255);
    mask[(j * N + i) * 2 + 1] = Math.round(urban * 255);
  }
}
console.timeEnd('heightmap');
function ground(x, z) {
  const gx = clamp((x + HALF) / CELL, 0, N - 1.001), gz = clamp((z + HALF) / CELL, 0, N - 1.001);
  const i = Math.floor(gx), j = Math.floor(gz), fx = gx - i, fz = gz - j;
  const a = hm[j * N + i], b = hm[j * N + i + 1], c = hm[(j + 1) * N + i], d = hm[(j + 1) * N + i + 1];
  return lerp(lerp(a, b, fx), lerp(c, d, fx), fz);
}

// ---------------------------------------------------------------- city
const R = mulberry32(1337);
const buildings = []; // [x0,z0,x1,z1,h,style,colorIdx,tiers...]
const parks = [];
const streetTrees = [];
const PARK_BLOCKS = new Set(['4,6', '6,3', '2,2', '8,7']);
for (let a = 0; a < STREETS.length - 1; a++) {
  for (let b = 0; b < STREETS.length - 1; b++) {
    const x0 = STREETS[a] + STREET_HW, x1 = STREETS[a + 1] - STREET_HW;
    const z0 = STREETS[b] + STREET_HW, z1 = STREETS[b + 1] - STREET_HW;
    const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2, dc = Math.hypot(cx, cz);
    // Sidewalk trees in the outer districts
    if (dc > 260) for (let t = x0 + 12; t < x1 - 6; t += 22) { streetTrees.push([t, cz < 0 ? z0 + 2.5 : z1 - 2.5]); }
    if (PARK_BLOCKS.has(`${a},${b}`)) { parks.push([x0, z0, x1, z1]); continue; }
    const ix0 = x0 + 5, ix1 = x1 - 5, iz0 = z0 + 5, iz1 = z1 - 5;
    const district = dc < 260 ? 0 : dc < 480 ? 1 : 2;
    const nx = district === 0 ? 1 + Math.floor(R() * 2) : 1 + Math.floor(R() * 3);
    const nz = district === 0 ? 1 + Math.floor(R() * 2) : 1 + Math.floor(R() * 3);
    const gap = 5;
    const lw = (ix1 - ix0 - (nx - 1) * gap) / nx, ld = (iz1 - iz0 - (nz - 1) * gap) / nz;
    for (let i = 0; i < nx; i++) for (let j = 0; j < nz; j++) {
      if (nx === 3 && nz === 3 && i === 1 && j === 1) continue;
      const lx0 = ix0 + i * (lw + gap), lz0 = iz0 + j * (ld + gap);
      const ins = R() * 1.5;
      const bx0 = lx0 + ins, bz0 = lz0 + ins, bx1 = lx0 + lw - ins, bz1 = lz0 + ld - ins;
      let h, style;
      if (district === 0) { h = 90 + R() * 160 + (R() < 0.25 ? 120 : 0); style = R() < 0.6 ? 0 : 1; }
      else if (district === 1) { h = 30 + R() * 80; style = R() < 0.3 ? 0 : 1; }
      else { h = 12 + R() * 30; style = R() < 0.55 ? 2 : 1; }
      h = Math.round(h / 3.8) * 3.8 + 1.2;
      const tiers = [];
      if (h > 70 && R() < 0.75) {
        // Setback towers on top of the podium
        let tw = (bx1 - bx0), td = (bz1 - bz0), th = h;
        const steps = 1 + Math.floor(R() * 2);
        for (let s = 0; s < steps; s++) {
          tw *= 0.62 + R() * 0.2; td *= 0.62 + R() * 0.2;
          const add = h * (0.18 + R() * 0.3);
          tiers.push([tw, td, th, add]);
          th += add;
        }
      }
      buildings.push({ b: [+bx0.toFixed(2), +bz0.toFixed(2), +bx1.toFixed(2), +bz1.toFixed(2), +h.toFixed(1)], s: style, c: Math.floor(R() * 8), t: tiers.map((t) => t.map((v) => +v.toFixed(1))) });
    }
  }
}

// ---------------------------------------------------------------- vegetation
console.time('trees');
const T = mulberry32(77);
const trees = []; // flat array: x,y,z,scale,kind(0 broadleaf,1 pine),rot
const STEP = 9;
for (let z = -HALF + 40; z < HALF - 40; z += STEP) {
  for (let x = -HALF + 40; x < HALF - 40; x += STEP) {
    const px = x + (T() - 0.5) * STEP, pz = z + (T() - 0.5) * STEP;
    if (Math.abs(px) < 720 && Math.abs(pz) < 720) continue;
    if (px > AIR.x0 - 60 && px < AIR.x1 + 60 && pz > AIR.z0 - 60 && pz < AIR.z1 + 60) continue;
    const dens = fbm(px * 0.0035, pz * 0.0035, 3) + 0.08;
    if (dens < 0 || T() > 0.55 + dens) continue;
    const h = ground(px, pz);
    if (h < WATER_Y + 3 || h > 330) continue;
    const sl = Math.abs(ground(px + 3, pz) - h) + Math.abs(ground(px, pz + 3) - h);
    if (sl > 3.2) continue;
    const q = roadQuery(px, pz);
    if (q && q.edge < 9) continue;
    const pine = h > 110 || fbm(px * 0.002 + 50, pz * 0.002, 2) > 0.15 ? 1 : 0;
    trees.push(+px.toFixed(1), +(h - 0.15).toFixed(2), +pz.toFixed(1), +(0.75 + T() * 0.7).toFixed(2), pine, +(T() * 6.28).toFixed(2));
  }
}
for (const p of parks) {
  for (let i = 0; i < 40; i++) trees.push(+lerp(p[0] + 8, p[2] - 8, T()).toFixed(1), 0.15, +lerp(p[1] + 8, p[3] - 8, T()).toFixed(1), +(0.8 + T() * 0.5).toFixed(2), 0, +(T() * 6.28).toFixed(2));
}
for (const [x, z] of streetTrees) trees.push(x, 0.15, z, +(0.55 + T() * 0.2).toFixed(2), 0, +(T() * 6.28).toFixed(2));
console.timeEnd('trees');

// ---------------------------------------------------------------- street lights
const lamps = []; // x,y,z,dirx,dirz
for (const s of STREETS) {
  for (let t = -CITY_EDGE + 30; t < CITY_EDGE - 10; t += 32) {
    if (STREETS.some((q) => Math.abs(q - t) < 16)) continue;
    lamps.push(s - 11.5, 0.15, t, 1, 0, s + 11.5, 0.15, t + 16, -1, 0, t, 0.15, s - 11.5, 0, 1, t + 16, 0.15, s + 11.5, 0, -1);
  }
}
for (const r of roads) {
  if (r.type === 'pass' || r.type === 'country') continue;
  const every = r.type === 'runway' ? 8 : 6;
  for (let i = 0; i < r.pts.length - 1; i += every) {
    const p = r.pts[i], q = r.pts[i + 1];
    let tx = q.x - p.x, tz = q.z - p.z; const l = Math.hypot(tx, tz) || 1; tx /= l; tz /= l;
    for (const side of r.type === 'hwy' || r.type === 'runway' ? [1, -1] : [(i / every) % 2 ? 1 : -1]) {
      const nx = -tz * side, nz = tx * side;
      const x = p.x + nx * (r.hw + 1.8), z = p.z + nz * (r.hw + 1.8);
      lamps.push(+x.toFixed(2), +ground(x, z).toFixed(2), +z.toFixed(2), +(-nx).toFixed(3), +(-nz).toFixed(3));
    }
  }
}

// ---------------------------------------------------------------- navigation graph
const nodes = []; // [x,z,typeIdx]
const TYPES = ['city', 'link', 'hwy', 'pass', 'country', 'runway'];
const adj = [];
const addNode = (x, z, type) => { nodes.push([+x.toFixed(1), +z.toFixed(1), TYPES.indexOf(type)]); adj.push([]); return nodes.length - 1; };
const link = (a, b) => { if (a === b) return; if (!adj[a].includes(b)) adj[a].push(b); if (!adj[b].includes(a)) adj[b].push(a); };
const SN = STREETS.length;
for (let i = 0; i < SN; i++) for (let j = 0; j < SN; j++) addNode(STREETS[i], STREETS[j], 'city');
for (let i = 0; i < SN; i++) for (let j = 0; j < SN; j++) { if (i + 1 < SN) link(i * SN + j, (i + 1) * SN + j); if (j + 1 < SN) link(i * SN + j, i * SN + j + 1); }
const nearestOf = (ids, x, z) => ids.reduce((b, k) => ((nodes[k][0] - x) ** 2 + (nodes[k][1] - z) ** 2 < (nodes[b][0] - x) ** 2 + (nodes[b][1] - z) ** 2 ? k : b), ids[0]);
const cityIds = [...Array(SN * SN).keys()];
const ringIds = [];
for (let i = 0; i < ring.length; i += 3) ringIds.push(addNode(ring[i].x, ring[i].z, 'hwy'));
for (let i = 0; i < ringIds.length; i++) link(ringIds[i], ringIds[(i + 1) % ringIds.length]);
const runwayIds = [];
for (const r of roads) {
  if (r.type === 'hwy') continue;
  const ids = [];
  for (let i = 0; i < r.pts.length; i += 3) ids.push(addNode(r.pts[i].x, r.pts[i].z, r.type));
  if ((r.pts.length - 1) % 3) ids.push(addNode(r.pts.at(-1).x, r.pts.at(-1).z, r.type));
  for (let i = 0; i < ids.length - 1; i++) link(ids[i], ids[i + 1]);
  if (r.type === 'runway') { runwayIds.push(...ids); continue; }
  const f = nodes[ids[0]], l = nodes[ids.at(-1)];
  if (r.name === 'Airfield Access') { link(nearestOf(ringIds, f[0], f[1]), ids[0]); continue; }
  link(r.type === 'link' ? nearestOf(cityIds, f[0], f[1]) : nearestOf(ringIds, f[0], f[1]), ids[0]);
  link(nearestOf(ringIds, l[0], l[1]), ids.at(-1));
}
{ // connect airfield access end to runway
  const acc = roads.find((r) => r.name === 'Airfield Access');
  const end = acc.pts.at(-1);
  const accEnd = nodes.findIndex((n) => Math.abs(n[0] - +end.x.toFixed(1)) < 0.2 && Math.abs(n[1] - +end.z.toFixed(1)) < 0.2);
  link(accEnd, nearestOf(runwayIds, end.x, end.z));
}

// ---------------------------------------------------------------- write
fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(OUT, 'height.bin'), Buffer.from(hm.buffer));
fs.writeFileSync(path.join(OUT, 'mask.bin'), Buffer.from(mask.buffer));
const round = (v) => +v.toFixed(2);
const world = {
  half: HALF, cell: CELL, n: N, water: WATER_Y, streets: STREETS, streetHw: STREET_HW, cityEdge: CITY_EDGE, air: AIR,
  roads: roads.map((r) => ({ name: r.name, type: r.type, hw: r.hw, closed: r.closed, pts: r.pts.flatMap((p) => [round(p.x), round(p.h), round(p.z)]) })),
  buildings, parks, trees, lamps, nodes, adj, types: TYPES,
};
fs.writeFileSync(path.join(OUT, 'world.json'), JSON.stringify(world));
const km = roads.reduce((s, r) => s + r.pts.length * 8, 0) / 1000;
console.log(`roads ${roads.length} (${km.toFixed(1)} km + ${(STREETS.length * 2 * 1.2).toFixed(1)} km city), buildings ${buildings.length}, trees ${trees.length / 6}, lamps ${lamps.length / 5}, nodes ${nodes.length}`);
{ let lo = Infinity, hi = -Infinity; for (const v of hm) { lo = Math.min(lo, v); hi = Math.max(hi, v); } console.log('height range', lo.toFixed(1), hi.toFixed(1)); }

// ---------------------------------------------------------------- minimap image (PNG)
import zlib from 'node:zlib';
function writePng(file, w, h, rgba) {
  const crcTable = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
  const crc = (buf) => { let c = -1; for (const b of buf) c = crcTable[(c ^ b) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]));
}
{
  const S = 1024, px = Buffer.alloc(S * S * 4);
  const put = (x, y, r, g, b, a = 255) => { if (x < 0 || y < 0 || x >= S || y >= S) return; const i = (y * S + x) * 4; px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = a; };
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const wx = -HALF + (x / S) * HALF * 2, wz = -HALF + (y / S) * HALF * 2;
    const h = ground(wx, wz);
    if (h < WATER_Y - 0.3) put(x, y, 14, 34, 52);
    else {
      const e = 1 - Math.min(1, Math.abs(ground(wx + 8, wz) - h) / 10);
      const v = Math.min(1, 0.25 + h / 600);
      put(x, y, Math.round(28 + 40 * v * e), Math.round(40 + 46 * v * e), Math.round(30 + 26 * v * e));
    }
  }
  const tm = (v) => Math.round(((v + HALF) / (HALF * 2)) * S);
  for (let y = tm(-690); y < tm(690); y++) for (let x = tm(-690); x < tm(690); x++) put(x, y, 34, 36, 42);
  for (const b of buildings) for (let y = tm(b.b[1]); y < tm(b.b[3]); y++) for (let x = tm(b.b[0]); x < tm(b.b[2]); x++) put(x, y, 62, 66, 76);
  const line = (x0, z0, x1, z1, wpx, c) => {
    const L = Math.hypot(x1 - x0, z1 - z0), n = Math.ceil(L / 2);
    for (let i = 0; i <= n; i++) {
      const cx = tm(lerp(x0, x1, i / n)), cy = tm(lerp(z0, z1, i / n));
      for (let dy = -wpx; dy <= wpx; dy++) for (let dx = -wpx; dx <= wpx; dx++) if (dx * dx + dy * dy <= wpx * wpx) put(cx + dx, cy + dy, ...c);
    }
  };
  for (const s of STREETS) { line(s, -CITY_EDGE, s, CITY_EDGE, 2, [205, 210, 218]); line(-CITY_EDGE, s, CITY_EDGE, s, 2, [205, 210, 218]); }
  for (const r of roads) {
    const c = r.type === 'hwy' ? [255, 196, 80] : r.type === 'runway' ? [170, 170, 180] : [225, 228, 234];
    const wpx = r.type === 'hwy' || r.type === 'runway' ? 3 : 2;
    const n = r.pts.length, last = r.closed ? n : n - 1;
    for (let i = 0; i < last; i++) { const p = r.pts[i], q = r.pts[(i + 1) % n]; line(p.x, p.z, q.x, q.z, wpx, c); }
  }
  writePng(path.join(OUT, 'map.png'), S, S, px);
  console.log('map.png written');
}
