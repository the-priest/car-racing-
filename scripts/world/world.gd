class_name World
extends Node3D
## Builds the open world from the baked data in res://assets/world.

signal progress(msg: String, frac: float)

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const ROAD_SHADER := preload("res://shaders/road.gdshader")
const BUILDING_SHADER := preload("res://shaders/building.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const EMISSIVE_SHADER := preload("res://shaders/emissive.gdshader")
const CONCRETE_SHADER := preload("res://shaders/concrete.gdshader")

const CHUNK := 256.0
const LAYER_WORLD := 1

var d: Dictionary
var N := 769
var HALF := 3072.0
var CELL := 8.0
var heights: PackedFloat32Array
var height_tex: ImageTexture
var mask_tex: ImageTexture
var noise_a: NoiseTexture2D
var noise_b: NoiseTexture2D
var noise_n: NoiseTexture2D
var q: Dictionary
var compat := false

# Navigation graph
var node_pos := PackedVector2Array()
var node_type := PackedInt32Array()
var adj: Array = []
var types: Array = []

var streets: Array = []
var buildings: Array = [] # Dictionaries {rect: Rect2, h: float, style: int}
var lamp_pos := PackedVector3Array()
var lamp_grid := {}
var lamp_lights: Array[SpotLight3D] = []
var lamp_timer := 0.0
var road_mats: Array[ShaderMaterial] = []
var grass_inst: MultiMeshInstance3D

func build(preset: Dictionary) -> void:
	q = preset
	compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	progress.emit("Loading world data", 0.02)
	await get_tree().process_frame
	var _t5943 := Time.get_ticks_msec()
	_load_data()
	if OS.is_stdout_verbose(): print('[world] _load_data() ', Time.get_ticks_msec() - _t5943, ' ms')
	noise_a = Proc.noise_tex(1, 0.012, 512)
	noise_b = Proc.noise_tex(2, 0.006, 512)
	noise_n = Proc.noise_tex(3, 0.02, 512, true)
	progress.emit("Sculpting terrain", 0.1)
	await get_tree().process_frame
	var _t2526 := Time.get_ticks_msec()
	_build_terrain()
	if OS.is_stdout_verbose(): print('[world] _build_terrain() ', Time.get_ticks_msec() - _t2526, ' ms')
	var _t3113 := Time.get_ticks_msec()
	_build_water()
	if OS.is_stdout_verbose(): print('[world] _build_water() ', Time.get_ticks_msec() - _t3113, ' ms')
	progress.emit("Paving 52 km of road", 0.3)
	await get_tree().process_frame
	var _t7674 := Time.get_ticks_msec()
	_build_roads()
	if OS.is_stdout_verbose(): print('[world] _build_roads() ', Time.get_ticks_msec() - _t7674, ' ms')
	progress.emit("Raising the city", 0.45)
	await get_tree().process_frame
	var _t9742 := Time.get_ticks_msec()
	_build_city()
	if OS.is_stdout_verbose(): print('[world] _build_city() ', Time.get_ticks_msec() - _t9742, ' ms')
	progress.emit("Wiring street lights", 0.6)
	await get_tree().process_frame
	var _t9854 := Time.get_ticks_msec()
	_build_lamps()
	if OS.is_stdout_verbose(): print('[world] _build_lamps() ', Time.get_ticks_msec() - _t9854, ' ms')
	progress.emit("Planting forests", 0.7)
	await get_tree().process_frame
	var _t4098 := Time.get_ticks_msec()
	_build_trees()
	if OS.is_stdout_verbose(): print('[world] _build_trees() ', Time.get_ticks_msec() - _t4098, ' ms')
	var _t3796 := Time.get_ticks_msec()
	_build_grass()
	if OS.is_stdout_verbose(): print('[world] _build_grass() ', Time.get_ticks_msec() - _t3796, ' ms')
	var _t5402 := Time.get_ticks_msec()
	_build_graph()
	if OS.is_stdout_verbose(): print('[world] _build_graph() ', Time.get_ticks_msec() - _t5402, ' ms')
	progress.emit("Ready", 1.0)

func _load_data() -> void:
	d = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/world.json"))
	N = int(d.n)
	HALF = float(d.half)
	CELL = float(d.cell)
	streets = d.streets
	var hb := FileAccess.get_file_as_bytes("res://assets/world/height.bin")
	heights = hb.to_float32_array()
	var himg := Image.create_from_data(N, N, false, Image.FORMAT_RF, hb)
	height_tex = ImageTexture.create_from_image(himg)
	var mb := FileAccess.get_file_as_bytes("res://assets/world/mask.bin")
	var mimg := Image.create_from_data(N, N, false, Image.FORMAT_RG8, mb)
	mask_tex = ImageTexture.create_from_image(mimg)

## Terrain height at a world position (matches the GPU displacement).
func ground(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / CELL, 0.0, N - 1.001)
	var gz := clampf((z + HALF) / CELL, 0.0, N - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var a := heights[j * N + i]
	var b := heights[j * N + i + 1]
	var c := heights[(j + 1) * N + i]
	var e := heights[(j + 1) * N + i + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, e, fx), fz)

func in_city(x: float, z: float) -> bool:
	return absf(x) < 680.0 and absf(z) < 680.0

# ---------------------------------------------------------------- terrain
func _grid_mesh(cells: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := CHUNK / cells
	var h := CHUNK * 0.5
	var vtx := func(x: float, z: float, skirt: float) -> void:
		st.set_color(Color(1, 1, 1, skirt))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(x / CHUNK + 0.5, z / CHUNK + 0.5))
		st.add_vertex(Vector3(x, 0, z))
	for j in cells:
		for i in cells:
			var x0 := -h + i * step
			var z0 := -h + j * step
			var x1 := x0 + step
			var z1 := z0 + step
			vtx.call(x0, z0, 0.0); vtx.call(x1, z0, 0.0); vtx.call(x0, z1, 0.0)
			vtx.call(x1, z0, 0.0); vtx.call(x1, z1, 0.0); vtx.call(x0, z1, 0.0)
	# Skirts along the four edges hide cracks between LOD levels.
	for k in cells:
		var a := -h + k * step
		var b := a + step
		for e in [[Vector2(a, -h), Vector2(b, -h)], [Vector2(b, h), Vector2(a, h)], [Vector2(-h, b), Vector2(-h, a)], [Vector2(h, a), Vector2(h, b)]]:
			var p: Vector2 = e[0]
			var r: Vector2 = e[1]
			vtx.call(p.x, p.y, 0.0); vtx.call(r.x, r.y, 0.0); vtx.call(r.x, r.y, 1.0)
			vtx.call(p.x, p.y, 0.0); vtx.call(r.x, r.y, 1.0); vtx.call(p.x, p.y, 1.0)
	st.generate_tangents()
	var m := ArrayMesh.new()
	st.commit(m)
	return m

func _build_terrain() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("heightmap", height_tex)
	mat.set_shader_parameter("maskmap", mask_tex)
	mat.set_shader_parameter("half_size", HALF)
	mat.set_shader_parameter("tex_size", float(N))
	mat.set_shader_parameter("noise_a", noise_a)
	mat.set_shader_parameter("noise_b", noise_b)
	mat.set_shader_parameter("noise_n", noise_n)
	var near_mesh := _grid_mesh(32)
	var far_mesh := _grid_mesh(8)
	var lod_dist: float = 700.0 if q.draw < 2500.0 else 1100.0
	var count := int(HALF * 2.0 / CHUNK)
	var root := Node3D.new()
	root.name = "Terrain"
	add_child(root)
	var aabb := AABB(Vector3(-CHUNK * 0.5, -60, -CHUNK * 0.5), Vector3(CHUNK, 760, CHUNK))
	for cz in count:
		for cx in count:
			var pos := Vector3(-HALF + (cx + 0.5) * CHUNK, 0, -HALF + (cz + 0.5) * CHUNK)
			var n := MeshInstance3D.new()
			n.mesh = near_mesh
			n.material_override = mat
			n.position = pos
			n.custom_aabb = aabb
			n.visibility_range_end = lod_dist
			n.visibility_range_end_margin = 40.0
			root.add_child(n)
			var f := MeshInstance3D.new()
			f.mesh = far_mesh
			f.material_override = mat
			f.position = pos
			f.custom_aabb = aabb
			f.visibility_range_begin = lod_dist
			f.visibility_range_begin_margin = 40.0
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(f)
	# Collision: uniform-scaled heightmap (heights stored pre-divided).
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.set_meta("surface", "terrain")
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	var scaled := PackedFloat32Array()
	scaled.resize(heights.size())
	for i in heights.size():
		scaled[i] = heights[i] / CELL
	shape.map_data = scaled
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(CELL, CELL, CELL)
	body.add_child(cs)
	add_child(body)

func _build_water() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("normal_a", Proc.noise_tex(21, 0.03, 512, true))
	mat.set_shader_parameter("normal_b", Proc.noise_tex(22, 0.05, 512, true))
	mat.set_shader_parameter("use_depth", not compat)
	var pm := PlaneMesh.new()
	pm.size = Vector2(16000, 7600)
	pm.subdivide_width = 200
	pm.subdivide_depth = 100
	var w := MeshInstance3D.new()
	w.mesh = pm
	w.material_override = mat
	w.position = Vector3(0, float(d.water) - 0.6, 1600.0 + 3800.0)
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w)

