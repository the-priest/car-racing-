#!/usr/bin/env python3
"""Generates the game's tileable PBR surface textures into assets/textures/.

All materials go into two texture arrays (one slice per material, in LAYERS
order), so every shader needs only two samplers:
  surfaces_albedo.jpg  sRGB base colour
  surfaces_nrh.jpg     linear: R,G = tangent-space normal XY, B = roughness

Everything is built from periodic noise (spectral fBm) and periodic Voronoi
(cKDTree with boxsize), so the textures tile seamlessly.

  python3 tools/textures/gen_textures.py
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures")
N = 1024


# ---------------------------------------------------------------- noise helpers
def fbm(n, beta, seed, lo=1.0, hi=None, aniso=(1.0, 1.0)):
    """Periodic fractal noise, normalised to 0..1. beta: spectral falloff (2 = smooth)."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((n, n))
    # aniso < 1 on an axis stretches features along that axis (aniso=(1, 0.1): long in Y)
    fx = np.fft.fftfreq(n)[None, :] * n / aniso[0]
    fy = np.fft.fftfreq(n)[:, None] * n / aniso[1]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = 1.0 / np.power(f, beta * 0.5)
    amp[f < lo] = 0.0
    if hi is not None:
        amp *= np.exp(-(f / hi) ** 2)
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def voronoi(n, count, seed, jitter_scale=None):
    """Periodic Voronoi: returns F1, F2 distances (pixels) and the cell id per pixel."""
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0, n, (count, 2))
    tree = cKDTree(pts, boxsize=n)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64) + 0.5
    q = np.stack([xx.ravel(), yy.ravel()], axis=1)
    if jitter_scale is not None:
        q = (q + jitter_scale.reshape(-1, 2)) % n
    d, idx = tree.query(q, k=2)
    return d[:, 0].reshape(n, n), d[:, 1].reshape(n, n), idx[:, 0].reshape(n, n)


def warp(n, amount, seed, beta=2.6):
    wx = (fbm(n, beta, seed) - 0.5) * amount
    wy = (fbm(n, beta, seed + 1) - 0.5) * amount
    return np.stack([wx, wy], axis=-1)


def sample_wrap(img, dx, dy):
    n = img.shape[0]
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    return ndimage.map_coordinates(img, [(yy + dy) % n, (xx + dx) % n], order=1, mode="grid-wrap")


def stones(n, count, seed, radius, warp_amt, sizes=(0.6, 1.0)):
    """Separate rounded stones: dome height (0 outside a stone), mask and per-stone id.
    radius is a fraction of the average stone spacing."""
    spacing = n / np.sqrt(count)
    f1, f2, cid = voronoi(n, count, seed, warp(n, warp_amt, seed + 100, 2.2))
    rng = np.random.default_rng(seed + 200)
    r = spacing * radius * rng.uniform(sizes[0], sizes[1], count)[cid]
    # keep stones inside their own cell so neighbours never fuse into a mosaic
    r = np.minimum(r, (f1 + f2) * 0.5 - 0.8)
    t = np.clip(1.0 - f1 / np.maximum(r, 0.5), 0.0, 1.0)
    dome = np.sqrt(t)
    return dome, (t > 0.0).astype(np.float64), cid


def ao_from_height(h, radius=6):
    blur = ndimage.uniform_filter(h, size=radius * 2 + 1, mode="wrap")
    return np.clip(1.0 - (blur - h) * 2.5, 0.35, 1.0)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx = -dx * strength
    ny = dy * strength  # +Y up in Godot's (OpenGL) normal map convention
    nz = np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return nx / l, ny / l


