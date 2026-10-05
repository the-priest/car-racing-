// Persistent progress stored in localStorage (gracefully degrades if blocked).
const KEY = 'velocity-heat-save-v1';

export const DEFAULT_SETTINGS = {
  quality: 'auto', resScale: 'auto', music: 0.45, sfx: 0.8, assist: true, manual: false,
  police: true, units: 'kmh', fps: false, timeMode: 'cycle', traffic: 'normal', camera: 0,
};

export function loadSave() {
  let data = null;
  try { data = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { data = null; }
  const base = {
    cash: 5000, owned: ['kaze'], car: 'kaze', up: {}, paint: {}, best: {}, wins: 0,
    settings: { ...DEFAULT_SETTINGS }, pos: null, hour: 17.5,
  };
  if (!data) return base;
  return { ...base, ...data, settings: { ...DEFAULT_SETTINGS, ...(data.settings || {}) } };
}

export function writeSave(s) {
  try { localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) { /* storage unavailable */ }
}

export function wipeSave() {
  try { localStorage.removeItem(KEY); } catch (e) { /* ignore */ }
}
