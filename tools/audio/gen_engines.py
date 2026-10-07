#!/usr/bin/env python3
"""Engine sound loops: assets/audio/engines/e<cyl>_<on|off>_<rpm>.wav

Each engine is rendered at several rpm points (games crossfade between the two
nearest and pitch-shift only a little). Pitch-shifting one recording across the
whole rev range drags the exhaust resonances up with it, which is what made the
old sounds whine like a scooter at high revs.

Model per firing event: a short pressure pulse (strength varies per cylinder and
per cycle, crossplane V8s alternate banks unevenly for the burble) driven
through a fixed exhaust: a few resonators (pipe/muffler modes that do NOT move
with rpm), a pipe echo comb filter and a muffler low-pass. Intake roar is band
noise modulated by the firing, and on load everything is driven into soft
saturation. Off load: weaker, irregular pulses with the odd crackle.

  python3 tools/audio/gen_engines.py
"""
import os

import numpy as np
from scipy import signal

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "engines")
RPMS = [1000, 2000, 3000, 4000, 5000, 6500, 8000, 9500]

# cyl: firing offsets (fraction of a 720 degree cycle), exhaust resonances (Hz, Q, gain),
# pipe echo delay (ms) and feedback, muffler cutoff (Hz), bank imbalance, rasp.
ENGINES = {
    4: dict(offs=[0, .25, .5, .75], res=[(130, 3, 1.0), (380, 4, .7), (950, 5, .45), (2100, 6, .25)],
            comb=(9.0, .45), lp=4200, imbalance=.10, rasp=.35),
    6: dict(offs=[i / 6 for i in range(6)], res=[(105, 3, 1.0), (310, 4, .8), (720, 5, .55), (1650, 6, .35), (3300, 7, .15)],
            comb=(11.0, .5), lp=5200, imbalance=.06, rasp=.22),
    8: dict(offs=[0, .09, .25, .375, .5, .59, .75, .875], res=[(68, 2.5, 1.2), (175, 3, .9), (390, 4, .55), (880, 5, .3)],
            comb=(14.0, .55), lp=3600, imbalance=.28, rasp=.18),
    10: dict(offs=[0, .072, .2, .272, .4, .472, .6, .672, .8, .872], res=[(90, 3, 1.0), (250, 4, .8), (600, 5, .5), (1350, 6, .35), (2700, 7, .2)],
             comb=(12.0, .5), lp=5000, imbalance=.12, rasp=.25),
    12: dict(offs=[i / 12 for i in range(12)], res=[(98, 3, .9), (290, 4, .8), (680, 5, .6), (1500, 6, .45), (3100, 7, .3)],
             comb=(10.0, .45), lp=6000, imbalance=.05, rasp=.2),
}


def resonator(x, f, q, gain):
    w0 = 2 * np.pi * f / SR
    alpha = np.sin(w0) / (2 * q)
    b = np.array([alpha, 0, -alpha]) * gain
    a = np.array([1 + alpha, -2 * np.cos(w0), 1 - alpha])
    return signal.lfilter(b / a[0], a / a[0], x)


def lowpass(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi):
    b, a = signal.butter(2, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def comb(x, delay_ms, fb):
    d = int(SR * delay_ms / 1000)
    y = np.copy(x)
    for i in range(d, len(y)):
        y[i] += fb * y[i - d]
    return y


def render(cyl, rpm, on_load, seed):
    cfg = ENGINES[cyl]
    rng = np.random.default_rng(seed)
    cycle = 120.0 / rpm  # seconds per 720 degrees
    cycles = max(4, int(round(1.4 / cycle)))  # loop = whole number of cycles (~1.4 s)
    pad = 0.25  # pre-roll so filters settle; cut before the loop
    n = int((cycles * cycle + 2 * pad) * SR)
    pulses = np.zeros(n)
    # Pulse shape: ~1.2 ms asymmetric bump (a combustion blow-down)
    pw = int(0.0012 * SR) + 2
    shape = np.sin(np.linspace(0, np.pi, pw)) ** 2 * np.exp(-np.linspace(0, 3, pw))
    bank = np.array([1.0 if k % 2 == 0 else 1.0 - cfg["imbalance"] for k in range(cyl)])
    t = -pad
    while t < cycles * cycle + pad:
        for k, o in enumerate(cfg["offs"]):
            te = t + o * cycle
            i0 = int((te + pad) * SR)
            if i0 < 0 or i0 + pw >= n:
                continue
            amp = bank[k] * (1.0 + rng.normal(0, .07 if on_load else .18))
            if not on_load:
                amp *= 0.45
                if rng.random() < 0.04:  # overrun crackle
                    amp *= 2.6
            pulses[i0:i0 + pw] += shape * amp
        t += cycle
    # Exhaust body: fixed resonances (they don't move with rpm)
    body = np.zeros(n)
    for f, q, g in cfg["res"]:
        body += resonator(pulses, f, q, g)
    body = comb(body, *cfg["comb"])
    # Rasp: raw pulse edge content, more at high rpm
    rasp = lowpass(pulses, 2500) * cfg["rasp"] * (0.5 + rpm / 9500)
    # Intake roar: band noise breathing with the firing
    env = lowpass(pulses, 60)
    env = env / (env.max() + 1e-9)
    noise = bandpass(rng.standard_normal(n), 700, 3200 if on_load else 1800) * (0.25 + 0.75 * env)
    intake = noise * (0.12 if on_load else 0.05) * (0.4 + rpm / 9500)
    x = body / (np.abs(body).max() + 1e-9) + rasp + intake
    # Muffler, then soft saturation under load
    x = lowpass(x, cfg["lp"] * (1.0 if on_load else 0.6) * (0.75 + 0.35 * rpm / 9500))
    if on_load:
        x = np.tanh(x * 2.2) * 0.9
    else:
        x = np.tanh(x * 1.2)
    # Remove DC rumble below audibility and cut the loop on whole cycles
    b, a = signal.butter(2, 30 / (SR / 2), "high")
    x = signal.lfilter(b, a, x)
    i0 = int(pad * SR)
    length = int(round(cycles * cycle * SR))
    loop = x[i0:i0 + length]
    # Tiny crossfade so the seam is inaudible even with per-cycle randomness
    f = min(200, length // 8)
    head = loop[:f].copy()
    loop[:f] = head * np.linspace(0, 1, f) + x[i0 + length:i0 + length + f] * np.linspace(1, 0, f)
    return loop / (np.abs(loop).max() + 1e-9) * 0.9


def write_wav(path, data):
    import wave
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for cyl in ENGINES:
        for rpm in RPMS:
            for on in (True, False):
                d = render(cyl, rpm, on, cyl * 1000 + rpm + (1 if on else 0))
                write_wav(os.path.join(OUT, "e%d_%s_%d.wav" % (cyl, "on" if on else "off", rpm)), d)
        print("engine", cyl, "done")
