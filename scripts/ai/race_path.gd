class_name RacePath
extends RefCounted
## Resampled route with a smoothed racing line and curvature for speed planning.

const SPACING := 3.0

var center := PackedVector2Array()
var line := PackedVector2Array()
var heights := PackedFloat32Array()
var cum := PackedFloat32Array()
var curv := PackedFloat32Array()
var closed := false
var n := 0
var length := 0.0

func _init(points: PackedVector2Array, is_closed: bool, world: World = null) -> void:
	closed = is_closed
	center = _resample(points, SPACING, closed)
	n = center.size()
	line = _smooth(center, 7, 3)
	cum.resize(n)
	cum[0] = 0.0
	for i in range(1, n):
		cum[i] = cum[i - 1] + center[i].distance_to(center[i - 1])
	length = cum[n - 1] + (center[n - 1].distance_to(center[0]) if closed else 0.0)
	curv.resize(n)
	for i in n:
		curv[i] = _curvature(at(i - 4, true), line[i], at(i + 4, true))
	if world:
		heights.resize(n)
		for i in n:
			heights[i] = world.ground(center[i].x, center[i].y)

func idx(i: int) -> int:
	if closed:
		return posmod(i, n)
	return clampi(i, 0, n - 1)

func at(i: int, use_line := false) -> Vector2:
	return line[idx(i)] if use_line else center[idx(i)]

func dir(i: int) -> Vector2:
	var a := at(i - 1)
	var b := at(i + 1)
	return (b - a).normalized()

func nearest(p: Vector2, hint: int, back := 10, ahead := 60) -> int:
	var best := hint
	var bd := INF
	for k in range(-back, ahead + 1):
		var i := idx(hint + k)
		var d := center[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best

func nearest_global(p: Vector2) -> int:
	var best := 0
	var bd := INF
	for i in n:
		var d := center[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best

func speed_profile(grip: float, brake: float, top: float) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		v[i] = minf(sqrt(grip / maxf(curv[i], 0.0001)), top)
	var passes := 2 if closed else 1
	for _p in passes:
		var i := n - 2 + (1 if closed else 0)
		while i >= 0:
			var j := idx(i + 1)
			v[i] = minf(v[i], sqrt(v[j] * v[j] + 2.0 * brake * SPACING))
			i -= 1
	return v

static func _resample(pts: PackedVector2Array, step: float, is_closed: bool) -> PackedVector2Array:
	var src := pts.duplicate()
	if is_closed:
		src.append(pts[0])
	var out := PackedVector2Array([src[0]])
	var carry := 0.0
	for i in src.size() - 1:
		var a := src[i]
		var b := src[i + 1]
		var L := a.distance_to(b)
		if L < 0.001:
			continue
		var t := step - carry
		while t <= L:
			out.append(a.lerp(b, t / L))
			t += step
		carry = L - (t - step)
	if is_closed:
		if out[out.size() - 1].distance_to(out[0]) < step * 0.5:
			out.remove_at(out.size() - 1)
	elif out[out.size() - 1].distance_to(src[src.size() - 1]) > 0.5:
		out.append(src[src.size() - 1])
	return out

func _smooth(pts: PackedVector2Array, win: int, iters: int) -> PackedVector2Array:
	var cur := pts.duplicate()
	for _it in iters:
		var nxt := PackedVector2Array()
		nxt.resize(n)
		for i in n:
			var s := Vector2.ZERO
			var c := 0
			for k in range(-win, win + 1):
				s += cur[idx(i + k)]
				c += 1
			nxt[i] = s / c
		cur = nxt
	for i in n:
		var dv := cur[i] - pts[i]
		if dv.length() > 6.5:
			cur[i] = pts[i] + dv.normalized() * 6.5
	return cur

static func _curvature(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var area2 := absf((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
	if ab * bc * ca < 0.000001:
		return 0.0
	return 2.0 * area2 / (ab * bc * ca)