def lerp(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(a) == 3 or np.ndim(b) == 3 else t
    return a + (b - a) * t


def rgb(c):
    return np.array(c, dtype=np.float64)[None, None, :]


RESULTS = {}


def save(name, albedo, height, strength, rough):
    a = np.clip(albedo, 0.0, 1.0)
    # albedo is authored in linear space; store sRGB
    a = np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1.0 / 2.4) - 0.055)
    nx, ny = normal_from_height(height, strength)
    nrh = np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, np.clip(rough, 0.0, 1.0)], axis=-1)
    RESULTS[name] = ((a * 255.0 + 0.5).astype(np.uint8), (nrh * 255.0 + 0.5).astype(np.uint8))
    print("made", name)


def write_arrays():
    """Slices go into an 8-wide grid (row-major), imported as a Texture2DArray."""
    os.makedirs(OUT, exist_ok=True)
    cols = 8
    rows = (len(LAYERS) + cols - 1) // cols
    for k, fname, q in [(0, "surfaces_albedo.jpg", 92), (1, "surfaces_nrh.jpg", 89)]:
        tiles = [RESULTS[nm][k] for nm in LAYERS]
        while len(tiles) < rows * cols:
            tiles.append(np.zeros_like(tiles[0]))
        grid = np.concatenate([np.concatenate(tiles[r * cols:(r + 1) * cols], axis=1) for r in range(rows)], axis=0)
        Image.fromarray(grid, "RGB").save(os.path.join(OUT, fname), quality=q, subsampling=0)
        print("wrote", fname, grid.shape, "slices", len(LAYERS))


# ---------------------------------------------------------------- materials
def asphalt():
    """Worn dense-graded asphalt, ~4 m per tile: grey chips set in black binder."""
    n = N
    rng = np.random.default_rng(13)
    dome, mask, cid = stones(n, 11000, 12, 0.5, 2.5, (0.45, 1.0))
    tone = rng.uniform(0.0, 1.0, 11000)[cid]
    fine_d, fine_m, fid = stones(n, 40000, 19, 0.45, 1.0, (0.4, 1.0))  # sand-size grit
    binder = fbm(n, 1.4, 15)
    big = fbm(n, 2.8, 14)
    pits = (fbm(n, 0.8, 16) > 0.88).astype(np.float64) * (1.0 - mask)
    wear = fbm(n, 2.4, 20)  # traffic polish: chips more exposed where worn
    exposed = mask * np.clip(0.55 + wear, 0.0, 1.0)
    h = dome * exposed * 0.8 + fine_d * 0.18 + binder * 0.15 - pits * 0.5 + big * 0.25
    ao = ao_from_height(h, 4)
    bind_col = rgb([0.022, 0.021, 0.02]) * (0.8 + 0.4 * binder[..., None]) * (1.0 + 0.6 * fine_m[..., None])
    stone_col = lerp(rgb([0.055, 0.055, 0.057]), rgb([0.15, 0.145, 0.14]), tone)
    stone_col = lerp(stone_col, rgb([0.26, 0.24, 0.22]), (tone > 0.95).astype(np.float64))
    col = lerp(bind_col, stone_col * (0.75 + 0.25 * dome[..., None]), exposed)
    fade = fbm(n, 3.0, 17)  # sun-bleached patches
    col = col * (0.85 + 0.35 * fade[..., None]) * ao[..., None]
    oil = np.clip((fbm(n, 2.6, 18) - 0.74) * 6.0, 0.0, 1.0)
    col = col * (1.0 - 0.35 * oil[..., None])
    rough = 0.8 + 0.1 * binder - 0.25 * exposed * dome - 0.25 * oil
    save("asphalt", col, h, 5.0, rough)

