import * as THREE from 'three';
import { CARS, STYLES, QUALITY, carStats } from './config.js';
import { World, WATER_Y, HALF } from './world.js';
import { Sky } from './sky.js';
import { Vehicle } from './physics.js';
import { buildCar, poseCar, setTrafficLightLevel } from './carmodel.js';
import { Input } from './input.js';
import { Audio } from './audio.js';
import { Traffic } from './traffic.js';
import { Police } from './police.js';
import { RaceManager } from './race.js';
import { HUD } from './hud.js';
import { UI } from './ui.js';
import { Smoke, Skids, CameraRig } from './effects.js';
import { loadSave, writeSave, wipeSave } from './save.js';
import { clamp, lerp } from './utils.js';

const PHYS_DT = 1 / 120;
const TRAFFIC_COUNT = { off: 0, low: 0.5, normal: 1, high: 1.5 };

// Pick a starting quality tier from the GPU; dynamic resolution fine-tunes from there.
function detectQuality() {
  try {
    const gl = document.createElement('canvas').getContext('webgl2') || document.createElement('canvas').getContext('webgl');
    if (!gl) return 'low';
    const ext = gl.getExtension('WEBGL_debug_renderer_info');
    const name = ext ? String(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL)) : '';
    gl.getExtension('WEBGL_lose_context')?.loseContext();
    const mobile = /Android|iPhone|iPad|Mobile/i.test(navigator.userAgent);
    const mem = navigator.deviceMemory || 8;
    if (mobile || mem <= 4 || /SwiftShader|llvmpipe|Basic Render|Mali|PowerVR/i.test(name)) return 'low';
    if (/Intel|Adreno|Apple GPU|Radeon\(TM\) Graphics|Vega/i.test(name)) return 'medium';
    return 'high';
  } catch (e) {
    return 'medium';
  }
}

class Game {
  constructor() {
    this.save = loadSave();
    this.state = 'loading';
    this.started = false;
    this.time = 0;
    this.acc = 0;
    this.hour = this.save.hour;
    this.drift = new DriftScore(this);
    this.renderScale = 1;
    this.frameTimes = [];
    this.scaleTimer = 0;
    this.saveTimer = 0;
  }

  async init() {
    const S = this.save.settings;
    const canvas = document.getElementById('game');
    this.qualityName = S.quality !== 'auto' ? S.quality : detectQuality();
    this.renderer = new THREE.WebGLRenderer({
      canvas, antialias: this.qualityName !== 'low', powerPreference: 'high-performance', stencil: false,
    });
    this.q = QUALITY[this.qualityName];
    const r = this.renderer;
    r.outputColorSpace = THREE.SRGBColorSpace;
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.toneMappingExposure = 1.05;
    r.shadowMap.enabled = this.q.shadows;
    r.shadowMap.type = THREE.PCFShadowMap;
    this.renderScale = Math.min(this.q.scale, window.devicePixelRatio || 1);

    this.scene = new THREE.Scene();
    this.cam = new THREE.PerspectiveCamera(65, 1, 0.3, this.q.draw + 150);
    this.uniforms = { uNight: { value: 0 } };
    this.setLoading('Generating city and terrain…', 0.2);
    await frame();
    this.sky = new Sky(this.scene, r, this.q);
    this.world = new World(this.scene, this.q, this.uniforms);
    this.setLoading('Tuning engines…', 0.7);
    await frame();

    this.input = new Input();
    this.input.onPadChange = (on, id) => this.hud?.toast(on ? 'Controller connected' : 'Controller disconnected', 2.5);
    this.audio = new Audio();
    this.camera = new CameraRig(this.cam, this.world);
    this.camera.mode = S.camera || 0;
    this.smoke = new Smoke(this.scene, this.qualityName === 'low' ? 140 : 260);
    this.skids = new Skids(this.scene, this.qualityName === 'low' ? 500 : 1000);

    const car = CARS.find((c) => c.id === this.save.car) || CARS[0];
    this.player = new Vehicle(carStats(car, this.save.up[car.id]), STYLES[car.style]);
    this.applyCar();
    const p = this.save.pos;
    if (p && Math.abs(p.x) < HALF - 50 && Math.abs(p.z) < HALF - 50) {
      this.player.reset(p.x, this.world.ground(p.x, p.z), p.z, p.yaw);
    } else {
      const sp = this.world.respawnAt(0, 30);
      this.player.reset(sp.x, sp.y, sp.z, sp.yaw);
    }
    this.traffic = new Traffic(this.scene, this.world, Math.round(this.q.traffic * 1.5));
    this.police = new Police(this);
    this.race = new RaceManager(this);
    this.hud = new HUD(this);
    this.ui = new UI(this);
    this.applySettings();
    this.setLoading('Ready', 1);

    window.addEventListener('resize', () => this.resize());
    this.resize();
    // Warm up shaders so the first frames don't hitch.
    this.sky.update(this.hour, this.player, this.cam);
    r.compile(this.scene, this.cam);

    document.getElementById('loading').classList.add('hidden');
    this.state = 'menu';
    this.ui.open('menu');
    const unlock = () => { this.audio.init(); this.applySettings(); };
    window.addEventListener('pointerdown', unlock, { once: true });
    window.addEventListener('keydown', unlock, { once: true });
    this.last = performance.now();
    requestAnimationFrame((t) => this.frame(t));
  }