# ---------------------------------------------------------------- roads
func _road_material(width: float, lanes: int, style: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROAD_SHADER
	m.set_shader_parameter("road_width", width)
	m.set_shader_parameter("lanes_per_side", lanes)
	m.set_shader_parameter("style", style)
	m.set_shader_parameter("noise_a", noise_a)
	m.set_shader_parameter("noise_b", noise_b)
	m.set_shader_parameter("noise_n", noise_n)
	road_mats.append(m)
	return m

func _build_roads() -> void:
	var root := Node3D.new()
	root.name = "Roads"
	add_child(root)
	var mats := {}
	for r in d.roads:
		var hw: float = r.hw
		var key := "%s_%d" % [r.type, int(hw * 10)]
		if not mats.has(key):
			match r.type:
				"hwy": mats[key] = _road_material(hw * 2, 3, 0)
				"link": mats[key] = _road_material(hw * 2, 2, 0)
				"runway": mats[key] = _road_material(hw * 2, 1, 2)
				_: mats[key] = _road_material(hw * 2, 1, 1)
		_build_ribbon(root, r.pts, hw, r.closed, mats[key], r.type)

func _build_ribbon(root: Node3D, flat: Array, hw: float, closed: bool, mat: Material, type: String) -> void:
	var pts := PackedVector3Array()
	for i in range(0, flat.size(), 3):
		pts.append(Vector3(flat[i], flat[i + 1] + 0.07, flat[i + 2]))
	var n := pts.size()
	var total := n + 1 if closed else n
	var rows: Array = []
	var dist := 0.0
	for i in total:
		var p := pts[i % n]
		var pp := pts[(i - 1 + n) % n] if closed else pts[maxi(i - 1, 0)]
		var pn := pts[(i + 1) % n] if closed else pts[mini(i + 1, n - 1)]
		var t := pn - pp
		t.y = 0.0
		t = t.normalized()
		var left := Vector3(-t.z, 0, t.x)
		if i > 0:
			dist += p.distance_to(pts[(i - 1) % n])
		var tan3 := (pn - pp).normalized()
		var nrm := tan3.cross(left).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		rows.append([p, left, nrm, dist])
	var K := 4
	var W := hw * 2.0
	var CH := 48
	var s := 0
	while s < rows.size() - 1:
		var e := mini(s + CH, rows.size() - 1)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var faces := PackedVector3Array()
		for i in range(s, e):
			var A: Array = rows[i]
			var B: Array = rows[i + 1]
			for k in K:
				var o0 := lerpf(hw, -hw, float(k) / K)
				var o1 := lerpf(hw, -hw, float(k + 1) / K)
				var a: Vector3 = A[0] + A[1] * o0
				var b: Vector3 = A[0] + A[1] * o1
				var c: Vector3 = B[0] + B[1] * o0
				var dd: Vector3 = B[0] + B[1] * o1
				var ua := Vector2(hw - o0, A[3])
				var ub := Vector2(hw - o1, A[3])
				var uc := Vector2(hw - o0, B[3])
				var ud := Vector2(hw - o1, B[3])
				for v in [[a, ua, A[2]], [b, ub, A[2]], [c, uc, B[2]], [b, ub, A[2]], [dd, ud, B[2]], [c, uc, B[2]]]:
					st.set_normal(v[2])
					st.set_uv(v[1])
					st.add_vertex(v[0])
				faces.append_array([a, b, c, b, dd, c])
			# Side skirts drop into the ground so road edges never float.
			for side in [hw, -hw]:
				var a2: Vector3 = A[0] + A[1] * side
				var c2: Vector3 = B[0] + B[1] * side
				var a3: Vector3 = A[0] + A[1] * side * 1.06 + Vector3(0, -0.8, 0)
				var c3: Vector3 = B[0] + B[1] * side * 1.06 + Vector3(0, -0.8, 0)
				var u := 0.0 if side > 0 else W
				var quad := [[a2, Vector2(u, A[3])], [c2, Vector2(u, B[3])], [c3, Vector2(u, B[3])], [a2, Vector2(u, A[3])], [c3, Vector2(u, B[3])], [a3, Vector2(u, A[3])]]
				if side > 0:
					quad = [quad[0], quad[2], quad[1], quad[3], quad[5], quad[4]]
				for v in quad:
					st.set_normal(A[1] * signf(side))
					st.set_uv(v[1])
					st.add_vertex(v[0])
		st.generate_tangents()
		var mesh := ArrayMesh.new()
		st.commit(mesh)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var body := StaticBody3D.new()
		body.set_meta("surface", "road")
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)
		s = e

