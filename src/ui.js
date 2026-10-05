// Menus: main, pause, garage, events, settings, controls, results.
// Fully navigable with mouse, keyboard or gamepad.
import { CARS, PAINTS, UPGRADES, RACES, carStats, perfIndex } from './config.js';
import { formatMoney, formatTime } from './utils.js';

const $ = (id) => document.getElementById(id);

const SETTINGS_DEF = [
  { key: 'quality', label: 'Graphics Quality', opts: ['auto', 'low', 'medium', 'high'], names: ['Auto', 'Low', 'Medium', 'High'], reload: true },
  { key: 'resScale', label: 'Resolution Scale', opts: ['auto', 0.5, 0.67, 0.8, 1, 1.25, 1.5], names: ['Dynamic', '50%', '67%', '80%', '100%', '125%', '150%'] },
  { key: 'traffic', label: 'Traffic Density', opts: ['off', 'low', 'normal', 'high'], names: ['Off', 'Low', 'Normal', 'High'] },
  { key: 'timeMode', label: 'Time of Day', opts: ['cycle', 'day', 'night'], names: ['Dynamic Cycle', 'Always Day', 'Always Night'] },
  { key: 'police', label: 'Police', opts: [true, false], names: ['On (night)', 'Off'] },
  { key: 'assist', label: 'Driving Assists', opts: [true, false], names: ['Traction + Stability', 'Off (pure sim)'] },
  { key: 'manual', label: 'Gearbox', opts: [false, true], names: ['Automatic', 'Manual (Q/E, LB/RB)'] },
  { key: 'units', label: 'Units', opts: ['kmh', 'mph'], names: ['km/h', 'mph'] },
  { key: 'music', label: 'Music Volume', opts: [0, 0.15, 0.3, 0.45, 0.6, 0.8, 1], names: ['Off', '15%', '30%', '45%', '60%', '80%', '100%'] },
  { key: 'sfx', label: 'Effects Volume', opts: [0, 0.2, 0.4, 0.6, 0.8, 1], names: ['Off', '20%', '40%', '60%', '80%', '100%'] },
  { key: 'fps', label: 'Show FPS', opts: [false, true], names: ['Off', 'On'] },
];

export class UI {
  constructor(game) {
    this.g = game;
    this.stack = [];
    this.focus = 0;
    this.garageSel = null;
    document.addEventListener('mouseover', (e) => {
      const el = e.target.closest('[data-nav]');
      if (!el) return;
      const list = this.navItems();
      const i = list.indexOf(el);
      if (i >= 0) this.setFocus(i);
    });
  }

  get current() { return this.stack[this.stack.length - 1] || null; }
  isOpen() { return this.stack.length > 0; }

  open(name, replace = false) {
    if (replace) this.stack.pop();
    if (this.current) $(this.current).classList.add('hidden');
    this.stack.push(name);
    this.render(name);
    $(name).classList.remove('hidden');
    this.focus = 0;
    this.setFocus(0);
    this.g.onScreenChange?.(name);
  }

  close() {
    const cur = this.stack.pop();
    if (cur) $(cur).classList.add('hidden');
    if (this.current) {
      this.render(this.current);
      $(this.current).classList.remove('hidden');
      this.setFocus(0);
    }
    this.g.onScreenChange?.(this.current);
  }

  closeAll() {
    while (this.stack.length) $(this.stack.pop()).classList.add('hidden');
    this.g.onScreenChange?.(null);
  }

  back() {
    const cur = this.current;
    if (!cur) return;
    if (cur === 'menu') return;
    if (cur === 'results') { this.closeAll(); this.g.resume(); return; }
    if (cur === 'pause') { this.closeAll(); this.g.resume(); return; }
    this.close();
    if (!this.current) this.g.resume();
  }

  navItems() {
    const cur = this.current;
    if (!cur) return [];
    return [...$(cur).querySelectorAll('[data-nav]')].filter((e) => e.offsetParent !== null && !e.disabled);
  }