  setLoading(msg, p) {
    document.getElementById('loadmsg').textContent = msg;
    document.querySelector('#loading .bar i').style.width = `${p * 100}%`;
  }

  resize() {
    const w = window.innerWidth, h = window.innerHeight;
    this.renderer.setPixelRatio(this.renderScale);
    this.renderer.setSize(w, h, false);
    this.cam.aspect = w / h;
    this.cam.updateProjectionMatrix();
  }

  // ------------------------------------------------------------ state changes
  play() {
    this.audio.init();
    this.started = true;
    this.ui.closeAll();
    this.resume();
  }

  resume() {
    if (this.ui.isOpen()) return;
    this.state = 'play';
    this.applyCar();
    this.hud.show(true);
    this.camera.snap = true;
  }

  pause(open = true) {
    if (this.state !== 'play') return;
    this.state = 'paused';
    this.audio.horn(false);
    if (open) this.ui.open('pause');
  }

  toMenu() {
    this.race.quit();
    this.persist();
    this.state = 'menu';
    this.hud.show(false);
    this.ui.open('menu');
  }

  onScreenChange(name) {
    if (name === 'garage') { this.state = 'garage'; this.hud.show(false); }
    else if (name === 'menu') { this.state = 'menu'; this.hud.show(false); }
    else if (name && this.state === 'garage') { this.state = 'paused'; this.applyCar(); }
    if (name !== 'garage' && this.ui) this.ui.garageSel = null;
  }

  applyCar() {
    const car = CARS.find((c) => c.id === this.save.car) || CARS[0];
    const stats = carStats(car, this.save.up[car.id]);
    const v = this.player;
    v.setStats(stats, STYLES[car.style]);
    this.setPlayerModel(car.id, this.save.paint[car.id] || car.color);
  }

  previewCar(id) {
    const car = CARS.find((c) => c.id === id);
    this.setPlayerModel(id, this.save.paint[id] || car.color);
  }

  setPlayerModel(id, color) {
    const key = id + color;
    if (this.modelKey === key) return;
    if (this.playerModel) {
      this.scene.remove(this.playerModel);
      const u = this.playerModel.userData;
      u.paint.dispose(); u.tailMat.dispose();
      u.body.traverse((o) => o.geometry?.dispose());
    }
    const car = CARS.find((c) => c.id === id);
    this.playerModel = buildCar(car.style, color);
    this.scene.add(this.playerModel);
    this.modelKey = key;
  }

  applySettings() {
    const S = this.save.settings;
    this.audio.setVolumes(S.sfx, S.music);
    const n = Math.round(this.q.traffic * (TRAFFIC_COUNT[S.traffic] ?? 1));
    this.traffic?.setCount(n);
    if (this.police) {
      this.police.enabled = S.police;
      if (!S.police && this.police.cops.length) this.police.clear();
    }
    const dpr = window.devicePixelRatio || 1;
    if (S.resScale !== 'auto') {
      this.renderScale = Math.min(S.resScale, dpr * 1.0);
      this.resize();
    }
    if (S.timeMode === 'day') this.hour = 13;
    if (S.timeMode === 'night') this.hour = 23;
  }

  persist() {
    const v = this.player;
    this.save.pos = { x: v.x, z: v.z, yaw: v.yaw };
    this.save.hour = this.hour;
    this.save.settings.camera = this.camera?.mode || 0;
    writeSave(this.save);
  }

