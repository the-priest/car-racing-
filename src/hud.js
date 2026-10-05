// Heads-up display: speedometer/tach, minimap, race info, drift score, toasts.
import { clamp, formatMoney, formatTime } from './utils.js';
import { HALF } from './world.js';

const $ = (id) => document.getElementById(id);

export class HUD {
  constructor(game) {
    this.g = game;
    this.root = $('hud');
    this.speedo = $('speedo').getContext('2d');
    this.mini = $('minimap').getContext('2d');
    this.bigEl = $('bigtext');
    this.toastsEl = $('toasts');
    this.bigTimer = 0;
    this.lastCash = -1;
    this.fpsEl = $('fps');
    this.frames = 0;
    this.fpsT = 0;
  }

  show(on) { this.root.classList.toggle('hidden', !on); }

  big(text, dur = 1.5) {
    this.bigEl.textContent = text;
    this.bigEl.classList.remove('pop');
    void this.bigEl.offsetWidth;
    this.bigEl.classList.add('pop');
    this.bigTimer = dur;
  }

  toast(text, dur = 2) {
    const d = document.createElement('div');
    d.className = 'toast';
    d.textContent = text;
    this.toastsEl.appendChild(d);
    setTimeout(() => d.classList.add('out'), dur * 1000);
    setTimeout(() => d.remove(), dur * 1000 + 400);
    while (this.toastsEl.children.length > 4) this.toastsEl.firstChild.remove();
  }

  update(dt) {
    const G = this.g, v = G.player, S = G.save.settings;
    if (this.bigTimer > 0) { this.bigTimer -= dt; if (this.bigTimer <= 0) this.bigEl.classList.remove('pop'); }
    if (G.save.cash !== this.lastCash) { this.lastCash = G.save.cash; $('cash').textContent = formatMoney(G.save.cash); }
    const h = G.hour, hh = Math.floor(h), mm = Math.floor((h - hh) * 60);
    $('clock').textContent = `${hh < 10 ? '0' : ''}${hh}:${mm < 10 ? '0' : ''}${mm} ${G.sky.night > 0.5 ? '☾ NIGHT' : '☀ DAY'}`;

    // Heat
    const P = G.police;
    const heatEl = $('heat');
    heatEl.innerHTML = P.pursuit || P.heat ? '<b>HEAT</b> ' + '★'.repeat(P.heat) + '<span>' + '★'.repeat(5 - P.heat) + '</span>' : '';
    const pe = $('pursuit');
    pe.classList.toggle('hidden', !P.pursuit);
    if (P.pursuit) {
      $('pursuit-label').textContent = P.bustTimer > 0.3 ? 'BUSTED IN ' + Math.max(0, 4 - P.bustTimer).toFixed(1) : P.cooldown > 0 ? 'EVADING…' : 'PURSUIT';
      $('cooldown').style.width = `${clamp(P.cooldown / 10, 0, 1) * 100}%`;
      pe.classList.toggle('busting', P.bustTimer > 0.3);
    }

    // Race panel
    const R = G.race.active;
    const rp = $('race-panel');
    rp.classList.toggle('hidden', !R);
    if (R) {
      if (R.def.type === 'drift') {
        $('rp-pos').textContent = `${Math.round(G.drift.total + G.drift.chain).toLocaleString()} pts`;
        $('rp-lap').textContent = `TARGET ${R.def.target.toLocaleString()}`;
        $('rp-time').textContent = formatTime(Math.max(0, R.def.time - R.raceTime));
      } else {
        $('rp-pos').innerHTML = `${R.position}<small>/${R.rivals.length + 1}</small>`;
        $('rp-lap').textContent = R.path.closed ? `LAP ${Math.min(R.lap + 1, R.laps)}/${R.laps}` : `CP ${R.nextCp}/${R.cps.length}`;
        $('rp-time').textContent = formatTime(R.raceTime);
      }
      $('rp-extra').textContent = R.wrong > 1 ? 'WRONG WAY' : '';
    }

    // Drift
    const D = G.drift;
    const de = $('drift');
    de.classList.toggle('on', D.chain > 0);
    if (D.chain > 0) {
      $('drift-score').textContent = Math.round(D.chain).toLocaleString();
      $('drift-mult').textContent = `DRIFT x${D.mult}`;
    }

    // Nitro vignette
    $('vignette').classList.toggle('on', v.nitroOn);

    this.drawSpeedo(v, S);
    this.drawMinimap();

    if (S.fps) {
      this.frames++;
      this.fpsT += dt;
      if (this.fpsT > 0.5) {
        this.fpsEl.textContent = `${Math.round(this.frames / this.fpsT)} FPS · ${Math.round(G.renderScale * 100)}%`;
        this.frames = 0; this.fpsT = 0;
      }
    }
    this.fpsEl.style.display = S.fps ? 'block' : 'none';
  }