# ---------------------------------------------------------------- city
func _build_city() -> void:
	var root := Node3D.new()
	root.name = "City"
	add_child(root)
	var hw: float = d.streetHw
	var edge: float = d.cityEdge
	var street_mat := _road_material(hw * 2, 2, 0)
	var cross_mat := _road_material(hw * 2, 2, 3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sx := SurfaceTool.new()
	sx.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(tool: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u0: Vector2, u1: Vector2, u2: Vector2, u3: Vector2) -> void:
		for v in [[p0, u0], [p1, u1], [p2, u2], [p0, u0], [p2, u2], [p3, u3]]:
			tool.set_normal(Vector3.UP)
			tool.set_uv(v[1])
			tool.add_vertex(v[0])
	var y := 0.03
	for a in streets.size():
		var s: float = streets[a]
		for b in streets.size() - 1:
			var z0: float = streets[b] + hw
			var z1: float = streets[b + 1] - hw
			var L := z1 - z0
			# Along Z
			quad.call(st, Vector3(s - hw, y, z0), Vector3(s + hw, y, z0), Vector3(s + hw, y, z1), Vector3(s - hw, y, z1),
				Vector2(0, 0), Vector2(hw * 2, 0), Vector2(hw * 2, L), Vector2(0, L))
			# Along X
			quad.call(st, Vector3(z0, y, s + hw), Vector3(z0, y, s - hw), Vector3(z1, y, s - hw), Vector3(z1, y, s + hw),
				Vector2(0, 0), Vector2(hw * 2, 0), Vector2(hw * 2, L), Vector2(0, L))
		for b in streets.size():
			var t: float = streets[b]
			quad.call(sx, Vector3(s - hw, y, t - hw), Vector3(s + hw, y, t - hw), Vector3(s + hw, y, t + hw), Vector3(s - hw, y, t + hw),
				Vector2(0, 0), Vector2(hw * 2, 0), Vector2(hw * 2, hw * 2), Vector2(0, hw * 2))
	for tool_mat in [[st, street_mat], [sx, cross_mat]]:
		var tool: SurfaceTool = tool_mat[0]
		tool.generate_tangents()
		var m := ArrayMesh.new()
		tool.commit(m)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = tool_mat[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

	# City ground collision (streets) and sidewalk blocks.
	var ground_body := StaticBody3D.new()
	ground_body.set_meta("surface", "road")
	var gshape := BoxShape3D.new()
	gshape.size = Vector3(1360, 2, 1360)
	var gcs := CollisionShape3D.new()
	gcs.shape = gshape
	gcs.position = Vector3(0, -1.0 + 0.03, 0)
	ground_body.add_child(gcs)
	root.add_child(ground_body)

	var walk_mat := ShaderMaterial.new()
	walk_mat.shader = CONCRETE_SHADER
	walk_mat.set_shader_parameter("noise_a", noise_a)
	walk_mat.set_shader_parameter("noise_b", noise_b)
	walk_mat.set_shader_parameter("noise_n", noise_n)
	var park_mat := StandardMaterial3D.new()
	park_mat.albedo_color = Color(0.2, 0.32, 0.1)
	park_mat.albedo_texture = noise_a
	park_mat.uv1_scale = Vector3(40, 40, 40)
	park_mat.roughness = 0.9
	var walk := SurfaceTool.new()
	walk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parks := SurfaceTool.new()
	parks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var park_set := {}
	for p in d.parks:
		park_set["%d,%d" % [int(p[0]), int(p[1])]] = true
	var walk_body := StaticBody3D.new()
	walk_body.set_meta("surface", "sidewalk")
	root.add_child(walk_body)
	for a in streets.size() - 1:
		for b in streets.size() - 1:
			var x0: float = streets[a] + hw
			var x1: float = streets[a + 1] - hw
			var z0: float = streets[b] + hw
			var z1: float = streets[b + 1] - hw
			var c := Vector3((x0 + x1) * 0.5, 0.09, (z0 + z1) * 0.5)
			var size := Vector3(x1 - x0, 0.18, z1 - z0)
			Proc.box(walk, c, size)
			if park_set.has("%d,%d" % [int(x0), int(z0)]):
				Proc.box(parks, Vector3(c.x, 0.2, c.z), Vector3(size.x - 8, 0.2, size.z - 8))
			var bs := BoxShape3D.new()
			bs.size = size
			var cs := CollisionShape3D.new()
			cs.shape = bs
			cs.position = c
			walk_body.add_child(cs)
	for pair in [[walk, walk_mat], [parks, park_mat]]:
		var tool: SurfaceTool = pair[0]
		tool.generate_tangents()
		var m := ArrayMesh.new()
		tool.commit(m)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = pair[1]
		root.add_child(mi)

	_build_buildings(root)
	_build_signals(root, hw)

func _build_buildings(root: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = BUILDING_SHADER
	mat.set_shader_parameter("noise_a", noise_a)
	mat.set_shader_parameter("noise_b", noise_b)
	mat.set_shader_parameter("noise_n", noise_n)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = mat
	var list: Array = d.buildings
	var total := 0
	for bld in list:
		total += 1 + bld.t.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = box
	mm.instance_count = total
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var body := StaticBody3D.new()
	body.set_meta("surface", "building")
	body.collision_layer = LAYER_WORLD
	root.add_child(body)
	# Rooftop parapets / plant rooms
	var props := SurfaceTool.new()
	props.begin(Mesh.PRIMITIVE_TRIANGLES)
	var signs: Array = []
	var k := 0
	for bld in list:
		var b: Array = bld.b
		var x0: float = b[0]
		var z0: float = b[1]
		var x1: float = b[2]
		var z1: float = b[3]
		var h: float = b[4]
		var w := x1 - x0
		var dd := z1 - z0
		var cx := (x0 + x1) * 0.5
		var cz := (z0 + z1) * 0.5
		var style := int(bld.s)
		var custom := Color(style / 3.0, float(bld.c) / 8.0, rng.randf(), 0)
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(w, h, dd)), Vector3(cx, h * 0.5, cz)))
		mm.set_instance_custom_data(k, custom)
		k += 1
		var top := h
		var tw := w
		var td := dd
		for t in bld.t:
			var tw2: float = t[0]
			var td2: float = t[1]
			var base: float = t[2]
			var add: float = t[3]
			mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(tw2, add, td2)), Vector3(cx, base + add * 0.5, cz)))
			mm.set_instance_custom_data(k, Color(custom.r, custom.g, rng.randf(), 0))
			k += 1
			top = base + add
			tw = tw2
			td = td2
		# Parapet and rooftop machinery on the highest tier
		var pc := Color(0.35, 0.35, 0.36)
		Proc.box(props, Vector3(cx, top + 0.6, cz - td * 0.5 + 0.2), Vector3(tw, 1.2, 0.4), pc)
		Proc.box(props, Vector3(cx, top + 0.6, cz + td * 0.5 - 0.2), Vector3(tw, 1.2, 0.4), pc)
		Proc.box(props, Vector3(cx - tw * 0.5 + 0.2, top + 0.6, cz), Vector3(0.4, 1.2, td), pc)
		Proc.box(props, Vector3(cx + tw * 0.5 - 0.2, top + 0.6, cz), Vector3(0.4, 1.2, td), pc)
		for i in rng.randi_range(1, 3):
			var s := Vector3(rng.randf_range(2, 5), rng.randf_range(1.5, 3.5), rng.randf_range(2, 5))
			Proc.box(props, Vector3(cx + rng.randf_range(-0.3, 0.3) * tw, top + s.y * 0.5, cz + rng.randf_range(-0.3, 0.3) * td), s, Color(0.45, 0.46, 0.47))
		# Collision for the footprint only (upper tiers are unreachable).
		var bs := BoxShape3D.new()
		bs.size = Vector3(w, h, dd)
		var cs := CollisionShape3D.new()
		cs.shape = bs
		cs.position = Vector3(cx, h * 0.5, cz)
		body.add_child(cs)
		var occ := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = Vector3(w - 1.0, h - 1.0, dd - 1.0)
		occ.occluder = bo
		occ.position = Vector3(cx, h * 0.5, cz)
		root.add_child(occ)
		buildings.append({"rect": Rect2(x0, z0, w, dd), "h": h, "style": style})
		if rng.randf() < 0.45 and h > 12.0:
			var side := rng.randi_range(0, 3)
			var sy := rng.randf_range(5.0, minf(16.0, h - 4.0))
			var sh := rng.randf_range(3.0, 7.0)
			var neon: Color = [Color(1, 0.15, 0.6), Color(0.1, 0.85, 1), Color(1, 0.8, 0.1), Color(0.55, 0.3, 1), Color(1, 0.3, 0.15), Color(0.2, 1, 0.5)][rng.randi_range(0, 5)]
			var pos: Vector3
			var size: Vector3
			match side:
				0: pos = Vector3(x0 - 0.35, sy, cz + rng.randf_range(-0.3, 0.3) * dd); size = Vector3(0.3, sh, rng.randf_range(1.2, 2.4))
				1: pos = Vector3(x1 + 0.35, sy, cz + rng.randf_range(-0.3, 0.3) * dd); size = Vector3(0.3, sh, rng.randf_range(1.2, 2.4))
				2: pos = Vector3(cx + rng.randf_range(-0.3, 0.3) * w, sy, z0 - 0.35); size = Vector3(rng.randf_range(1.2, 2.4), sh, 0.3)
				_: pos = Vector3(cx + rng.randf_range(-0.3, 0.3) * w, sy, z1 + 0.35); size = Vector3(rng.randf_range(1.2, 2.4), sh, 0.3)
			signs.append([pos, size, neon])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "Buildings"
	root.add_child(mmi)
	props.generate_normals()
	var pm := ArrayMesh.new()
	props.commit(pm)
	var pmat := StandardMaterial3D.new()
	pmat.vertex_color_use_as_albedo = true
	pmat.albedo_texture = noise_a
	pmat.roughness = 0.85
	var pmi := MeshInstance3D.new()
	pmi.mesh = pm
	pmi.material_override = pmat
	root.add_child(pmi)
	_emissive_boxes(root, signs, 6.0)

