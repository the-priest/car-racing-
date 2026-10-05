// Fully synthesized audio: engine, tires, wind, nitro, impacts, sirens, music.
import { clamp } from './utils.js';

export class Audio {
  constructor() {
    this.ctx = null;
    this.enabled = true;
    this.sfxVol = 0.8;
    this.musicVol = 0.45;
  }

  init() {
    if (this.ctx) { this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    const ctx = (this.ctx = new AC());
    this.master = ctx.createGain();
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -14;
    comp.ratio.value = 4;
    this.master.connect(comp).connect(ctx.destination);
    this.sfx = ctx.createGain();
    this.sfx.gain.value = this.sfxVol;
    this.sfx.connect(this.master);
    this.musicBus = ctx.createGain();
    this.musicBus.gain.value = this.musicVol;
    this.musicBus.connect(this.master);

    // Shared noise buffer
    const len = ctx.sampleRate * 2;
    this.noiseBuf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = this.noiseBuf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;

    // Engine
    this.engGain = ctx.createGain();
    this.engGain.gain.value = 0;
    this.engFilter = ctx.createBiquadFilter();
    this.engFilter.type = 'lowpass';
    this.engFilter.Q.value = 3;
    const shaper = ctx.createWaveShaper();
    const curve = new Float32Array(1024);
    for (let i = 0; i < 1024; i++) { const x = i / 512 - 1; curve[i] = Math.tanh(x * 2.5); }
    shaper.curve = curve;
    this.engMix = ctx.createGain();
    this.engMix.gain.value = 0.35;
    this.engMix.connect(shaper).connect(this.engFilter).connect(this.engGain).connect(this.sfx);
    this.oscs = [
      this.osc('sawtooth', 0.55), this.osc('square', 0.35), this.osc('sawtooth', 0.22), this.osc('triangle', 0.4),
    ];
    // Electric whine
    this.whine = ctx.createOscillator();
    this.whine.type = 'sine';
    this.whineGain = ctx.createGain();
    this.whineGain.gain.value = 0;
    this.whine.connect(this.whineGain).connect(this.sfx);
    this.whine.start();

    this.tire = this.noiseLoop('bandpass', 1100, 2.5);
    this.wind = this.noiseLoop('lowpass', 500, 0.7);
    this.nitroS = this.noiseLoop('highpass', 1800, 0.5);
    this.gravel = this.noiseLoop('lowpass', 260, 1.2);

    // Siren
    this.siren = ctx.createOscillator();
    this.siren.type = 'square';
    this.sirenGain = ctx.createGain();
    this.sirenGain.gain.value = 0;
    const sf = ctx.createBiquadFilter();
    sf.type = 'lowpass';
    sf.frequency.value = 1800;
    this.siren.connect(sf).connect(this.sirenGain).connect(this.sfx);
    this.siren.start();
    this.sirenT = 0;

    this.startMusic();
  }

  osc(type, gain) {
    const o = this.ctx.createOscillator();
    o.type = type;
    const g = this.ctx.createGain();
    g.gain.value = gain;
    o.connect(g).connect(this.engMix);
    o.start();
    return o;
  }

  noiseLoop(type, freq, q) {
    const src = this.ctx.createBufferSource();
    src.buffer = this.noiseBuf;
    src.loop = true;
    const f = this.ctx.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    f.Q.value = q;
    const g = this.ctx.createGain();
    g.gain.value = 0;
    src.connect(f).connect(g).connect(this.sfx);
    src.start();
    return { g, f };
  }

  setVolumes(sfx, music) {
    this.sfxVol = sfx;
    this.musicVol = music;
    if (!this.ctx) return;
    this.sfx.gain.value = sfx;
    this.musicBus.gain.value = music;
  }

  // Called every frame with the player's vehicle state.
  updateCar(v, dt, active) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const st = v.stats;
    const rpmN = clamp((v.rpm - (st.idle || 0)) / ((st.red || 7000) - (st.idle || 0)), 0, 1.05);
    const k = 0.04;
    if (st.cyl > 0) {
      const f = (v.rpm / 60) * (st.cyl / 2);
      this.oscs[0].frequency.setTargetAtTime(f, t, k);
      this.oscs[1].frequency.setTargetAtTime(f * 0.5, t, k);
      this.oscs[2].frequency.setTargetAtTime(f * 1.5 + 3, t, k);
      this.oscs[3].frequency.setTargetAtTime(f * 0.25, t, k);
      const load = v.throttle;
      this.engFilter.frequency.setTargetAtTime(300 + rpmN * 1800 + load * 2200, t, k);
      this.engGain.gain.setTargetAtTime(active ? 0.16 + load * 0.2 + rpmN * 0.1 : 0, t, 0.06);
      this.whineGain.gain.setTargetAtTime(0, t, 0.1);
    } else {
      this.engGain.gain.setTargetAtTime(active ? 0.03 + v.throttle * 0.03 : 0, t, 0.1);
      this.oscs[0].frequency.setTargetAtTime(40 + v.speed * 2, t, k);
      this.engFilter.frequency.setTargetAtTime(400, t, k);
      this.whine.frequency.setTargetAtTime(180 + v.speed * 38, t, k);
      this.whineGain.gain.setTargetAtTime(active ? 0.02 + v.throttle * 0.05 + v.speed * 0.0006 : 0, t, 0.08);
    }
    const slip = v.onGround ? clamp((Math.abs(v.driftAngle) - 0.1) * 2.5 + v.wheelspin * 0.6, 0, 1) * clamp(v.speed / 10, 0, 1) : 0;
    const roadSlip = v.offroad ? 0 : slip;
    this.tire.g.gain.setTargetAtTime(active ? roadSlip * 0.22 : 0, t, 0.05);
    this.tire.f.frequency.setTargetAtTime(900 + roadSlip * 500, t, 0.05);
    this.gravel.g.gain.setTargetAtTime(active && v.offroad ? clamp(v.speed / 30, 0, 1) * 0.35 : 0, t, 0.08);
    this.wind.g.gain.setTargetAtTime(active ? clamp(v.speed / 90, 0, 1) ** 2 * 0.35 : 0, t, 0.1);
    this.nitroS.g.gain.setTargetAtTime(active && v.nitroOn ? 0.16 : 0, t, 0.05);
    // Turbo blow-off when lifting at high rpm
    if (st.cyl > 0 && st.cyl <= 6 && this.lastThrottle > 0.8 && v.throttle < 0.2 && rpmN > 0.6) this.burst(2600, 0.25, 0.12, 'highpass');
    this.lastThrottle = v.throttle;
  }

