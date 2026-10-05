// Open world: procedural city, terrain, coast, highway ring, mountain pass,
// road graph for AI/traffic/races, and building collision.
import * as THREE from 'three';
import { clamp, lerp, smoothstep, fbm, ridged, mulberry32, distToSegment, colorize, mergeGeometries } from './utils.js';
import { STREETS } from './config.js';
import * as TX from './textures.js';

export const HALF = 2048;
const CELL = 16;
const N = HALF * 2 / CELL + 1; // 257 vertices per side
const CITY_EDGE = 449;
const STREET_HW = 9;
export const WATER_Y = -1.5;
const SEG_GRID = 64;

// Base terrain shape before roads are carved in.
function baseHeight(x, z) {
  const d = Math.max(Math.abs(x), Math.abs(z));
  const cityMask = smoothstep(500, 780, d);
  let h = 7 + fbm(x * 0.0016, z * 0.0016, 4) * 50 + fbm(x * 0.006 + 3, z * 0.006, 3) * 7;
  const mx = (x - 420) / 700, mz = (z + 1560) / 520;
  h += Math.exp(-(mx * mx + mz * mz)) * (110 + ridged(x * 0.003, z * 0.003, 4) * 230);
  const rim = smoothstep(1450, 2000, Math.max(Math.abs(x), -z));
  h += rim * (90 + ridged(x * 0.004 + 9, z * 0.004, 4) * 160);
  h = lerp(0, h, cityMask);
  const coast = smoothstep(1250, 1580, z + fbm(x * 0.002, 7.3, 3) * 160);
  return lerp(h, -24, coast);
}

export class World {
  constructor(scene, quality, uniforms) {
    this.scene = scene;
    this.q = quality;
    this.U = uniforms;
    this.rnd = mulberry32(1337);
    this.roads = [];       // { pts:[{x,z,h}], hw, type, closed }
    this.segs = [];        // flattened segments for queries
    this.segGrid = new Map();
    this.buildings = [];   // AABBs {x0,z0,x1,z1,h}
    this.bGrid = new Map();
    this.nodes = [];
    this.nightObjects = [];

    this.buildRoadLines();
    this.indexSegments();
    this.buildHeightmap();
    this.buildTerrain();
    this.buildWater();
    this.buildCity();
    this.buildRoadMeshes();
    this.buildTrees();
    this.buildLamps();
    this.buildGraph();
    this.buildMapImage();
  }

  // ---------------------------------------------------------------- roads
  buildRoadLines() {
    const ringCtl = [
      [0, -1050], [550, -1000], [950, -760], [1150, -260], [1110, 300], [950, 800], [520, 1130],
      [0, 1180], [-560, 1150], [-1000, 860], [-1160, 300], [-1150, -300], [-950, -800], [-500, -1050],
    ];
    const ring = this.splinePoints(ringCtl, true, 8);
    this.smoothHeights(ring, true);
    this.ring = this.addRoad(ring, 12, 'hwy', true);

    const ringNear = (x, z) => {
      let best = 0, bd = Infinity;
      ring.forEach((p, i) => {
        const d = (p.x - x) ** 2 + (p.z - z) ** 2;
        if (d < bd) { bd = d; best = i; }
      });
      return ring[best];
    };
    const link = (ax, az, end) => {
      const len = Math.hypot(end.x - ax, end.z - az);
      const n = Math.ceil(len / 8);
      const pts = [];
      for (let i = 0; i <= n; i++) pts.push({ x: lerp(ax, end.x, i / n), z: lerp(az, end.z, i / n) });
      this.smoothHeights(pts, false, 0, end.h);
      return this.addRoad(pts, STREET_HW, 'link', false);
    };
    link(0, -CITY_EDGE, ringNear(0, -1050));
    link(0, CITY_EDGE, ringNear(0, 1180));
    link(CITY_EDGE, 0, ringNear(1140, 0));
    link(-CITY_EDGE, 0, ringNear(-1155, 0));

    const a = ringNear(550, -1000), b = ringNear(-500, -1050);
    const passCtl = [
      [a.x, a.z], [650, -1200], [900, -1330], [1080, -1520], [930, -1700], [680, -1640], [480, -1790],
      [230, -1660], [330, -1470], [120, -1310], [-180, -1420], [-480, -1560], [-720, -1380], [-700, -1200], [b.x, b.z],
    ];
    const pass = this.splinePoints(passCtl, false, 8);
    this.smoothHeights(pass, false, a.h, b.h);
    this.pass = this.addRoad(pass, 7, 'pass', false);
  }

  splinePoints(ctl, closed, spacing) {
    const curve = new THREE.CatmullRomCurve3(ctl.map(([x, z]) => new THREE.Vector3(x, 0, z)), closed, 'centripetal');
    const n = Math.ceil(curve.getLength() / spacing);
    return curve.getSpacedPoints(closed ? n : n).slice(0, closed ? n : n + 1).map((v) => ({ x: v.x, z: v.z }));
  }

  // Road elevations: smoothed terrain, grade-limited, pinned at junction ends.
  smoothHeights(pts, closed, h0, h1) {
    const n = pts.length;
    let h = pts.map((p) => Math.max(baseHeight(p.x, p.z), 1.2));
    for (let pass = 0; pass < 4; pass++) {
      const out = new Array(n);
      for (let i = 0; i < n; i++) {
        let s = 0, c = 0;
        for (let k = -12; k <= 12; k++) {
          let j = i + k;
          if (closed) j = (j + n) % n; else if (j < 0 || j >= n) continue;
          s += h[j]; c++;
        }
        out[i] = s / c;
      }
      h = out;
    }
    const g = 0.075 * 8;
    for (let it = 0; it < 2; it++) {
      for (let i = 1; i < n; i++) h[i] = clamp(h[i], h[i - 1] - g, h[i - 1] + g);
      for (let i = n - 2; i >= 0; i--) h[i] = clamp(h[i], h[i + 1] - g, h[i + 1] + g);
    }
    if (!closed && h0 !== undefined) {
      const d0 = h0 - h[0], d1 = (h1 ?? h[n - 1]) - h[n - 1];
      for (let i = 0; i < n; i++) h[i] += lerp(d0, d1, i / (n - 1));
    }
    pts.forEach((p, i) => (p.h = Math.max(h[i], 1.0)));
  }

