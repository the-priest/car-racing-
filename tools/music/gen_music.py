#!/usr/bin/env python3
"""Synthesizes the Velocity Heat soundtrack (synthwave) into assets/music/*.ogg.

Requires numpy, scipy and ffmpeg (with libvorbis). Deterministic: same output every run.
Usage: python3 tools/music/gen_music.py [track_id ...]
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
import scipy.signal as sg

SR = 44100
MINOR = [0, 2, 3, 5, 7, 8, 10]
DORIAN = [0, 2, 3, 5, 7, 9, 10]
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "music")


def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def deg_midi(root, scale, deg):
    o, d = divmod(deg, 7)
    return root + 12 * o + scale[d]


# ---------------------------------------------------------------- DSP helpers

def lp(x, fc, order=2):
    fc = min(fc, SR * 0.45)
    return sg.sosfilt(sg.butter(order, fc, fs=SR, output="sos"), x, axis=-1)


def hp(x, fc, order=2):
    return sg.sosfilt(sg.butter(order, fc, fs=SR, btype="high", output="sos"), x, axis=-1)


def bp(x, lo, hi, order=2):
    return sg.sosfilt(sg.butter(order, [lo, min(hi, SR * 0.45)], fs=SR, btype="band", output="sos"), x, axis=-1)


def sweep(x, f0, f1, kind="low", blocks=96):
    """Time-varying filter, exponential cutoff sweep from f0 to f1."""
    out = np.zeros_like(x)
    n = x.shape[-1]
    zi = None
    edges = np.linspace(0, n, blocks + 1).astype(int)
    for i in range(blocks):
        fc = f0 * (f1 / f0) ** (i / max(blocks - 1, 1))
        sos = sg.butter(2, min(fc, SR * 0.45), fs=SR, btype=kind, output="sos")
        seg = x[..., edges[i]:edges[i + 1]]
        if zi is None:
            zi = np.zeros((sos.shape[0],) + seg.shape[:-1] + (2,))
            zi = np.moveaxis(zi, -1, 1) if seg.ndim > 1 else zi
        out[..., edges[i]:edges[i + 1]], zi = sg.sosfilt(sos, seg, axis=-1, zi=zi)
    return out


def saw(f, t, ph=0.0):
    return 2.0 * ((f * t + ph) % 1.0) - 1.0


def square(f, t, ph=0.0, pw=0.5):
    return np.where(((f * t + ph) % 1.0) < pw, 1.0, -1.0)


def tri(f, t, ph=0.0):
    return 2.0 * np.abs(saw(f, t, ph)) - 1.0


def env_adsr(n, a, d, s, r, gate):
    """Sample-domain ADSR. gate = samples key held."""
    t = np.arange(n) / SR
    g = gate / SR
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    held = e[min(gate, n - 1)] if gate < n else e[-1]
    rel = held * np.exp(-(t - g) / max(r, 1e-4))
    return np.where(t < g, e, rel)


def compress(x, thr_rel, ratio):
    """Bus compressor: smoothed peak envelope, threshold relative to the track's peak."""
    from scipy.ndimage import maximum_filter1d
    lvl = maximum_filter1d(np.abs(x).max(0), int(0.006 * SR))
    lvl = lp(lvl, 6.0, 1)
    thr = thr_rel * np.abs(x).max()
    g = np.where(lvl > thr, (thr / np.maximum(lvl, 1e-9)) ** (1 - 1 / ratio), 1.0)
    return x * g


def haas(x, secs):
    """Widen: mid->side by delaying one side's copy (inverted on the other)."""
    d = int(secs * SR)
    side = np.zeros(x.shape[1])
    m = x.mean(0)
    side[d:] = m[:-d]
    side = hp(side, 300)
    return np.stack([side, -side])


def pan2(x, p):
    p = np.clip(p, -1, 1)
    return np.stack([x * np.sqrt((1 - p) / 2), x * np.sqrt((1 + p) / 2)])


def reverb(x, decay, seed=1, tone=6000.0, pre=0.012):
    rng = np.random.default_rng(seed)
    n = int(decay * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 6.9 / decay)
    ir = rng.standard_normal((2, n)) * env
    ir = lp(ir, tone)
    ir[:, : int(pre * SR)] = 0
    ir /= np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))
    out = np.stack([sg.oaconvolve(x[0], ir[0])[: x.shape[1]], sg.oaconvolve(x[1], ir[1])[: x.shape[1]]])
    return out * 0.5