  resetProgress() {
    wipeSave();
    location.reload();
  }

  skipTime(toNight) {
    const S = this.save.settings;
    if (S.timeMode !== 'cycle') S.timeMode = 'cycle';
    const night = toNight || this.sky.night <= 0.5;
    this.hour = night ? 22 : 10;
    if (!night && this.police.pursuit) this.police.endPursuit(true);
    this.sky.update(this.hour, this.player, this.cam);
    this.persist();
  }

  resetToRoad() {
    const v = this.player;
    const sp = this.world.respawnAt(v.x, v.z);
    v.reset(sp.x, sp.y, sp.z, sp.yaw);
    this.camera.snap = true;
    this.skids.last.clear();
  }

  travelTo(def) {
    if (this.police.pursuit) { this.hud.toast("Can't fast travel during a pursuit"); this.resume(); return; }
    const path = this.race.pathFor(def);
    const a = path.at(0), d = path.dir(0);
    this.player.reset(a.x, this.world.ground(a.x, a.z), a.z, d.yaw);
    this.camera.snap = true;
    this.skids.clear();
    this.resume();
    this.hud.toast(`Drive into the marker and press ${this.input.usingPad ? 'D-pad ↑' : 'ENTER'} to start`, 3.5);
  }

  // ------------------------------------------------------------ main loop
  frame(now) {
    requestAnimationFrame((t) => this.frame(t));
    let dt = (now - this.last) / 1000;
    this.last = now;
    if (dt > 0.1) dt = 0.1;
    this.time += dt;
    const input = this.input;
    input.update(dt, this.player.speed);

    if (this.state === 'play') {
      if (input.pressed('pause')) this.pause();
      else this.simulate(dt);
    } else {
      this.idle(dt);
      this.ui.update(input);
      if (this.state === 'paused' && !this.ui.isOpen()) this.resume();
    }
    this.renderer.render(this.scene, this.cam);
    this.adaptResolution(dt);
  }

  // Dynamic resolution keeps the frame rate smooth on weak GPUs.
  adaptResolution(dt) {
    if (this.save.settings.resScale !== 'auto' || this.state !== 'play') return;
    this.frameTimes.push(dt);
    this.scaleTimer += dt;
    if (this.scaleTimer < 1.5) return;
    const avg = this.frameTimes.reduce((a, b) => a + b, 0) / this.frameTimes.length;
    this.frameTimes.length = 0;
    this.scaleTimer = 0;
    const max = Math.min(this.q.maxScale, window.devicePixelRatio || 1);
    let s = this.renderScale;
    if (avg > 1 / 50) s -= avg > 1 / 35 ? 0.15 : 0.07;
    else if (avg < 1 / 58) s += 0.05;
    s = clamp(s, 0.5, max);
    if (Math.abs(s - this.renderScale) > 0.01) { this.renderScale = s; this.resize(); }
  }

  updateTimeOfDay(dt) {
    const S = this.save.settings;
    if (S.timeMode === 'cycle') this.hour = (this.hour + dt / 40) % 24;
    else this.hour = S.timeMode === 'day' ? 13 : 23;
    this.sky.update(this.hour, this.player, this.cam);
    const n = this.sky.night;
    this.uniforms.uNight.value = n;
    this.world.setNight(n);
    setTrafficLightLevel(n);
  }

  idle(dt) {
    // Menu backdrop / garage turntable
    this.updateTimeOfDay(this.state === 'menu' ? dt * 0.3 : 0);
    const v = this.player;
    v.nitroOn = false;
    poseCar(this.playerModel, v, this.sky.night, this.time);
    this.audio.updateCar(v, dt, false);
    this.audio.updateSiren(dt, 0);
    if (this.state === 'garage') {
      const a = this.time * 0.35;
      this.cam.position.set(v.x + Math.sin(a) * 7.5, v.y + 2.2, v.z + Math.cos(a) * 7.5);
      this.cam.lookAt(v.x, v.y + 0.7, v.z);
      if (this.cam.fov !== 50) { this.cam.fov = 50; this.cam.updateProjectionMatrix(); }
    } else if (this.state === 'menu') {
      const a = this.time * 0.05;
      this.cam.position.set(Math.sin(a) * 650, 170, Math.cos(a) * 650);
      this.cam.lookAt(0, 40, 0);
      if (this.cam.fov !== 60) { this.cam.fov = 60; this.cam.updateProjectionMatrix(); }
    }
    this.world.update(dt);
  }