func _emissive_boxes(root: Node3D, items: Array, strength: float) -> void:
	if items.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = EMISSIVE_SHADER
	mat.set_shader_parameter("strength", strength)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	bm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = bm
	mm.instance_count = items.size()
	for i in items.size():
		var it: Array = items[i]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(it[1]), it[0]))
		var c: Color = it[2]
		mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, it[3] if it.size() > 3 else 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)

func _build_signals(root: Node3D, hw: float) -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.vertex_color_use_as_albedo = true
	pole_mat.metallic = 0.4
	pole_mat.roughness = 0.5
	var mesh := Proc.signal_pole_mesh(pole_mat)
	var xf: Array[Transform3D] = []
	var lights: Array = []
	for a in streets.size():
		for b in streets.size():
			var sx: float = streets[a]
			var sz: float = streets[b]
			if absf(sx) > 590 or absf(sz) > 590:
				continue
			# Two diagonal corners, arms reaching over the lanes.
			for corner in [[Vector3(sx - hw - 1.5, 0.18, sz - hw - 1.5), 0.0, 0.6], [Vector3(sx + hw + 1.5, 0.18, sz + hw + 1.5), PI, 0.6],
					[Vector3(sx + hw + 1.5, 0.18, sz - hw - 1.5), -PI * 0.5, 0.9], [Vector3(sx - hw - 1.5, 0.18, sz + hw + 1.5), PI * 0.5, 0.9]]:
				var bas := Basis(Vector3.UP, corner[1])
				var t := Transform3D(bas, corner[0])
				xf.append(t)
				var head := t * Vector3(0, 5.3, 6.0)
				var face := bas * Vector3(0, 0, 0.17)
				var phase: float = corner[2]
				lights.append([head + Vector3(0, 0.3, 0) + face, Vector3.ONE * 0.2, Color(1, 0.05, 0.02), phase])
				lights.append([head + Vector3(0, -0.3, 0) + face, Vector3.ONE * 0.2, Color(0.1, 1, 0.35), 1.5 - phase])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)
	_emissive_boxes(root, lights, 8.0)