def delay(x, secs, fb, pingpong=True, tone=3500.0):
    out = np.zeros_like(x)
    d = int(secs * SR)
    g = 1.0
    k = 1
    tap = lp(x, tone)
    while g * fb > 0.02 and k * d < x.shape[1]:
        g *= fb
        src = tap if not pingpong else (tap[::-1] if k % 2 else tap)
        out[:, k * d:] += src[:, : x.shape[1] - k * d] * g
        k += 1
    return out


# ---------------------------------------------------------------- instruments

def kick(punch=1.0):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 48 + 140 * np.exp(-t * 28) * punch
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 7.5)
    click = hp(np.random.default_rng(3).standard_normal(n), 2500) * np.exp(-t * 300) * 0.25
    return np.tanh((body + click) * 1.6) * 0.9


def snare(gated=True):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(5)
    noise = bp(rng.standard_normal(n), 900, 9000) * np.exp(-t * 16)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 30) * 0.6
    return (noise * 0.8 + tone) * 0.55


def clap():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(9)
    e = np.zeros(n)
    for k, off in enumerate([0.0, 0.011, 0.022]):
        i = int(off * SR)
        e[i:] += np.exp(-(t[: n - i]) * (140 if k < 2 else 22))
    return bp(rng.standard_normal(n), 1000, 6000) * e * 0.45


def hat(open_=False):
    n = int((0.35 if open_ else 0.08) * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(11 if open_ else 12)
    return hp(rng.standard_normal(n), 7500, 4) * np.exp(-t * (11 if open_ else 70)) * 0.19


def crash():
    n = int(2.4 * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(13)
    x = hp(rng.standard_normal((2, n)), 4500) * np.exp(-t * 1.9)
    return x * 0.22


def tom(f0):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.6 * np.exp(-t * 18))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 8) * 0.5


def riser(secs, seed=21):
    n = int(secs * SR)
    rng = np.random.default_rng(seed)
    x = rng.standard_normal((2, n))
    x = sweep(x, 300, 9000, "low")
    x = sweep(x, 120, 2500, "high")
    return x * np.linspace(0, 1, n) ** 2 * 0.25


def impact():
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    sub = np.sin(2 * np.pi * np.cumsum(30 + 60 * np.exp(-t * 6)) / SR) * np.exp(-t * 2.5)
    return sub * 0.7


def bass_note(midi, n_gate, style="saw", cut=900.0, env_amt=2200.0):
    n = n_gate + int(0.08 * SR)
    t = np.arange(n) / SR
    f = mtof(midi)
    if style == "saw":
        x = saw(f, t) * 0.6 + saw(f * 1.004, t, 0.3) * 0.4
    elif style == "square":
        x = square(f, t, pw=0.42) * 0.7
    else:  # sub / soft
        x = tri(f, t) * 0.8 + saw(f, t) * 0.25
    x += np.sin(2 * np.pi * f / 2 * t) * 0.35
    fe = np.exp(-t * 14)
    lo = lp(x, cut)
    hi = lp(x, cut + env_amt)
    x = lo * (1 - fe) + hi * fe
    return x * env_adsr(n, 0.004, 0.25, 0.75, 0.04, n_gate) * 0.5


def pluck(midi, n_gate, bright=4500.0, wave_="square"):
    n = n_gate + int(0.25 * SR)
    t = np.arange(n) / SR
    f = mtof(midi)
    x = (square(f, t, pw=0.3) if wave_ == "square" else saw(f, t)) * 0.5 + saw(f * 2.003, t) * 0.15
    fe = np.exp(-t * 18)
    x = lp(x, 1100) * (1 - fe) + lp(x, bright) * fe
    return x * env_adsr(n, 0.002, 0.18, 0.15, 0.12, n_gate) * 0.32


def lead_note(midi, n_gate, prev_midi=None, glide=0.05, vib=0.18, tone=5200.0, wave_="saw"):
    n = n_gate + int(0.35 * SR)
    t = np.arange(n) / SR
    f = np.full(n, mtof(midi))
    if prev_midi is not None and glide > 0:
        gl = np.exp(-t / glide)
        f = mtof(midi) * (mtof(prev_midi) / mtof(midi)) ** gl
    v = np.clip((t - 0.22) / 0.3, 0, 1) * vib
    f = f * 2 ** (v * np.sin(2 * np.pi * 5.6 * t) / 12)
    ph = np.cumsum(f) / SR
    if wave_ == "saw":
        x = (2 * (ph % 1) - 1) * 0.5 + (2 * ((ph * 1.006 + 0.4) % 1) - 1) * 0.5
    else:
        x = np.where((ph % 1) < 0.5, 1.0, -1.0) * 0.45 + (2 * ((ph * 0.997) % 1) - 1) * 0.35
    x = lp(x, tone)
    return x * env_adsr(n, 0.012, 0.4, 0.8, 0.22, n_gate) * 0.26


