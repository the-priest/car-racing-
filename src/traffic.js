// Ambient traffic driving the road graph. Traffic never blocks the player:
// contact just knocks the civilian car away.
import { buildTrafficCar } from './carmodel.js';
import { lerp, wrapAngle } from './utils.js';

const COLORS = [0xd8d8d8, 0x2a2a2a, 0x8b1a1a, 0x1c3f7a, 0x6e7378, 0xc9b27c, 0x2f5d3a, 0xf2f2f2, 0x5a2a6e, 0xb35a1f];
const STYLES = ['sedan', 'sedan', 'sedan', 'van', 'sport'];
const SPEED = { city: 13, link: 19, hwy: 25, pass: 14 };

export class Traffic {
  constructor(scene, world, count) {
    this.scene = scene;
    this.world = world;
    this.cars = [];
    this.count = count;
    this.candidates = world.nodes.filter((n) => n.type !== 'pass');
    for (let i = 0; i < count; i++) {
      const style = STYLES[i % STYLES.length];
      const model = buildTrafficCar(style, COLORS[i % COLORS.length]);
      scene.add(model);
      this.cars.push({ model, a: 0, b: 0, t: 0, speed: 0, yaw: 0, x: 0, z: 0, y: 0, knock: 0, vx: 0, vz: 0, spin: 0, active: false, len: 4.6 });
    }
  }

  setCount(n) {
    for (let i = 0; i < this.cars.length; i++) {
      const c = this.cars[i];
      c.disabled = i >= n;
      c.model.visible = !c.disabled && c.active;
    }
  }

  spawn(c, px, pz, minD, maxD) {
    for (let tries = 0; tries < 30; tries++) {
      const n = this.candidates[Math.floor(Math.random() * this.candidates.length)];
      const d = Math.hypot(n.x - px, n.z - pz);
      if (d < minD || d > maxD || !n.adj.length) continue;
      c.a = n.id;
      c.b = n.adj[Math.floor(Math.random() * n.adj.length)];
      c.t = Math.random() * 0.8;
      c.speed = SPEED[n.type] || 14;
      c.knock = 0;
      c.active = true;
      this.place(c, true);
      c.model.visible = true;
      return;
    }
    c.active = false;
    c.model.visible = false;
  }

  place(c, snap) {
    const W = this.world;
    const A = W.nodes[c.a], B = W.nodes[c.b];
    const dx = B.x - A.x, dz = B.z - A.z;
    const L = Math.hypot(dx, dz) || 1;
    const ux = dx / L, uz = dz / L;
    const lane = A.type === 'city' || A.type === 'link' ? 4.5 : A.type === 'hwy' ? 6 : 3;
    const rx = -uz, rz = ux; // right-hand lane
    const x = A.x + dx * c.t + rx * lane, z = A.z + dz * c.t + rz * lane;
    const yaw = Math.atan2(ux, uz);
    c.x = x; c.z = z;
    c.yaw = snap ? yaw : c.yaw + wrapAngle(yaw - c.yaw) * 0.15;
    c.edgeLen = L;
  }

