// Night-time police: patrols, pursuits with heat levels, evasion and busts.
// Cops can never physically stop the player; busts only happen if you stop.
import { Vehicle } from './physics.js';
import { buildCar } from './carmodel.js';
import { STYLES } from './config.js';
import { clamp, wrapAngle } from './utils.js';

const COP_STATS = {
  name: 'Interceptor', accel: 10, top: 78, grip: 15, brake: 28, drift: 0.9, nitro: 8, mass: 1650,
  gears: 6, cyl: 8, idle: 800, red: 7000, nitroCap: 6, awd: true,
};

export class Police {
  constructor(game) {
    this.g = game;
    this.cops = [];
    this.heat = 0;
    this.pursuit = false;
    this.cooldown = 0;
    this.pursuitTime = 0;
    this.bustTimer = 0;
    this.patrolTimer = 5;
    this.enabled = true;
  }

  makeCop(x, z, yaw) {
    const G = this.g;
    const v = new Vehicle({ ...COP_STATS }, STYLES.sedan);
    v.reset(x, G.world.ground(x, z), z, yaw);
    const model = buildCar('sedan', '#e9edf2', { police: true });
    G.scene.add(model);
    const cop = { v, model, mode: 'patrol', route: [], ri: 0, repath: 0, stuck: 0, patrolNode: -1 };
    this.cops.push(cop);
    return cop;
  }

  removeCop(c) {
    this.g.scene.remove(c.model);
    c.model.userData.paint.dispose();
    c.model.userData.tailMat.dispose();
    c.model.userData.body.traverse((o) => o.geometry?.dispose());
    this.cops.splice(this.cops.indexOf(c), 1);
  }

  clear() {
    while (this.cops.length) this.removeCop(this.cops[0]);
    this.pursuit = false;
    this.heat = 0;
    this.cooldown = 0;
    this.bustTimer = 0;
  }

  // Spawn a cop on a road node at a distance from the player.
  spawnNear(minD, maxD, mode) {
    const W = this.g.world, p = this.g.player;
    const nodes = W.nodes;
    for (let t = 0; t < 40; t++) {
      const n = nodes[Math.floor(Math.random() * nodes.length)];
      const d = Math.hypot(n.x - p.x, n.z - p.z);
      if (d < minD || d > maxD || !n.adj.length) continue;
      const nb = nodes[n.adj[0]];
      const c = this.makeCop(n.x, n.z, Math.atan2(nb.x - n.x, nb.z - n.z));
      c.mode = mode;
      if (mode === 'chase') { c.v.vx = Math.sin(c.v.yaw) * 20; c.v.vz = Math.cos(c.v.yaw) * 20; }
      return c;
    }
    return null;
  }

  startPursuit(reason) {
    if (this.pursuit) return;
    this.pursuit = true;
    this.heat = Math.max(1, this.heat);
    this.pursuitTime = 0;
    this.cooldown = 0;
    for (const c of this.cops) c.mode = 'chase';
    this.g.hud.toast(reason || 'POLICE PURSUIT!', 2.5);
    this.g.audio.beep(300, 0.4, 0.2);
  }

  endPursuit(escaped) {
    const G = this.g;
    if (escaped) {
      const bounty = Math.round(1500 * this.heat + this.pursuitTime * 40);
      G.save.cash += bounty;
      G.hud.big('ESCAPED', 2);
      G.hud.toast(`Bounty +$${bounty.toLocaleString()}`, 3);
    } else {
      const fine = Math.min(G.save.cash, 2000 * this.heat);
      G.save.cash -= fine;
      G.hud.big('BUSTED', 2.5);
      G.hud.toast(`Fine -$${fine.toLocaleString()}`, 3);
      G.player.vx = G.player.vz = 0;
    }
    G.persist();
    this.pursuit = false;
    this.heat = 0;
    // Cops head off; despawn them out of view.
    for (const c of [...this.cops]) this.removeCop(c);
  }

