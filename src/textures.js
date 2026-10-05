// Procedurally painted textures (no external assets needed).
import * as THREE from 'three';
import { makeCanvas, mulberry32 } from './utils.js';

function asphalt(ctx, w, h, seed, base = [46, 47, 50]) {
  const rnd = mulberry32(seed);
  ctx.fillStyle = `rgb(${base[0]},${base[1]},${base[2]})`;
  ctx.fillRect(0, 0, w, h);
  const img = ctx.getImageData(0, 0, w, h);
  for (let i = 0; i < img.data.length; i += 4) {
    const n = (rnd() - 0.5) * 12;
    img.data[i] += n; img.data[i + 1] += n; img.data[i + 2] += n;
  }
  ctx.putImageData(img, 0, 0);
  // Tire wear lanes
  ctx.globalAlpha = 0.08;
  ctx.fillStyle = '#000';
  for (let i = 0; i < 6; i++) {
    const x = (i + 0.5) * (w / 6);
    ctx.fillRect(x - w * 0.03, 0, w * 0.06, h);
  }
  ctx.globalAlpha = 1;
}

function tex(canvas, aniso, repeat = true) {
  const t = new THREE.CanvasTexture(canvas);
  t.colorSpace = THREE.SRGBColorSpace;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = aniso;
  t.generateMipmaps = true;
  t.minFilter = THREE.LinearMipmapLinearFilter;
  return t;
}

// Multi-lane road: width maps to u (0..1), length to v (one tile = 2x width).
export function roadTexture(kind, aniso) {
  const w = 256, h = 512;
  const c = makeCanvas(w, h);
  const ctx = c.getContext('2d');
  asphalt(ctx, w, h, kind.length * 7 + 3);
  const line = (x, lw, color, dash) => {
    ctx.fillStyle = color;
    if (!dash) ctx.fillRect(x - lw / 2, 0, lw, h);
    else for (let y = 0; y < h; y += 256) ctx.fillRect(x - lw / 2, y + 30, lw, 150);
  };
  const white = 'rgba(235,235,230,0.92)', yellow = 'rgba(240,190,40,0.95)';
  if (kind === 'pass') {
    line(10, 6, white);
    line(w - 10, 6, white);
    line(w / 2, 5, yellow, true);
  } else {
    line(8, 5, white);
    line(w - 8, 5, white);
    line(w / 2 - 5, 4, yellow);
    line(w / 2 + 5, 4, yellow);
    line(w * 0.25, 4, white, true);
    line(w * 0.75, 4, white, true);
  }
  return tex(c, aniso);
}

export function intersectionTexture(aniso) {
  const s = 256;
  const c = makeCanvas(s, s);
  const ctx = c.getContext('2d');
  asphalt(ctx, s, s, 99);
  ctx.fillStyle = 'rgba(235,235,230,0.85)';
  const band = 30, gap = 12;
  for (let i = 18; i < s - 18; i += gap * 2) {
    ctx.fillRect(i, 4, gap, band);
    ctx.fillRect(i, s - 4 - band, gap, band);
    ctx.fillRect(4, i, band, gap);
    ctx.fillRect(s - 4 - band, i, band, gap);
  }
  return tex(c, aniso, false);
}

export function sidewalkTexture(aniso) {
  const s = 128;
  const c = makeCanvas(s, s);
  const ctx = c.getContext('2d');
  asphalt(ctx, s, s, 5, [120, 118, 112]);
  ctx.strokeStyle = 'rgba(60,60,60,0.5)';
  ctx.lineWidth = 2;
  for (let i = 0; i <= s; i += 32) {
    ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i, s); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(0, i); ctx.lineTo(s, i); ctx.stroke();
  }
  return tex(c, aniso);
}

// Grayscale detail noise multiplied over terrain vertex colors.
export function detailTexture(aniso) {
  const s = 128;
  const c = makeCanvas(s, s);
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(s, s);
  const rnd = mulberry32(42);
  for (let i = 0; i < s * s; i++) {
    const v = 200 + rnd() * 55;
    img.data[i * 4] = v; img.data[i * 4 + 1] = v; img.data[i * 4 + 2] = v; img.data[i * 4 + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  // soft blobs
  for (let i = 0; i < 60; i++) {
    ctx.fillStyle = `rgba(${rnd() > 0.5 ? 255 : 120},${rnd() > 0.5 ? 255 : 130},120,0.06)`;
    ctx.beginPath();
    ctx.arc(rnd() * s, rnd() * s, 6 + rnd() * 18, 0, Math.PI * 2);
    ctx.fill();
  }
  const t = tex(c, aniso);
  t.colorSpace = THREE.NoColorSpace;
  return t;
}

export function waterNormalTexture() {
  const s = 128;
  const c = makeCanvas(s, s);
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(s, s);
  const hgt = (x, y) =>
    Math.sin((x / s) * Math.PI * 8) * 0.5 + Math.sin(((x + y) / s) * Math.PI * 6) * 0.35 +
    Math.cos((y / s) * Math.PI * 10 + Math.sin((x / s) * Math.PI * 4)) * 0.4;
  for (let y = 0; y < s; y++) {
    for (let x = 0; x < s; x++) {
      const dx = hgt(x + 1, y) - hgt(x - 1, y);
      const dy = hgt(x, y + 1) - hgt(x, y - 1);
      const i = (y * s + x) * 4;
      img.data[i] = 128 + dx * 60;
      img.data[i + 1] = 128 + dy * 60;
      img.data[i + 2] = 255;
      img.data[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

export function glowTexture(inner = 'rgba(255,220,160,1)', outer = 'rgba(255,180,90,0)') {
  const s = 64;
  const c = makeCanvas(s, s);
  const ctx = c.getContext('2d');
  const g = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
  g.addColorStop(0, inner);
  g.addColorStop(1, outer);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, s, s);
  return new THREE.CanvasTexture(c);
}

// Soft cone for headlight beams projected on the road.
export function beamTexture() {
  const w = 64, h = 128;
  const c = makeCanvas(w, h);
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(w, h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const v = y / h; // 0 near car, 1 far
      const spread = 0.15 + v * 0.85;
      const dx = Math.abs(x / w - 0.5) * 2 / spread;
      const a = Math.max(0, 1 - dx * dx) * Math.pow(1 - v, 1.2) * Math.min(1, v * 8);
      const i = (y * w + x) * 4;
      img.data[i] = 255; img.data[i + 1] = 240; img.data[i + 2] = 210;
      img.data[i + 3] = a * 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return new THREE.CanvasTexture(c);
}

export function smokeTexture() {
  const s = 64;
  const c = makeCanvas(s, s);
  const ctx = c.getContext('2d');
  const g = ctx.createRadialGradient(s / 2, s / 2, 2, s / 2, s / 2, s / 2);
  g.addColorStop(0, 'rgba(255,255,255,0.9)');
  g.addColorStop(0.5, 'rgba(255,255,255,0.35)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, s, s);
  return new THREE.CanvasTexture(c);
}
