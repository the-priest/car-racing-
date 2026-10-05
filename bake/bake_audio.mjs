// Offline audio synthesiser: engine loops, tyre/wind/siren/nitro loops, one-shots
// and the soundtrack. Output: assets/audio/*.wav (16-bit mono).
// Run: node bake/bake_audio.mjs
import fs from 'node:fs';
import path from 'node:path';

const OUT = path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'assets', 'audio');
fs.mkdirSync(OUT, { recursive: true });
const SR = 44100;

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function writeWav(name, data, sr = SR) {
  let peak = 0;
  for (const v of data) peak = Math.max(peak, Math.abs(v));
  const g = peak > 0 ? 0.92 / peak : 1;
  const buf = Buffer.alloc(44 + data.length * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + data.length * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(sr, 24); buf.writeUInt32LE(sr * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(data.length * 2, 40);
  for (let i = 0; i < data.length; i++) buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, data[i] * g)) * 32767), 44 + i * 2);
  fs.writeFileSync(path.join(OUT, name + '.wav'), buf);
}

// One-pole filters
function lowpass(x, cutoff, sr = SR) {
  const a = Math.exp(-2 * Math.PI * cutoff / sr);
  let y = 0;
  return x.map((v) => (y = (1 - a) * v + a * y));
}
function highpass(x, cutoff, sr = SR) {
  const lp = lowpass(x, cutoff, sr);
  return x.map((v, i) => v - lp[i]);
}
// Make a loop seamless by crossfading its tail into its head.
function loopify(x, fade = 2000) {
  const n = x.length - fade;
  const out = x.slice(0, n);
  for (let i = 0; i < fade; i++) {
    const t = i / fade;
    out[i] = x[i] * t + x[n + i] * (1 - t);
  }
  return out;
}

// ---------------------------------------------------------------- engines
// Each firing event is a damped resonant pulse; uneven firing and cycle-to-cycle
// variation give the burble. Base recording rpm = 3000.
function engine(cyl, onLoad, seed) {
  const R = rng(seed);
  const rpm = 3000;
  const dur = 2.0;
  const n = Math.floor(SR * dur);
  const x = new Float32Array(n);
  const cycle = 120 / rpm; // seconds per 720 degrees
  const events = [];
  // Firing offsets within a cycle (crossplane V8 is uneven).
  let offs = [];
  for (let c = 0; c < cyl; c++) offs.push(c / cyl);
  if (cyl === 8) offs = [0, 0.09, 0.25, 0.375, 0.5, 0.59, 0.75, 0.875];
  for (let t = 0; t < dur + cycle; t += cycle) {
    offs.forEach((o, k) => events.push({ t: t + o * cycle, amp: (0.75 + R() * 0.5) * (k % 2 ? 0.9 : 1), k }));
  }
  const res = onLoad ? [95, 180, 340, 720, 1400] : [80, 150, 260];
  const decay = onLoad ? 0.012 : 0.008;
  for (const e of events) {
    const i0 = Math.floor(e.t * SR);
    const len = Math.floor(SR * decay * 5);
    for (let i = 0; i < len; i++) {
      const j = i0 + i;
      if (j < 0 || j >= n) continue;
      const tt = i / SR;
      const env = Math.exp(-tt / decay);
      let s = 0;
      res.forEach((f, r) => (s += Math.sin(2 * Math.PI * f * (1 + (cyl - 6) * 0.03) * tt + e.k) / (r + 1)));
      x[j] += s * env * e.amp;
    }
  }
  // Intake/mechanical noise
  let nz = new Float32Array(n).map(() => R() * 2 - 1);
  nz = highpass(lowpass(nz, onLoad ? 3500 : 1500), 300);
  for (let i = 0; i < n; i++) x[i] += nz[i] * (onLoad ? 0.18 : 0.07);
  // Exhaust saturation when loaded
  const y = x.map((v) => (onLoad ? Math.tanh(v * 1.8) : v * 0.6));
  return loopify(Array.from(lowpass(y, onLoad ? 6000 : 2500)));
}

// Electric drivetrain whine
function electric(onLoad) {
  const n = SR * 2;
  const x = [];
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    let s = Math.sin(2 * Math.PI * 300 * t) * 0.6 + Math.sin(2 * Math.PI * 900 * t) * 0.25 + Math.sin(2 * Math.PI * 1500 * t) * 0.12;
    if (!onLoad) s *= 0.4;
    x.push(s);
  }
  return loopify(x);
}

for (const c of [4, 6, 8, 10, 12]) {
  writeWav(`engine_${c}_on`, engine(c, true, c * 7 + 1));
  writeWav(`engine_${c}_off`, engine(c, false, c * 7 + 2));
}
writeWav('engine_0_on', electric(true));
writeWav('engine_0_off', electric(false));