  addRoad(pts, hw, type, closed) {
    const road = { pts, hw, type, closed };
    this.roads.push(road);
    return road;
  }

  indexSegments() {
    // City streets as long straight segments at height 0.
    for (const s of STREETS) {
      this.segs.push({ ax: s, az: -CITY_EDGE, bx: s, bz: CITY_EDGE, ha: 0, hb: 0, hw: STREET_HW, type: 'city' });
      this.segs.push({ ax: -CITY_EDGE, az: s, bx: CITY_EDGE, bz: s, ha: 0, hb: 0, hw: STREET_HW, type: 'city' });
    }
    for (const r of this.roads) {
      const n = r.pts.length;
      const last = r.closed ? n : n - 1;
      for (let i = 0; i < last; i++) {
        const p = r.pts[i], q = r.pts[(i + 1) % n];
        this.segs.push({ ax: p.x, az: p.z, bx: q.x, bz: q.z, ha: p.h, hb: q.h, hw: r.hw, type: r.type });
      }
    }
    const margin = 70;
    this.segs.forEach((s, idx) => {
      const x0 = Math.floor((Math.min(s.ax, s.bx) - margin + HALF) / SEG_GRID);
      const x1 = Math.floor((Math.max(s.ax, s.bx) + margin + HALF) / SEG_GRID);
      const z0 = Math.floor((Math.min(s.az, s.bz) - margin + HALF) / SEG_GRID);
      const z1 = Math.floor((Math.max(s.az, s.bz) + margin + HALF) / SEG_GRID);
      for (let gx = x0; gx <= x1; gx++)
        for (let gz = z0; gz <= z1; gz++) {
          const k = gx * 1000 + gz;
          let arr = this.segGrid.get(k);
          if (!arr) this.segGrid.set(k, (arr = []));
          arr.push(idx);
        }
    });
  }

  // Nearest road info at a point (within ~70m), or null.
  roadQuery(x, z) {
    const k = Math.floor((x + HALF) / SEG_GRID) * 1000 + Math.floor((z + HALF) / SEG_GRID);
    const arr = this.segGrid.get(k);
    if (!arr) return null;
    let best = null, bd = Infinity;
    for (const i of arr) {
      const s = this.segs[i];
      const r = distToSegment(x, z, s.ax, s.az, s.bx, s.bz);
      const d = r.d - s.hw;
      if (d < bd) { bd = d; best = { d: r.d, edge: d, h: lerp(s.ha, s.hb, r.t), hw: s.hw, seg: s, t: r.t }; }
    }
    return best;
  }

  // ---------------------------------------------------------------- terrain
  buildHeightmap() {
    this.hm = new Float32Array(N * N);
    this.roadDist = new Float32Array(N * N);
    for (let j = 0; j < N; j++) {
      for (let i = 0; i < N; i++) {
        const x = -HALF + i * CELL, z = -HALF + j * CELL;
        let h = baseHeight(x, z);
        let rd = 999;
        const q = this.roadQuery(x, z);
        if (q && q.seg.type !== 'city') {
          rd = q.edge;
          const w = smoothstep(4, 48, q.edge);
          h = lerp(q.h, h, w);
        }
        if (Math.abs(x) < 470 && Math.abs(z) < 470) h = 0;
        this.hm[j * N + i] = h;
        this.roadDist[j * N + i] = rd;
      }
    }
  }

  // Terrain height, interpolated exactly like the rendered triangles.
  ground(x, z) {
    const gx = clamp((x + HALF) / CELL, 0, N - 1.001);
    const gz = clamp((z + HALF) / CELL, 0, N - 1.001);
    const i = Math.floor(gx), j = Math.floor(gz);
    const fx = gx - i, fz = gz - j;
    const hm = this.hm;
    const h00 = hm[j * N + i], h10 = hm[j * N + i + 1];
    const h01 = hm[(j + 1) * N + i], h11 = hm[(j + 1) * N + i + 1];
    if (fx + fz <= 1) return h00 + (h10 - h00) * fx + (h01 - h00) * fz;
    return h11 + (h01 - h11) * (1 - fx) + (h10 - h11) * (1 - fz);
  }

  surface(x, z) {
    if (Math.abs(x) < 470 && Math.abs(z) < 470) return PAVED;
    const q = this.roadQuery(x, z);
    if (q && q.edge < 1) return PAVED;
    if (q && q.edge < 5) return SHOULDER;
    return this.ground(x, z) < WATER_Y + 0.3 ? SAND : GRASS;
  }