  drawSpeedo(v, S) {
    const c = this.speedo, W = 260, cx = 130, cy = 140, R = 108;
    c.clearRect(0, 0, W, W);
    const st = v.stats;
    const rpmN = clamp(v.rpm / (st.red || 8000), 0, 1.05);
    const a0 = Math.PI * 0.75, a1 = Math.PI * 2.25;
    // Backplate
    c.beginPath();
    c.arc(cx, cy, R + 14, 0, Math.PI * 2);
    c.fillStyle = 'rgba(6,8,14,0.55)';
    c.fill();
    // Tach arc
    c.lineCap = 'butt';
    c.lineWidth = 10;
    c.beginPath(); c.arc(cx, cy, R, a0, a1); c.strokeStyle = 'rgba(255,255,255,0.12)'; c.stroke();
    const redStart = a0 + (a1 - a0) * 0.85;
    c.beginPath(); c.arc(cx, cy, R, redStart, a1); c.strokeStyle = 'rgba(255,40,60,0.55)'; c.stroke();
    const grad = c.createLinearGradient(0, 0, W, 0);
    grad.addColorStop(0, '#19c8ff'); grad.addColorStop(1, rpmN > 0.85 ? '#ff2840' : '#ff7a1a');
    c.beginPath(); c.arc(cx, cy, R, a0, a0 + (a1 - a0) * Math.min(rpmN, 1)); c.strokeStyle = grad; c.stroke();
    // Ticks
    c.strokeStyle = 'rgba(255,255,255,0.6)';
    c.lineWidth = 2;
    const ticks = Math.ceil((st.red || 8000) / 1000);
    c.font = '600 11px Rajdhani, sans-serif';
    c.fillStyle = 'rgba(255,255,255,0.65)';
    c.textAlign = 'center';
    c.textBaseline = 'middle';
    for (let i = 0; i <= ticks; i++) {
      const a = a0 + (a1 - a0) * (i * 1000 / (st.red || 8000));
      if (a > a1 + 0.01) break;
      c.beginPath();
      c.moveTo(cx + Math.cos(a) * (R - 14), cy + Math.sin(a) * (R - 14));
      c.lineTo(cx + Math.cos(a) * (R - 6), cy + Math.sin(a) * (R - 6));
      c.stroke();
      if (st.cyl > 0 || i % 4 === 0) c.fillText(String(i), cx + Math.cos(a) * (R - 26), cy + Math.sin(a) * (R - 26));
    }
    // Nitro arc (inner)
    c.lineWidth = 6;
    c.beginPath(); c.arc(cx, cy, R - 40, Math.PI * 0.8, Math.PI * 1.2); c.strokeStyle = 'rgba(255,255,255,0.12)'; c.stroke();
    c.beginPath(); c.arc(cx, cy, R - 40, Math.PI * 1.2 - Math.PI * 0.4 * v.nitro, Math.PI * 1.2);
    c.strokeStyle = v.nitroOn ? '#9fe1ff' : '#2f8cff'; c.stroke();
    // Speed
    const mph = S.units === 'mph';
    const spd = Math.round(v.speed * (mph ? 2.237 : 3.6));
    c.fillStyle = '#fff';
    c.font = '700 54px Rajdhani, sans-serif';
    c.fillText(String(spd), cx, cy - 2);
    c.font = '600 13px Rajdhani, sans-serif';
    c.fillStyle = 'rgba(255,255,255,0.6)';
    c.fillText(mph ? 'MPH' : 'KM/H', cx, cy + 28);
    // Gear
    const gear = v.reverse ? 'R' : v.speed < 0.5 && v.throttle < 0.05 ? 'N' : String(v.gear + 1);
    c.font = '700 26px Rajdhani, sans-serif';
    c.fillStyle = rpmN > 0.92 ? '#ff2840' : '#ff7a1a';
    c.fillText(gear, cx, cy + 62);
    c.font = '600 10px Rajdhani, sans-serif';
    c.fillStyle = 'rgba(160,210,255,0.8)';
    c.fillText('N₂O', cx - (R - 40) - 2, cy + 22);
  }