# ---------------------------------------------------------------- lamps
func _build_lamps() -> void:
	var root := Node3D.new()
	root.name = "Lamps"
	add_child(root)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.5
	mat.roughness = 0.45
	var mesh := Proc.lamp_mesh(mat)
	var L: Array = d.lamps
	var count := L.size() / 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var bulbs := MultiMesh.new()
	bulbs.transform_format = MultiMesh.TRANSFORM_3D
	bulbs.use_custom_data = true
	var bmat := ShaderMaterial.new()
	bmat.shader = EMISSIVE_SHADER
	bmat.set_shader_parameter("strength", 14.0)
	bmat.set_shader_parameter("day_strength", 0.0)
	var bmesh := Proc.lamp_bulb_mesh()
	bmesh.surface_set_material(0, bmat)
	bulbs.mesh = bmesh
	bulbs.instance_count = count
	for i in count:
		var p := Vector3(L[i * 5], L[i * 5 + 1], L[i * 5 + 2])
		var dir := Vector3(L[i * 5 + 3], 0, L[i * 5 + 4])
		var bas := Basis(Vector3.UP, atan2(dir.x, dir.z))
		var t := Transform3D(bas, p)
		mm.set_instance_transform(i, t)
		bulbs.set_instance_transform(i, t)
		bulbs.set_instance_custom_data(i, Color(1.0, 0.78, 0.5, 0))
		var head := t * Vector3(0, 8.9, 2.9)
		lamp_pos.append(head)
		var key := Vector2i(floori(head.x / 100.0), floori(head.z / 100.0))
		if not lamp_grid.has(key):
			lamp_grid[key] = PackedInt32Array()
		lamp_grid[key].append(lamp_pos.size() - 1)
	for m in [mm, bulbs]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = m
		mmi.visibility_range_end = 1600.0
		root.add_child(mmi)
	# Real light pool, moved to the lamps nearest the camera.
	for i in int(q.lamp_lights):
		var l := SpotLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.52)
		l.spot_range = 28.0
		l.spot_angle = 62.0
		l.spot_attenuation = 1.2
		l.light_energy = 0.0
		l.shadow_enabled = bool(q.lamp_shadows) and i < 8
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.visible = false
		root.add_child(l)
		lamp_lights.append(l)