  // Inputs for one cop (called per frame; physics stepped by the game loop).
  driveCop(c, dt) {
    const v = c.v, p = this.g.player, W = this.g.world;
    const dp = Math.hypot(p.x - v.x, p.z - v.z);
    let tx, tz, maxSpeed = 60;
    if (c.mode === 'chase') {
      // Predict where the player is heading; aim straight when close.
      if (dp < 90) {
        const lead = clamp(dp / 40, 0, 1.2);
        tx = p.x + p.vx * lead; tz = p.z + p.vz * lead;
        maxSpeed = Math.max(p.speed + 12, 25);
      } else {
        c.repath -= dt;
        if (c.repath <= 0 || !c.route.length) {
          const a = W.nearestNode(v.x, v.z), b = W.nearestNode(p.x, p.z);
          c.route = W.route(a, b);
          c.ri = 0;
          c.repath = 1.5;
        }
        while (c.ri < c.route.length - 1) {
          const n = W.nodes[c.route[c.ri]];
          if (Math.hypot(n.x - v.x, n.z - v.z) < 14 + v.speed * 0.3) c.ri++; else break;
        }
        const n = W.nodes[c.route[Math.min(c.ri, c.route.length - 1)]];
        tx = n.x; tz = n.z;
        maxSpeed = 70;
      }
    } else {
      // Patrol: wander the graph at cruising speed.
      if (c.patrolNode < 0) c.patrolNode = W.nearestNode(v.x, v.z);
      let n = W.nodes[c.patrolNode];
      if (Math.hypot(n.x - v.x, n.z - v.z) < 10) {
        const opts = n.adj.filter((k) => k !== c.lastNode);
        c.lastNode = c.patrolNode;
        c.patrolNode = opts.length ? opts[Math.floor(Math.random() * opts.length)] : n.adj[0];
        n = W.nodes[c.patrolNode];
      }
      const ln = W.nodes[c.lastNode ?? c.patrolNode];
      const dx = n.x - ln.x, dz = n.z - ln.z, l = Math.hypot(dx, dz) || 1;
      tx = n.x - (dz / l) * 4; tz = n.z + (dx / l) * 4;
      maxSpeed = n.type === 'city' ? 13 : 22;
    }
    const ang = wrapAngle(Math.atan2(tx - v.x, tz - v.z) - v.yaw);
    const steer = clamp(-ang * 2.2, -1, 1);
    const turnLimit = Math.abs(ang) > 0.6 ? 14 : Math.abs(ang) > 0.3 ? 28 : 999;
    const vt = Math.min(maxSpeed, turnLimit);
    let throttle = 0, brake = 0;
    if (v.speed < vt) throttle = 1; else brake = clamp((v.speed - vt) / 8, 0, 1);
    if (v.u < -1 && ang < 2) { throttle = 1; brake = 0; }
    // Recover if stuck
    if (v.speed < 1.5 && throttle > 0) c.stuck += dt; else c.stuck = 0;
    if (c.stuck > 2.5) {
      c.stuck = 0;
      const sp = W.respawnAt(v.x + (p.x - v.x) * 0.1, v.z + (p.z - v.z) * 0.1);
      v.reset(sp.x, sp.y, sp.z, sp.yaw);
    }
    return { throttle, brake, steer, handbrake: 0, nitro: c.mode === 'chase' && dp > 60 && Math.abs(ang) < 0.15, assist: true };
  }

  update(dt) {
    const G = this.g, p = G.player;
    const night = G.sky.night > 0.5;
    if (!this.enabled || (!night && !this.pursuit)) {
      if (this.cops.length && !this.pursuit) for (const c of [...this.cops]) this.removeCop(c);
      return;
    }
    // Patrols
    if (!this.pursuit) {
      this.patrolTimer -= dt;
      if (this.patrolTimer <= 0 && this.cops.length < 2) {
        this.patrolTimer = 15;
        this.spawnNear(200, 450, 'patrol');
      }
      for (const c of [...this.cops]) {
        const d = Math.hypot(c.v.x - p.x, c.v.z - p.z);
        if (d > 700) { this.removeCop(c); continue; }
        if (d < 70 && p.speed > 31) this.startPursuit('SPEEDING — POLICE PURSUIT!');
        if (d < 4) this.startPursuit('YOU HIT A COP!');
      }
      if (G.race.active && G.race.active.def.night && !G.race.active.copsCalled && G.race.active.raceTime > 25) {
        G.race.active.copsCalled = true;
        if (Math.random() < 0.6) { this.spawnNear(150, 300, 'chase'); this.startPursuit('COPS ON THE RACE!'); }
      }
      return;
    }

    // Pursuit
    this.pursuitTime += dt;
    this.heat = Math.min(5, 1 + Math.floor(this.pursuitTime / 35));
    const want = Math.min(1 + this.heat, 6);
    if (this.cops.length < want) {
      this.reinforce = (this.reinforce || 0) - dt;
      if (this.reinforce <= 0) { this.reinforce = 6; this.spawnNear(180, 350, 'chase'); }
    }
    let nearest = Infinity;
    for (const c of [...this.cops]) {
      const d = Math.hypot(c.v.x - p.x, c.v.z - p.z);
      if (d > 800) { this.removeCop(c); continue; }
      nearest = Math.min(nearest, d);
      // Cops get faster with heat but never ram you to a stop.
      c.v.powerMul = 1 + this.heat * 0.05 + (d > 200 ? 0.15 : 0);
    }
    if (nearest > 260) {
      this.cooldown += dt;
      if (this.cooldown > 10) this.endPursuit(true);
    } else this.cooldown = Math.max(0, this.cooldown - dt * 2);
    if (nearest < 14 && p.speed < 2.5) {
      this.bustTimer += dt;
      if (this.bustTimer > 4) this.endPursuit(false);
    } else this.bustTimer = Math.max(0, this.bustTimer - dt * 2);
  }

  vehicles() { return this.cops.map((c) => c.v); }
}
