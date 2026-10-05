// Keyboard, gamepad (with rumble) and touch input unified into driving actions.
import { clamp, moveToward } from './utils.js';

const KEYMAP = {
  throttle: ['KeyW', 'ArrowUp'],
  brake: ['KeyS', 'ArrowDown'],
  left: ['KeyA', 'ArrowLeft'],
  right: ['KeyD', 'ArrowRight'],
  handbrake: ['Space'],
  nitro: ['ShiftLeft', 'ShiftRight', 'KeyN'],
  camera: ['KeyC'],
  reset: ['KeyR'],
  interact: ['Enter', 'KeyF'],
  map: ['KeyM'],
  pause: ['Escape', 'KeyP'],
  lookBack: ['KeyB'],
  shiftUp: ['KeyE'],
  shiftDown: ['KeyQ'],
  time: ['KeyT'],
  horn: ['KeyH'],
  up: ['ArrowUp', 'KeyW'],
  down: ['ArrowDown', 'KeyS'],
  menuLeft: ['ArrowLeft', 'KeyA'],
  menuRight: ['ArrowRight', 'KeyD'],
  accept: ['Enter', 'Space'],
  back: ['Escape', 'Backspace'],
};

// Standard gamepad mapping (Xbox layout names).
const PAD = { A: 0, B: 1, X: 2, Y: 3, LB: 4, RB: 5, LT: 6, RT: 7, VIEW: 8, START: 9, LS: 10, RS: 11, UP: 12, DOWN: 13, LEFT: 14, RIGHT: 15 };
const PADMAP = {
  handbrake: [PAD.A], nitro: [PAD.X, PAD.LS], reset: [PAD.B], camera: [PAD.Y], shiftDown: [PAD.LB], shiftUp: [PAD.RB],
  pause: [PAD.START], map: [PAD.VIEW], interact: [PAD.UP], lookBack: [PAD.RS], time: [],
  up: [PAD.UP], down: [PAD.DOWN], menuLeft: [PAD.LEFT], menuRight: [PAD.RIGHT], accept: [PAD.A], back: [PAD.B],
};

export class Input {
  constructor() {
    this.keys = new Set();
    this.prev = new Map();
    this.now = new Map();
    this.steer = 0;
    this.throttle = 0;
    this.brake = 0;
    this.usingPad = false;
    this.padName = '';
    this.pad = null;
    this.touch = new Set();
    this.resetHold = 0;
    this.lookX = 0;
    window.addEventListener('keydown', (e) => {
      if (e.code === 'Space' || e.code.startsWith('Arrow')) e.preventDefault();
      this.keys.add(e.code);
      this.usingPad = false;
    });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => this.keys.clear());
    window.addEventListener('gamepadconnected', (e) => {
      this.padName = e.gamepad.id;
      this.onPadChange?.(true, e.gamepad.id);
    });
    window.addEventListener('gamepaddisconnected', () => this.onPadChange?.(false, ''));
    this.setupTouch();
  }

  setupTouch() {
    const el = document.getElementById('touch');
    if (!el) return;
    const isTouch = 'ontouchstart' in window || navigator.maxTouchPoints > 0;
    if (!isTouch) return;
    el.classList.add('on');
    el.querySelectorAll('[data-a]').forEach((b) => {
      const a = b.dataset.a;
      const on = (e) => { e.preventDefault(); this.touch.add(a); b.classList.add('down'); };
      const off = (e) => { e.preventDefault(); this.touch.delete(a); b.classList.remove('down'); };
      b.addEventListener('pointerdown', on);
      b.addEventListener('pointerup', off);
      b.addEventListener('pointercancel', off);
      b.addEventListener('pointerleave', off);
    });
  }

  readPad() {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    this.pad = null;
    for (const p of pads) if (p && p.connected) { this.pad = p; break; }
    return this.pad;
  }

  raw(action) {
    for (const k of KEYMAP[action] || []) if (this.keys.has(k)) return 1;
    if (this.touch.has(action)) return 1;
    const p = this.pad;
    if (p) {
      for (const b of PADMAP[action] || []) if (p.buttons[b]?.pressed) return 1;
      // Left stick also navigates menus.
      const ax = p.axes[0] || 0, ay = p.axes[1] || 0;
      if (action === 'up' && ay < -0.6) return 1;
      if (action === 'down' && ay > 0.6) return 1;
      if (action === 'menuLeft' && ax < -0.6) return 1;
      if (action === 'menuRight' && ax > 0.6) return 1;
    }
    return 0;
  }

  update(dt, speed = 0) {
    this.readPad();
    const p = this.pad;
    for (const a of Object.keys(KEYMAP)) {
      this.prev.set(a, this.now.get(a) || 0);
      this.now.set(a, this.raw(a));
    }
    // Analog driving input
    let padSteer = 0, padThrottle = 0, padBrake = 0;
    if (p) {
      const ax = p.axes[0] || 0;
      const dz = 0.1;
      padSteer = Math.abs(ax) < dz ? 0 : Math.sign(ax) * Math.pow((Math.abs(ax) - dz) / (1 - dz), 1.35);
      padThrottle = p.buttons[PAD.RT]?.value || 0;
      padBrake = p.buttons[PAD.LT]?.value || 0;
      this.lookX = Math.abs(p.axes[2] || 0) > 0.2 ? p.axes[2] : 0;
      if (Math.abs(ax) > 0.25 || padThrottle > 0.1 || padBrake > 0.1 || p.buttons.some((b) => b.pressed)) this.usingPad = true;
    }
    const kSteer = (this.raw('right') ? 1 : 0) - (this.raw('left') ? 1 : 0);
    const kThrottle = this.raw('throttle');
    const kBrake = this.raw('brake');
    if (this.usingPad && p) {
      this.steer = moveToward(this.steer, padSteer, dt * 12);
      this.throttle = padThrottle;
      this.brake = padBrake;
    } else {
      // Keyboard: ramped steering that tightens less at speed for stability.
      const rate = (kSteer === 0 || Math.sign(kSteer) !== Math.sign(this.steer) ? 6.5 : 3.2) / (1 + speed / 55);
      this.steer = moveToward(this.steer, kSteer, dt * rate);
      this.throttle = moveToward(this.throttle, kThrottle, dt * 7);
      this.brake = moveToward(this.brake, kBrake, dt * 9);
    }
    this.steer = clamp(this.steer, -1, 1);
    this.handbrake = this.now.get('handbrake') ? 1 : 0;
    this.nitro = !!this.now.get('nitro');
  }

  down(a) { return !!this.now.get(a); }
  pressed(a) { return !!this.now.get(a) && !this.prev.get(a); }

  rumble(strong, weak, ms) {
    const act = this.pad?.vibrationActuator;
    if (!act || !this.usingPad) return;
    try {
      act.playEffect('dual-rumble', { duration: ms, strongMagnitude: clamp(strong, 0, 1), weakMagnitude: clamp(weak, 0, 1) });
    } catch (e) { /* unsupported */ }
  }
}