def grass():
    """Meadow grass from above: blade clumps, some dry straw and soil, ~3 m tile."""
    n = N
    rng = np.random.default_rng(21)
    # blades: strongly anisotropic noise at several orientations
    blades = np.zeros((n, n))
    for i, ang in enumerate(np.linspace(0, np.pi, 6, endpoint=False)):
        b = fbm(n, 1.2, 22 + i, aniso=(1.0, 0.18), hi=180)
        b = ndimage.rotate(np.tile(b, (2, 2)), np.degrees(ang), reshape=False, order=1, mode="wrap")[n // 2:n // 2 + n, n // 2:n // 2 + n]
        blades = np.maximum(blades, b)
    blades = np.roll(blades, (rng.integers(n), rng.integers(n)), (0, 1))
    blades = (blades - blades.min()) / (blades.max() - blades.min())
    clumps = fbm(n, 2.2, 30)
    dry = fbm(n, 2.8, 31)
    soil = np.clip((fbm(n, 2.4, 32) - 0.66) * 4.0, 0.0, 1.0) * (1.0 - blades)
    h = blades * 0.8 + clumps * 0.5
    lush = rgb([0.035, 0.085, 0.018])
    lush2 = rgb([0.06, 0.12, 0.025])
    straw = rgb([0.2, 0.17, 0.07])
    col = lerp(lush, lush2, clumps)
    col = lerp(col, straw, np.clip((dry - 0.55) * 2.5, 0.0, 1.0) * 0.8)
    col = col * (0.45 + 0.85 * blades[..., None])
    col = lerp(col, rgb([0.09, 0.065, 0.04]), soil)
    rough = 0.82 + 0.1 * (1.0 - blades)
    save("grass", col, h, 5.0, rough)


def dirt():
    """Packed dirt with half-buried pebbles and dry cracks, ~4 m tile."""
    n = N
    rng = np.random.default_rng(44)
    base = fbm(n, 2.0, 41)
    clods = fbm(n, 1.6, 40)
    dome, mask, cid = stones(n, 1400, 42, 0.32, 3.0, (0.3, 1.0))
    keep = (rng.uniform(0, 1, 1400)[cid] > 0.35).astype(np.float64)
    dome *= keep
    mask *= keep
    c1, c2, _ = voronoi(n, 50, 45, warp(n, 40.0, 46))
    crack = np.clip(1.0 - (c2 - c1) / 2.0, 0, 1) * np.clip((fbm(n, 2.4, 47) - 0.5) * 4.0, 0, 1)
    h = base * 0.5 + clods * 0.3 + dome * 0.6 - crack * 0.4
    ao = ao_from_height(h, 5)
    col = lerp(rgb([0.085, 0.062, 0.042]), rgb([0.17, 0.13, 0.09]), np.clip(base * 0.7 + clods * 0.4, 0, 1))
    tone = rng.uniform(0, 1, 1400)[cid]
    peb = lerp(rgb([0.1, 0.09, 0.08]), rgb([0.22, 0.2, 0.17]), tone) * (0.7 + 0.3 * dome[..., None])
    col = lerp(col, peb, mask * np.clip(dome * 3.0, 0, 1))
    col = col * (1.0 - 0.45 * crack[..., None]) * ao[..., None]
    rough = 0.92 - 0.12 * mask
    save("dirt", col, h, 5.0, rough)

def rock():
    """Fractured cliff rock, ~8 m tile, sampled triplanar: faceted blocks split by
    cracks, faint warped layering and vertical weathering streaks."""
    n = N
    rng = np.random.default_rng(56)
    count = 34
    w = warp(n, 90.0, 53, 2.0)
    f1, f2, cid = voronoi(n, count, 52, w)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    # Each block is a tilted facet: a random plane per cell gives sharp, chunky light.
    gx = rng.uniform(-1, 1, count)[cid]
    gy = rng.uniform(-1, 1, count)[cid]
    cxs = rng.uniform(0, n, count)
    facet = (gx * np.sin(xx * 2 * np.pi / n) + gy * np.sin(yy * 2 * np.pi / n)) * 0.5
    edge = f2 - f1
    # Only some block edges are open cracks; elsewhere the rock is continuous.
    crack = np.clip(1.0 - edge / 3.5, 0, 1) * np.clip((fbm(n, 2.4, 64) - 0.42) * 4.0, 0, 1)
    rim = np.clip(edge / 18.0, 0, 1)  # blocks round off toward their edges
    sub1, sub2, _ = voronoi(n, 600, 57, warp(n, 12.0, 58))
    small_crack = np.clip(1.0 - (sub2 - sub1) / 1.4, 0, 1) * np.clip((fbm(n, 2.0, 59) - 0.62) * 5.0, 0, 1)
    layers = 0.5 + 0.5 * np.sin((yy + w[..., 1] * 3.0 + w[..., 0]) * (2 * np.pi * 5 / n))
    streaks = fbm(n, 2.2, 60, aniso=(1.0, 0.12))  # vertical: long in Y
    grain = fbm(n, 1.3, 61)
    big = fbm(n, 2.4, 55)
    h = facet * 0.6 + np.sqrt(rim) * 0.35 + big * 0.8 + grain * 0.25 - crack * 0.8 - small_crack * 0.25 + layers * 0.08
    ao = ao_from_height(h, 10)
    tone = rng.uniform(0, 1, count)[cid]
    col = lerp(rgb([0.13, 0.12, 0.11]), rgb([0.3, 0.28, 0.25]), np.clip(0.5 * tone + 0.3 * big + 0.2 * layers, 0, 1))
    col = lerp(col, rgb([0.3, 0.22, 0.15]), np.clip((fbm(n, 2.8, 62) - 0.62) * 3.0, 0, 1) * 0.5)  # iron stain
    col = col * (0.82 + 0.25 * streaks[..., None])  # rain streaks down the face
    lichen = np.clip((fbm(n, 2.2, 63) - 0.7) * 5.0, 0, 1) * np.clip(grain * 1.6 - 0.4, 0, 1)
    col = lerp(col, rgb([0.15, 0.17, 0.1]), lichen * 0.55)
    col = col * (0.8 + 0.35 * grain[..., None]) * (1.0 - 0.55 * crack[..., None]) * (1.0 - 0.3 * small_crack[..., None]) * ao[..., None]
    rough = 0.82 + 0.1 * crack
    save("rock", col, h, 10.0, rough)

def sand():
    """Beach sand with wind ripples, ~4 m tile."""
    n = N
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    w = warp(n, 50.0, 61, 2.4)
    rip = 0.5 + 0.5 * np.sin((xx * 0.35 + yy + w[..., 0]) * (2 * np.pi * 24 / n))
    rip = np.power(rip, 1.6)
    grain = fbm(n, 0.3, 62)
    big = fbm(n, 2.6, 63)
    h = rip * 0.6 * (0.6 + 0.4 * big) + grain * 0.12
    col = lerp(rgb([0.38, 0.32, 0.22]), rgb([0.55, 0.48, 0.35]), big)
    col = col * (0.88 + 0.2 * grain[..., None]) * (0.92 + 0.12 * rip[..., None])
    shells = (fbm(n, 0.6, 64) > 0.93).astype(np.float64)
    col = lerp(col, rgb([0.7, 0.66, 0.58]), shells * 0.6)
    rough = 0.88 - 0.05 * rip
    save("sand", col, h, 3.0, rough)


def gravel():
    """Loose road-shoulder gravel, ~3 m tile: rounded stones with dark gaps."""
    n = N
    rng = np.random.default_rng(73)
    dome, mask, cid = stones(n, 3800, 71, 0.62, 3.0, (0.55, 1.0))
    d2, m2, c2 = stones(n, 9000, 75, 0.5, 2.0, (0.4, 1.0))  # smaller stones in the gaps
    tone = rng.uniform(0, 1, 3800)[cid]
    tone2 = np.random.default_rng(76).uniform(0, 1, 9000)[c2]
    under = m2 * (1.0 - mask)
    h = dome * 0.9 + d2 * under * 0.45 + fbm(n, 1.0, 74) * 0.1
    ao = ao_from_height(h, 5)
    c_big = lerp(rgb([0.09, 0.088, 0.085]), rgb([0.3, 0.285, 0.26]), tone)
    c_big = lerp(c_big, rgb([0.26, 0.2, 0.14]), (tone > 0.85).astype(np.float64) * 0.7)
    c_small = lerp(rgb([0.07, 0.065, 0.06]), rgb([0.2, 0.19, 0.17]), tone2)
    col = rgb([0.03, 0.027, 0.024]) * np.ones((n, n, 1))
    col = lerp(col, c_small * (0.6 + 0.4 * d2[..., None]), under)
    col = lerp(col, c_big * (0.6 + 0.4 * dome[..., None]), mask)
    col = col * ao[..., None]
    rough = 0.85 - 0.12 * dome
    save("gravel", col, h, 7.0, rough)

def concrete():
    """Broom-finished pavement concrete with stains, ~3 m tile (joints come from the shader)."""
    n = N
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    broom = fbm(n, 1.0, 81, aniso=(0.06, 1.0))
    grain = fbm(n, 0.4, 82)
    big = fbm(n, 2.8, 83)
    stain = np.clip((fbm(n, 2.4, 84) - 0.62) * 3.5, 0, 1)
    pores = (fbm(n, 0.2, 85) > 0.9).astype(np.float64)
    h = broom * 0.35 + grain * 0.2 + big * 0.2 - pores * 0.3
    col = lerp(rgb([0.27, 0.27, 0.26]), rgb([0.4, 0.395, 0.38]), big)
    col = col * (0.9 + 0.12 * grain[..., None] + 0.08 * broom[..., None])
    col = col * (1.0 - 0.35 * stain[..., None])
    col = col * (1.0 - 0.4 * pores[..., None])
    rough = 0.86 - 0.06 * stain
    save("concrete", col, h, 4.0, rough)


def snow():
    """Wind-packed snow, ~6 m tile."""
    n = N
    big = fbm(n, 2.4, 91)
    drift = fbm(n, 2.0, 92, aniso=(1.0, 0.35))
    grain = fbm(n, 0.3, 93)
    h = big * 0.5 + drift * 0.6 + grain * 0.05
    col = lerp(rgb([0.7, 0.74, 0.8]), rgb([0.9, 0.92, 0.95]), np.clip(big * 0.5 + drift * 0.6, 0, 1))
    rough = 0.55 + 0.25 * grain
    save("snow", col, h, 2.5, rough)


# ---------------------------------------------------------------- building & prop materials
def bond(n, cols, rows, stagger=0.5, jitter=None):
    """Running-bond grid that tiles: per-pixel unit id, distance to the nearest joint
    (pixels) and position inside the unit (0..1)."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    if jitter is not None:
        xx = xx + jitter[..., 0]
        yy = yy + jitter[..., 1]
    bw = n / cols
    bh = n / rows
    row = np.floor(yy / bh)
    xs = xx + (row % 2) * stagger * bw
    col = np.floor(xs / bw)
    fx = xs / bw - col
    fy = yy / bh - row
    dx = np.minimum(fx, 1 - fx) * bw
    dy = np.minimum(fy, 1 - fy) * bh
    uid = (np.mod(row, rows) * 1000 + np.mod(col, cols)).astype(np.int64)
    return uid, np.minimum(dx, dy), fx, fy


def per_unit(uid, seed):
    rng = np.random.default_rng(seed)
    table = rng.uniform(0, 1, 1000 * 1000 // 50 + 64000)
    return table[uid % table.size]


def brick():
    """Red brick, running bond, ~2.4 m square tile: 11 bricks across, 32 courses."""
    n = N
    uid, edge, fx, fy = bond(n, 11, 32, 0.5, warp(n, 1.2, 101, 2.2))
    tone = per_unit(uid, 102)
    tone2 = per_unit(uid, 103)
    chip = fbm(n, 1.2, 104)
    mortar = np.clip(1.0 - (edge - 2.0 - chip * 2.5) / 1.5, 0, 1)  # ~1 cm joints, ragged edges
    face = fbm(n, 0.8, 105)  # sandy brick face
    big = fbm(n, 2.6, 106)
    h = (1.0 - mortar) * (0.7 + 0.15 * face) + mortar * 0.15 * fbm(n, 0.5, 107) - (np.clip(1.0 - edge / 6.0, 0, 1) * 0.15)
    ao = ao_from_height(h, 3)
    brick_col = lerp(rgb([0.32, 0.1, 0.06]), rgb([0.5, 0.22, 0.13]), tone)
    brick_col = lerp(brick_col, rgb([0.22, 0.12, 0.09]), (tone2 > 0.88).astype(np.float64) * 0.8)  # dark clinkers
    brick_col = lerp(brick_col, rgb([0.55, 0.38, 0.28]), (tone2 < 0.07).astype(np.float64) * 0.7)  # pale ones
    brick_col = brick_col * (0.82 + 0.3 * face[..., None])
    mortar_col = rgb([0.42, 0.4, 0.36]) * (0.85 + 0.25 * fbm(n, 0.6, 108)[..., None])
    col = lerp(brick_col, mortar_col, mortar)
    soot = np.clip((fbm(n, 2.4, 109, aniso=(1.0, 0.25)) - 0.55) * 2.5, 0, 1)  # weathering streaks
    col = col * (1.0 - 0.3 * soot[..., None]) * (0.9 + 0.2 * big[..., None]) * ao[..., None]
    rough = 0.82 + 0.1 * mortar
    save("brick", col, h, 6.0, rough)


def stucco():
    """Painted render / stucco (white-ish, tinted per building in the shader), ~3 m tile."""
    n = N
    bump = fbm(n, 1.1, 111)
    blot = fbm(n, 2.0, 112)
    big = fbm(n, 2.8, 113)
    c1, c2, _ = voronoi(n, 40, 114, warp(n, 40.0, 115))
    crack = np.clip(1.0 - (c2 - c1) / 1.5, 0, 1) * np.clip((fbm(n, 2.2, 116) - 0.62) * 5.0, 0, 1)
    drip = np.clip((fbm(n, 1.8, 117, aniso=(1.0, 0.08)) - 0.5) * 2.0, 0, 1)
    h = bump * 0.5 + blot * 0.3 - crack * 0.4
    col = rgb([0.72, 0.7, 0.66]) * (0.9 + 0.12 * bump[..., None]) * (0.92 + 0.12 * big[..., None])
    col = col * (1.0 - 0.18 * drip[..., None]) * (1.0 - 0.45 * crack[..., None])
    rough = 0.88 - 0.05 * blot
    save("stucco", col, h, 3.5, rough)


def limestone():
    """Limestone cladding: big ashlar blocks 1.2 x 0.6 m with thin joints, ~3.6 m tile."""
    n = N
    uid, edge, fx, fy = bond(n, 3, 6, 0.5)
    tone = per_unit(uid, 121)
    grain = fbm(n, 0.7, 122)
    fossils = (fbm(n, 0.4, 123) > 0.82).astype(np.float64)
    big = fbm(n, 2.6, 124)
    joint = np.clip(1.0 - (edge - 1.0) / 1.2, 0, 1)
    h = (1.0 - joint) * (0.8 + 0.1 * grain) - fossils * 0.05
    col = lerp(rgb([0.62, 0.58, 0.5]), rgb([0.76, 0.72, 0.63]), tone) * (0.9 + 0.15 * grain[..., None])
    col = col * (1.0 - 0.15 * fossils[..., None]) * (0.9 + 0.15 * big[..., None])
    col = lerp(col, rgb([0.3, 0.29, 0.27]), joint * 0.8)
    soot = np.clip((fbm(n, 2.2, 125, aniso=(1.0, 0.2)) - 0.6) * 2.0, 0, 1)
    col = col * (1.0 - 0.3 * soot[..., None])
    rough = 0.8 + 0.1 * joint
    save("limestone", col, h, 4.0, rough)


def metal_panel():
    """Standing-seam metal wall panels, ~3 m tile (8 panels), neutral grey to tint."""
    n = N
    xx = np.mgrid[0:n, 0:n][1].astype(np.float64)
    period = n / 8
    f = (xx % period) / period
    seam = np.exp(-((f - 0.0) * period / 2.5) ** 2) + np.exp(-((f - 1.0) * period / 2.5) ** 2)
    canning = fbm(n, 2.6, 131, aniso=(0.3, 1.0)) * 0.3
    brushed = fbm(n, 0.9, 132, aniso=(0.04, 1.0))
    h = seam * 1.0 + canning
    col = rgb([0.5, 0.51, 0.52]) * (0.9 + 0.12 * brushed[..., None]) * (0.92 + 0.1 * canning[..., None] / 0.3)
    dirt = np.clip((fbm(n, 2.2, 133, aniso=(1.0, 0.15)) - 0.55) * 2.0, 0, 1)
    col = col * (1.0 - 0.25 * dirt[..., None])
    rough = 0.45 + 0.15 * brushed + 0.2 * dirt
    save("metal_panel", col, h, 5.0, rough)


def painted_metal():
    """Painted steel for poles and props: chipped paint, scratches and rust, ~1 m tile."""
    n = N
    rng = np.random.default_rng(141)
    paint_n = fbm(n, 1.4, 142)
    rust_mask = np.clip((fbm(n, 2.0, 143) - 0.68) * 5.0, 0, 1)
    pits = (fbm(n, 0.6, 144) > 0.78).astype(np.float64) * rust_mask
    scratches = np.zeros((n, n))
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    for i in range(160):
        x0, y0 = rng.uniform(0, n, 2)
        ang = rng.normal(0.3, 0.4)
        ln = rng.uniform(20, 140)
        d = np.abs((xx - x0) * np.sin(ang) - (yy - y0) * np.cos(ang))
        t = (xx - x0) * np.cos(ang) + (yy - y0) * np.sin(ang)
        scratches = np.maximum(scratches, np.clip(1.0 - d / 0.9, 0, 1) * (t > 0) * (t < ln) * rng.uniform(0.3, 1.0))
    h = paint_n * 0.15 - rust_mask * 0.3 - pits * 0.3 - scratches * 0.2
    col = rgb([0.5, 0.5, 0.5]) * (0.95 + 0.08 * paint_n[..., None])
    col = lerp(col, rgb([0.65, 0.66, 0.67]), scratches * 0.8)  # bare steel in scratches
    rust = lerp(rgb([0.25, 0.1, 0.04]), rgb([0.45, 0.2, 0.07]), fbm(n, 1.0, 145))
    col = lerp(col, rust, rust_mask * 0.85)
    rough = 0.4 + 0.45 * rust_mask - 0.15 * scratches
    save("painted_metal", col, h, 3.0, rough)


def roof():
    """Flat-roof membrane with welded seams, patches and gravel, ~4 m tile."""
    n = N
    yy = np.mgrid[0:n, 0:n][0].astype(np.float64)
    period = n / 4
    f = (yy % period) / period
    seam = np.exp(-((f - 0.02) * period / 3.0) ** 2)
    wrinkle = fbm(n, 2.0, 151) * 0.4
    grav_d, grav_m, gid = stones(n, 5000, 152, 0.4, 2.0, (0.4, 1.0))
    gravel_zone = np.clip((fbm(n, 2.4, 153) - 0.55) * 4.0, 0, 1)
    patch = np.clip((fbm(n, 2.6, 154) - 0.7) * 6.0, 0, 1)
    h = seam * 0.5 + wrinkle + grav_d * gravel_zone * 0.6
    col = rgb([0.12, 0.12, 0.125]) * (0.85 + 0.3 * fbm(n, 1.0, 155)[..., None])
    col = lerp(col, rgb([0.2, 0.2, 0.2]), patch * 0.6)
    gtone = np.random.default_rng(156).uniform(0, 1, 5000)[gid]
    col = lerp(col, lerp(rgb([0.25, 0.24, 0.22]), rgb([0.45, 0.43, 0.4]), gtone), grav_m * gravel_zone)
    col = col * (1.0 - 0.2 * seam[..., None])
    rough = 0.85 - 0.1 * patch
    save("roof", col, h, 4.0, rough)


def pavers():
    """Concrete block pavers (20 x 10 cm, herringbone-free running bond), ~2 m tile."""
    n = N
    uid, edge, fx, fy = bond(n, 10, 20, 0.5)
    tone = per_unit(uid, 161)
    face = fbm(n, 0.8, 162)
    joint = np.clip(1.0 - (edge - 1.5) / 1.5, 0, 1)
    bevel = np.clip(edge / 4.0, 0, 1)
    h = np.sqrt(bevel) * (0.8 + 0.1 * face) - joint * 0.2
    ao = ao_from_height(h, 3)
    col = lerp(rgb([0.33, 0.31, 0.29]), rgb([0.47, 0.44, 0.4]), tone) * (0.88 + 0.2 * face[..., None])
    col = lerp(col, rgb([0.22, 0.2, 0.17]), joint * 0.9)  # sand / dirt in the joints
    moss = np.clip((fbm(n, 2.0, 163) - 0.7) * 5.0, 0, 1) * joint
    col = lerp(col, rgb([0.12, 0.16, 0.07]), moss * 0.8)
    stains = np.clip((fbm(n, 2.6, 164) - 0.62) * 3.0, 0, 1)
    col = col * (1.0 - 0.3 * stains[..., None]) * ao[..., None]
    rough = 0.85 - 0.05 * stains
    save("pavers", col, h, 5.0, rough)


def bark():
    """Tree bark: deep vertical furrows between corky plates, ~1 m tile (wraps a trunk)."""
    n = N
    w = warp(n, 30.0, 171, 2.2)
    furrow_n = fbm(n, 1.6, 172, aniso=(1.0, 0.1))  # long vertical structures
    plates = sample_wrap(furrow_n, w[..., 0], w[..., 1] * 0.2)
    ridge = 1.0 - np.abs(plates - 0.5) * 2.0
    cracks = np.clip((0.35 - ridge) * 4.0, 0, 1)
    grain = fbm(n, 0.8, 173, aniso=(1.0, 0.3))
    h = ridge * 0.9 + grain * 0.2 - cracks * 0.5
    ao = ao_from_height(h, 6)
    col = lerp(rgb([0.06, 0.045, 0.035]), rgb([0.2, 0.16, 0.12]), np.clip(ridge * 0.8 + grain * 0.3, 0, 1))
    lichen = np.clip((fbm(n, 2.0, 174) - 0.72) * 5.0, 0, 1) * ridge
    col = lerp(col, rgb([0.22, 0.26, 0.16]), lichen * 0.6) * ao[..., None]
    rough = 0.9
    save("bark", col, h, 9.0, np.full((n, n), rough))


# Slice order in the texture arrays (shaders index them with these numbers).
LAYERS = ["asphalt", "grass", "dirt", "rock", "sand", "gravel", "concrete", "snow",
          "brick", "stucco", "limestone", "metal_panel", "painted_metal", "roof", "pavers", "bark"]
MATERIALS = {"asphalt": asphalt, "grass": grass, "dirt": dirt, "rock": rock, "sand": sand,
             "gravel": gravel, "concrete": concrete, "snow": snow, "brick": brick, "stucco": stucco,
             "limestone": limestone, "metal_panel": metal_panel, "painted_metal": painted_metal,
             "roof": roof, "pavers": pavers, "bark": bark}

if __name__ == "__main__":
    for nm in LAYERS:
        MATERIALS[nm]()
    write_arrays()