  setFocus(i) {
    const list = this.navItems();
    list.forEach((e) => e.classList.remove('focus'));
    if (!list.length) return;
    this.focus = (i + list.length) % list.length;
    const el = list[this.focus];
    el.classList.add('focus');
    el.scrollIntoView?.({ block: 'nearest' });
  }

  update(input) {
    if (!this.isOpen()) return;
    if (input.pressed('down')) this.setFocus(this.focus + 1);
    if (input.pressed('up')) this.setFocus(this.focus - 1);
    const el = this.navItems()[this.focus];
    if (el && el.dataset.opt !== undefined) {
      if (input.pressed('menuLeft')) this.cycleOpt(el.dataset.opt, -1);
      if (input.pressed('menuRight')) this.cycleOpt(el.dataset.opt, 1);
    }
    if (input.pressed('accept') && el) el.click();
    if (input.pressed('back') || (input.pressed('pause') && this.current !== 'menu')) this.back();
  }

  btn(label, fn, cls = '') {
    const b = document.createElement('button');
    b.className = 'btn ' + cls;
    b.innerHTML = label;
    b.dataset.nav = '1';
    if (cls.includes('disabled')) b.disabled = true;
    b.addEventListener('click', () => { this.g.audio.beep(760, 0.05, 0.08); fn(); });
    return b;
  }

  render(name) {
    const G = this.g;
    const el = $(name);
    if (name === 'menu') {
      const box = el.querySelector('.buttons');
      box.innerHTML = '';
      box.append(
        this.btn(G.started ? 'Continue' : 'Drive', () => G.play(), 'primary'),
        this.btn('Events', () => this.open('events')),
        this.btn('Garage', () => this.open('garage')),
        this.btn('Settings', () => this.open('settings')),
        this.btn('Controls', () => this.open('controls')),
      );
      $('menu-cash').textContent = formatMoney(G.save.cash);
    }
    if (name === 'pause') {
      const box = el.querySelector('.buttons');
      box.innerHTML = '';
      const inRace = !!G.race.active;
      box.append(this.btn('Resume', () => this.back(), 'primary'));
      if (inRace) {
        box.append(this.btn('Restart Event', () => { this.closeAll(); G.race.restart(); G.resume(); }));
        box.append(this.btn('Quit Event', () => { this.closeAll(); G.race.quit(); G.resume(); }));
      } else {
        box.append(this.btn('Events &amp; Fast Travel', () => this.open('events')));
        box.append(this.btn('Garage', () => this.open('garage'), G.police.pursuit ? 'disabled' : ''));
      }
      box.append(this.btn(G.sky.night > 0.5 ? 'Skip to Day ☀' : 'Skip to Night ☾', () => { G.skipTime(); this.render('pause'); this.setFocus(0); }));
      box.append(this.btn('Reset Car to Road', () => { this.closeAll(); G.resetToRoad(); G.resume(); }));
      box.append(this.btn('Settings', () => this.open('settings')));
      box.append(this.btn('Controls', () => this.open('controls')));
      box.append(this.btn('Main Menu', () => { this.closeAll(); G.toMenu(); }));
    }
    if (name === 'settings') this.renderSettings(el);
    if (name === 'garage') this.renderGarage(el);
    if (name === 'events') this.renderEvents(el);
    if (name === 'controls') {
      const b = el.querySelector('.buttons');
      b.innerHTML = '';
      b.append(this.btn('Back', () => this.back()));
    }
  }

  renderSettings(el) {
    const G = this.g, S = G.save.settings;
    const list = el.querySelector('.list');
    list.innerHTML = '';
    for (const d of SETTINGS_DEF) {
      const row = document.createElement('div');
      row.className = 'opt';
      row.dataset.nav = '1';
      row.dataset.opt = d.key;
      const i = Math.max(0, d.opts.indexOf(S[d.key]));
      row.innerHTML = `<span>${d.label}${d.reload ? ' <em>(applies on reload)</em>' : ''}</span><b><i class="arr">‹</i>${d.names[i]}<i class="arr">›</i></b>`;
      row.addEventListener('click', (e) => {
        const r = row.getBoundingClientRect();
        this.cycleOpt(d.key, e.clientX && e.clientX < r.left + r.width * 0.6 ? -1 : 1);
      });
      list.appendChild(row);
    }
    const b = el.querySelector('.buttons');
    b.innerHTML = '';
    b.append(this.btn('Back', () => this.back()));
    b.append(this.btn('Reset Progress', () => {
      if (confirm('Erase all progress, cars and cash?')) G.resetProgress();
    }, 'danger'));
  }

