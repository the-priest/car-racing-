// Static game data: car roster, events, quality presets.

// Car body styles. Profiles are side silhouettes as [z, y] points (front is +z).
export const STYLES = {
  tuner: {
    L: 4.3, W: 1.86, wheelR: 0.36, wheelZ: 1.38,
    body: [[-2.15, 0.32], [2.15, 0.32], [2.2, 0.6], [2.0, 0.78], [0.9, 0.9], [-1.9, 0.95], [-2.2, 0.9]],
    cabin: [[-1.85, 0.93], [0.85, 0.9], [0.1, 1.36], [-1.3, 1.38], [-1.9, 1.08]],
    wing: true, wingH: 1.15, wingZ: -2.0,
  },
  muscle: {
    L: 4.7, W: 1.95, wheelR: 0.4, wheelZ: 1.5,
    body: [[-2.35, 0.35], [2.35, 0.35], [2.4, 0.75], [2.2, 0.95], [0.8, 1.0], [-1.9, 1.0], [-2.35, 1.0]],
    cabin: [[-1.45, 0.98], [0.75, 0.98], [0.0, 1.42], [-0.9, 1.42], [-1.65, 1.0]],
    scoop: true,
  },
  sport: {
    L: 4.5, W: 1.92, wheelR: 0.37, wheelZ: 1.45,
    body: [[-2.25, 0.32], [2.25, 0.32], [2.3, 0.58], [2.05, 0.76], [0.75, 0.88], [-1.9, 0.92], [-2.28, 0.82]],
    cabin: [[-1.6, 0.9], [0.7, 0.88], [-0.05, 1.3], [-0.9, 1.32], [-1.75, 0.95]],
    lip: true,
  },
  electric: {
    L: 4.6, W: 1.95, wheelR: 0.38, wheelZ: 1.5,
    body: [[-2.3, 0.3], [2.3, 0.3], [2.36, 0.55], [2.15, 0.7], [0.9, 0.84], [-1.6, 0.98], [-2.3, 0.86]],
    cabin: [[-1.9, 0.94], [0.85, 0.84], [0.05, 1.3], [-1.0, 1.33]],
  },
  super: {
    L: 4.6, W: 2.0, wheelR: 0.37, wheelZ: 1.48,
    body: [[-2.3, 0.28], [2.3, 0.28], [2.38, 0.5], [2.1, 0.64], [0.7, 0.8], [-2.0, 0.9], [-2.32, 0.8]],
    cabin: [[-1.4, 0.85], [0.65, 0.8], [-0.1, 1.18], [-0.7, 1.2], [-1.6, 0.9]],
    wing: true, wingH: 1.02, wingZ: -2.1, lip: true,
  },
  hyper: {
    L: 4.75, W: 2.05, wheelR: 0.38, wheelZ: 1.55,
    body: [[-2.38, 0.26], [2.38, 0.26], [2.45, 0.44], [2.15, 0.58], [0.8, 0.76], [-2.1, 0.88], [-2.42, 0.76]],
    cabin: [[-1.25, 0.8], [0.75, 0.76], [0.0, 1.12], [-0.6, 1.14], [-1.5, 0.86]],
    wing: true, wingH: 1.18, wingZ: -2.15, lip: true, fin: true,
  },
  sedan: {
    L: 4.6, W: 1.85, wheelR: 0.36, wheelZ: 1.45,
    body: [[-2.3, 0.35], [2.3, 0.35], [2.35, 0.7], [2.1, 0.85], [1.0, 0.92], [-2.0, 0.95], [-2.3, 0.9]],
    cabin: [[-1.75, 0.93], [0.95, 0.9], [0.3, 1.45], [-1.2, 1.45], [-1.9, 1.0]],
  },
  van: {
    L: 4.8, W: 2.0, wheelR: 0.4, wheelZ: 1.6,
    body: [[-2.4, 0.42], [2.4, 0.42], [2.45, 0.95], [2.1, 1.12], [-2.4, 1.12]],
    cabin: [[-2.35, 1.1], [1.7, 1.1], [1.1, 1.85], [-2.35, 1.85]],
  },
};

// Car performance: accel (m/s^2 at launch), top (m/s), grip (lateral m/s^2),
// drift (slide willingness), nitro (extra m/s^2 while boosting).
export const CARS = [
  { id: 'kaze', name: 'Kaze RS', cls: 'D', style: 'tuner', price: 0, color: '#ff6a1a',
    accel: 8.2, top: 64, grip: 13.5, brake: 24, drift: 1.0, nitro: 7.5, mass: 1250, gears: 5, cyl: 4, idle: 900, red: 8000 },
  { id: 'vortex', name: 'Vortex GT', cls: 'C', style: 'muscle', price: 16000, color: '#1f6bff',
    accel: 9.0, top: 71, grip: 13.0, brake: 25, drift: 1.15, nitro: 8, mass: 1600, gears: 6, cyl: 8, idle: 750, red: 6800 },
  { id: 'strada', name: 'Strada 900', cls: 'C', style: 'sport', price: 28000, color: '#e8e8ea',
    accel: 9.8, top: 76, grip: 15.0, brake: 27, drift: 0.9, nitro: 8.5, mass: 1400, gears: 6, cyl: 6, idle: 900, red: 7600 },
  { id: 'raptor', name: 'Raptor V8', cls: 'B', style: 'muscle', price: 42000, color: '#141414',
    accel: 10.8, top: 80, grip: 14.5, brake: 27, drift: 1.3, nitro: 9, mass: 1650, gears: 6, cyl: 8, idle: 700, red: 7000 },
  { id: 'nova', name: 'Nova E-GT', cls: 'B', style: 'electric', price: 65000, color: '#19e3c6',
    accel: 13.0, top: 82, grip: 16.0, brake: 28, drift: 0.85, nitro: 9, mass: 1900, awd: true, gears: 1, cyl: 0, idle: 0, red: 16000 },
  { id: 'phantom', name: 'Phantom LM', cls: 'A', style: 'super', price: 105000, color: '#d4142b',
    accel: 12.8, top: 92, grip: 17.5, brake: 30, drift: 1.05, nitro: 10, mass: 1450, awd: true, gears: 7, cyl: 10, idle: 1000, red: 8700 },
  { id: 'apex', name: 'Apex Zero', cls: 'S', style: 'hyper', price: 210000, color: '#b44dff',
    accel: 14.5, top: 104, grip: 19.0, brake: 32, drift: 1.0, nitro: 11, mass: 1400, awd: true, gears: 7, cyl: 12, idle: 1000, red: 9200 },
];