  buildTerrain() {
    const CH = 32; // cells per chunk
    const chunks = (N - 1) / CH;
    this.detailTex = TX.detailTexture(this.q.aniso);
    const mat = new THREE.MeshLambertMaterial({ vertexColors: true, map: this.detailTex });
    const grassA = new THREE.Color(0.16, 0.36, 0.1), grassB = new THREE.Color(0.38, 0.44, 0.16);
    const rock = new THREE.Color(0.36, 0.34, 0.31), snow = new THREE.Color(0.92, 0.94, 0.97);
    const sand = new THREE.Color(0.74, 0.67, 0.48), concrete = new THREE.Color(0.33, 0.33, 0.34);
    const gravel = new THREE.Color(0.4, 0.38, 0.34);
    const col = new THREE.Color();
    for (let cz = 0; cz < chunks; cz++) {
      for (let cx = 0; cx < chunks; cx++) {
        const vs = CH + 1;
        const pos = new Float32Array(vs * vs * 3), nrm = new Float32Array(vs * vs * 3);
        const clr = new Float32Array(vs * vs * 3), uv = new Float32Array(vs * vs * 2);
        let k = 0;
        for (let j = 0; j < vs; j++) {
          for (let i = 0; i < vs; i++) {
            const gi = cx * CH + i, gj = cz * CH + j;
            const x = -HALF + gi * CELL, z = -HALF + gj * CELL;
            const h = this.hm[gj * N + gi];
            pos[k * 3] = x; pos[k * 3 + 1] = h; pos[k * 3 + 2] = z;
            const hl = this.hm[gj * N + Math.max(gi - 1, 0)], hr = this.hm[gj * N + Math.min(gi + 1, N - 1)];
            const hd = this.hm[Math.max(gj - 1, 0) * N + gi], hu = this.hm[Math.min(gj + 1, N - 1) * N + gi];
            const nx = (hl - hr) / (2 * CELL), nz = (hd - hu) / (2 * CELL);
            const il = 1 / Math.hypot(nx, 1, nz);
            nrm[k * 3] = nx * il; nrm[k * 3 + 1] = il; nrm[k * 3 + 2] = nz * il;
            const slope = Math.hypot(nx, nz);
            const n1 = fbm(x * 0.01, z * 0.01, 2) * 0.5 + 0.5;
            col.copy(grassA).lerp(grassB, n1);
            col.lerp(rock, smoothstep(0.45, 0.8, slope));
            col.lerp(snow, smoothstep(185, 230, h + n1 * 25) * (1 - smoothstep(0.9, 1.2, slope)));
            col.lerp(sand, 1 - smoothstep(WATER_Y + 0.5, WATER_Y + 4, h));
            const rd = this.roadDist[gj * N + gi];
            col.lerp(gravel, (1 - smoothstep(1, 6, rd)) * 0.6);
            if (Math.abs(x) < 480 && Math.abs(z) < 480) col.copy(concrete);
            clr[k * 3] = col.r; clr[k * 3 + 1] = col.g; clr[k * 3 + 2] = col.b;
            uv[k * 2] = x / 9; uv[k * 2 + 1] = z / 9;
            k++;
          }
        }
        const idx = [];
        for (let j = 0; j < CH; j++) {
          for (let i = 0; i < CH; i++) {
            const a = j * vs + i, b = a + 1, c = a + vs, d = c + 1;
            idx.push(a, c, b, b, c, d);
          }
        }
        const g = new THREE.BufferGeometry();
        g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
        g.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
        g.setAttribute('color', new THREE.BufferAttribute(clr, 3));
        g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
        g.setIndex(idx);
        g.computeBoundingSphere();
        const m = new THREE.Mesh(g, mat);
        m.receiveShadow = true;
        m.matrixAutoUpdate = false;
        this.scene.add(m);
      }
    }
  }

  buildWater() {
    const nt = TX.waterNormalTexture();
    nt.repeat.set(400, 400);
    this.waterNormal = nt;
    const mat = new THREE.MeshPhongMaterial({
      color: 0x0d3a4f, specular: 0x9ab8c8, shininess: 120, normalMap: nt,
      normalScale: new THREE.Vector2(0.35, 0.35), transparent: true, opacity: 0.92,
    });
    const m = new THREE.Mesh(new THREE.PlaneGeometry(9000, 9000), mat);
    m.rotation.x = -Math.PI / 2;
    m.position.y = WATER_Y;
    m.matrixAutoUpdate = true;
    this.scene.add(m);
    this.water = m;
  }