func update_lamps(delta: float, cam_pos: Vector3, night: float) -> void:
	lamp_timer -= delta
	if lamp_timer > 0.0:
		return
	lamp_timer = 0.3
	var on := night > 0.15
	if not on:
		for l in lamp_lights:
			l.visible = false
		return
	var key := Vector2i(floori(cam_pos.x / 100.0), floori(cam_pos.z / 100.0))
	var cand: Array = []
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var k := key + Vector2i(dx, dz)
			if lamp_grid.has(k):
				for idx in lamp_grid[k]:
					cand.append([lamp_pos[idx].distance_squared_to(cam_pos), idx])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for i in lamp_lights.size():
		var l := lamp_lights[i]
		if i < cand.size():
			l.visible = true
			l.position = lamp_pos[cand[i][1]] - Vector3(0, 0.2, 0)
			l.light_energy = 6.0 * night
		else:
			l.visible = false

# ---------------------------------------------------------------- vegetation
func _build_trees() -> void:
	var root := Node3D.new()
	root.name = "Trees"
	add_child(root)
	var bark := StandardMaterial3D.new()
	bark.vertex_color_use_as_albedo = true
	bark.albedo_texture = noise_a
	bark.uv1_scale = Vector3(3, 6, 1)
	bark.roughness = 0.95
	var leaf_b := ShaderMaterial.new()
	leaf_b.shader = FOLIAGE_SHADER
	leaf_b.set_shader_parameter("leaf_tex", Proc.leaf_texture(false))
	var leaf_p := ShaderMaterial.new()
	leaf_p.shader = FOLIAGE_SHADER
	leaf_p.set_shader_parameter("leaf_tex", Proc.leaf_texture(true))
	leaf_p.set_shader_parameter("sway", 0.06)
	var meshes := {
		"b_near": Proc.tree_mesh(false, 18, bark, leaf_b), "b_far": Proc.tree_mesh(false, 6, bark, leaf_b),
		"p_near": Proc.tree_mesh(true, 42, bark, leaf_p), "p_far": Proc.tree_mesh(true, 18, bark, leaf_p),
	}
	var T: Array = d.trees
	var count := T.size() / 6
	var keep: float = q.trees
	var tiles := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in count:
		if rng.randf() > keep and not in_city(T[i * 6], T[i * 6 + 2]):
			continue
		var key := Vector2i(floori((float(T[i * 6]) + HALF) / 512.0), floori((float(T[i * 6 + 2]) + HALF) / 512.0)) * 2 + Vector2i(int(T[i * 6 + 4]), 0)
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(i)
	var near_end: float = q.tree_dist
	var far_end: float = minf(q.draw * 0.85, 3500.0)
	for key in tiles:
		var idxs: Array = tiles[key]
		var pine := int(T[idxs[0] * 6 + 4]) == 1
		for lod in ["near", "far"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = meshes[("p_" if pine else "b_") + lod]
			mm.instance_count = idxs.size()
			var center := Vector3.ZERO
			for j in idxs.size():
				var i: int = idxs[j]
				var p := Vector3(T[i * 6], T[i * 6 + 1], T[i * 6 + 2])
				center += p
				var s: float = T[i * 6 + 3]
				var t := Transform3D(Basis(Vector3.UP, T[i * 6 + 5]).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), p)
				mm.set_instance_transform(j, t)
				var g := rng.randf_range(0.8, 1.15)
				mm.set_instance_custom_data(j, Color(g * rng.randf_range(0.9, 1.1), g, g * rng.randf_range(0.85, 1.0), rng.randf()))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if lod == "near":
				mmi.visibility_range_end = near_end
				mmi.visibility_range_end_margin = 60.0
			else:
				mmi.visibility_range_begin = near_end
				mmi.visibility_range_begin_margin = 60.0
				mmi.visibility_range_end = far_end
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)

