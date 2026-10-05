// Race paths (racing line + speed profile) and the AI driver that follows them
// using the same vehicle physics and inputs as the player.
import { clamp, lerp, wrapAngle } from './utils.js';

const SPACING = 3;

export class RacePath {
  // pts: [{x,z}] polyline along road centres
  constructor(rawPts, closed) {
    this.closed = closed;
    const pts = resample(rawPts, SPACING, closed);
    this.center = pts;
    this.n = pts.length;
    this.line = smoothLine(pts, closed, 7, 3);
    this.cum = [0];
    for (let i = 1; i < this.n; i++) this.cum.push(this.cum[i - 1] + dist(pts[i - 1], pts[i]));
    this.len = this.cum[this.n - 1] + (closed ? dist(pts[this.n - 1], pts[0]) : 0);
    this.curv = new Float32Array(this.n);
    const k = 4;
    for (let i = 0; i < this.n; i++) {
      const a = this.at(i - k, true), b = this.line[i], c = this.at(i + k, true);
      this.curv[i] = curvature(a, b, c);
    }
  }

  idx(i) {
    if (this.closed) return ((i % this.n) + this.n) % this.n;
    return clamp(i, 0, this.n - 1);
  }

  at(i, line = false) {
    return (line ? this.line : this.center)[this.idx(i)];
  }

  dir(i) {
    const a = this.at(i), b = this.at(i + 1 >= this.n && !this.closed ? i : i + 1);
    const c = this.at(i - 1);
    const dx = (b.x - c.x), dz = (b.z - c.z);
    const l = Math.hypot(dx, dz) || 1;
    return { x: dx / l, z: dz / l, yaw: Math.atan2(dx, dz), a };
  }

  // Nearest index searching a window around a hint.
  nearest(x, z, hint, back = 8, ahead = 60) {
    let best = hint, bd = Infinity;
    for (let k = -back; k <= ahead; k++) {
      const i = this.idx(hint + k);
      const p = this.center[i];
      const d = (p.x - x) ** 2 + (p.z - z) ** 2;
      if (d < bd) { bd = d; best = i; }
    }
    return { i: best, d: Math.sqrt(bd) };
  }

  nearestGlobal(x, z) {
    let best = 0, bd = Infinity;
    for (let i = 0; i < this.n; i++) {
      const p = this.center[i];
      const d = (p.x - x) ** 2 + (p.z - z) ** 2;
      if (d < bd) { bd = d; best = i; }
    }
    return best;
  }

  // Max speed profile for a given lateral grip and braking capability.
  speedProfile(grip, brake, top) {
    const v = new Float32Array(this.n);
    for (let i = 0; i < this.n; i++) {
      const c = Math.max(this.curv[i], 1e-4);
      v[i] = Math.min(Math.sqrt(grip / c), top);
    }
    const passes = this.closed ? 2 : 1;
    for (let p = 0; p < passes; p++) {
      for (let i = this.n - 2 + (this.closed ? 1 : 0); i >= 0; i--) {
        const j = this.idx(i + 1);
        v[i] = Math.min(v[i], Math.sqrt(v[j] * v[j] + 2 * brake * SPACING));
      }
    }
    return v;
  }
}

function dist(a, b) { return Math.hypot(a.x - b.x, a.z - b.z); }

function resample(pts, step, closed) {
  const out = [];
  const src = closed ? [...pts, pts[0]] : pts;
  let carry = 0;
  out.push({ x: src[0].x, z: src[0].z });
  for (let i = 0; i < src.length - 1; i++) {
    const a = src[i], b = src[i + 1];
    const L = dist(a, b);
    let t = step - carry;
    while (t <= L) {
      out.push({ x: lerp(a.x, b.x, t / L), z: lerp(a.z, b.z, t / L) });
      t += step;
    }
    carry = L - (t - step);
  }
  if (!closed) {
    const last = src[src.length - 1];
    if (dist(out[out.length - 1], last) > 0.5) out.push({ x: last.x, z: last.z });
  } else if (dist(out[out.length - 1], out[0]) < step * 0.5) out.pop();
  return out;
}

function smoothLine(pts, closed, win, iters) {
  let cur = pts.map((p) => ({ x: p.x, z: p.z }));
  const n = pts.length;
  for (let it = 0; it < iters; it++) {
    const next = [];
    for (let i = 0; i < n; i++) {
      let sx = 0, sz = 0, c = 0;
      for (let k = -win; k <= win; k++) {
        let j = i + k;
        if (closed) j = ((j % n) + n) % n; else j = clamp(j, 0, n - 1);
        sx += cur[j].x; sz += cur[j].z; c++;
      }
      next.push({ x: sx / c, z: sz / c });
    }
    cur = next;
  }
  // Keep the racing line within ~5.5m of the centre so cars stay on the road.
  for (let i = 0; i < n; i++) {
    const dx = cur[i].x - pts[i].x, dz = cur[i].z - pts[i].z;
    const d = Math.hypot(dx, dz);
    if (d > 5.5) { cur[i].x = pts[i].x + (dx / d) * 5.5; cur[i].z = pts[i].z + (dz / d) * 5.5; }
  }
  return cur;
}

