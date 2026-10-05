class_name Proc
extends RefCounted
## Procedural textures and meshes (no external art needed for the environment).

static func noise_tex(seed: int, freq: float, size := 512, normal := false, octaves := 5) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	return t

static func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r

## Broadleaf / pine foliage atlas drawn leaf by leaf.
static func leaf_texture(pine: bool) -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.16, 0.05, 0.0))
	var r := _rng(11 if pine else 7)
	var count := 900 if pine else 420
	for i in count:
		var cx := r.randf_range(8, s - 8)
		var cy := r.randf_range(8, s - 8)
		# Keep the silhouette roughly round so cards don't look square.
		var dc := Vector2(cx - s / 2.0, cy - s / 2.0).length() / (s / 2.0)
		if dc > 0.95 or r.randf() < dc * 0.6:
			continue
		var ang := r.randf() * TAU
		var g := r.randf_range(0.65, 1.15)
		var col := Color(0.16 * g, 0.30 * g, 0.08 * g) if not pine else Color(0.07 * g, 0.17 * g, 0.08 * g)
		col = col.lerp(Color(0.32, 0.36, 0.12), r.randf() * 0.25)
		var lw := r.randf_range(5.0, 9.0) if not pine else r.randf_range(1.0, 1.6)
		var lh := r.randf_range(2.5, 4.5) if not pine else r.randf_range(7.0, 12.0)
		var ca := cos(ang)
		var sa := sin(ang)
		var rad := int(maxf(lw, lh)) + 1
		for y in range(-rad, rad + 1):
			for x in range(-rad, rad + 1):
				var lx := (x * ca + y * sa) / lw
				var ly := (-x * sa + y * ca) / lh
				var d := lx * lx + ly * ly
				if d <= 1.0:
					var px := int(cx) + x
					var py := int(cy) + y
					if px >= 0 and py >= 0 and px < s and py < s:
						var shade := 1.0 - d * 0.35 + lx * 0.12
						img.set_pixel(px, py, Color(col.r * shade, col.g * shade, col.b * shade, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func grass_texture() -> ImageTexture:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.3, 0.1, 0.0))
	var r := _rng(5)
	for i in 70:
		var x0 := r.randf_range(4, w - 4)
		var lean := r.randf_range(-18, 18)
		var top := r.randf_range(h * 0.05, h * 0.5)
		var wid := r.randf_range(1.5, 3.2)
		var g := r.randf_range(0.7, 1.2)
		for y in range(int(top), h):
			var t := (y - top) / (h - top)
			var cx := x0 + lean * (1.0 - t) * (1.0 - t)
			var hw := wid * (0.25 + 0.75 * t)
			for x in range(int(cx - hw), int(cx + hw) + 1):
				if x >= 0 and x < w:
					var c := Color(0.22 * g, 0.36 * g, 0.1 * g).lerp(Color(0.5, 0.48, 0.22), (1.0 - t) * 0.35)
					img.set_pixel(x, y, Color(c.r * (0.55 + t * 0.45), c.g * (0.55 + t * 0.45), c.b, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- meshes
static func _cylinder(st: SurfaceTool, base: Vector3, top: Vector3, r0: float, r1: float, sides: int, col: Color) -> void:
	var axis := (top - base).normalized()
	var side := axis.cross(Vector3.FORWARD if abs(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := axis.cross(side)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := side * cos(a0) + fwd * sin(a0)
		var d1 := side * cos(a1) + fwd * sin(a1)
		var p := [base + d0 * r0, base + d1 * r0, top + d1 * r1, top + d0 * r1]
		var n := [d0, d1, d1, d0]
		var uv := [Vector2(float(i) / sides, 0), Vector2(float(i + 1) / sides, 0), Vector2(float(i + 1) / sides, 1), Vector2(float(i) / sides, 1)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(n[k])
			st.set_uv(uv[k])
			st.add_vertex(p[k])

static func _card(st: SurfaceTool, c: Vector3, right: Vector3, up: Vector3, nrm: Vector3) -> void:
	var p := [c - right - up, c + right - up, c + right + up, c - right + up]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(nrm)
		st.set_uv(uv[k])
		st.add_vertex(p[k])

## Tree mesh with two surfaces: bark (vertex colours) and leaf cards.
static func tree_mesh(pine: bool, cards: int, bark_mat: Material, leaf_mat: Material) -> ArrayMesh:
	var r := _rng(3 if pine else 9)
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark := Color(0.23, 0.17, 0.12) if not pine else Color(0.2, 0.14, 0.1)
	var trunk_h := 4.2 if not pine else 10.5
	_cylinder(st, Vector3.ZERO, Vector3(0, trunk_h, 0), 0.32 if not pine else 0.28, 0.12, 7, bark)
	if not pine:
		for i in 4:
			var a := TAU * i / 4.0 + 0.4
			var b := Vector3(0, 2.8 + i * 0.35, 0)
			_cylinder(st, b, b + Vector3(cos(a) * 1.6, 1.6, sin(a) * 1.6), 0.11, 0.04, 5, bark)
	st.generate_tangents()
	st.commit(mesh)

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if pine:
		var tiers := maxi(3, cards / 6)
		for t in tiers:
			var tt := float(t) / tiers
			var y := 2.0 + tt * 9.5
			var rad := lerpf(2.9, 0.6, tt)
			var per := 7 if cards > 20 else 4
			for i in per:
				var a := TAU * i / per + t * 0.7
				var out := Vector3(cos(a), 0, sin(a))
				var right := Vector3(-sin(a), 0, cos(a)) * rad * 0.55
				var c := Vector3(0, y, 0) + out * rad * 0.5 + Vector3(0, -0.45, 0)
				var up := (out * rad * 0.5 + Vector3(0, 0.55, 0)) * 0.95
				_card(st, c, right, up, (out + Vector3(0, 0.6, 0)).normalized())
		_card(st, Vector3(0, 11.8, 0), Vector3(0.7, 0, 0), Vector3(0, 1.2, 0), Vector3.UP)
		_card(st, Vector3(0, 11.8, 0), Vector3(0, 0, 0.7), Vector3(0, 1.2, 0), Vector3.UP)
	else:
		var center := Vector3(0, 5.6, 0)
		for i in cards:
			# Cards on an ellipsoid shell, normals pointing outward for soft canopy lighting.
			var u := r.randf() * TAU
			var v := acos(r.randf_range(-0.55, 1.0))
			var dir := Vector3(sin(v) * cos(u), cos(v) * 0.85, sin(v) * sin(u)).normalized()
			var pos := center + Vector3(dir.x * 2.7, dir.y * 2.2, dir.z * 2.7)
			var t1 := dir.cross(Vector3.UP if abs(dir.y) < 0.95 else Vector3.RIGHT).normalized()
			var t2 := dir.cross(t1).normalized()
			var roll := r.randf() * TAU
			var right := (t1 * cos(roll) + t2 * sin(roll)) * 1.7
			var up := (t2 * cos(roll) - t1 * sin(roll)) * 1.7
			_card(st, pos, right, up, dir)
		for k in 3:
			var a := k * PI / 3.0
			_card(st, center, Vector3(cos(a), 0, sin(a)) * 2.8, Vector3(0, 2.3, 0), Vector3.UP)
	st.commit(mesh)
	mesh.surface_set_material(0, bark_mat)
	mesh.surface_set_material(1, leaf_mat)
	return mesh

static func grass_clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var right := Vector3(cos(a), 0, sin(a)) * 0.38
		_card(st, Vector3(0, 0.32, 0), right, Vector3(0, 0.34, 0), Vector3.UP)
	var m := ArrayMesh.new()
	st.commit(m)
	return m

static func box(st: SurfaceTool, c: Vector3, s: Vector3, col := Color.WHITE) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n * h
		var uu := u * h
		var vv := v * h
		var p := [o - uu - vv, o + uu - vv, o + uu + vv, o - uu + vv]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(uv[k])
			st.add_vertex(p[k])

## Street lamp: pole along +Y, arm pointing +Z.
static func lamp_mesh(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(0.22, 0.23, 0.24)
	_cylinder(st, Vector3.ZERO, Vector3(0, 0.6, 0), 0.22, 0.16, 8, c)
	_cylinder(st, Vector3(0, 0.6, 0), Vector3(0, 9.0, 0), 0.12, 0.08, 8, c)
	_cylinder(st, Vector3(0, 8.8, 0), Vector3(0, 9.2, 2.6), 0.06, 0.05, 6, c)
	box(st, Vector3(0, 9.15, 2.9), Vector3(0.45, 0.16, 1.0), Color(0.12, 0.12, 0.13))
	st.generate_tangents()
	var m := ArrayMesh.new()
	st.commit(m)
	m.surface_set_material(0, mat)
	return m

static func lamp_bulb_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	box(st, Vector3(0, 9.05, 2.9), Vector3(0.36, 0.04, 0.8))
	var m := ArrayMesh.new()
	st.commit(m)
	return m

static func signal_pole_mesh(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(0.16, 0.17, 0.18)
	_cylinder(st, Vector3.ZERO, Vector3(0, 6.2, 0), 0.13, 0.1, 8, c)
	_cylinder(st, Vector3(0, 6.0, 0), Vector3(0, 6.0, 6.5), 0.08, 0.06, 6, c)
	box(st, Vector3(0, 5.3, 6.0), Vector3(0.38, 1.1, 0.32), Color(0.08, 0.08, 0.08))
	box(st, Vector3(0, 2.8, 0.2), Vector3(0.32, 0.9, 0.28), Color(0.08, 0.08, 0.08))
	var m := ArrayMesh.new()
	st.commit(m)
	m.surface_set_material(0, mat)
	return m

static func sphere_lamp() -> ArrayMesh:
	var s := SphereMesh.new()
	s.radius = 0.11
	s.height = 0.22
	s.radial_segments = 8
	s.rings = 4
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s.get_mesh_arrays())
	return m