func _build_grass() -> void:
	var lvl := int(q.grass)
	if lvl <= 0 or compat:
		return
	var radius := 55.0 if lvl == 1 else 85.0
	var spacing := 1.25 if lvl == 1 else 0.85
	var side := int(radius * 2.0 / spacing)
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mat.set_shader_parameter("heightmap", height_tex)
	mat.set_shader_parameter("maskmap", mask_tex)
	mat.set_shader_parameter("blade_tex", Proc.grass_texture())
	mat.set_shader_parameter("noise_a", noise_a)
	mat.set_shader_parameter("half_size", HALF)
	mat.set_shader_parameter("tex_size", float(N))
	mat.set_shader_parameter("radius", radius)
	var mesh := Proc.grass_clump()
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = side * side
	var i := 0
	for z in side:
		for x in side:
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(-radius + (x + 0.5) * spacing, 0, -radius + (z + 0.5) * spacing)))
			i += 1
	grass_inst = MultiMeshInstance3D.new()
	grass_inst.multimesh = mm
	grass_inst.custom_aabb = AABB(Vector3(-HALF, -100, -HALF), Vector3(HALF * 2, 900, HALF * 2))
	grass_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass_inst)

func set_wetness(w: float) -> void:
	RenderingServer.global_shader_parameter_set("wetness", w)