  simulate(dt) {
    const input = this.input, S = this.save.settings, v = this.player;
    this.updateTimeOfDay(dt);
    this.world.update(dt);

    // One-shot actions
    if (input.pressed('camera')) this.camera.cycle();
    if (input.pressed('map')) this.toggleMap();
    if (input.pressed('time') && !this.race.active) this.skipTime();
    if (input.down('reset')) {
      this.resetHold = (this.resetHold || 0) + dt;
      if (this.resetHold > (input.usingPad ? 0.8 : 0) && !this.resetDone) { this.resetToRoad(); this.resetDone = true; }
    } else { this.resetHold = 0; this.resetDone = false; }
    this.audio.horn(input.down('horn'));
    const ev = this.race.nearbyEvent(v);
    const prompt = document.getElementById('prompt');
    if (ev && !this.police.pursuit) {
      const ok = this.race.available(ev);
      prompt.innerHTML = ok
        ? `<b>${ev.name}</b> · ${ev.type.toUpperCase()} · ${'$' + ev.reward.toLocaleString()}<br>Press <kbd>${input.usingPad ? 'D-pad ↑' : 'ENTER'}</kbd> to start`
        : `<b>${ev.name}</b> is a night-only event`;
      prompt.classList.remove('hidden');
      if (ok && input.pressed('interact')) { this.race.start(ev); prompt.classList.add('hidden'); }
    } else prompt.classList.add('hidden');

    // Inputs
    const R = this.race.active;
    const frozen = R && R.countdown > 0;
    const pin = {
      throttle: input.throttle, brake: input.brake, steer: input.steer, handbrake: input.handbrake,
      nitro: input.nitro, assist: S.assist, manual: S.manual,
      shiftUp: input.pressed('shiftUp'), shiftDown: input.pressed('shiftDown'),
    };
    const env = this.world;
    const envObj = { ground: (x, z) => env.ground(x, z), surface: (x, z) => env.surface(x, z) };
    const rivals = this.race.rivals();
    const cops = this.police.cops;
    const all = [v, ...rivals.map((r) => r.v), ...cops.map((c) => c.v)];
    const rivalIn = rivals.map((r) => r.ai.drive(dt, all, frozen));
    const copIn = cops.map((c) => this.police.driveCop(c, dt));

    // Fixed-step physics
    this.acc += dt;
    let steps = 0;
    let impact = 0;
    while (this.acc >= PHYS_DT && steps < 12) {
      if (!frozen) {
        v.step(PHYS_DT, pin, envObj);
        pin.shiftUp = pin.shiftDown = false;
        impact = Math.max(impact, this.collideBuildings(v));
      } else {
        v.rpm = lerp(v.rpm, (v.stats.idle || 900) + input.throttle * ((v.stats.red || 7000) - (v.stats.idle || 900)) * 0.85, 0.2);
        v.throttle = input.throttle;
      }
      rivals.forEach((r, i) => { if (!frozen) { r.v.step(PHYS_DT, rivalIn[i], envObj); this.collideBuildings(r.v); } });
      cops.forEach((c, i) => { c.v.step(PHYS_DT, copIn[i], envObj); this.collideBuildings(c.v); });
      this.collideCars(all);
      this.acc -= PHYS_DT;
      steps++;
    }
    if (steps >= 12) this.acc = 0;

    // World bounds and water
    for (const c of all) {
      const lim = HALF - 40;
      if (Math.abs(c.x) > lim) { c.x = Math.sign(c.x) * lim; c.vx = 0; }
      if (Math.abs(c.z) > lim) { c.z = Math.sign(c.z) * lim; c.vz = 0; }
    }
    if (this.world.ground(v.x, v.z) < WATER_Y - 1.0 && v.onGround) {
      this.hud.toast('Back to the road!', 1.5);
      this.resetToRoad();
    }

    // Traffic (never blocks you)
    this.traffic.update(dt, v, [...rivals.map((r) => r.v), ...cops.map((c) => c.v)]);
    this.traffic.collide(v, (s) => { impact = Math.max(impact, s * 0.5); });
    for (const o of all) if (o !== v) this.traffic.collide(o);
    const misses = this.traffic.nearMiss(v);
    if (misses) { v.nitro = Math.min(1, v.nitro + 0.12 * misses); this.hud.toast('NEAR MISS +N₂O', 1); this.drift.bonus(500); }

    // Landing from jumps
    if (v.landImpact) {
      if (v.landImpact > 4) { this.camera.shake = Math.min(1, v.landImpact / 12); input.rumble(0.6, 0.4, 150); }
      v.landImpact = 0;
    }
    if (v.airTime > 0.7 && !this.airShown) { this.airShown = true; this.hud.toast('BIG AIR +N₂O', 1.2); v.nitro = Math.min(1, v.nitro + 0.15); this.drift.bonus(1000); }
    if (v.onGround) this.airShown = false;

    if (impact > 3) {
      this.camera.shake = Math.min(1, impact / 20);
      this.audio.impact(impact);
      input.rumble(Math.min(1, impact / 15), 0.5, 220);
    }
    if (impact > 6) this.drift.crash();

    // Nitro refill at high speed
    if (v.speed > 50 && !v.nitroOn) v.nitro = Math.min(1, v.nitro + dt * 0.012);

    this.drift.update(dt, v, !!R && R.def.type === 'drift');
    this.race.update(dt, this.time);
    this.police.update(dt);

    // Visuals
    const night = this.sky.night;
    poseCar(this.playerModel, v, night, this.time);
    for (const r of rivals) poseCar(r.model, r.v, night, this.time);
    for (const c of cops) poseCar(c.model, c.v, night, this.time);
    this.tireFx(v, 'p', true);
    for (const r of rivals) this.tireFx(r.v, r, false);
    this.smoke.update(dt, lerp(1, 0.35, night), this.renderer.domElement.height);

    // Audio + haptics
    this.audio.updateCar(v, dt, true);
    let siren = 0;
    if (this.police.pursuit) for (const c of cops) siren = Math.max(siren, clamp(1 - Math.hypot(c.v.x - v.x, c.v.z - v.z) / 250, 0, 1));
    this.audio.updateSiren(dt, siren);
    if (input.usingPad) {
      const slip = clamp(Math.abs(v.driftAngle) * 1.2 + v.wheelspin * 0.4, 0, 1);
      const rough = v.offroad ? clamp(v.speed / 30, 0, 0.6) : 0;
      const strong = rough * 0.5 + (v.nitroOn ? 0.25 : 0);
      const weak = slip * 0.5 + rough * 0.3 + (v.rpm / (v.stats.red || 7000) > 0.95 ? 0.15 : 0);
      if (strong + weak > 0.05) input.rumble(strong, weak, 80);
    }

    this.camera.update(dt, v, input.down('lookBack'), input.lookX, v.nitroOn);
    this.hud.update(dt);
    if (this.mapOpen) {
      this.mapTimer = (this.mapTimer || 0) - dt;
      if (this.mapTimer <= 0) { this.mapTimer = 0.25; this.hud.drawBigMap(document.getElementById('bigmap-canvas')); }
    }
    this.saveTimer += dt;
    if (this.saveTimer > 10) { this.saveTimer = 0; this.persist(); }
  }

