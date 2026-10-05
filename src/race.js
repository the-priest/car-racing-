// Race events: start markers, grids, checkpoints, AI rivals, standings, rewards.
import * as THREE from 'three';
import { RACES, CARS, STYLES } from './config.js';
import { RacePath, AIDriver } from './ai.js';
import { Vehicle } from './physics.js';
import { buildCar } from './carmodel.js';
import { clamp, mulberry32 } from './utils.js';

const TYPE_COLOR = { circuit: 0xff7a1a, sprint: 0x19c8ff, drift: 0xff2fa0 };
const NIGHT_COLOR = 0xa04dff;

function beamMaterial(color) {
  const c = document.createElement('canvas');
  c.width = 4; c.height = 128;
  const ctx = c.getContext('2d');
  const g = ctx.createLinearGradient(0, 0, 0, 128);
  g.addColorStop(0, 'rgba(255,255,255,0)');
  g.addColorStop(0.7, 'rgba(255,255,255,0.35)');
  g.addColorStop(1, 'rgba(255,255,255,0.9)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 4, 128);
  return new THREE.MeshBasicMaterial({
    map: new THREE.CanvasTexture(c), color, transparent: true, blending: THREE.AdditiveBlending,
    depthWrite: false, side: THREE.DoubleSide, toneMapped: false, fog: false,
  });
}

export class RaceManager {
  constructor(game) {
    this.g = game;
    this.active = null;
    this.markers = [];
    this.gates = [];
    this.buildMarkers();
    this.buildGates();
  }

  pathFor(def) {
    if (def._path) return def._path;
    const W = this.g.world;
    const ids = def.pts.map(([x, z]) => W.nearestNode(x, z, def.roads));
    let route = [];
    const loop = def.type === 'circuit' || !!def.loop;
    const legs = loop ? [...ids, ids[0]] : ids;
    for (let i = 0; i < legs.length - 1; i++) {
      const leg = W.route(legs[i], legs[i + 1], def.roads);
      route.push(...(route.length ? leg.slice(1) : leg));
    }
    if (loop) route.pop();
    const pts = route.map((id) => ({ x: W.nodes[id].x, z: W.nodes[id].z }));
    def._path = new RacePath(pts, def.type === 'circuit' || !!def.loop);
    return def._path;
  }

  buildMarkers() {
    const W = this.g.world;
    for (const def of RACES) {
      const path = this.pathFor(def);
      const p = path.at(4);
      const color = def.night ? NIGHT_COLOR : TYPE_COLOR[def.type];
      const g = new THREE.Group();
      const beamMat = beamMaterial(color);
      const beam = new THREE.Mesh(new THREE.CylinderGeometry(3.2, 3.2, 140, 20, 1, true), beamMat);
      beam.position.y = 70;
      const ring = new THREE.Mesh(new THREE.RingGeometry(5, 6.2, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({
        color, transparent: true, opacity: 0.8, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false,
      }));
      ring.position.y = 0.3;
      g.add(beam, ring);
      g.position.set(p.x, W.ground(p.x, p.z), p.z);
      this.g.scene.add(g);
      this.markers.push({ def, group: g, x: p.x, z: p.z, ring, color, beamMat });
    }
  }

  buildGates() {
    const mat = beamMaterial(0x26e0ff);
    const matNext = beamMaterial(0xffb020);
    for (let i = 0; i < 2; i++) {
      const g = new THREE.Group();
      const m = i === 0 ? matNext : mat;
      const l = new THREE.Mesh(new THREE.CylinderGeometry(0.6, 0.6, 14, 10, 1, true), m);
      const r = l.clone();
      const top = new THREE.Mesh(new THREE.BoxGeometry(1, 0.5, 0.5), new THREE.MeshBasicMaterial({ color: i === 0 ? 0xffb020 : 0x26e0ff, toneMapped: false }));
      g.add(l, r, top);
      g.visible = false;
      g.userData = { l, r, top };
      this.g.scene.add(g);
      this.gates.push(g);
    }
  }

  placeGate(gate, i, final) {
    const W = this.g.world;
    const path = this.active.path;
    const p = path.at(i), d = path.dir(i);
    const q = W.roadQuery(p.x, p.z);
    const hw = (q ? q.hw : 9) + 1.5;
    const lx = d.z, lz = -d.x;
    const y = W.ground(p.x, p.z);
    const u = gate.userData;
    u.l.position.set(lx * hw, 7, lz * hw);
    u.r.position.set(-lx * hw, 7, -lz * hw);
    u.top.scale.set(hw * 2, 1, 1);
    u.top.position.set(0, 13.5, 0);
    u.top.rotation.y = d.yaw + Math.PI / 2;
    u.top.material.color.set(final ? 0xffffff : gate === this.gates[0] ? 0xffb020 : 0x26e0ff);
    gate.position.set(p.x, y, p.z);
    gate.visible = true;
  }

  available(def) {
    return !def.night || this.g.sky.night > 0.5;
  }

  // Nearby event marker for the "start race" prompt.
  nearbyEvent(v) {
    if (this.active) return null;
    for (const m of this.markers) {
      if (Math.hypot(m.x - v.x, m.z - v.z) < 14) return m.def;
    }
    return null;
  }

  update(dt, t) {
    const night = this.g.sky.night;
    for (const m of this.markers) {
      const vis = !this.active && (!m.def.night || night > 0.5);
      m.beamMat.opacity = 0.35 + night * 0.65;
      m.group.visible = vis;
      m.ring.rotation.y = t * 0.6;
      m.ring.scale.setScalar(1 + Math.sin(t * 3) * 0.06);
    }
    if (!this.active) return;
    const R = this.active;
    const v = this.g.player;
    R.time += dt;
    if (R.countdown > 0) {
      const before = Math.ceil(R.countdown);
      R.countdown -= dt;
      const after = Math.ceil(R.countdown);
      if (after !== before) {
        if (after > 0) { this.g.hud.big(String(after), 0.9); this.g.audio.beep(520, 0.18); }
        else { this.g.hud.big('GO!', 1.0); this.g.audio.beep(1040, 0.4); R.time = 0; }
      }
      if (R.countdown > 0) return;
    }
    if (R.done) return;
    R.raceTime += dt;

    // Player progress along the route
    const path = R.path;
    const prev = R.pIdx;
    const near = path.nearest(v.x, v.z, R.pIdx, 12, 60);
    R.pIdx = near.i;
    if (path.closed && prev > path.n * 0.85 && R.pIdx < path.n * 0.15) {
      if (R.nextCp >= R.cps.length) { R.lap++; R.nextCp = 0; if (R.lap < R.laps) this.g.hud.toast(`LAP ${R.lap + 1}/${R.laps}`); }
      else R.pIdx = prev; // skipped checkpoints: don't count the lap
    }
    R.progress = R.lap * path.len + path.cum[R.pIdx];

    // Checkpoints
    if (R.nextCp < R.cps.length) {
      const ci = R.cps[R.nextCp];
      const cp = path.at(ci);
      const passed = Math.hypot(cp.x - v.x, cp.z - v.z) < 22 || (R.pIdx >= ci && R.pIdx - ci < 40 && near.d < 30);
      if (passed) {
        R.nextCp++;
        this.g.audio.beep(880, 0.08, 0.15);
        if (R.def.type !== 'drift') this.g.hud.toast('CHECKPOINT', 0.8);
      }
    }
    const lastLap = R.lap >= R.laps - 1;
    const finished = R.def.type === 'drift'
      ? R.raceTime >= R.def.time || (!path.closed && R.pIdx >= path.n - 3)
      : path.closed ? (R.lap >= R.laps) : (R.nextCp >= R.cps.length && R.pIdx >= path.n - 4);

    // Gates
    if (R.def.type !== 'drift') {
      if (R.nextCp < R.cps.length) {
        this.placeGate(this.gates[0], R.cps[R.nextCp], R.nextCp === R.cps.length - 1 && (lastLap || !path.closed));
        if (R.nextCp + 1 < R.cps.length) this.placeGate(this.gates[1], R.cps[R.nextCp + 1], false);
        else this.gates[1].visible = false;
      } else if (path.closed) {
        this.placeGate(this.gates[0], R.cps[0], lastLap);
        this.gates[1].visible = false;
      }
    }

    // Wrong way
    const d = path.dir(R.pIdx);
    const dot = Math.sin(v.yaw) * d.x + Math.cos(v.yaw) * d.z;
    R.wrong = dot < -0.4 && v.speed > 6 ? R.wrong + dt : 0;

    // Rivals
    for (const r of R.rivals) {
      if (!r.finished && ((path.closed && r.ai.lap >= R.laps) || (!path.closed && r.ai.idx >= path.n - 4))) {
        r.finished = true;
        r.time = R.raceTime;
      }
      // Rubber band: gentle, keeps races tight without cheating too much.
      const gap = R.progress - r.ai.progress;
      r.v.powerMul = 1 + clamp(gap / 500, -0.08, 0.12);
    }
    // Standings
    const entries = [{ me: true, prog: R.progress + (finished ? 1e7 : 0) }, ...R.rivals.map((r) => ({ r, prog: r.finished ? 1e7 + (1e5 - r.time) : r.ai.progress }))];
    entries.sort((a, b) => b.prog - a.prog);
    R.position = entries.findIndex((e) => e.me) + 1;

    if (finished) this.finish();
  }

  start(def) {
    const G = this.g;
    const path = this.pathFor(def);
    const v = G.player;
    const laps = def.type === 'circuit' ? def.laps : 1;
    const startIdx = 14;
    this.lastDef = def;
    const cps = [];
    const step = def.type === 'drift' ? 60 : 50;
    for (let i = startIdx + step; i < path.n - (path.closed ? 10 : 4); i += step) cps.push(i);
    if (!path.closed) cps.push(path.n - 4);
    else cps.push(path.n - 2);

    const R = (this.active = {
      def, path, laps, cps, nextCp: 0, lap: 0, pIdx: startIdx, progress: 0, countdown: 3.99, time: 0, raceTime: 0,
      rivals: [], position: 1, done: false, wrong: 0, startCash: G.save.cash,
    });
    G.drift.reset();
    // Grid: two columns, player on row 1
    const gridSlot = (k) => {
      const row = Math.floor(k / 2), col = k % 2 ? -1 : 1;
      const i = startIdx - row * 3;
      const p = path.at(i), d = path.dir(i);
      const lx = d.z, lz = -d.x;
      return { x: p.x + lx * col * 3, z: p.z + lz * col * 3, yaw: d.yaw };
    };
    const n = def.type === 'drift' ? 0 : def.ai;
    const playerSlot = n > 0 ? 2 : 0;
    const ps = gridSlot(playerSlot);
    v.reset(ps.x, G.world.ground(ps.x, ps.z), ps.z, ps.yaw);
    v.nitro = 1;
    const rnd = mulberry32((Date.now() & 0xffff) + 7);
    let slot = 0;
    for (let k = 0; k < n; k++) {
      if (slot === playerSlot) slot++;
      const s = gridSlot(slot++);
      const base = CARS[Math.floor(rnd() * CARS.length)];
      const st = { ...v.stats };
      const f = def.skill * (0.97 + rnd() * 0.06) + 0.06;
      st.accel *= f; st.top *= 0.98 + (f - 1) * 0.5; st.grip *= 0.97 + rnd() * 0.05;
      st.cyl = base.cyl; st.idle = base.idle; st.red = base.red; st.gears = base.gears;
      const style = STYLES[base.style];
      const rv = new Vehicle(st, style);
      rv.reset(s.x, G.world.ground(s.x, s.z), s.z, s.yaw);
      const colors = ['#e8e8ea', '#ffd400', '#2fd34a', '#ff2fa0', '#1f6bff', '#d4142b', '#19e3c6'];
      const model = buildCar(base.style, colors[k % colors.length]);
      G.scene.add(model);
      const ai = new AIDriver(rv, path, def.skill * (0.97 + rnd() * 0.05), (k % 3 - 1) * 2.2);
      ai.idx = path.nearestGlobal(s.x, s.z);
      R.rivals.push({ v: rv, model, ai, name: RIVAL_NAMES[k % RIVAL_NAMES.length], finished: false, time: Infinity });
    }
    G.hud.toast(def.name.toUpperCase(), 2.5);
    G.camera.snap = true;
  }

  finish() {
    const R = this.active;
    R.done = true;
    const G = this.g;
    let win, reward = 0, place = R.position;
    if (R.def.type === 'drift') {
      const score = G.drift.total + G.drift.chain;
      win = score >= R.def.target;
      reward = win ? R.def.reward : Math.round(R.def.reward * 0.15 * clamp(score / R.def.target, 0, 1));
      place = win ? 1 : 2;
      R.score = Math.round(score);
    } else {
      const mult = [1, 0.5, 0.3, 0.15, 0.1, 0.08][place - 1] ?? 0.05;
      reward = Math.round(R.def.reward * mult);
      win = place === 1;
    }
    if (G.sky.night > 0.5) reward = Math.round(reward * 1.5);
    G.save.cash += reward;
    const best = G.save.best[R.def.id];
    if (win && R.def.type !== 'drift' && (!best || R.raceTime < best)) G.save.best[R.def.id] = R.raceTime;
    if (win) G.save.wins = (G.save.wins || 0) + 1;
    G.persist();
    G.audio.beep(win ? 1320 : 440, 0.5, 0.2);
    G.ui.showResults({ def: R.def, place, total: R.rivals.length + 1, time: R.raceTime, reward, win, score: R.score, night: G.sky.night > 0.5 });
    this.cleanup();
  }

  cleanup() {
    const R = this.active;
    if (!R) return;
    for (const r of R.rivals) {
      this.g.scene.remove(r.model);
      const u = r.model.userData;
      u.paint.dispose();
      u.tailMat.dispose();
      u.body.traverse((o) => o.geometry?.dispose());
    }
    for (const gt of this.gates) gt.visible = false;
    this.active = null;
  }

  quit() {
    this.cleanup();
  }

  restart() {
    const def = this.active?.def || this.lastDef;
    this.cleanup();
    if (def) this.start(def);
  }

  rivals() {
    return this.active ? this.active.rivals : [];
  }
}

const RIVAL_NAMES = ['Nyx', 'Torque', 'Vega', 'Rook', 'Blaze', 'Kai', 'Mara'];