// ---------------------------------------------------------------- loops
function noise(seconds, seed) {
  const R = rng(seed);
  return Array.from({ length: Math.floor(SR * seconds) }, () => R() * 2 - 1);
}
{
  // Tyre squeal: band-limited noise around 1-2 kHz with a tonal component
  const n = noise(2.5, 3);
  const bp = highpass(lowpass(n, 2200), 700);
  const out = bp.map((v, i) => v * 0.6 + Math.sin(2 * Math.PI * 1180 * i / SR + Math.sin(i / SR * 9) * 3) * 0.25);
  writeWav('tire_squeal', loopify(out, 4000));
}
writeWav('wind', loopify(lowpass(noise(3, 4), 600), 6000));
writeWav('gravel', loopify(highpass(lowpass(noise(2, 5), 1800), 120).map((v, i) => v * (0.6 + 0.4 * Math.sin(i / SR * 40))), 3000));
writeWav('nitro', loopify(highpass(noise(2, 6), 1500), 3000));
{
  const n = SR * 2, x = [];
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const f = 700 + 450 * Math.sin(2 * Math.PI * 0.5 * t); // wail
    x.push(Math.sign(Math.sin(2 * Math.PI * f * t + Math.cos(2 * Math.PI * 0.5 * t) * 900 / 0.5 / (2 * Math.PI) * 0)) * 0.5);
  }
  // Phase-continuous wail
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const f = 720 + 430 * Math.sin(2 * Math.PI * 0.5 * t);
    ph += 2 * Math.PI * f / SR;
    x[i] = Math.tanh(Math.sin(ph) * 3) * 0.6;
  }
  writeWav('siren', lowpass(x, 3500));
}
// ---------------------------------------------------------------- one-shots
{
  const n = noise(0.5, 7);
  writeWav('impact', lowpass(n, 900).map((v, i) => v * Math.exp(-i / SR * 9) + Math.sin(2 * Math.PI * 60 * i / SR) * Math.exp(-i / SR * 12) * 0.8));
  writeWav('blowoff', highpass(noise(0.45, 8), 2500).map((v, i) => v * Math.exp(-i / SR * 7)));
  writeWav('backfire', lowpass(noise(0.18, 9), 1200).map((v, i) => v * Math.exp(-i / SR * 30) * 1.5));
  const x = [];
  for (let i = 0; i < SR * 0.12; i++) x.push(Math.sin(2 * Math.PI * 880 * i / SR) * Math.exp(-i / SR * 20));
  writeWav('beep', x);
  const ring = [];
  for (let i = 0; i < SR * 2.0; i++) {
    const t = i / SR, on = (t % 1.0) < 0.6 && ((t * 20) % 1) < 0.5;
    ring.push(on ? (Math.sin(2 * Math.PI * 1400 * t) + Math.sin(2 * Math.PI * 1750 * t)) * 0.4 : 0);
  }
  writeWav('phone_ring', ring);
  const sh = [];
  for (let i = 0; i < SR * 0.25; i++) { const t = i / SR; sh.push(Math.sin(2 * Math.PI * (300 + 600 * t) * t) * Math.exp(-t * 8) * 0.4); }
  writeWav('whoosh', highpass(sh, 200));
  const cash = [];
  for (let i = 0; i < SR * 0.6; i++) { const t = i / SR; cash.push((Math.sin(2 * Math.PI * 1318 * t) * (t < 0.1 ? 1 : 0) + Math.sin(2 * Math.PI * 1760 * t) * (t >= 0.1 ? 1 : 0)) * Math.exp(-t * 5)); }
  writeWav('reward', cash);
}

// ---------------------------------------------------------------- soundtrack
// Two synthwave/darksynth loops (mono 22.05 kHz to keep the build small).
function track(seed, bpm, roots, minor) {
  const sr = 22050, R = rng(seed);
  const spb = 60 / bpm / 4;
  const bars = roots.length * 4;
  const n = Math.floor(sr * spb * 16 * bars);
  const x = new Float32Array(n);
  const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
  const add = (start, len, fn) => { const i0 = Math.floor(start * sr); for (let i = 0; i < len * sr; i++) if (i0 + i < n) x[i0 + i] += fn(i / sr); };
  const scale = minor ? [0, 3, 7, 10, 12, 15, 19] : [0, 4, 7, 11, 12, 16, 19];
  for (let b = 0; b < bars; b++) {
    const root = roots[Math.floor(b / 4) % roots.length];
    for (let s = 0; s < 16; s++) {
      const t0 = (b * 16 + s) * spb;
      if (s % 4 === 0) add(t0, 0.35, (t) => Math.sin(2 * Math.PI * (45 + 90 * Math.exp(-t * 30)) * t) * Math.exp(-t * 7) * 0.9);
      if (s === 4 || s === 12) add(t0, 0.25, (t) => (R() * 2 - 1) * Math.exp(-t * 14) * 0.45 + Math.sin(2 * Math.PI * 190 * t) * Math.exp(-t * 20) * 0.3);
      if (s % 2 === 1) add(t0, 0.05, (t) => (R() * 2 - 1) * Math.exp(-t * 80) * 0.12);
      // Rolling bass (16ths)
      const bn = root - 24 + (s % 4 === 3 ? 12 : 0);
      add(t0, spb * 0.95, (t) => { const f = mtof(bn); const ph = (f * t) % 1; return (ph * 2 - 1) * 0.28 * Math.exp(-t * 4); });
      // Arp in second half of each 8 bars
      if (b % 8 >= 4) {
        const note = root + scale[(s * 3 + b) % scale.length];
        add(t0, spb * 0.9, (t) => Math.sign(Math.sin(2 * Math.PI * mtof(note) * t)) * 0.06 * Math.exp(-t * 9));
      }
    }
    // Pad
    const chord = minor ? [0, 3, 7, 10] : [0, 4, 7, 11];
    add(b * 16 * spb, 16 * spb, (t) => chord.reduce((a, iv) => a + Math.sin(2 * Math.PI * mtof(root + iv) * t * 1.002) + Math.sin(2 * Math.PI * mtof(root + iv) * t * 0.998), 0) * 0.025 * Math.min(1, t * 2) * Math.min(1, (16 * spb - t) * 4));
  }
  return { data: Array.from(lowpass(x, 7000, sr)), sr };
}
{
  const a = track(11, 104, [45, 41, 48, 43], true);
  writeWav('music_night', a.data, a.sr);
  const b = track(12, 118, [40, 40, 36, 38], true);
  writeWav('music_chase', b.data, b.sr);
}
console.log('audio baked to', OUT);