  // ---------------------------------------------------------------- city
  buildCity() {
    const aniso = this.q.aniso;
    const R = this.rnd;
    // Streets between intersections
    const roadTex = TX.roadTexture('city', aniso);
    this.roadTexCity = roadTex;
    const pos = [], uv = [];
    const quad = (x0, z0, x1, z1, y, alongZ, vLen) => {
      // Quad with u across the road and v along it.
      const v = [[x0, z0], [x1, z0], [x1, z1], [x0, z1]];
      const uvs = alongZ
        ? [[0, 0], [1, 0], [1, vLen], [0, vLen]]
        : [[0, 0], [0, vLen], [1, vLen], [1, 0]];
      for (const t of [0, 2, 1, 0, 3, 2]) {
        pos.push(v[t][0], y, v[t][1]);
        uv.push(uvs[t][0], uvs[t][1]);
      }
    };
    for (let a = 0; a < STREETS.length; a++) {
      for (let b = 0; b < STREETS.length - 1; b++) {
        const s = STREETS[a], z0 = STREETS[b] + STREET_HW, z1 = STREETS[b + 1] - STREET_HW;
        const vl = (z1 - z0) / 36;
        quad(s - STREET_HW, z0, s + STREET_HW, z1, 0.02, true, vl);
        quad(z0, s - STREET_HW, z1, s + STREET_HW, 0.02, false, vl);
      }
    }
    this.scene.add(this.flatMesh(pos, uv, new THREE.MeshLambertMaterial({ map: roadTex })));

    const ipos = [], iuv = [];
    for (const sx of STREETS) for (const sz of STREETS) {
      const v = [[sx - 9, sz - 9], [sx + 9, sz - 9], [sx + 9, sz + 9], [sx - 9, sz + 9]];
      const u = [[0, 0], [1, 0], [1, 1], [0, 1]];
      for (const t of [0, 2, 1, 0, 3, 2]) { ipos.push(v[t][0], 0.02, v[t][1]); iuv.push(u[t][0], u[t][1]); }
    }
    this.scene.add(this.flatMesh(ipos, iuv, new THREE.MeshLambertMaterial({ map: TX.intersectionTexture(aniso) })));

    // Sidewalk slabs + building lots
    const spos = [], suv = [];
    const lots = [];
    const parks = [];
    for (let a = 0; a < STREETS.length - 1; a++) {
      for (let b = 0; b < STREETS.length - 1; b++) {
        const x0 = STREETS[a] + STREET_HW, x1 = STREETS[a + 1] - STREET_HW;
        const z0 = STREETS[b] + STREET_HW, z1 = STREETS[b + 1] - STREET_HW;
        const v = [[x0, z0], [x1, z0], [x1, z1], [x0, z1]];
        for (const t of [0, 2, 1, 0, 3, 2]) { spos.push(v[t][0], 0.07, v[t][1]); suv.push(v[t][0] / 6, v[t][1] / 6); }
        const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2;
        const dc = Math.hypot(cx, cz);
        if ((a === 3 && b === 5) || (a === 5 && b === 2) || (R() < 0.07 && dc > 200)) { parks.push({ x0, z0, x1, z1 }); continue; }
        const ix0 = x0 + 4, ix1 = x1 - 4, iz0 = z0 + 4, iz1 = z1 - 4;
        const nx = 1 + Math.floor(R() * 3), nz = 1 + Math.floor(R() * 3);
        const lw = (ix1 - ix0 - (nx - 1) * 4) / nx, ld = (iz1 - iz0 - (nz - 1) * 4) / nz;
        for (let i = 0; i < nx; i++) for (let j = 0; j < nz; j++) {
          // Interior lots of a 3x3 split are hidden; skip them.
          if (nx === 3 && nz === 3 && i === 1 && j === 1) continue;
          const lx0 = ix0 + i * (lw + 4), lz0 = iz0 + j * (ld + 4);
          const inset = R() * 2.5;
          lots.push({ x0: lx0 + inset, z0: lz0 + inset, x1: lx0 + lw - inset, z1: lz0 + ld - inset, dc });
        }
      }
    }
    this.scene.add(this.flatMesh(spos, suv, new THREE.MeshLambertMaterial({ map: TX.sidewalkTexture(aniso) })));

    // Parks: grass slab and trees
    const ppos = [];
    for (const p of parks) {
      const v = [[p.x0 + 3, p.z0 + 3], [p.x1 - 3, p.z0 + 3], [p.x1 - 3, p.z1 - 3], [p.x0 + 3, p.z1 - 3]];
      for (const t of [0, 2, 1, 0, 3, 2]) ppos.push(v[t][0], 0.1, v[t][1]);
    }
    const pg = new THREE.BufferGeometry();
    pg.setAttribute('position', new THREE.Float32BufferAttribute(ppos, 3));
    pg.computeVertexNormals();
    this.scene.add(new THREE.Mesh(pg, new THREE.MeshLambertMaterial({ color: 0x2e5a22 })));
    this.parkTrees = [];
    for (const p of parks) {
      for (let t = 0; t < 26; t++) {
        this.parkTrees.push({ x: lerp(p.x0 + 6, p.x1 - 6, R()), z: lerp(p.z0 + 6, p.z1 - 6, R()), y: 0.1, s: 0.8 + R() * 0.6 });
      }
    }

    // Buildings (instanced, procedural windows)
    const palette = [0x8a8f96, 0x6f7780, 0xa59c8e, 0x5d6670, 0x9fa9b3, 0x7b6f63, 0x4f5a66, 0xb8b2a6, 0x3e4a57, 0x8c7f75];
    const geo = new THREE.BoxGeometry(1, 1, 1);
    geo.translate(0, 0.5, 0);
    const mat = this.facadeMaterial();
    const count = lots.length * 2;
    const inst = new THREE.InstancedMesh(geo, mat, count);
    const m4 = new THREE.Matrix4(), c = new THREE.Color();
    let n = 0;
    const roofs = [];
    const signs = [];
    for (const l of lots) {
      const down = 1 - clamp(l.dc / 520, 0, 1);
      const w = l.x1 - l.x0, d = l.z1 - l.z0;
      let h = 9 + R() * 18 + down * down * (30 + R() * 150);
      if (R() < 0.1 * down) h += 80;
      h = Math.round(h / 3.6) * 3.6 + 0.4;
      const cx = (l.x0 + l.x1) / 2, cz = (l.z0 + l.z1) / 2;
      m4.makeScale(w, h, d).setPosition(cx, 0, cz);
      inst.setMatrixAt(n, m4);
      inst.setColorAt(n, c.setHex(palette[Math.floor(R() * palette.length)]));
      n++;
      this.addBuilding(l.x0, l.z0, l.x1, l.z1, h);
      // Setback tower
      if (h > 50 && R() < 0.6) {
        const s = 0.55 + R() * 0.25, th = h * (0.15 + R() * 0.35);
        m4.makeScale(w * s, th, d * s).setPosition(cx, h, cz);
        inst.setMatrixAt(n, m4);
        inst.setColorAt(n, c.setHex(palette[Math.floor(R() * palette.length)]));
        n++;
        roofs.push({ x: cx, z: cz, y: h + th, w: w * s, d: d * s });
      } else roofs.push({ x: cx, z: cz, y: h, w, d });
      if (R() < 0.45) {
        // Neon sign on a random street-facing side
        const side = Math.floor(R() * 4);
        const sy = 5 + R() * Math.min(12, h - 8);
        const sh = 3 + R() * 6;
        if (side === 0) signs.push([l.x0 - 0.3, sy, cz + (R() - 0.5) * d * 0.5, 0.3, sh, 1.6 + R() * 2]);
        if (side === 1) signs.push([l.x1 + 0.3, sy, cz + (R() - 0.5) * d * 0.5, 0.3, sh, 1.6 + R() * 2]);
        if (side === 2) signs.push([cx + (R() - 0.5) * w * 0.5, sy, l.z0 - 0.3, 1.6 + R() * 2, sh, 0.3]);
        if (side === 3) signs.push([cx + (R() - 0.5) * w * 0.5, sy, l.z1 + 0.3, 1.6 + R() * 2, sh, 0.3]);
      }
    }
    inst.count = n;
    inst.instanceMatrix.needsUpdate = true;
    inst.computeBoundingSphere();
    inst.castShadow = true;
    inst.receiveShadow = true;
    this.scene.add(inst);
    this.buildingMesh = inst;

    // Rooftop clutter (AC units, water tanks)
    const rg = new THREE.BoxGeometry(1, 1, 1);
    rg.translate(0, 0.5, 0);
    const rmesh = new THREE.InstancedMesh(rg, new THREE.MeshLambertMaterial({ color: 0x777b80 }), roofs.length * 3);
    let rn = 0;
    for (const r of roofs) {
      const k = 1 + Math.floor(R() * 3);
      for (let i = 0; i < k; i++) {
        const sx = 2 + R() * 4, sz = 2 + R() * 4, sy = 1.5 + R() * 2.5;
        m4.makeScale(sx, sy, sz).setPosition(r.x + (R() - 0.5) * (r.w - sx), r.y, r.z + (R() - 0.5) * (r.d - sz));
        rmesh.setMatrixAt(rn++, m4);
      }
    }
    rmesh.count = rn;
    rmesh.computeBoundingSphere();
    this.scene.add(rmesh);

    // Neon signs (glow at night)
    const neonCols = [0xff2fa0, 0x19e3ff, 0xffd400, 0x8a5cff, 0xff4b2b, 0x2fff8a];
    const sg = new THREE.BoxGeometry(1, 1, 1);
    const smat = new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false });
    const smesh = new THREE.InstancedMesh(sg, smat, signs.length);
    signs.forEach((s, i) => {
      m4.makeScale(s[3], s[4], s[5]).setPosition(s[0], s[1] + s[4] / 2, s[2]);
      smesh.setMatrixAt(i, m4);
      smesh.setColorAt(i, c.setHex(neonCols[Math.floor(R() * neonCols.length)]));
    });
    smesh.computeBoundingSphere();
    this.scene.add(smesh);
    this.neonMat = smat;
  }

  flatMesh(pos, uv, mat) {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.computeVertexNormals();
    g.computeBoundingSphere();
    const m = new THREE.Mesh(g, mat);
    m.receiveShadow = true;
    m.matrixAutoUpdate = false;
    return m;
  }

  facadeMaterial() {
    const mat = new THREE.MeshLambertMaterial({ color: 0xffffff });
    const U = this.U;
    mat.onBeforeCompile = (sh) => {
      sh.uniforms.uNight = U.uNight;
      sh.vertexShader = 'varying vec3 vWPos;\nvarying vec3 vWNrm;\n' + sh.vertexShader.replace(
        '#include <project_vertex>',
        `#include <project_vertex>
        vec4 wpp = vec4(transformed, 1.0);
        vec3 wnn = objectNormal;
        #ifdef USE_INSTANCING
          wpp = instanceMatrix * wpp;
          wnn = mat3(instanceMatrix) * wnn;
        #endif
        vWPos = (modelMatrix * wpp).xyz;
        vWNrm = normalize(mat3(modelMatrix) * wnn);`
      );
      sh.fragmentShader = 'uniform float uNight;\nvarying vec3 vWPos;\nvarying vec3 vWNrm;\n' +
        'float bh(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }\n' +
        sh.fragmentShader
          .replace('#include <color_fragment>', `#include <color_fragment>
          float wall = 1.0 - step(0.5, abs(vWNrm.y));
          vec2 fp = abs(vWNrm.x) > 0.5 ? vec2(vWPos.z, vWPos.y) : vec2(vWPos.x, vWPos.y);
          vec2 cel = fp / vec2(2.3, 3.4);
          vec2 fw = fract(cel);
          vec2 cid = floor(cel);
          float win = wall * step(0.18, fw.x) * step(fw.x, 0.82) * step(0.25, fw.y) * step(fw.y, 0.8) * step(1.0, cid.y);
          float shop = wall * (1.0 - step(1.0, cid.y)) * step(0.3, fw.y) * step(fw.y, 0.95) * step(0.05, fw.x) * step(fw.x, 0.95);
          float rr = bh(cid + floor(vWPos.xz * 0.02) * 13.0 + vWNrm.xz * 7.0);
          vec3 glass = mix(vec3(0.1, 0.14, 0.2), vec3(0.32, 0.42, 0.52), rr * 0.6);
          diffuseColor.rgb = mix(diffuseColor.rgb, glass, (win + shop) * 0.85);
          diffuseColor.rgb *= 1.0 - (1.0 - wall) * 0.35;
          float lit = win * step(0.62, rr) * (0.55 + 0.45 * fract(rr * 7.3)) + shop * step(0.3, rr) * 0.8;
          vec3 wcol = mix(vec3(1.0, 0.68, 0.34), vec3(0.55, 0.78, 1.0), step(0.86, rr));`)
          .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
          totalEmissiveRadiance += lit * wcol * uNight * 0.6;`);
    };
    return mat;
  }

  addBuilding(x0, z0, x1, z1, h) {
    const b = { x0, z0, x1, z1, h };
    this.buildings.push(b);
    const g0x = Math.floor((x0 + HALF) / 50), g1x = Math.floor((x1 + HALF) / 50);
    const g0z = Math.floor((z0 + HALF) / 50), g1z = Math.floor((z1 + HALF) / 50);
    for (let gx = g0x; gx <= g1x; gx++)
      for (let gz = g0z; gz <= g1z; gz++) {
        const k = gx * 1000 + gz;
        let arr = this.bGrid.get(k);
        if (!arr) this.bGrid.set(k, (arr = []));
        arr.push(b);
      }
  }

  // ---------------------------------------------------------------- road meshes
  buildRoadMeshes() {
    const aniso = this.q.aniso;
    const texHwy = TX.roadTexture('hwy', aniso);
    const texPass = TX.roadTexture('pass', aniso);
    const mk = (map) => new THREE.MeshLambertMaterial({ map, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -4 });
    const mats = { hwy: mk(texHwy), link: mk(this.roadTexCity), pass: mk(texPass) };
    const lift = { hwy: 0.16, link: 0.13, pass: 0.12 };
    for (const r of this.roads) {
      const pts = r.pts;
      const n = pts.length;
      const K = r.type === 'pass' ? 2 : 4;
      const tile = r.hw * 4;
      const total = r.closed ? n + 1 : n;
      let dist = 0;
      const rows = [];
      for (let i = 0; i < total; i++) {
        const p = pts[i % n];
        const pp = pts[r.closed ? (i - 1 + n) % n : Math.max(i - 1, 0)];
        const pn = pts[r.closed ? (i + 1) % n : Math.min(i + 1, n - 1)];
        let tx = pn.x - pp.x, tz = pn.z - pp.z;
        const tl = Math.hypot(tx, tz) || 1;
        tx /= tl; tz /= tl;
        const lx = tz, lz = -tx;
        if (i > 0) { const q = pts[(i - 1) % n]; dist += Math.hypot(p.x - q.x, p.z - q.z); }
        const row = [];
        for (let k = 0; k <= K; k++) {
          const o = lerp(r.hw, -r.hw, k / K);
          const x = p.x + lx * o, z = p.z + lz * o;
          row.push([x, this.ground(x, z) + lift[r.type], z, k / K, dist / tile]);
        }
        rows.push(row);
      }
      // Chunk for frustum culling.
      const CH = 40;
      for (let s = 0; s < rows.length - 1; s += CH) {
        const e = Math.min(s + CH, rows.length - 1);
        const pos = [], uv = [];
        for (let i = s; i < e; i++) {
          for (let k = 0; k < K; k++) {
            const a = rows[i][k], b = rows[i][k + 1], c = rows[i + 1][k], d = rows[i + 1][k + 1];
            for (const v of [a, b, c, b, d, c]) { pos.push(v[0], v[1], v[2]); uv.push(v[3], v[4]); }
          }
        }
        this.scene.add(this.flatMesh(pos, uv, mats[r.type]));
      }
      if (r.type === 'pass') this.buildGuardrails(r, rows);
    }
  }

  // Low guard rails on the mountain pass (visual only, cars are never blocked).
  buildGuardrails(r, rows) {
    const pos = [];
    const add = (a, b) => {
      const h0 = 0.45, h1 = 0.85;
      const quad = [[a[0], a[1] + h0, a[2]], [b[0], b[1] + h0, b[2]], [b[0], b[1] + h1, b[2]], [a[0], a[1] + h1, a[2]]];
      for (const t of [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]) pos.push(...quad[t]);
    };
    for (let i = 0; i < rows.length - 1; i++) {
      const K = rows[i].length - 1;
      for (const k of [0, K]) {
        const a = rows[i][k], b = rows[i + 1][k];
        const off = k === 0 ? 1.2 : -1.2;
        const p = this.offsetRow(rows, i, k, off), q = this.offsetRow(rows, i + 1, k, off);
        if (a && b) add(p, q);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.computeVertexNormals();
    const m = new THREE.Mesh(g, new THREE.MeshLambertMaterial({ color: 0xb8bcc2 }));
    m.matrixAutoUpdate = false;
    this.scene.add(m);
  }

  offsetRow(rows, i, k, off) {
    const row = rows[i];
    const a = row[k], c = row[Math.floor(row.length / 2)];
    const dx = a[0] - c[0], dz = a[2] - c[2];
    const l = Math.hypot(dx, dz) || 1;
    const x = a[0] + (dx / l) * Math.abs(off), z = a[2] + (dz / l) * Math.abs(off);
    return [x, this.ground(x, z) - 0.1, z];
  }

  // ---------------------------------------------------------------- vegetation
  buildTrees() {
    const R = mulberry32(77);
    const trunk = colorize(new THREE.CylinderGeometry(0.22, 0.3, 2.4, 5).translate(0, 1.2, 0), 0x4a3424);
    const c1 = colorize(new THREE.ConeGeometry(2.2, 4.2, 7).translate(0, 4.0, 0), 0x2f5a26);
    const c2 = colorize(new THREE.ConeGeometry(1.6, 3.4, 7).translate(0, 6.0, 0), 0x3a6b2c);
    const geo = mergeGeometries([trunk, c1, c2]);
    const list = [...this.parkTrees];
    const max = Math.floor(5000 * this.q.trees);
    const step = 15 / Math.sqrt(this.q.trees);
    for (let z = -HALF + 40; z < HALF - 40 && list.length < max; z += step) {
      for (let x = -HALF + 40; x < HALF - 40 && list.length < max; x += step) {
        const px = x + (R() - 0.5) * step, pz = z + (R() - 0.5) * step;
        if (Math.abs(px) < 520 && Math.abs(pz) < 520) continue;
        const dens = fbm(px * 0.004, pz * 0.004, 3);
        if (dens < -0.02 || R() > 0.75) continue;
        const h = this.ground(px, pz);
        if (h < WATER_Y + 2 || h > 200) continue;
        const sl = Math.abs(this.ground(px + 3, pz) - h) + Math.abs(this.ground(px, pz + 3) - h);
        if (sl > 3.5) continue;
        const q = this.roadQuery(px, pz);
        if (q && q.edge < 7) continue;
        list.push({ x: px, z: pz, y: h - 0.2, s: 0.7 + R() * 0.9 });
      }
    }
    const mat = new THREE.MeshLambertMaterial({ vertexColors: true });
    // Split into spatial clusters so off-screen trees get culled.
    const buckets = new Map();
    for (const t of list) {
      const k = Math.floor((t.x + HALF) / 512) * 100 + Math.floor((t.z + HALF) / 512);
      if (!buckets.has(k)) buckets.set(k, []);
      buckets.get(k).push(t);
    }
    const m4 = new THREE.Matrix4(), qt = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0);
    const col = new THREE.Color();
    for (const arr of buckets.values()) {
      const im = new THREE.InstancedMesh(geo, mat, arr.length);
      arr.forEach((t, i) => {
        qt.setFromAxisAngle(up, R() * 6.28);
        m4.compose(new THREE.Vector3(t.x, t.y, t.z), qt, new THREE.Vector3(t.s, t.s * (0.85 + R() * 0.4), t.s));
        im.setMatrixAt(i, m4);
        im.setColorAt(i, col.setHSL(0.25 + R() * 0.08, 0.5, 0.45 + R() * 0.25));
      });
      im.computeBoundingSphere();
      im.castShadow = this.q.shadows;
      this.scene.add(im);
    }
    this.treeCount = list.length;
  }

  // ---------------------------------------------------------------- street lights
  buildLamps() {
    const lamps = [];
    for (const s of STREETS) {
      for (let t = -CITY_EDGE + 25; t < CITY_EDGE - 10; t += 36) {
        if (STREETS.some((q) => Math.abs(q - t) < 14)) continue;
        lamps.push({ x: s - 10.5, z: t, ax: 1, az: 0, y: 0.07 });
        lamps.push({ x: s + 10.5, z: t + 18, ax: -1, az: 0, y: 0.07 });
        lamps.push({ x: t, z: s - 10.5, ax: 0, az: 1, y: 0.07 });
        lamps.push({ x: t + 18, z: s + 10.5, ax: 0, az: -1, y: 0.07 });
      }
    }
    for (const r of this.roads) {
      if (r.type === 'pass') continue;
      const every = r.type === 'hwy' ? 7 : 5;
      for (let i = 0; i < r.pts.length - 1; i += every) {
        const p = r.pts[i], q = r.pts[i + 1];
        let tx = q.x - p.x, tz = q.z - p.z;
        const l = Math.hypot(tx, tz) || 1;
        tx /= l; tz /= l;
        const side = (i / every) % 2 === 0 ? 1 : -1;
        const lx = tz * side, lz = -tx * side;
        const x = p.x + lx * (r.hw + 1.6), z = p.z + lz * (r.hw + 1.6);
        lamps.push({ x, z, ax: -lx, az: -lz, y: this.ground(x, z) });
      }
    }
    const pole = colorize(new THREE.CylinderGeometry(0.12, 0.16, 8, 6).translate(0, 4, 0), 0x3b3f45);
    const arm = colorize(new THREE.BoxGeometry(0.14, 0.14, 2.6).translate(0, 7.9, 1.2), 0x3b3f45);
    const head = colorize(new THREE.BoxGeometry(0.5, 0.18, 0.9).translate(0, 7.8, 2.4), 0x2a2d31);
    const geo = mergeGeometries([pole, arm, head]);
    const im = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true }), lamps.length);
    const bulbGeo = new THREE.BoxGeometry(0.4, 0.08, 0.7);
    const bulbMat = new THREE.MeshBasicMaterial({ color: 0x555555, toneMapped: false });
    const bulbs = new THREE.InstancedMesh(bulbGeo, bulbMat, lamps.length);
    const glowGeo = new THREE.PlaneGeometry(16, 16).rotateX(-Math.PI / 2);
    const glowMat = new THREE.MeshBasicMaterial({
      map: TX.glowTexture('rgba(255,210,150,0.55)', 'rgba(255,170,90,0)'), transparent: true,
      blending: THREE.AdditiveBlending, depthWrite: false, opacity: 0,
      polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -8,
    });
    const glows = new THREE.InstancedMesh(glowGeo, glowMat, lamps.length);
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0);
    const one = new THREE.Vector3(1, 1, 1);
    lamps.forEach((L, i) => {
      const ang = Math.atan2(L.ax, L.az);
      q.setFromAxisAngle(up, ang);
      m4.compose(new THREE.Vector3(L.x, L.y, L.z), q, one);
      im.setMatrixAt(i, m4);
      const hx = L.x + L.ax * 2.4, hz = L.z + L.az * 2.4;
      m4.compose(new THREE.Vector3(hx, L.y + 7.68, hz), q, one);
      bulbs.setMatrixAt(i, m4);
      const gx = L.x + L.ax * 3.5, gz = L.z + L.az * 3.5;
      m4.makeTranslation(gx, this.ground(gx, gz) + 0.3, gz);
      glows.setMatrixAt(i, m4);
    });
    for (const m of [im, bulbs, glows]) { m.computeBoundingSphere(); this.scene.add(m); }
    glows.renderOrder = 2;
    this.lampBulbMat = bulbMat;
    this.lampGlow = glows;
    this.lampGlowMat = glowMat;
  }

  // Day/night response of world materials.
  setNight(n) {
    this.neonMat.color.setScalar(0.25 + n * 1.6);
    this.lampBulbMat.color.setRGB(0.35 + n * 2.2, 0.33 + n * 1.8, 0.3 + n * 1.2);
    this.lampGlowMat.opacity = n;
    this.lampGlow.visible = n > 0.02;
  }

  update(dt) {
    this.waterNormal.offset.x += dt * 0.004;
    this.waterNormal.offset.y += dt * 0.0025;
  }

  // ---------------------------------------------------------------- road graph
  buildGraph() {
    const nodes = this.nodes;
    const add = (x, z, type) => { nodes.push({ x, z, type, adj: [], id: nodes.length }); return nodes.length - 1; };
    const link = (a, b) => {
      if (a === b) return;
      if (!nodes[a].adj.includes(b)) nodes[a].adj.push(b);
      if (!nodes[b].adj.includes(a)) nodes[b].adj.push(a);
    };
    const S = STREETS.length;
    const cityId = (i, j) => i * S + j;
    for (let i = 0; i < S; i++) for (let j = 0; j < S; j++) add(STREETS[i], STREETS[j], 'city');
    for (let i = 0; i < S; i++) for (let j = 0; j < S; j++) {
      if (i + 1 < S) link(cityId(i, j), cityId(i + 1, j));
      if (j + 1 < S) link(cityId(i, j), cityId(i, j + 1));
    }
    const nearestCity = (x, z) => {
      let b = 0, bd = Infinity;
      for (let k = 0; k < S * S; k++) { const d = (nodes[k].x - x) ** 2 + (nodes[k].z - z) ** 2; if (d < bd) { bd = d; b = k; } }
      return b;
    };
    const roadNodes = new Map();
    for (const r of this.roads) {
      if (r.type !== 'hwy') continue;
      const ids = [];
      for (let i = 0; i < r.pts.length; i += 3) ids.push(add(r.pts[i].x, r.pts[i].z, r.type));
      for (let i = 0; i < ids.length - 1; i++) link(ids[i], ids[i + 1]);
      link(ids[ids.length - 1], ids[0]);
      roadNodes.set(r, ids);
    }
    const ringIds = roadNodes.get(this.ring);
    const nearestRing = (x, z) => {
      let b = ringIds[0], bd = Infinity;
      for (const k of ringIds) { const d = (nodes[k].x - x) ** 2 + (nodes[k].z - z) ** 2; if (d < bd) { bd = d; b = k; } }
      return b;
    };
    for (const r of this.roads) {
      if (r.type === 'hwy') continue;
      const ids = [];
      const pts = r.pts;
      for (let i = 0; i < pts.length; i += 3) ids.push(add(pts[i].x, pts[i].z, r.type));
      const lastI = pts.length - 1;
      if ((lastI % 3) !== 0) ids.push(add(pts[lastI].x, pts[lastI].z, r.type));
      for (let i = 0; i < ids.length - 1; i++) link(ids[i], ids[i + 1]);
      const first = nodes[ids[0]], last = nodes[ids[ids.length - 1]];
      if (r.type === 'link') {
        link(nearestCity(first.x, first.z), ids[0]);
      } else {
        link(nearestRing(first.x, first.z), ids[0]);
      }
      link(nearestRing(last.x, last.z), ids[ids.length - 1]);
    }
  }

  nearestNode(x, z, types) {
    let b = -1, bd = Infinity;
    for (const n of this.nodes) {
      if (types && !types.includes(n.type)) continue;
      const d = (n.x - x) ** 2 + (n.z - z) ** 2;
      if (d < bd) { bd = d; b = n.id; }
    }
    return b;
  }

  // Dijkstra shortest path over allowed road types.
  route(a, b, types) {
    const nodes = this.nodes;
    const dist = new Float64Array(nodes.length).fill(Infinity);
    const prev = new Int32Array(nodes.length).fill(-1);
    const heap = [[0, a]];
    dist[a] = 0;
    const push = (item) => {
      heap.push(item);
      let i = heap.length - 1;
      while (i > 0) {
        const p = (i - 1) >> 1;
        if (heap[p][0] <= heap[i][0]) break;
        [heap[p], heap[i]] = [heap[i], heap[p]];
        i = p;
      }
    };
    const pop = () => {
      const top = heap[0];
      const last = heap.pop();
      if (heap.length) {
        heap[0] = last;
        let i = 0;
        for (;;) {
          const l = i * 2 + 1, r = l + 1;
          let m = i;
          if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
          if (r < heap.length && heap[r][0] < heap[m][0]) m = r;
          if (m === i) break;
          [heap[m], heap[i]] = [heap[i], heap[m]];
          i = m;
        }
      }
      return top;
    };
    while (heap.length) {
      const [d, u] = pop();
      if (u === b) break;
      if (d > dist[u]) continue;
      for (const v of nodes[u].adj) {
        if (types && !types.includes(nodes[v].type)) continue;
        const nd = d + Math.hypot(nodes[u].x - nodes[v].x, nodes[u].z - nodes[v].z);
        if (nd < dist[v]) { dist[v] = nd; prev[v] = u; push([nd, v]); }
      }
    }
    const path = [];
    for (let u = b; u !== -1; u = prev[u]) path.push(u);
    path.reverse();
    return path[0] === a ? path : [a, b];
  }

  // Safe spot on the nearest road to respawn a car.
  respawnAt(x, z) {
    const id = this.nearestNode(x, z);
    const n = this.nodes[id];
    const nb = this.nodes[n.adj[0]];
    let best = nb, bestDot = -Infinity;
    for (const k of n.adj) {
      // Prefer the neighbour that keeps the car heading roughly away from where it came from.
      const m = this.nodes[k];
      const dot = (m.x - n.x) * (n.x - x) + (m.z - n.z) * (n.z - z);
      if (dot > bestDot) { bestDot = dot; best = m; }
    }
    const yaw = Math.atan2(best.x - n.x, best.z - n.z);
    // Shift into the right-hand lane.
    const rx = -Math.cos(yaw), rz = Math.sin(yaw);
    const px = n.x + rx * 4, pz = n.z + rz * 4;
    return { x: px, z: pz, y: this.ground(px, pz), yaw };
  }

  // ---------------------------------------------------------------- collision
  // Pushes a circle out of buildings. Returns contact normal + depth or null.
  collideCircle(x, z, r) {
    const k = Math.floor((x + HALF) / 50) * 1000 + Math.floor((z + HALF) / 50);
    const arr = this.bGrid.get(k);
    if (!arr) return null;
    let res = null;
    for (const b of arr) {
      const cx = clamp(x, b.x0, b.x1), cz = clamp(z, b.z0, b.z1);
      let dx = x - cx, dz = z - cz;
      let d = Math.hypot(dx, dz);
      if (d >= r) continue;
      let depth, nx, nz;
      if (d < 1e-4) {
        // Centre inside the box: push out along the shallowest axis.
        const l = x - b.x0, rr = b.x1 - x, t = z - b.z0, bt = b.z1 - z;
        const m = Math.min(l, rr, t, bt);
        if (m === l) { nx = -1; nz = 0; depth = l + r; }
        else if (m === rr) { nx = 1; nz = 0; depth = rr + r; }
        else if (m === t) { nx = 0; nz = -1; depth = t + r; }
        else { nx = 0; nz = 1; depth = bt + r; }
      } else {
        nx = dx / d; nz = dz / d; depth = r - d;
      }
      if (!res || depth > res.depth) res = { nx, nz, depth };
    }
    return res;
  }

  // ---------------------------------------------------------------- minimap
  buildMapImage() {
    const S = 1024;
    const c = document.createElement('canvas');
    c.width = c.height = S;
    const ctx = c.getContext('2d');
    const img = ctx.createImageData(S, S);
    for (let y = 0; y < S; y++) {
      for (let x = 0; x < S; x++) {
        const wx = -HALF + (x / S) * HALF * 2, wz = -HALF + (y / S) * HALF * 2;
        const h = this.ground(wx, wz);
        const i = (y * S + x) * 4;
        if (h < WATER_Y) { img.data[i] = 14; img.data[i + 1] = 44; img.data[i + 2] = 66; }
        else {
          const v = clamp(30 + h * 0.35, 30, 110);
          img.data[i] = v * 0.55; img.data[i + 1] = v * 0.7; img.data[i + 2] = v * 0.55;
        }
        img.data[i + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);
    const tm = (v) => ((v + HALF) / (HALF * 2)) * S;
    ctx.fillStyle = '#2b2f36';
    ctx.fillRect(tm(-470), tm(-470), tm(470) - tm(-470), tm(470) - tm(-470));
    ctx.fillStyle = '#4b525c';
    for (const b of this.buildings) ctx.fillRect(tm(b.x0), tm(b.z0), tm(b.x1) - tm(b.x0), tm(b.z1) - tm(b.z0));
    ctx.lineCap = 'round';
    ctx.strokeStyle = '#d9dde3';
    ctx.lineWidth = 4;
    for (const s of STREETS) {
      ctx.beginPath(); ctx.moveTo(tm(s), tm(-CITY_EDGE)); ctx.lineTo(tm(s), tm(CITY_EDGE)); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(tm(-CITY_EDGE), tm(s)); ctx.lineTo(tm(CITY_EDGE), tm(s)); ctx.stroke();
    }
    for (const r of this.roads) {
      ctx.strokeStyle = r.type === 'hwy' ? '#ffcf5a' : r.type === 'pass' ? '#f0f0f0' : '#d9dde3';
      ctx.lineWidth = r.type === 'hwy' ? 6 : 4;
      ctx.beginPath();
      r.pts.forEach((p, i) => (i ? ctx.lineTo(tm(p.x), tm(p.z)) : ctx.moveTo(tm(p.x), tm(p.z))));
      if (r.closed) ctx.closePath();
      ctx.stroke();
    }
    this.mapImage = c;
  }
}

const PAVED = { grip: 1, drag: 0, offroad: false };
const SHOULDER = { grip: 0.85, drag: 0.15, offroad: false };
const GRASS = { grip: 0.68, drag: 0.6, offroad: true };
const SAND = { grip: 0.6, drag: 1.2, offroad: true };