def pad_chord(midis, n_gate, rng, cut=1800.0, voices=5, det=0.16, attack=0.35):
    n = n_gate + int(1.2 * SR)
    t = np.arange(n) / SR
    out = np.zeros((2, n))
    for m in midis:
        f = mtof(m)
        for i in range(voices):
            d = (i - (voices - 1) / 2) / ((voices - 1) / 2) * det
            s = saw(f * 2 ** (d / 12), t, rng.random())
            out += pan2(s, (i / (voices - 1)) * 1.6 - 0.8)
    out = lp(out, cut * 1.5)
    out *= env_adsr(n, attack, 0.8, 0.85, 0.9, n_gate)
    return out * (0.11 / np.sqrt(len(midis)))


# ---------------------------------------------------------------- song builder

class Song:
    def __init__(self, bpm, bars, root, scale=MINOR, swing=0.0, tail=4.0, seed=0):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bars = bars
        self.root = root
        self.scale = scale
        self.swing = swing
        self.length = int(round(bars * 4 * self.beat * SR))
        self.n = self.length + int(tail * SR)
        self.rng = np.random.default_rng(seed)
        self.bus = {k: np.zeros((2, self.n)) for k in
                    ["drums", "kick", "bass", "pad", "arp", "lead", "fx", "verb_send", "delay_send"]}
        self.kicks = []
        self.prog = []

    def idx(self, bar, step16=0.0):
        s = step16
        if self.swing and int(s) % 2 == 1:
            s += self.swing
        return int(round((bar * 4 + s / 4.0) * self.beat * SR))

    def samples(self, steps16):
        return int(steps16 / 4.0 * self.beat * SR)

    def put(self, bus, x, at, gain=1.0, p=0.0):
        if x.ndim == 1:
            x = pan2(x, p)
        if at >= self.n:
            return
        end = min(self.n, at + x.shape[1])
        self.bus[bus][:, at:end] += x[:, : end - at] * gain

    def deg(self, d, octave=0):
        return deg_midi(self.root + 12 * octave, self.scale, d)

    def fit(self, d, chord_deg, octave):
        """Nudge a held/strong-beat melody note off a semitone clash with the chord."""
        ct = [m % 12 for m in self.chord(chord_deg)]
        pc = self.deg(d, octave) % 12
        if pc in ct or min(min((pc - c) % 12, (c - pc) % 12) for c in ct) > 1:
            return d
        for nd in (d - 1, d + 1):
            if self.deg(nd, octave) % 12 in ct:
                return nd
        return d

    def chord(self, d, octave=0, seventh=False):
        out = [self.deg(d, octave), self.deg(d + 2, octave), self.deg(d + 4, octave)]
        if seventh:
            out.append(self.deg(d + 6, octave))
        return out

    # --- parts
    def drums(self, bar, pat, vel=1.0, kick_punch=1.0):
        """pat: dict name -> 16-char string, x = hit, o = soft hit."""
        sounds = {"k": None, "s": None, "c": None, "h": None, "H": None}
        for name, row in pat.items():
            for i, ch in enumerate(row):
                if ch in ".-":
                    continue
                g = vel * (0.55 if ch == "o" else 1.0)
                at = self.idx(bar, i)
                if name == "k":
                    self.put("kick", kick(kick_punch), at, g)
                    self.kicks.append(at)
                elif name == "s":
                    s = snare()
                    self.put("drums", s, at, g)
                    self.put("verb_send", s, at, g * 0.9)
                elif name == "c":
                    c = clap()
                    self.put("drums", c, at, g, 0.1)
                    self.put("verb_send", c, at, g * 0.6)
                elif name == "h":
                    self.put("drums", hat(), at, g * (0.8 if i % 2 else 1.0), 0.35)
                elif name == "H":
                    self.put("drums", hat(True), at, g, -0.3)
        del sounds

    def fill(self, bar, kind="snare", vel=1.0):
        if kind == "snare":
            for i in range(8, 16):
                g = vel * (0.35 + 0.65 * (i - 8) / 7)
                self.put("drums", snare(), self.idx(bar, i), g)
                self.put("verb_send", snare(), self.idx(bar, i), g * 0.7)
        else:
            for k, i in enumerate(range(8, 16, 2)):
                tm = tom(160 - k * 25)
                self.put("drums", tm, self.idx(bar, i), vel, 0.5 - k * 0.33)
                self.put("verb_send", tm, self.idx(bar, i), vel * 0.5)

    def crash(self, bar, g=1.0):
        self.put("drums", crash(), self.idx(bar), g)

    def riser(self, bar, bars=2, g=1.0):
        r = riser(bars * 4 * self.beat)
        self.put("fx", r, self.idx(bar), g)

    def impact(self, bar, g=1.0):
        self.put("fx", impact(), self.idx(bar), g)

    def bassline(self, bar, chord_deg, pattern, style="saw", octave=-2, cut=900.0, gain=1.0):
        """pattern: list of (step16, len16, offset_degree or 'o' for octave)."""
        for st, ln, off in pattern:
            if off == "o":
                m = self.deg(chord_deg, octave + 1)
            elif off == "5":
                m = self.deg(chord_deg + 4, octave)
            else:
                m = self.deg(chord_deg + off, octave)
            self.put("bass", bass_note(m, self.samples(ln), style, cut), self.idx(bar, st), gain)

    def pad(self, bar, chord_deg, bars=1, octave=0, seventh=True, cut=1800.0, gain=1.0, attack=0.35):
        ch = self.chord(chord_deg, octave, seventh)
        x = pad_chord(ch, self.samples(16 * bars) - int(0.05 * SR), self.rng, cut, attack=attack)
        self.put("pad", x, self.idx(bar), gain)
        self.put("verb_send", x, self.idx(bar), gain * 0.8)

    def arp(self, bar, chord_deg, order, octave=1, step=1, gain=1.0, bright=4500.0, wave_="square", p=0.0):
        ch = self.chord(chord_deg, octave, True) + [self.deg(chord_deg, octave + 1)]
        for k, i in enumerate(range(0, 16, step)):
            o = order[k % len(order)]
            if o is None:
                continue
            x = pluck(ch[o], self.samples(step) - int(0.01 * SR), bright, wave_)
            at = self.idx(bar, i)
            self.put("arp", x, at, gain, p)
            self.put("delay_send", x, at, gain * 0.6)

    def melody(self, bar, notes, octave=1, gain=1.0, tone=5200.0, wave_="saw", glide=0.04, p=0.0):
        """notes: list of (step16 from bar start (may exceed 16), len16, degree)."""
        prev = None
        for st, ln, d in notes:
            if d is None:
                prev = None
                continue
            if self.prog and (st % 16 in (0, 8) or ln >= 4):
                d = self.fit(d, self.prog[(bar + st // 16) % len(self.prog)], octave)
            m = self.deg(d, octave)
            x = lead_note(m, self.samples(ln), prev, glide, tone=tone, wave_=wave_)
            at = self.idx(bar, st)
            self.put("lead", x, at, gain, p)
            self.put("delay_send", x, at, gain * 0.5)
            self.put("verb_send", x, at, gain * 0.5)
            prev = m

    # --- mixdown
    def render(self, loop=False, sc_depth=0.55, verb=2.8, dly=0.75, mix=None):
        mix = mix or {}
        n = self.n
        sc = np.ones(n)
        rel = int(self.beat * 0.9 * SR)
        curve = 1 - sc_depth * np.exp(-np.arange(rel) / (0.11 * SR))
        curve[: int(0.004 * SR)] = np.linspace(1, curve[int(0.004 * SR)], int(0.004 * SR))
        for k in self.kicks:
            e = min(n, k + rel)
            sc[k:e] = np.minimum(sc[k:e], curve[: e - k])
        b = self.bus
        wet_v = reverb(b["verb_send"], verb, seed=2)
        wet_d = delay(b["delay_send"], self.beat * 0.75, 0.42)
        wet_d += reverb(wet_d, verb * 0.7, seed=4) * 0.6
        pad = b["pad"] + haas(b["pad"], 0.011) * 0.5
        out = (b["kick"] * mix.get("kick", 0.75)
               + b["drums"] * mix.get("drums", 1.0)
               + hp(b["bass"], 35) * sc * mix.get("bass", 0.6)
               + pad * sc * mix.get("pad", 1.25)
               + b["arp"] * sc * mix.get("arp", 1.0)
               + (b["lead"] + haas(b["lead"], 0.017) * 0.35) * mix.get("lead", 1.05)
               + b["fx"] * mix.get("fx", 0.8)
               + wet_v * sc * mix.get("verb", 0.55)
               + wet_d * mix.get("delay", 0.35) * dly)
        out = hp(out, 25)
        # Master tilt: tame mud, open up the top end.
        out = out - 0.3 * bp(out, 150, 400) + 1.0 * hp(out, 2600) + 0.2 * hp(out, 7500)
        if loop:
            tail = out[:, self.length:]
            out = out[:, : self.length].copy()
            out[:, : tail.shape[1]] += tail
        else:
            fade = int(3.5 * SR)
            out[:, -fade:] *= np.linspace(1, 0, fade) ** 2
        out = compress(out, 0.25, 3.0)
        peak = np.percentile(np.abs(out), 99.97)
        out = np.tanh(out / peak * 1.1) / np.tanh(1.1) * 0.72
        return out


def write_ogg(name, x, title, artist):
    os.makedirs(OUT_DIR, exist_ok=True)
    pcm = (np.clip(x, -1, 1).T * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    dst = os.path.join(OUT_DIR, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", "3",
                    "-metadata", "title=" + title, "-metadata", "artist=" + artist, dst], check=True)
    os.unlink(path)
    print("wrote", dst, round(x.shape[1] / SR, 1), "s")


# ---------------------------------------------------------------- tracks

FOUR = {"k": "x...x...x...x...", "s": "....x.......x...", "h": "..x...x...x...x."}
FOUR_16 = {"k": "x...x...x...x...", "s": "....x.......x...", "h": "xxxxxxxxxxxxxxxx"}
HALF = {"k": "x.........x.....", "s": "........x.......", "h": "x.x.x.x.x.x.x.x."}

EIGHTH_BASS = [(i, 2, 0) for i in range(0, 16, 2)]
OCT_BASS = [(i, 1, 0 if (i // 2) % 2 == 0 else "o") for i in range(0, 16, 2)]
GALLOP = [(0, 1, 0), (1, 1, 0), (2, 2, 0), (4, 1, 0), (5, 1, 0), (6, 2, 0),
          (8, 1, 0), (9, 1, 0), (10, 2, 0), (12, 1, 0), (13, 1, 0), (14, 2, "o")]
SIXTEENTH = [(i, 1, 0 if i % 4 else "o") for i in range(16)]


def solano_nights():
    """Free roam: classic synthwave, A minor, 102 BPM."""
    s = Song(102, 72, 57, MINOR, seed=1)
    prog = [0, 5, 2, 6]  # Am F C G
    s.prog = prog
    mel_a = [(0, 3, 4), (3, 3, 2), (6, 2, 4), (8, 6, 7), (14, 2, 6),
             (16, 3, 5), (19, 3, 4), (22, 2, 2), (24, 8, 4),
             (32, 3, 4), (35, 3, 2), (38, 2, 4), (40, 6, 7), (46, 2, 9),
             (48, 4, 8), (52, 2, 7), (54, 2, 6), (56, 8, 6)]
    mel_b = [(0, 2, 7), (2, 2, 9), (4, 4, 11), (8, 2, 9), (10, 2, 7), (12, 4, 9),
             (16, 6, 7), (22, 2, 5), (24, 8, 4),
             (32, 2, 4), (34, 2, 5), (36, 4, 7), (40, 2, 6), (42, 2, 4), (44, 4, 6),
             (48, 4, 4), (52, 4, 2), (56, 8, 1)]
    for bar in range(s.bars):
        c = prog[bar % 4]
        sec = bar // 8
        # 0 intro, 1 build, 2-3 A, 4-5 B, 6 break, 7-8 B' (big)
        if bar % 4 == 0:
            s.pad(bar, c, 1, 0, cut=900 if sec == 0 else 1900, gain=0.8 if sec == 0 else 1.0)
        else:
            s.pad(bar, c, 1, 0, cut=900 if sec == 0 else 1900, gain=0.8 if sec == 0 else 1.0)
        if sec >= 1 and sec != 6:
            s.arp(bar, c, [0, 1, 2, 4, 2, 1, 3, 1], 1, 2, 0.8 if sec < 7 else 0.9, 3800 if sec < 2 else 5000)
        if sec == 0:
            s.arp(bar, c, [0, None, 2, None, 4, None, 2, None], 1, 2, 0.5, 1800)
        if sec >= 2 and sec != 6:
            s.drums(bar, FOUR if sec < 7 else FOUR_16)
            s.bassline(bar, c, OCT_BASS if sec < 7 else GALLOP, "saw", -2, 800)
        if sec == 1:
            s.drums(bar, {"h": "..x...x...x...x."}, 0.7)
            s.bassline(bar, c, [(0, 14, 0)], "soft", -2, 500, 0.9)
        if sec == 6:
            s.drums(bar, {"k": "x..............." if bar % 2 == 0 else "................"}, 0.6)
            s.bassline(bar, c, [(0, 15, 0)], "soft", -2, 400, 0.8)
        if sec in (4, 5) and bar % 4 == 0:
            s.melody(bar, mel_a if (bar // 4) % 2 == 0 else mel_b, 1, 1.0)
        if sec in (7, 8) and bar % 4 == 0:
            s.melody(bar, mel_a if (bar // 4) % 2 == 0 else mel_b, 1, 0.95)
            s.melody(bar, mel_a if (bar // 4) % 2 == 0 else mel_b, 2, 0.35, 3500, "square", 0.0, 0.3)
        if sec == 6 and bar % 4 == 0:
            s.melody(bar, mel_b, 0, 0.6, 2400, "square")
        if bar % 8 == 7 and sec in (1, 3, 5):
            s.fill(bar, "tom" if sec == 3 else "snare", 0.8)
        if bar % 8 == 0 and sec in (2, 4, 7):
            s.crash(bar)
            s.impact(bar, 0.6)
    s.riser(6, 2)
    s.riser(54, 2)
    return s.render(loop=False)


def coast_road():
    """Free roam: brighter, laid-back drive, E minor (dorian), 94 BPM."""
    s = Song(94, 64, 52, DORIAN, swing=0.12, seed=2)
    prog = [0, 3, 6, 2]  # Em A D G
    s.prog = prog
    mel = [(0, 2, 4), (2, 2, 5), (4, 6, 6), (10, 2, 4), (12, 4, 2),
           (16, 2, 3), (18, 2, 4), (20, 8, 5), (28, 4, None),
           (32, 2, 6), (34, 2, 7), (36, 6, 8), (42, 2, 7), (44, 4, 6),
           (48, 3, 4), (51, 3, 5), (54, 2, 4), (56, 8, 1)]
    mel2 = [(0, 4, 7), (4, 4, 8), (8, 4, 9), (12, 4, 7),
            (16, 6, 6), (22, 2, 5), (24, 8, 4),
            (32, 4, 4), (36, 4, 6), (40, 4, 7), (44, 4, 5),
            (48, 6, 4), (54, 2, 2), (56, 8, 3)]
    for bar in range(s.bars):
        c = prog[bar % 4]
        sec = bar // 8
        s.pad(bar, c, 1, 0, cut=1400 if sec in (0, 5) else 2200, gain=0.9)
        s.arp(bar, c, [0, 2, 4, 2, 3, 2, 4, 1], 1, 2, 0.55 if sec == 0 else 0.7, 3000, "saw", -0.3)
        if sec >= 1 and sec != 5:
            pat = {"k": "x.....x...x.....", "s": "....x.......x...", "h": "x.xxx.xxx.xxx.xx", "H": "..............x."}
            s.drums(bar, pat if sec > 1 else {"k": "x.....x...x.....", "h": "x.x.x.x.x.x.x.x."}, 0.9)
            s.bassline(bar, c, [(0, 3, 0), (3, 3, 0), (6, 2, "o"), (8, 3, 0), (11, 3, "5"), (14, 2, "o")], "soft", -2, 700)
        if sec == 5:
            s.bassline(bar, c, [(0, 16, 0)], "soft", -2, 450, 0.8)
        if sec in (2, 3, 6, 7) and bar % 4 == 0:
            s.melody(bar, mel if (bar // 4) % 2 == 0 else mel2, 1, 0.9, 4200, "square", 0.06)
        if sec == 5 and bar % 4 == 0:
            s.melody(bar, mel2, 0, 0.5, 2200, "square")
        if bar % 8 == 7 and sec in (1, 4):
            s.fill(bar, "tom", 0.7)
        if bar % 8 == 0 and sec in (2, 6):
            s.crash(bar, 0.8)
    s.riser(46, 2, 0.7)
    return s.render(loop=False, sc_depth=0.35)


def afterhours():
    """Free roam: dark club groove, C# minor, 112 BPM."""
    s = Song(112, 72, 61 - 12, MINOR, seed=3)
    prog = [0, 5, 3, 4]  # C#m A F#m G#m
    s.prog = prog
    hook = [(0, 2, 0), (2, 2, 0), (4, 2, 2), (6, 2, 0), (8, 2, 4), (10, 2, 3), (12, 4, 2),
            (16, 2, 0), (18, 2, 0), (20, 2, 2), (22, 2, 0), (24, 2, -1), (26, 2, 0), (28, 4, None)]
    lead = [(0, 6, 7), (6, 2, 6), (8, 8, 4), (16, 4, 5), (20, 4, 4), (24, 8, 2),
            (32, 6, 7), (38, 2, 9), (40, 8, 8), (48, 4, 7), (52, 4, 6), (56, 8, 4)]
    for bar in range(s.bars):
        c = prog[bar % 4]
        sec = bar // 8
        s.pad(bar, c, 1, 1, cut=1100 if sec < 2 else 1600, gain=0.75)
        if sec >= 1:
            s.drums(bar, {"k": "x...x...x...x...", "c": "....x.......x...", "h": "..x...x...x...xo",
                          "H": "..x...x...x...x."} if sec >= 2 and sec != 6 else {"h": "..x...x...x...x."}, 0.95)
            if sec != 6:
                s.bassline(bar, c, SIXTEENTH if sec >= 4 else OCT_BASS, "square", -1, 600, 0.85)
        if bar % 2 == 0 and sec >= 2:
            s.melody(bar, hook, 1, 0.55, 2600, "square", 0.0, 0.25)
        if sec in (4, 5, 7, 8) and bar % 4 == 0:
            s.melody(bar, lead, 1, 0.9, 5000, "saw", 0.05)
        if sec == 6:
            s.arp(bar, c, [0, 2, 4, 1, 3, 2, 4, 3], 1, 1, 0.5, 2500)
        if bar % 8 == 7 and sec in (3, 5):
            s.fill(bar, "snare", 0.75)
        if bar % 8 == 0 and sec in (2, 4, 7):
            s.crash(bar)
            s.impact(bar, 0.7)
    s.riser(54, 2)
    s.riser(14, 2, 0.6)
    return s.render(loop=False, sc_depth=0.6)


def heat_index():
    """Pursuit: darksynth, D minor, 132 BPM, loops."""
    s = Song(132, 48, 50, MINOR, seed=4)
    prog = [0, 6, 5, 6]  # Dm C Bb C
    s.prog = prog
    riff = [(0, 2, 0), (2, 1, 0), (3, 1, 2), (4, 2, 3), (6, 2, 2), (8, 2, 0), (10, 2, -1), (12, 4, 0),
            (16, 2, 0), (18, 1, 0), (19, 1, 2), (20, 2, 3), (22, 2, 4), (24, 2, 5), (26, 2, 4), (28, 4, 6)]
    lead = [(0, 4, 7), (4, 4, 9), (8, 6, 10), (14, 2, 9), (16, 4, 7), (20, 4, 6), (24, 8, 7),
            (32, 4, 7), (36, 4, 9), (40, 4, 10), (44, 4, 12), (48, 6, 11), (54, 2, 10), (56, 8, 9)]
    for bar in range(s.bars):
        c = prog[bar % 4]
        sec = bar // 8
        s.pad(bar, c, 1, 0, cut=1200, gain=0.7, attack=0.05)
        drums = {"k": "x...x...x...x.x.", "s": "....x.......x...", "h": "xxxxxxxxxxxxxxxx", "H": "..x...x...x...x."}
        if sec == 3:
            drums = {"k": "x.......x.......", "s": "........x.......", "h": "x.x.x.x.x.x.x.x."}
        s.drums(bar, drums, 1.0, 1.15)
        s.bassline(bar, c, GALLOP if sec != 3 else [(0, 16, 0)], "saw", -2, 1000 if sec != 3 else 500)
        if sec in (0, 2, 4, 5) and bar % 2 == 0:
            s.melody(bar, riff, 0, 0.75, 3200, "saw", 0.0, -0.2)
        if sec in (1, 4, 5) and bar % 4 == 0:
            s.melody(bar, lead, 1, 0.85, 5500, "saw", 0.05, 0.15)
        if sec == 3:
            s.arp(bar, c, [0, 1, 2, 3, 4, 3, 2, 1], 1, 1, 0.6, 4000, "saw")
        if bar % 8 == 7:
            s.fill(bar, "snare" if sec % 2 else "tom", 0.85)
        if bar % 8 == 0:
            s.crash(bar)
            s.impact(bar, 0.8)
    s.riser(30, 2, 0.8)
    return s.render(loop=True, sc_depth=0.5, verb=2.0, mix={"drums": 0.9})


def redline():
    """Races: high-energy outrun, F# minor, 142 BPM, loops."""
    s = Song(142, 48, 54, MINOR, seed=5)
    prog = [0, 5, 2, 6]
    s.prog = prog
    lead = [(0, 3, 7), (3, 3, 6), (6, 2, 7), (8, 4, 9), (12, 4, 7),
            (16, 3, 6), (19, 3, 5), (22, 2, 6), (24, 8, 4),
            (32, 3, 7), (35, 3, 6), (38, 2, 7), (40, 4, 9), (44, 4, 11),
            (48, 6, 10), (54, 2, 9), (56, 8, 7)]
    for bar in range(s.bars):
        c = prog[bar % 4]
        sec = bar // 8
        s.pad(bar, c, 1, 0, cut=2200, gain=0.8, attack=0.08)
        s.arp(bar, c, [0, 1, 2, 4, 3, 2, 4, 1], 1, 1, 0.65, 5000, "square", 0.2)
        s.drums(bar, FOUR_16 if sec != 3 else HALF, 1.0, 1.1)
        s.bassline(bar, c, OCT_BASS if sec in (0, 3) else SIXTEENTH, "saw", -2, 900)
        if sec in (1, 2, 4, 5) and bar % 4 == 0:
            s.melody(bar, lead, 1 if sec in (1, 4) else 2, 0.85, 6000, "saw", 0.04, -0.1)
        if bar % 8 == 7:
            s.fill(bar, "snare", 0.85)
        if bar % 8 == 0:
            s.crash(bar)
    s.riser(22, 2)
    return s.render(loop=True, sc_depth=0.5, verb=2.0)


def garage():
    """Menus and garage: mellow, G minor, 84 BPM, loops."""
    s = Song(84, 32, 55, DORIAN, swing=0.18, seed=6)
    prog = [0, 3, 5, 4]
    s.prog = prog
    mel = [(0, 4, 4), (4, 2, 3), (6, 2, 2), (8, 8, 4),
           (16, 4, 6), (20, 2, 5), (22, 2, 4), (24, 8, 2),
           (32, 4, 4), (36, 2, 5), (38, 2, 6), (40, 8, 7),
           (48, 4, 6), (52, 4, 4), (56, 8, 3)]
    for bar in range(s.bars):
        c = prog[bar % 4]
        sec = bar // 8
        s.pad(bar, c, 1, 0, cut=1100, gain=1.0, attack=0.6)
        s.arp(bar, c, [0, None, 2, 1, None, 3, 2, None], 1, 2, 0.45, 2200, "saw", -0.4)
        if sec >= 1:
            s.drums(bar, {"k": "x.......x.x.....", "s": "....o.......o...", "h": "x.x.x.x.x.x.x.xo"}, 0.7)
            s.bassline(bar, c, [(0, 6, 0), (6, 2, "5"), (8, 6, 0), (14, 2, "o")], "soft", -2, 500, 0.9)
        if sec in (2, 3) and bar % 4 == 0:
            s.melody(bar, mel, 1, 0.7, 2600, "square", 0.08)
    return s.render(loop=True, sc_depth=0.25, verb=3.2)


TRACKS = {
    "solano_nights": (solano_nights, "Solano Nights", "Midnight Grid"),
    "coast_road": (coast_road, "Coast Road", "Palm Static"),
    "afterhours": (afterhours, "Afterhours", "Neon Ward"),
    "heat_index": (heat_index, "Heat Index", "Kill Switch"),
    "redline": (redline, "Redline", "Overdrive 84"),
    "garage": (garage, "Dex's Garage", "Low Tide"),
}

if __name__ == "__main__":
    pick = sys.argv[1:] or list(TRACKS)
    for k in pick:
        fn, title, artist = TRACKS[k]
        write_ogg(k, fn(), title, artist)