  drawMinimap() {
    const G = this.g, v = G.player, c = this.mini, S = 220, half = S / 2;
    const img = G.world.mapImage;
    const scale = img.width / (HALF * 2); // px per metre in map image
    const zoom = 1.6 - clamp(v.speed / 80, 0, 1) * 0.6; // screen px per map px
    c.save();
    c.clearRect(0, 0, S, S);
    c.beginPath();
    c.arc(half, half, half - 2, 0, Math.PI * 2);
    c.clip();
    c.fillStyle = '#0b0f16';
    c.fillRect(0, 0, S, S);
    c.translate(half, half);
    c.rotate(Math.PI + v.yaw);
    c.scale(zoom, zoom);
    const mx = (v.x + HALF) * scale, mz = (v.z + HALF) * scale;
    c.globalAlpha = 0.9;
    c.drawImage(img, -mx, -mz);
    c.globalAlpha = 1;
    const tm = (x, z) => [(x + HALF) * scale - mx, (z + HALF) * scale - mz];
    // Route
    const R = G.race.active;
    if (R) {
      c.strokeStyle = '#ffb020';
      c.lineWidth = 3 / zoom * 1.5;
      c.beginPath();
      const p = R.path;
      for (let k = 0; k < 220; k += 2) {
        const q = p.at(R.pIdx + k);
        const [x, z] = tm(q.x, q.z);
        k ? c.lineTo(x, z) : c.moveTo(x, z);
        if (!p.closed && R.pIdx + k >= p.n - 1) break;
      }
      c.stroke();
    }
    // Event markers
    if (!R) for (const m of G.race.markers) {
      if (!m.group.visible) continue;
      const [x, z] = tm(m.x, m.z);
      c.fillStyle = '#' + m.color.toString(16).padStart(6, '0');
      c.beginPath(); c.arc(x, z, 5 / zoom * 1.4, 0, Math.PI * 2); c.fill();
    }
    // Rivals & cops
    for (const r of G.race.rivals()) {
      const [x, z] = tm(r.v.x, r.v.z);
      c.fillStyle = '#ff4060';
      c.beginPath(); c.arc(x, z, 3.5 / zoom * 1.4, 0, Math.PI * 2); c.fill();
    }
    for (const cop of G.police.cops) {
      const [x, z] = tm(cop.v.x, cop.v.z);
      c.fillStyle = Math.floor(performance.now() / 250) % 2 ? '#ff2030' : '#2060ff';
      c.beginPath(); c.arc(x, z, 4 / zoom * 1.4, 0, Math.PI * 2); c.fill();
    }
    c.restore();
    // Player arrow (always up)
    c.fillStyle = '#ffffff';
    c.beginPath();
    c.moveTo(half, half - 8); c.lineTo(half + 6, half + 6); c.lineTo(half, half + 3); c.lineTo(half - 6, half + 6);
    c.closePath(); c.fill();
    c.strokeStyle = 'rgba(255,255,255,0.25)';
    c.lineWidth = 2;
    c.beginPath(); c.arc(half, half, half - 2, 0, Math.PI * 2); c.stroke();
    // North marker
    const na = Math.PI + v.yaw;
    c.fillStyle = '#ff7a1a';
    c.font = '700 12px Rajdhani, sans-serif';
    c.textAlign = 'center';
    c.fillText('N', half + Math.sin(na) * (half - 12), half - Math.cos(na) * (half - 12) + 4);
  }

  drawBigMap(canvas) {
    const G = this.g, c = canvas.getContext('2d'), S = canvas.width;
    const img = G.world.mapImage;
    c.drawImage(img, 0, 0, S, S);
    const tm = (x, z) => [((x + HALF) / (HALF * 2)) * S, ((z + HALF) / (HALF * 2)) * S];
    c.font = '700 13px Rajdhani, sans-serif';
    c.textAlign = 'left';
    for (const m of G.race.markers) {
      const [x, z] = tm(m.x, m.z);
      const avail = G.race.available(m.def);
      c.fillStyle = '#' + m.color.toString(16).padStart(6, '0');
      c.globalAlpha = avail ? 1 : 0.45;
      c.beginPath(); c.arc(x, z, 7, 0, Math.PI * 2); c.fill();
      c.fillStyle = '#fff';
      c.fillText(m.def.name + (m.def.night && !avail ? ' (night)' : ''), x + 10, z + 4);
      c.globalAlpha = 1;
    }
    const v = G.player;
    const [px, pz] = tm(v.x, v.z);
    c.save();
    c.translate(px, pz);
    c.rotate(-v.yaw + Math.PI);
    c.fillStyle = '#fff';
    c.strokeStyle = '#000';
    c.beginPath(); c.moveTo(0, -11); c.lineTo(8, 9); c.lineTo(0, 4); c.lineTo(-8, 9); c.closePath();
    c.fill(); c.stroke();
    c.restore();
  }
}