  toggleMap() {
    this.mapOpen = !this.mapOpen;
    document.getElementById('bigmap').classList.toggle('hidden', !this.mapOpen);
    if (this.mapOpen) this.hud.drawBigMap(document.getElementById('bigmap-canvas'));
  }

  // Building collisions: the only thing in the world that can stop a car.
  collideBuildings(v) {
    let impact = 0;
    const fx = Math.sin(v.yaw), fz = Math.cos(v.yaw);
    const r = v.W / 2 + 0.05;
    for (const off of [v.L / 2 - r, 0, -(v.L / 2 - r)]) {
      const cx = v.x + fx * off, cz = v.z + fz * off;
      const res = this.world.collideCircle(cx, cz, r);
      if (!res) continue;
      v.x += res.nx * res.depth;
      v.z += res.nz * res.depth;
      const vn = v.vx * res.nx + v.vz * res.nz;
      if (vn < 0) {
        impact = Math.max(impact, -vn);
        v.vx -= 1.2 * vn * res.nx;
        v.vz -= 1.2 * vn * res.nz;
        // Scrape: lose a bit of tangential speed and get rotated by the hit.
        v.vx *= 0.985; v.vz *= 0.985;
        const lever = off * (fx * res.nz - fz * res.nx);
        v.w += clamp(-vn * lever * 0.06, -2.5, 2.5);
      }
    }
    return impact;
  }

