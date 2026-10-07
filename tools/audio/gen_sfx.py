#!/usr/bin/env python3
"""Car sound effects: tyres, road roar, wind, gravel, nitrous, crashes, turbo,
backfire and the gas station service. Writes assets/audio/<name>.wav.

Loops end on a crossfade so they repeat without a click. One-shots are layered
from a few physical parts (a low body thump, ringing sheet metal, glass) rather
than one filtered noise burst.

  python3 tools/audio/gen_sfx.py
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")


def write_wav(name, data, peak=0.9):
    data = np.asarray(data, dtype=np.float64)
    data = data / (np.abs(data).max() + 1e-9) * peak
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def lp(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def smooth_noise(rng, n, rate):
    """Slowly wandering noise in [-1, 1], about `rate` changes per second."""
    k = max(4, int(n / SR * rate) + 4)
    pts = rng.uniform(-1, 1, k)
    return np.interp(np.linspace(0, k - 3, n), np.arange(k), pts)


def loop(x, fade=0.25):
    """Crossfade the tail into the head so the loop is seamless."""
    f = int(SR * fade)
    body = x[:-f].copy()
    tail = x[-f:]
    ramp = np.linspace(0, 1, f)
    body[:f] = body[:f] * ramp + tail * (1 - ramp)
    return body


def pink(rng, n):
    w = rng.standard_normal(n)
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, w)


def tire_squeal(rng):
    # Stick-slip screech: a few partials whose pitch jitters and wanders, chopped
    # by fast amplitude flutter, over a bed of hiss.
    sec = 3.25
    t = t_axis(sec)
    n = t.size
    f0 = 820 + 90 * smooth_noise(rng, n, 1.5) + 25 * smooth_noise(rng, n, 30)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    tone = np.zeros(n)
    for k, g in [(1, 1.0), (2, 0.45), (3, 0.3), (4.1, 0.12), (5.2, 0.07)]:
        tone += g * np.sin(ph * k + rng.uniform(0, 6.28))
    flutter = 0.6 + 0.4 * np.clip(smooth_noise(rng, n, 22) * 1.6, -1, 1)
    hiss = bp(rng.standard_normal(n), 1500, 5000) * 0.1
    rough = bp(rng.standard_normal(n), 300, 1200) * 0.25 * (0.6 + 0.4 * smooth_noise(rng, n, 8))
    x = tone * flutter * 0.55 + hiss + rough
    return loop(lp(np.tanh(x * 1.2), 6000))


def road(rng):
    # Tyre roar on asphalt: pink noise shaped to a low hump with coarse texture.
    t = t_axis(3.25)
    n = t.size
    x = lp(hp(pink(rng, n), 60), 1400)
    x += bp(rng.standard_normal(n), 140, 420) * 0.15 * (0.7 + 0.3 * smooth_noise(rng, n, 6))
    # Expansion joints / patches: soft thumps now and then
    for k in range(4):
        i = rng.integers(0, n - SR // 10)
        thud = np.sin(2 * np.pi * 70 * t[: SR // 10]) * np.exp(-t[: SR // 10] * 45)
        x[i:i + SR // 10] += thud * 0.6
    return loop(x)


def wind(rng):
    t = t_axis(4.25)
    n = t.size
    gust = 0.65 + 0.35 * smooth_noise(rng, n, 0.8)
    low = lp(pink(rng, n), 500) * 1.0
    mid = bp(rng.standard_normal(n), 500, 2500) * 0.18 * (0.5 + 0.5 * smooth_noise(rng, n, 2.5))
    # A faint whistle around the mirrors that drifts in pitch
    f = 1150 + 120 * smooth_noise(rng, n, 0.6)
    whistle = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.03 * (0.5 + 0.5 * smooth_noise(rng, n, 1.2))
    return loop((low + mid) * gust + whistle)


def gravel(rng):
    # Crunching stones: dense random grains (short clicks) through a couple of
    # resonances, on top of a low rumble.
    sec = 2.25
    n = int(SR * sec)
    grains = np.zeros(n)
    count = int(sec * 900)
    idx = rng.integers(0, n - 200, count)
    amps = rng.exponential(0.35, count)
    for i, a in zip(idx, amps):
        L = int(rng.integers(20, 120))
        grains[i:i + L] += a * rng.standard_normal(L) * np.exp(-np.linspace(0, 6, L))
    crunch = bp(grains, 400, 5000) + resonate(grains, [(900, 6), (1900, 8), (3200, 10)]) * 0.3
    rumble = lp(pink(rng, n), 250) * 0.8
    x = crunch * 0.8 + rumble
    return loop(lp(np.tanh(x / (np.sqrt((x ** 2).mean()) * 3.0)), 6000))


def resonate(x, modes):
    y = np.zeros_like(x)
    for f, q in modes:
        w0 = 2 * np.pi * f / SR
        alpha = np.sin(w0) / (2 * q)
        b = np.array([alpha, 0, -alpha])
        a = np.array([1 + alpha, -2 * np.cos(w0), 1 - alpha])
        y += signal.lfilter(b / a[0], a / a[0], x)
    return y


def nitro(rng):
    # Pressurised gas rushing: bright hiss plus a low turbulent roar.
    t = t_axis(2.25)
    n = t.size
    hiss = bp(rng.standard_normal(n), 1800, 6500) * 0.12
    roar = bp(pink(rng, n), 120, 900) * 2.5 * (0.8 + 0.2 * smooth_noise(rng, n, 9))
    return loop(hiss + roar)


def ring(t, f, decay, amp=1.0):
    return amp * np.sin(2 * np.pi * f * t) * np.exp(-t * decay)


def impact(rng, heavy):
    # Low body thump, a crunch of buckling panels, ringing sheet metal (inharmonic
    # modes) and, for heavy hits, glass and debris settling afterwards.
    sec = 1.6 if heavy else 0.9
    t = t_axis(sec)
    n = t.size
    thump = np.sin(2 * np.pi * (55 + 40 * np.exp(-t * 30)) * t) * np.exp(-t * (9 if heavy else 14)) * 1.4
    crunch_env = np.exp(-t * (11 if heavy else 18)) * (1 + 0.5 * (smooth_noise(rng, n, 60) > 0.2))
    crunch = bp(rng.standard_normal(n), 200, 2800) * crunch_env * 0.9
    metal = np.zeros(n)
    for _ in range(9 if heavy else 6):
        f = rng.uniform(350, 3200)
        metal += ring(t, f, rng.uniform(6, 16), rng.uniform(0.05, 0.16))
    x = thump + crunch + metal
    if heavy:
        glass = np.zeros(n)
        for _ in range(26):
            i = int(rng.uniform(0.03, 0.55) * SR)
            L = int(0.12 * SR)
            tt = t[:L]
            ping = sum(ring(tt, rng.uniform(3500, 9000), rng.uniform(25, 60), rng.uniform(0.02, 0.06)) for _ in range(2))
            ping += hp(rng.standard_normal(L), 4000) * np.exp(-tt * 70) * 0.04
            glass[i:i + L] += ping
        debris = np.zeros(n)
        for _ in range(10):
            i = int(rng.uniform(0.15, 1.1) * SR)
            L = int(0.05 * SR)
            debris[i:i + L] += bp(rng.standard_normal(L), 600, 3000) * np.exp(-t[:L] * 90) * rng.uniform(0.05, 0.15)
        x += glass * 0.7 + debris
    return lp(np.tanh(x * 1.6), 8000)


def backfire(rng):
    t = t_axis(0.45)
    n = t.size
    pop = lp(rng.standard_normal(n), 2500) * np.exp(-t * 90)
    boom = np.sin(2 * np.pi * (70 + 60 * np.exp(-t * 40)) * t) * np.exp(-t * 18)
    body = resonate(pop, [(180, 4), (420, 5), (900, 6)]) * 0.6
    tail = lp(rng.standard_normal(n), 1200) * np.exp(-t * 14) * 0.15
    return lp(np.tanh((pop * 0.5 + boom + body + tail) * 2.0), 5000)


def blowoff(rng):
    # Turbo blow-off: a sharp pssh that falls in pitch with a little flutter.
    t = t_axis(0.55)
    n = t.size
    env = np.minimum(t / 0.01, 1) * np.exp(-t * 6.5)
    x = np.zeros(n)
    hop = 512
    noise = rng.standard_normal(n)
    for i in range(0, n - hop, hop):
        fc = 2400 + 3200 * np.exp(-t[i] * 5)
        seg = bp(noise[max(0, i - 2048):i + hop], fc * 0.55, min(fc * 1.6, SR / 2 - 100))
        x[i:i + hop] = seg[-hop:]
    flutter = 1 - 0.35 * (np.sin(2 * np.pi * 34 * t) > 0) * (t > 0.12)
    return lp(x * env * flutter, 7000)


def repair(rng):
    # Gas station service: two bursts of an impact wrench, a hood clunk, the pump
    # nozzle clicking off and a short pleasant chime.
    sec = 2.1
    t = t_axis(sec)
    n = t.size
    x = np.zeros(n)

    def wrench(start, dur):
        i = int(start * SR)
        L = int(dur * SR)
        tt = t[:L]
        hammer = (np.sin(2 * np.pi * 38 * tt) > 0.6).astype(float)  # rotor hammering ~38 Hz
        clicks = lp(np.diff(hammer, prepend=0) ** 2, 6000)
        motor = np.sin(2 * np.pi * np.cumsum(np.full(L, 480.0) + 60 * np.sin(2 * np.pi * 38 * tt)) / SR)
        air = bp(rng.standard_normal(L), 2000, 6000) * 0.05
        env = np.minimum(tt / 0.02, 1) * np.minimum((dur - tt) / 0.03, 1)
        x[i:i + L] += (resonate(clicks, [(1300, 8), (2700, 10), (4100, 12)]) * 2.0 + motor * 0.12 + air) * env

    wrench(0.05, 0.42)
    wrench(0.62, 0.3)
    # Hood clunk
    i = int(1.05 * SR)
    L = int(0.3 * SR)
    tt = t[:L]
    x[i:i + L] += (np.sin(2 * np.pi * 95 * tt) * np.exp(-tt * 25) + bp(rng.standard_normal(L), 200, 2000) * np.exp(-tt * 40) * 0.5) * 1.2
    # Nozzle click-off
    i = int(1.32 * SR)
    L = int(0.06 * SR)
    x[i:i + L] += resonate(rng.standard_normal(L) * np.exp(-t[:L] * 200), [(2200, 12), (3600, 14)]) * 1.2
    # Chime
    for k, (f, st) in enumerate([(1046.5, 1.45), (1568.0, 1.58)]):
        i = int(st * SR)
        L = n - i
        tt = t[:L]
        x[i:] += (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * f * 2 * tt)) * np.exp(-tt * 5) * 0.35
    return lp(x, 8000)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(7)
    write_wav("tire_squeal", tire_squeal(rng))
    write_wav("road", road(rng))
    write_wav("wind", wind(rng))
    write_wav("gravel", gravel(rng))
    write_wav("nitro", nitro(rng))
    write_wav("impact", impact(rng, False))
    write_wav("impact_heavy", impact(rng, True))
    write_wav("backfire", backfire(rng))
    write_wav("blowoff", blowoff(rng), 0.7)
    write_wav("repair", repair(rng))
    print("sfx done")