  cycleOpt(key, dir) {
    const G = this.g, S = G.save.settings;
    const d = SETTINGS_DEF.find((x) => x.key === key);
    if (!d) return;
    const i = Math.max(0, d.opts.indexOf(S[key]));
    S[key] = d.opts[(i + dir + d.opts.length) % d.opts.length];
    G.applySettings();
    G.persist();
    const f = this.focus;
    this.renderSettings($('settings'));
    this.setFocus(f);
  }

  renderGarage(el) {
    const G = this.g, save = G.save;
    if (!this.garageSel) this.garageSel = save.car;
    const sel = CARS.find((c) => c.id === this.garageSel);
    const owned = save.owned.includes(sel.id);
    const up = save.up[sel.id] || { engine: 0, handling: 0, nitro: 0 };
    const stats = carStats(sel, up);
    G.previewCar(sel.id);

    const list = el.querySelector('.cars');
    list.innerHTML = '';
    for (const c of CARS) {
      const own = save.owned.includes(c.id);
      const b = this.btn(
        `<span class="cls cls-${c.cls}">${c.cls}</span>${c.name}<small>${own ? (save.car === c.id ? 'DRIVING' : 'OWNED') : formatMoney(c.price)}</small>`,
        () => { this.garageSel = c.id; this.render('garage'); this.setFocus(CARS.indexOf(c)); },
        'carbtn' + (c.id === this.garageSel ? ' sel' : '')
      );
      list.appendChild(b);
    }
    const info = el.querySelector('.info');
    const bar = (label, val, max) => `<div class="stat"><span>${label}</span><div class="sbar"><i style="width:${Math.min(100, (val / max) * 100)}%"></i></div></div>`;
    info.innerHTML = `
      <h2><span class="cls cls-${sel.cls}">${sel.cls}</span> ${sel.name}</h2>
      <div class="pi">PI ${perfIndex(stats)} · ${sel.awd ? 'AWD' : 'RWD'} · ${sel.cyl ? sel.cyl + ' cyl' : 'Electric'} · ${Math.round(stats.top * 3.6)} km/h</div>
      ${bar('Top Speed', stats.top, 110)}${bar('Acceleration', stats.accel, 16)}${bar('Handling', stats.grip, 21)}${bar('Nitrous', stats.nitro * stats.nitroCap, 60)}
      <div class="ups"></div><div class="paints"></div><div class="act"></div>`;
    const ups = info.querySelector('.ups');
    if (owned) {
      for (const [k, u] of Object.entries(UPGRADES)) {
        const lvl = up[k] || 0;
        const cost = u.cost[lvl];
        const label = `${u.name} <span class="lv">${'■'.repeat(lvl)}${'□'.repeat(3 - lvl)}</span><small>${lvl >= 3 ? 'MAXED' : formatMoney(cost)}</small>`;
        const b = this.btn(label, () => {
          if (lvl >= 3 || save.cash < cost) { G.audio.beep(200, 0.15); return; }
          save.cash -= cost;
          save.up[sel.id] = { ...up, [k]: lvl + 1 };
          G.persist();
          G.applyCar();
          this.render('garage');
          this.setFocus(CARS.length + Object.keys(UPGRADES).indexOf(k));
        }, 'upbtn' + (lvl >= 3 || save.cash < cost ? ' dim' : ''));
        ups.appendChild(b);
      }
      const paints = info.querySelector('.paints');
      PAINTS.forEach((p) => {
        const s = document.createElement('button');
        s.className = 'swatch' + ((save.paint[sel.id] || sel.color) === p ? ' sel' : '');
        s.style.background = p;
        s.dataset.nav = '1';
        s.addEventListener('click', () => {
          save.paint[sel.id] = p;
          G.persist();
          G.previewCar(sel.id, true);
          const f = this.focus;
          this.render('garage');
          this.setFocus(f);
        });
        paints.appendChild(s);
      });
    }
    const act = info.querySelector('.act');
    if (!owned) {
      act.append(this.btn(`Buy for ${formatMoney(sel.price)}`, () => {
        if (save.cash < sel.price) { G.audio.beep(200, 0.15); G.hud.toast('Not enough cash'); return; }
        save.cash -= sel.price;
        save.owned.push(sel.id);
        save.car = sel.id;
        G.persist();
        G.applyCar();
        this.render('garage');
      }, save.cash >= sel.price ? 'primary' : 'dim'));
    } else if (save.car !== sel.id) {
      act.append(this.btn('Drive this car', () => { save.car = sel.id; G.persist(); G.applyCar(); this.render('garage'); }, 'primary'));
    }
    act.append(this.btn('Back', () => this.back()));
    $('garage-cash').textContent = formatMoney(save.cash);
  }