  update(dt, player, others) {
    const W = this.world;
    for (const c of this.cars) {
      if (c.disabled) continue;
      const dp = Math.hypot(c.x - player.x, c.z - player.z);
      if (!c.active || dp > 520) { this.spawn(c, player.x, player.z, 160, 450); continue; }

      if (c.knock > 0) {
        // Sliding after being hit
        c.knock -= dt;
        c.x += c.vx * dt; c.z += c.vz * dt;
        const f = Math.exp(-1.6 * dt);
        c.vx *= f; c.vz *= f;
        c.yaw += c.spin * dt;
        c.spin *= Math.exp(-2 * dt);
        if (c.knock <= 0) {
          // Rejoin the nearest road and carry on
          const id = W.nearestNode(c.x, c.z, ['city', 'link', 'hwy']);
          const n = W.nodes[id];
          c.a = id; c.b = n.adj[Math.floor(Math.random() * n.adj.length)]; c.t = 0;
          if (Math.hypot(n.x - player.x, n.z - player.z) < 60) { this.spawn(c, player.x, player.z, 160, 450); continue; }
          this.place(c, true);
        }
      } else {
        // Slow for cars ahead (including the player and racers) in our lane.
        const fx = Math.sin(c.yaw), fz = Math.cos(c.yaw);
        let target = SPEED[W.nodes[c.a].type] || 14;
        const blockers = [player, ...others];
        for (const o of blockers) {
          const dx = o.x - c.x, dz = o.z - c.z;
          const ahead = dx * fx + dz * fz;
          const side = Math.abs(dx * fz - dz * fx);
          if (ahead > 0 && ahead < 18 && side < 2.5) target = Math.min(target, Math.max(0, (ahead - 7) * 1.2));
        }
        for (const o of this.cars) {
          if (o === c || !o.active || o.disabled) continue;
          const dx = o.x - c.x, dz = o.z - c.z;
          const ahead = dx * fx + dz * fz;
          const side = Math.abs(dx * fz - dz * fx);
          if (ahead > 0 && ahead < 16 && side < 2.2) target = Math.min(target, Math.max(0, (ahead - 7) * 1.4));
        }
        // Slow before sharp turns at the end of an edge.
        if (c.t > 0.6 && W.nodes[c.a].type === 'city') target = Math.min(target, 8);
        c.speed = lerp(c.speed, target, 1 - Math.exp(-2 * dt));
        c.t += (c.speed * dt) / (c.edgeLen || 10);
        while (c.t >= 1) {
          c.t -= 1;
          const B = W.nodes[c.b];
          const opts = B.adj.filter((k) => k !== c.a && W.nodes[k].type !== 'pass');
          const next = opts.length ? opts[Math.floor(Math.random() * opts.length)] : c.a;
          c.a = c.b; c.b = next;
          c.edgeLen = Math.hypot(W.nodes[c.b].x - B.x, W.nodes[c.b].z - B.z) || 10;
        }
        this.place(c, false);
      }
      c.y = W.ground(c.x, c.z) + 0.02;
      c.model.position.set(c.x, c.y, c.z);
      c.model.rotation.y = c.yaw;
    }
  }

  // Soft contact: civilians get shoved, the player keeps nearly all speed.
  collide(v, onHit) {
    for (const c of this.cars) {
      if (!c.active || c.disabled) continue;
      const dx = c.x - v.x, dz = c.z - v.z;
      const d2 = dx * dx + dz * dz;
      if (d2 > 9 || Math.abs(c.y - v.y) > 3) continue;
      const d = Math.sqrt(d2) || 0.01;
      const nx = dx / d, nz = dz / d;
      const rel = (v.vx - (c.knock > 0 ? c.vx : Math.sin(c.yaw) * c.speed)) * nx + (v.vz - (c.knock > 0 ? c.vz : Math.cos(c.yaw) * c.speed)) * nz;
      if (rel <= 0 && c.knock > 0) continue;
      c.knock = 3;
      c.vx = v.vx * 0.85 + nx * (4 + Math.max(rel, 0) * 0.4);
      c.vz = v.vz * 0.85 + nz * (4 + Math.max(rel, 0) * 0.4);
      c.spin = (Math.random() - 0.5) * 6;
      c.x = v.x + nx * 3.05; c.z = v.z + nz * 3.05;
      v.vx *= 0.97; v.vz *= 0.97;
      onHit?.(Math.max(rel, 0));
    }
  }

  // Near-miss detection for nitro rewards.
  nearMiss(v) {
    let n = 0;
    for (const c of this.cars) {
      if (!c.active || c.disabled || c.knock > 0) continue;
      const d = Math.hypot(c.x - v.x, c.z - v.z);
      if (d < 4.6 && d > 3.0 && v.speed > 25) {
        if (!c.missed) { c.missed = true; n++; }
      } else if (d > 12) c.missed = false;
    }
    return n;
  }
}