  burst(freq, dur, vol, type = 'lowpass') {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noiseBuf;
    const f = this.ctx.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    src.connect(f).connect(g).connect(this.sfx);
    src.start(t, Math.random());
    src.stop(t + dur + 0.05);
  }

  impact(strength) {
    this.burst(250 + strength * 30, 0.35, clamp(strength / 25, 0.05, 0.6));
  }

  beep(freq = 660, dur = 0.15, vol = 0.25) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const o = this.ctx.createOscillator();
    o.type = 'square';
    o.frequency.value = freq;
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g).connect(this.sfx);
    o.start(t);
    o.stop(t + dur + 0.02);
  }

  horn(on) {
    if (!this.ctx) return;
    if (on && !this.hornNode) {
      const g = this.ctx.createGain();
      g.gain.value = 0.12;
      const a = this.ctx.createOscillator(), b = this.ctx.createOscillator();
      a.type = b.type = 'square';
      a.frequency.value = 420; b.frequency.value = 530;
      a.connect(g); b.connect(g); g.connect(this.sfx);
      a.start(); b.start();
      this.hornNode = { a, b, g };
    } else if (!on && this.hornNode) {
      this.hornNode.a.stop(); this.hornNode.b.stop();
      this.hornNode = null;
    }
  }

  updateSiren(dt, intensity) {
    if (!this.ctx) return;
    this.sirenT += dt;
    const f = 650 + Math.sin(this.sirenT * 2.2) * 350;
    this.siren.frequency.setTargetAtTime(f, this.ctx.currentTime, 0.02);
    this.sirenGain.gain.setTargetAtTime(intensity * 0.09, this.ctx.currentTime, 0.1);
  }

  // ---- Procedural synthwave soundtrack ----
  startMusic() {
    const ctx = this.ctx;
    this.bpm = 112;
    this.step = 0;
    this.nextTime = ctx.currentTime + 0.1;
    const roots = [45, 41, 48, 43]; // A2, F2, C3, G2
    this.prog = roots;
    const tick = () => {
      if (!this.ctx) return;
      const spb = 60 / this.bpm / 4; // 16th notes
      while (this.nextTime < ctx.currentTime + 0.15) {
        if (this.musicVol > 0.001) this.playStep(this.step, this.nextTime, spb);
        this.nextTime += spb;
        this.step = (this.step + 1) % 256;
      }
    };
    this.musicTimer = setInterval(tick, 40);
  }

  playStep(step, t, spb) {
    const ctx = this.ctx;
    const bar = Math.floor(step / 16) % 4;
    const s = step % 16;
    const root = this.prog[bar];
    const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
    // Kick on beats
    if (s % 4 === 0) {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.frequency.setValueAtTime(140, t);
      o.frequency.exponentialRampToValueAtTime(40, t + 0.12);
      g.gain.setValueAtTime(0.5, t);
      g.gain.exponentialRampToValueAtTime(0.001, t + 0.25);
      o.connect(g).connect(this.musicBus);
      o.start(t); o.stop(t + 0.3);
    }
    // Snare on 2 and 4
    if (s === 4 || s === 12) {
      const src = ctx.createBufferSource();
      src.buffer = this.noiseBuf;
      const f = ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = 1800;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.25, t);
      g.gain.exponentialRampToValueAtTime(0.001, t + 0.18);
      src.connect(f).connect(g).connect(this.musicBus);
      src.start(t, Math.random()); src.stop(t + 0.2);
    }
    // Hats
    if (s % 2 === 1) {
      const src = ctx.createBufferSource();
      src.buffer = this.noiseBuf;
      const f = ctx.createBiquadFilter(); f.type = 'highpass'; f.frequency.value = 7000;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.06, t);
      g.gain.exponentialRampToValueAtTime(0.001, t + 0.05);
      src.connect(f).connect(g).connect(this.musicBus);
      src.start(t, Math.random()); src.stop(t + 0.06);
    }
    // Driving bass (8ths with octave jumps)
    if (s % 2 === 0) {
      const o = ctx.createOscillator(), g = ctx.createGain(), f = ctx.createBiquadFilter();
      o.type = 'sawtooth';
      o.frequency.value = mtof(root - 12 + (s % 4 === 2 ? 12 : 0));
      f.type = 'lowpass'; f.frequency.value = 700; f.Q.value = 6;
      g.gain.setValueAtTime(0.16, t);
      g.gain.exponentialRampToValueAtTime(0.001, t + spb * 1.8);
      o.connect(f).connect(g).connect(this.musicBus);
      o.start(t); o.stop(t + spb * 2);
    }
    // Arpeggio lead
    const arp = [0, 7, 12, 15, 12, 7, 3, 7];
    if (step % 64 >= 32 || bar >= 2) {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.type = 'square';
      o.frequency.value = mtof(root + 12 + arp[s % 8]);
      g.gain.setValueAtTime(0.035, t);
      g.gain.exponentialRampToValueAtTime(0.001, t + spb * 0.9);
      o.connect(g).connect(this.musicBus);
      o.start(t); o.stop(t + spb);
    }
    // Pad chord at bar start
    if (s === 0) {
      for (const iv of [0, 3, 7, 10]) {
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.type = 'sawtooth';
        o.frequency.value = mtof(root + 12 + iv);
        o.detune.value = (Math.random() - 0.5) * 14;
        const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 1200;
        g.gain.setValueAtTime(0.0001, t);
        g.gain.linearRampToValueAtTime(0.025, t + 0.4);
        g.gain.linearRampToValueAtTime(0.0001, t + spb * 16);
        o.connect(f).connect(g).connect(this.musicBus);
        o.start(t); o.stop(t + spb * 16 + 0.05);
      }
    }
  }
}