# ---------------------------------------------------------------- graph
func _build_graph() -> void:
	types = d.types
	for n in d.nodes:
		node_pos.append(Vector2(n[0], n[1]))
		node_type.append(int(n[2]))
	adj = d.adj

func node_type_name(i: int) -> String:
	return types[node_type[i]]

func nearest_node(p: Vector2, allowed: Array = []) -> int:
	var best := -1
	var bd := INF
	for i in node_pos.size():
		if not allowed.is_empty() and not allowed.has(types[node_type[i]]):
			continue
		var dd := node_pos[i].distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = i
	return best

## Dijkstra over the road graph, optionally limited to some road types.
func route(a: int, b: int, allowed: Array = []) -> PackedInt32Array:
	var n := node_pos.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	dist[a] = 0.0
	var open: Array = [a]
	while not open.is_empty():
		var bi := 0
		for k in open.size():
			if dist[open[k]] < dist[open[bi]]:
				bi = k
		var u: int = open[bi]
		open.remove_at(bi)
		if u == b:
			break
		if done[u]:
			continue
		done[u] = 1
		for v in adj[u]:
			if not allowed.is_empty() and not allowed.has(types[node_type[v]]):
				continue
			var nd := dist[u] + node_pos[u].distance_to(node_pos[v])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				open.append(v)
	var path := PackedInt32Array()
	var u := b
	while u != -1:
		path.append(u)
		u = prev[u]
	path.reverse()
	if path.is_empty() or path[0] != a:
		return PackedInt32Array([a, b])
	return path

## A safe point on the nearest road, facing along it.
func respawn_at(p: Vector3) -> Transform3D:
	var id := nearest_node(Vector2(p.x, p.z))
	var n := node_pos[id]
	var best: Vector2 = node_pos[adj[id][0]]
	var bd := -INF
	for k in adj[id]:
		var m := node_pos[k]
		var dot := (m - n).dot(n - Vector2(p.x, p.z))
		if dot > bd:
			bd = dot
			best = m
	var dir := (best - n).normalized()
	var right := Vector2(-dir.y, dir.x)
	var pos2 := n + right * 3.5
	var y := ground(pos2.x, pos2.y)
	if in_city(pos2.x, pos2.y):
		y = 0.03
	var fwd := Vector3(dir.x, 0, dir.y)
	var basis := Basis.looking_at(fwd, Vector3.UP)
	return Transform3D(basis, Vector3(pos2.x, y + 1.0, pos2.y))
