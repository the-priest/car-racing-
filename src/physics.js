// Vehicle dynamics: planar rigid body on a two-axle (bicycle) tire model with
// slip-angle based lateral forces, longitudinal load transfer, friction-circle
// traction limits, aero drag/downforce, a power-limited engine with gearbox and
// simple vertical motion for hills and jumps. No three.js dependency.
import { clamp, smoothstep, wrapAngle, lerp } from './utils.js';

const G = 9.81;

// Simplified Pacejka curve: peaks near 0.16 rad, falls to ~85% when sliding.
function tireCurve(alpha) {
  return Math.sin(1.35 * Math.atan(14.5 * alpha));
}

export class Vehicle {
  constructor(stats, style) {
    this.setStats(stats, style);
    this.reset(0, 0, 0, 0);
  }

  setStats(stats, style) {
    this.stats = stats;
    const m = stats.mass;
    this.m = m;
    this.L = style.L;
    this.W = style.W;
    this.wheelR = style.wheelR;
    const wb = style.wheelZ * 2;
    this.a = wb * 0.47; // CG to front axle
    this.b = wb * 0.53; // CG to rear axle
    this.wb = wb;
    this.h = 0.48;
    this.I = (m * (style.L * style.L + style.W * style.W)) / 12 * 1.15;
    this.mu = stats.grip / G;
    this.awd = !!stats.awd;
    this.gears = stats.gears;
    // Drag coefficient chosen so drag decel at top speed is ~4.5 m/s^2.
    this.cd = 4.5 / (stats.top * stats.top);
    this.crr = 0.12;
    this.power = (4.5 * stats.top + this.crr * stats.top) * m; // W-ish (force*speed)
    this.driveF = m * stats.accel;
    this.downforce = 0.00011; // fraction of weight per (m/s)^2
    this.gearTop = [];
    for (let g = 0; g < this.gears; g++) {
      this.gearTop.push(stats.top * 1.06 * Math.pow((g + 1) / this.gears, 0.72));
    }
    this.nitroCap = stats.nitroCap || 4;
    this.powerMul = this.powerMul ?? 1;
  }

  reset(x, y, z, yaw) {
    this.x = x; this.y = y; this.z = z;
    this.yaw = yaw;
    this.vx = 0; this.vz = 0; this.vy = 0;
    this.w = 0;
    this.onGround = true;
    this.airTime = 0;
    this.gear = 0;
    this.rpm = this.stats.idle || 900;
    this.shiftCut = 0;
    this.nitro = this.nitro ?? 1;
    this.nitroOn = false;
    this.ax = 0; this.ay = 0; // local accelerations (for load transfer & body motion)
    this.slipF = 0; this.slipR = 0; this.wheelspin = 0;
    this.speed = 0; this.u = 0; this.s = 0;
    this.steerAngle = 0;
    this.wheelRot = 0;
    this.reverse = false;
    this.offroad = false;
    this.pitch = 0; this.roll = 0;
    this.groundNx = 0; this.groundNz = 0;
    this.throttle = 0; this.brake = 0;
  }

  get kmh() { return this.speed * 3.6; }

  // Body side slip angle (rad): positive when sliding with nose pointing right of travel.
  get driftAngle() {
    if (this.speed < 4) return 0;
    return Math.atan2(this.s, Math.abs(this.u));
  }