  // Cars rub and nudge each other but contact never brings you to a stop.
  collideCars(list) {
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        const a = list[i], b = list[j];
        const dx = b.x - a.x, dz = b.z - a.z;
        const d2 = dx * dx + dz * dz;
        if (d2 > 25) continue;
        const d = Math.sqrt(d2) || 0.01;
        // Approximate each car as an oriented capsule by using the closest points along their axes.
        const pen = 2.3 - d;
        if (pen <= 0) continue;
        const nx = dx / d, nz = dz / d;
        a.x -= nx * pen * 0.5; a.z -= nz * pen * 0.5;
        b.x += nx * pen * 0.5; b.z += nz * pen * 0.5;
        const rel = (b.vx - a.vx) * nx + (b.vz - a.vz) * nz;
        if (rel < 0) {
          const k = rel * 0.25;
          a.vx += nx * k; a.vz += nz * k;
          b.vx -= nx * k; b.vz -= nz * k;
        }
      }
    }
  }

  tireFx(v, key, isPlayer) {
    const slip = Math.abs(v.driftAngle);
    const sliding = v.onGround && v.speed > 6 && (slip > 0.18 || v.wheelspin > 0.15 || (v.brake > 0.8 && v.speed > 15 && v.ax < -8));
    const fx = Math.sin(v.yaw), fz = Math.cos(v.yaw), lx = Math.cos(v.yaw), lz = -Math.sin(v.yaw);
    const rz = -v.L / 2 + 0.9, hw = v.W / 2 - 0.2;
    for (const side of [-1, 1]) {
      const x = v.x + fx * rz + lx * hw * side, z = v.z + fz * rz + lz * hw * side;
      const y = v.y;
      this.skids.mark((isPlayer ? 'p' : key.name) + side, x, y, z, sliding && !v.offroad);
      if ((sliding || (v.offroad && v.speed > 12)) && Math.random() < (isPlayer ? 0.9 : 0.35)) {
        const dirt = v.offroad;
        const c = dirt ? [0.55, 0.45, 0.32] : [0.9, 0.9, 0.92];
        this.smoke.emit(x, y + 0.3, z, -v.vx * 0.15 + (Math.random() - 0.5) * 2, 0.8 + Math.random(), -v.vz * 0.15 + (Math.random() - 0.5) * 2,
          dirt ? 1.8 : 2.4, dirt ? 1.0 : 1.6 + slip, c[0], c[1], c[2]);
      }
    }
  }
}

// Drift chains with multipliers; banked for cash in free roam.
class DriftScore {
  constructor(game) { this.g = game; this.reset(); }
  reset() { this.chain = 0; this.total = 0; this.mult = 1; this.chainTime = 0; this.idle = 0; }
  bonus(n) { if (this.chain > 0) this.chain += n * this.mult; }
  crash() {
    if (this.chain > 0) { this.g.hud.toast('DRIFT CHAIN LOST', 1.2); this.chain = 0; this.mult = 1; this.chainTime = 0; }
  }
  update(dt, v, event) {
    const ang = Math.abs(v.driftAngle);
    const drifting = v.onGround && v.speed > 11 && ang > 0.24 && ang < 1.6 && v.u > 0;
    if (drifting) {
      this.idle = 0;
      this.chainTime += dt;
      this.mult = Math.min(5, 1 + Math.floor(this.chainTime / 2.5));
      this.chain += dt * v.speed * Math.min(ang, 1.1) * 30 * this.mult;
      v.nitro = Math.min(1, v.nitro + dt * 0.08);
    } else if (this.chain > 0) {
      this.idle += dt;
      if (this.idle > 1.8) {
        const pts = Math.round(this.chain);
        this.total += pts;
        if (!event && pts > 300) {
          const cash = Math.round(pts / 40);
          this.g.save.cash += cash;
          this.g.hud.toast(`DRIFT ${pts.toLocaleString()} · +$${cash}`, 1.6);
        }
        this.chain = 0; this.mult = 1; this.chainTime = 0;
      }
    }
  }
}

function frame() {
  return new Promise((r) => requestAnimationFrame(() => setTimeout(r, 0)));
}

const game = new Game();
window.__game = game;
game.init().catch((e) => {
  console.error(e);
  document.getElementById('loadmsg').textContent = 'Failed to start: ' + e.message + ' (WebGL required)';
});