function curvature(a, b, c) {
  const ab = dist(a, b), bc = dist(b, c), ca = dist(c, a);
  const area2 = Math.abs((b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x));
  if (ab * bc * ca < 1e-6) return 0;
  return (2 * area2) / (ab * bc * ca);
}

export class AIDriver {
  constructor(vehicle, path, skill, laneOffset) {
    this.v = vehicle;
    this.path = path;
    this.skill = skill;
    this.lane = laneOffset;
    this.idx = 0;
    this.stuck = 0;
    this.lap = 0;
    this.progress = 0;
    this.finished = false;
    this.nitroBias = Math.random();
    this.refreshProfile();
  }

  refreshProfile() {
    const st = this.v.stats;
    this.profile = this.path.speedProfile(st.grip * 0.9 * this.skill, Math.min(st.brake, st.grip) * 0.75, st.top * 1.1);
  }

  // others: array of vehicles to avoid
  drive(dt, others, frozen) {
    const v = this.v, p = this.path;
    const prevIdx = this.idx;
    const near = p.nearest(v.x, v.z, this.idx, 10, 50);
    this.idx = near.i;
    if (p.closed && prevIdx > p.n * 0.8 && this.idx < p.n * 0.2) this.lap++;
    this.progress = this.lap * p.len + p.cum[this.idx];

    const look = 7 + v.speed * 0.42;
    const ti = this.idx + Math.round(look / SPACING);
    const tgt = p.at(ti, true);
    const d = p.dir(ti);
    // Lane offset to spread cars, plus avoidance of cars directly ahead.
    let off = this.lane;
    const fx = Math.sin(v.yaw), fz = Math.cos(v.yaw);
    const lx = Math.cos(v.yaw), lz = -Math.sin(v.yaw);
    for (const o of others) {
      if (o === v) continue;
      const dx = o.x - v.x, dz = o.z - v.z;
      const ahead = dx * fx + dz * fz, side = dx * lx + dz * lz;
      if (ahead > 0 && ahead < 14 + v.speed * 0.3 && Math.abs(side) < 2.4 && v.speed > o.speed - 1) {
        off += side > 0 ? -3 : 3;
        break;
      }
    }
    const llx = d.z, llz = -d.x; // left of path direction
    const tx = tgt.x + llx * off - v.x, tz = tgt.z + llz * off - v.z;
    const fwd = tx * fx + tz * fz, left = tx * lx + tz * lz;
    const ang = Math.atan2(left, Math.max(fwd, 0.1));
    let steer = clamp(-ang * 2.4 + v.w * 0.08, -1, 1);

    // Speed control from the precomputed profile, looking ahead for braking.
    let vt = Infinity;
    const ahead = Math.round((v.speed * 0.5) / SPACING) + 2;
    for (let k = 0; k < ahead; k += 2) vt = Math.min(vt, this.profile[p.idx(this.idx + k)]);
    // Ease off if steering hard (we are off the line).
    vt *= 1 - Math.min(Math.abs(ang), 0.6) * 0.5;
    let throttle = 0, brake = 0;
    const err = vt - v.speed;
    if (err > 1.5) throttle = 1;
    else if (err > -1) throttle = 0.4 + err * 0.2;
    else brake = clamp(-err / 6, 0.2, 1);
    const nitro = err > 12 && Math.abs(ang) < 0.08 && v.nitro > 0.15 && this.nitroBias < 0.85;

    if (frozen) { throttle = 0; brake = 1; steer = 0; }
    if (!p.closed && this.idx >= p.n - 2) { throttle = 0; brake = 0.5; }

    // Stuck / lost recovery
    if (!frozen && (v.speed < 2 || near.d > 30)) this.stuck += dt; else this.stuck = Math.max(0, this.stuck - dt);
    if (this.stuck > 3) {
      this.stuck = 0;
      const q = p.at(this.idx + 3);
      const dd = p.dir(this.idx + 3);
      v.reset(q.x, v.y, q.z, dd.yaw);
      v.vx = dd.x * 12; v.vz = dd.z * 12;
    }
    return { throttle, brake, steer, handbrake: 0, nitro, assist: true };
  }
}

export function angleTo(v, x, z) {
  return wrapAngle(Math.atan2(x - v.x, z - v.z) - v.yaw);
}