  step(dt, inp, env) {
    const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
    const lx = Math.cos(this.yaw), lz = -Math.sin(this.yaw); // left vector
    let u = this.vx * fx + this.vz * fz;
    let s = this.vx * lx + this.vz * lz;
    const w = this.w;
    const speed = Math.hypot(this.vx, this.vz);
    const st = this.stats;
    const assist = inp.assist !== false;

    const surf = env.surface(this.x, this.z);
    this.offroad = surf.offroad;
    const mu = this.mu * surf.grip;

    // --- Steering ---
    // Speed sensitive lock keeps high-speed input sane; counter-steer assist helps catch slides.
    const lock = 0.62 / (1 + Math.max(0, Math.abs(u) - 5) / 16);
    let delta = -inp.steer * lock; // positive delta = steer left
    if (assist && speed > 6) {
      const beta = Math.atan2(s, Math.abs(u));
      delta += clamp(beta, -0.5, 0.5) * 0.55 * smoothstep(0.08, 0.3, Math.abs(beta)) * Math.sign(u);
    }
    delta = clamp(delta, -0.75, 0.75);
    this.steerAngle = delta;

    // --- Loads ---
    const df = this.downforce * u * u * this.m * G;
    const transfer = (this.m * this.ax * this.h) / this.wb;
    let Fzf = (this.m * G * this.b) / this.wb + df * 0.45 - transfer;
    let Fzr = (this.m * G * this.a) / this.wb + df * 0.55 + transfer;
    Fzf = Math.max(Fzf, this.m * G * 0.12);
    Fzr = Math.max(Fzr, this.m * G * 0.12);
    if (!this.onGround) { Fzf = 0; Fzr = 0; }

    // --- Engine / gearbox ---
    const absU = Math.abs(u);
    const idle = st.idle || 900, red = st.red || 7000;
    if (this.shiftCut > 0) this.shiftCut -= dt;
    let throttle = inp.throttle, brake = inp.brake;
    // Brake held at standstill engages reverse; throttle cancels it.
    if (brake > 0.1 && u < 0.8 && throttle < 0.1) this.reverse = true;
    if (throttle > 0.1 && u > -0.8) this.reverse = false;
    if (this.reverse) { const t = throttle; throttle = brake; brake = t; }

    const gt = this.gearTop[this.gear];
    let rpmN = clamp(absU / gt, 0, 1.05);
    if (this.gears > 1 && !inp.manual) {
      if (rpmN > 0.97 && this.gear < this.gears - 1 && !this.reverse) {
        this.gear++; this.shiftCut = 0.14;
      } else if (this.gear > 0 && absU < this.gearTop[this.gear - 1] * 0.62) {
        this.gear--;
      }
    } else if (inp.manual) {
      if (inp.shiftUp && this.gear < this.gears - 1) { this.gear++; this.shiftCut = 0.1; }
      if (inp.shiftDown && this.gear > 0) this.gear--;
    }
    rpmN = clamp(absU / this.gearTop[this.gear], 0, 1.05);
    const targetRpm = idle + (red - idle) * Math.max(rpmN, throttle > 0.05 && absU < 3 ? 0.3 * throttle : 0);
    this.rpm = lerp(this.rpm, Math.min(targetRpm, red * 1.01), 1 - Math.exp(-25 * dt));

    let drive = 0;
    if (throttle > 0) {
      const torqueShape = this.gears > 1 ? 0.75 + 0.25 * Math.sin(Math.PI * clamp(0.1 + rpmN * 0.75, 0, 1)) : 1;
      const limiter = rpmN >= 1.0 && this.gear === this.gears - 1 ? 0 : rpmN >= 1.02 ? 0 : 1;
      const powerF = this.power / Math.max(absU, 1);
      drive = throttle * Math.min(this.driveF, powerF) * torqueShape * limiter * this.powerMul;
      if (this.shiftCut > 0) drive *= 0.2;
      if (this.reverse) drive = absU > 15 ? 0 : -drive * 0.55;
    }

    // Nitrous
    this.nitroOn = false;
    let boost = 0;
    if (inp.nitro && this.nitro > 0 && !this.reverse && this.onGround && u > 2) {
      this.nitroOn = true;
      this.nitro = Math.max(0, this.nitro - dt / this.nitroCap);
      boost = this.m * st.nitro * (1 - smoothstep(st.top * 1.05, st.top * 1.22, absU));
    }

    // Brakes (ABS assumed): split 65/35, limited by available grip.
    const brakeF = brake * st.brake * this.m;
    const dirU = Math.sign(u) || 1;
    let Fbf = absU > 0.05 ? -dirU * Math.min(brakeF * 0.65, mu * Fzf) : 0;
    let Fbr = absU > 0.05 ? -dirU * Math.min(brakeF * 0.35, mu * Fzr) : 0;
    const hb = inp.handbrake;
    if (hb > 0) Fbr += absU > 0.05 ? -dirU * Math.min(hb * this.m * 6, mu * Fzr * 0.6) : 0;

    // Distribute drive and clamp to traction (wheelspin when exceeded).
    let Fdf = 0, Fdr = drive;
    if (this.awd) {
      // Rear-biased torque vectoring once the rear steps out keeps AWD cars driftable.
      const rearSlide = smoothstep(0.08, 0.3, Math.abs(this.slipR));
      Fdf = drive * (hb > 0 ? 0.08 : lerp(0.35, 0.12, rearSlide));
      Fdr = drive - Fdf;
    }
    let spin = 0;
    // Traction control: trims power when the slide angle gets too big to hold.
    const betaNow = speed > 6 ? Math.abs(Math.atan2(s, absU)) : 0;
    const tcsStart = lerp(0.22, 0.55, smoothstep(0.1, 0.5, Math.abs(inp.steer)));
    const tcs = assist ? lerp(0.95, 0.55, smoothstep(tcsStart, tcsStart + 0.35, betaNow)) : 1.0;
    const maxRear = mu * Fzr * tcs, maxFront = mu * Fzf * tcs;
    if (Math.abs(Fdr) > maxRear) { spin = Math.abs(Fdr) / maxRear - 1; Fdr = Math.sign(Fdr) * (assist ? maxRear : maxRear * 0.85); }
    if (Math.abs(Fdf) > maxFront) { spin = Math.max(spin, Math.abs(Fdf) / maxFront - 1); Fdf = Math.sign(Fdf) * maxFront; }
    this.wheelspin = spin;

    const Fxf = Fdf + Fbf;
    let Fxr = Fdr + Fbr;

    // --- Lateral tire forces ---
    const blend = smoothstep(1.5, 5, speed); // kinematic at very low speed
    const uDen = Math.max(absU, 4);
    const cosD = Math.cos(delta), sinD = Math.sin(delta);
    const vlf = -sinD * u + cosD * (s + w * this.a);
    const vuf = cosD * u + sinD * (s + w * this.a);
    const alphaF = Math.atan2(vlf, Math.max(Math.abs(vuf), 4));
    const alphaR = Math.atan2(s - w * this.b, uDen);
    let muR = mu;
    if (hb > 0) muR *= lerp(1, 0.3, hb);
    // Sliding rear tires hold less grip than gripping ones; this sustains drifts.
    if (Math.abs(alphaR) > 0.22 && speed > 8) muR *= 1 - 0.1 * st.drift;
    let Fyf = -mu * Fzf * tireCurve(alphaF) * (1 - 0.1 * Math.min(spin, 1));
    let Fyr = -muR * Fzr * tireCurve(alphaR);
    // Friction circle on the rear: longitudinal use eats into lateral capacity.
    const capR = Math.sqrt(Math.max(0, (muR * Fzr) ** 2 - Fxr * Fxr)) * (spin > 0 ? 0.7 : 1);
    if (Math.abs(Fyr) > capR) Fyr = Math.sign(Fyr) * capR;
    const capF = Math.sqrt(Math.max(0, (mu * Fzf) ** 2 - Fxf * Fxf));
    if (Math.abs(Fyf) > capF) Fyf = Math.sign(Fyf) * capF;
    this.slipF = alphaF;
    this.slipR = alphaR;

    // Car-frame forces
    let Fx = Fxf * cosD - Fyf * sinD + Fxr;
    let Fy = Fxf * sinD + Fyf * cosD + Fyr;
    let torque = this.a * (Fxf * sinD + Fyf * cosD) - this.b * Fyr;

    // Resistances
    const rr = this.crr * (surf.offroad ? 4 : 1) + surf.drag;
    Fx -= this.m * (rr * Math.sign(u) * Math.min(absU, 1) + this.cd * u * absU);
    Fx += boost;

    // Stability assist: pull the nose back toward the direction of travel once the
    // slide angle gets large, so drifts stay controllable instead of spinning out.
    if (assist && this.onGround && speed > 8 && u > 0) {
      const beta = Math.atan2(s, absU);
      const hold = lerp(0.12, 0.5, smoothstep(0.1, 0.5, Math.abs(inp.steer)) * (inp.throttle > 0.2 || hb > 0 ? 1 : 0.5));
      const excess = Math.max(0, Math.abs(beta) - hold);
      torque += Math.sign(beta) * excess * this.I * 14;
      torque -= w * this.I * excess * 3;
    }

    // Airborne: no tire forces, keep momentum.
    if (!this.onGround) { Fx = boost * 0.3; Fy = 0; torque = -w * this.I * 0.5; }

    // --- Integrate ---
    const axL = Fx / this.m, ayL = Fy / this.m;
    let nvx = this.vx + (fx * axL + lx * ayL) * dt;
    let nvz = this.vz + (fz * axL + lz * ayL) * dt;
    let nw = w + (torque / this.I) * dt;

    // Gravity along slope when grounded.
    if (this.onGround) {
      nvx -= G * this.groundNx * dt * 0.9;
      nvz -= G * this.groundNz * dt * 0.9;
    }

    // Low-speed kinematic blend prevents jitter when parking/turning slowly.
    if (blend < 1 && this.onGround) {
      const nu = nvx * fx + nvz * fz;
      let ns = nvx * lx + nvz * lz;
      ns *= blend;
      nvx = fx * nu + lx * ns;
      nvz = fz * nu + lz * ns;
      const kin = (nu * Math.tan(delta)) / this.wb;
      nw = lerp(kin, nw, blend);
      // Hold still when no input instead of creeping.
      if (throttle < 0.05 && Math.abs(nu) < 0.3 && !this.reverse) {
        nvx *= 0.9; nvz *= 0.9;
      }
    }

    this.vx = nvx; this.vz = nvz; this.w = nw;
    this.yaw = wrapAngle(this.yaw + nw * dt);
    this.x += nvx * dt;
    this.z += nvz * dt;

    // Local accelerations for load transfer (smoothed) and visuals.
    this.ax = lerp(this.ax, axL, 1 - Math.exp(-10 * dt));
    this.ay = lerp(this.ay, ayL, 1 - Math.exp(-10 * dt));

    // --- Vertical ---
    const gh = env.ground(this.x, this.z);
    const e = 1.2;
    const gx = (env.ground(this.x + e, this.z) - env.ground(this.x - e, this.z)) / (2 * e);
    const gz = (env.ground(this.x, this.z + e) - env.ground(this.x, this.z - e)) / (2 * e);
    if (this.onGround) {
      const vyNew = (gh - this.y) / dt;
      // Leave the ground if the terrain drops away faster than gravity can follow.
      const predicted = this.y + this.vy * dt - G * dt * dt;
      if (predicted > gh + 0.05 && this.vy > 2) {
        this.onGround = false;
        this.y += this.vy * dt;
      } else {
        this.vy = lerp(this.vy, vyNew, 0.5);
        this.y = gh;
      }
      this.groundNx = gx; this.groundNz = gz;
      this.airTime = 0;
    } else {
      this.vy -= G * dt;
      this.y += this.vy * dt;
      this.airTime += dt;
      if (this.y <= gh) {
        this.y = gh;
        this.landImpact = Math.max(0, -this.vy);
        this.vy = 0;
        this.onGround = true;
      }
    }

    // Visual chassis motion (pitch from braking/accel, roll from cornering).
    const tp = clamp(-this.ax * 0.006, -0.06, 0.06);
    const tr = clamp(this.ay * 0.0065, -0.07, 0.07);
    this.pitch = lerp(this.pitch, tp, 1 - Math.exp(-8 * dt));
    this.roll = lerp(this.roll, tr, 1 - Math.exp(-8 * dt));

    this.u = this.vx * fx + this.vz * fz;
    this.s = this.vx * lx + this.vz * lz;
    this.speed = Math.hypot(this.vx, this.vz);
    this.wheelRot += (this.u / this.wheelR) * dt * (spin > 0.05 ? 1.6 : 1);
    this.throttle = throttle;
    this.brake = brake;
  }
}