export const PAINTS = ['#ff6a1a', '#d4142b', '#1f6bff', '#19e3c6', '#ffd400', '#b44dff', '#e8e8ea', '#141414', '#2fd34a', '#ff2fa0', '#7a8a99', '#0b2f6b'];

export const UPGRADES = {
  engine: { name: 'Engine', desc: '+Acceleration & top speed', cost: [6000, 14000, 30000] },
  handling: { name: 'Handling', desc: '+Grip & braking', cost: [5000, 12000, 26000] },
  nitro: { name: 'Nitrous', desc: '+Boost power & capacity', cost: [4000, 10000, 22000] },
};

// Apply upgrade levels to a car's base stats.
export function carStats(car, up = {}) {
  const e = up.engine || 0, h = up.handling || 0, n = up.nitro || 0;
  return {
    ...car,
    accel: car.accel * (1 + 0.08 * e),
    top: car.top * (1 + 0.045 * e),
    grip: car.grip * (1 + 0.06 * h),
    brake: car.brake * (1 + 0.06 * h),
    nitro: car.nitro * (1 + 0.15 * n),
    nitroCap: 4 + n * 1.2,
  };
}

export function perfIndex(stats) {
  return Math.round(stats.accel * 18 + stats.top * 4 + stats.grip * 12 + stats.nitro * 5);
}

// City street coordinates (9 streets each direction, 110m apart).
export const STREETS = [-440, -330, -220, -110, 0, 110, 220, 330, 440];

// Race events. Waypoints are snapped to the road graph and routed between.
export const RACES = [
  { id: 'downtown', name: 'Downtown Circuit', type: 'circuit', laps: 3, reward: 7000, ai: 5, skill: 0.86,
    pts: [[-220, -220], [220, -220], [220, 220], [-220, 220]], roads: ['city'] },
  { id: 'zigzag', name: 'Midtown Zigzag', type: 'sprint', reward: 6000, ai: 5, skill: 0.88,
    pts: [[-440, 440], [-110, 440], [-110, 110], [220, 110], [220, -220], [440, -220], [440, -440]], roads: ['city'] },
  { id: 'cdrift', name: 'Downtown Drift', type: 'drift', time: 75, target: 30000, reward: 6500,
    pts: [[-110, -110], [110, -110], [110, 110], [-110, 110]], roads: ['city'], loop: true },
  { id: 'ring', name: 'Ring Road Rally', type: 'circuit', laps: 1, reward: 12000, ai: 5, skill: 0.9,
    pts: [[0, -1050], [1140, 0], [0, 1180], [-1150, 0]], roads: ['hwy'] },
  { id: 'coast', name: 'Coastal Sprint', type: 'sprint', reward: 9000, ai: 5, skill: 0.9,
    pts: [[0, 220], [0, 1180], [-550, 1150], [-1150, 0], [-440, 0]], roads: ['city', 'link', 'hwy'] },
  { id: 'summit', name: 'Summit Pass', type: 'sprint', reward: 15000, ai: 5, skill: 0.92,
    pts: [[560, -1000], [450, -1780], [-480, -1060]], roads: ['pass', 'hwy'] },
  { id: 'canyon', name: 'Canyon Drift', type: 'drift', time: 90, target: 55000, reward: 14000,
    pts: [[560, -1000], [450, -1780]], roads: ['pass', 'hwy'] },
  { id: 'neon', name: 'Neon Nights', type: 'circuit', laps: 2, reward: 18000, ai: 5, skill: 0.95, night: true,
    pts: [[0, -330], [0, -1050], [1140, 0], [440, 0], [0, 0]], roads: ['city', 'link', 'hwy'] },
  { id: 'tour', name: 'Grand Tour', type: 'sprint', reward: 40000, ai: 5, skill: 0.97, night: true,
    pts: [[0, 0], [440, 0], [1140, 0], [560, -1000], [450, -1780], [-480, -1060], [-1150, 0], [-440, 0], [-110, -110]],
    roads: ['city', 'link', 'hwy', 'pass'] },
];

export const QUALITY = {
  low: { scale: 0.7, maxScale: 0.85, shadows: false, shadowSize: 0, draw: 750, trees: 0.45, traffic: 10, aniso: 1 },
  medium: { scale: 1.0, maxScale: 1.0, shadows: true, shadowSize: 1024, draw: 1150, trees: 0.75, traffic: 18, aniso: 4 },
  high: { scale: 1.0, maxScale: 1.5, shadows: true, shadowSize: 2048, draw: 1700, trees: 1.0, traffic: 26, aniso: 8 },
};