  renderEvents(el) {
    const G = this.g;
    const list = el.querySelector('.list');
    list.innerHTML = '';
    for (const def of RACES) {
      const path = G.race.pathFor(def);
      const avail = G.race.available(def);
      const best = G.save.best[def.id];
      const len = def.type === 'circuit' ? (path.len * def.laps) / 1000 : path.len / 1000;
      const row = this.btn(
        `<span class="etype t-${def.night ? 'night' : def.type}">${def.night ? 'NIGHT ' : ''}${def.type.toUpperCase()}</span>
         <span class="ename">${def.name}</span>
         <span class="emeta">${def.type === 'drift' ? `${def.time}s · target ${def.target.toLocaleString()}` : `${len.toFixed(1)} km${def.laps > 1 ? ` · ${def.laps} laps` : ''} · ${def.ai} rivals`}</span>
         <span class="ereward">${formatMoney(def.reward)}${best ? `<small>best ${formatTime(best)}</small>` : ''}</span>`,
        () => {
          if (!avail) { G.skipTime(true); }
          this.closeAll();
          G.travelTo(def);
        },
        'eventrow' + (avail ? '' : ' dim')
      );
      list.appendChild(row);
    }
    const b = el.querySelector('.buttons');
    b.innerHTML = '';
    b.append(this.btn('Back', () => this.back()));
  }

  showResults(r) {
    const el = $('results');
    const ord = ['1st', '2nd', '3rd', '4th', '5th', '6th', '7th'][r.place - 1] || r.place + 'th';
    el.querySelector('.content').innerHTML = `
      <div class="rtitle ${r.win ? 'win' : ''}">${r.def.type === 'drift' ? (r.win ? 'TARGET SMASHED' : 'TARGET MISSED') : r.win ? 'VICTORY' : ord + ' PLACE'}</div>
      <div class="rname">${r.def.name}</div>
      <div class="rgrid">
        ${r.def.type === 'drift' ? `<div><span>Score</span><b>${r.score.toLocaleString()}</b></div><div><span>Target</span><b>${r.def.target.toLocaleString()}</b></div>`
          : `<div><span>Position</span><b>${ord} / ${r.total}</b></div><div><span>Time</span><b>${formatTime(r.time)}</b></div>`}
        <div><span>Reward${r.night ? ' (night x1.5)' : ''}</span><b class="money">+${formatMoney(r.reward)}</b></div>
      </div>`;
    const b = el.querySelector('.buttons');
    b.innerHTML = '';
    b.append(this.btn('Continue', () => { this.closeAll(); this.g.resume(); }, 'primary'));
    b.append(this.btn('Retry', () => { this.closeAll(); this.g.race.restart(); this.g.resume(); }));
    this.g.pause(false);
    this.open('results');
  }
}
