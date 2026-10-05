class_name BodyGen
extends RefCounted
## Procedural classic car bodies: lofted superellipse sections with wheel
## arches, a glass greenhouse, chrome bumpers and round lamps. Cars face -Z.

const BODIES := {
	# Late-60s fastback muscle car
	"stallion": {
		"wheel_r": 0.36, "wheel_front": -1.42, "wheel_rear": 1.46, "track": 0.8,
		"body": [ # [z, half-width, bottom, top]
			[-2.42, 0.86, 0.36, 0.78], [-2.30, 0.93, 0.32, 0.84], [-1.9, 0.95, 0.3, 0.86], [-1.2, 0.96, 0.3, 0.88],
			[-0.5, 0.97, 0.3, 0.9], [0.4, 0.97, 0.3, 0.92], [1.2, 0.97, 0.3, 0.93], [1.9, 0.96, 0.32, 0.93],
			[2.32, 0.92, 0.36, 0.9], [2.45, 0.86, 0.4, 0.84],
		],
		"cabin": [ # [z, half-width, roof]
			[-0.62, 0.8, 0.9], [-0.25, 0.74, 1.3], [0.35, 0.72, 1.34], [0.9, 0.72, 1.24], [1.6, 0.74, 0.96],
		],
		"n_body": 5.0, "n_cabin": 3.0, "scoop": true, "round_lights": true, "chrome": true,
	},
	# Late-70s wedge supercar
	"wedge": {
		"wheel_r": 0.36, "wheel_front": -1.36, "wheel_rear": 1.32, "track": 0.82,
		"body": [
			[-2.3, 0.88, 0.32, 0.5], [-2.0, 0.96, 0.28, 0.62], [-1.2, 1.0, 0.28, 0.76], [-0.4, 1.0, 0.28, 0.86],
			[0.6, 1.0, 0.28, 0.92], [1.5, 1.0, 0.3, 0.94], [2.1, 0.97, 0.32, 0.9], [2.3, 0.9, 0.36, 0.82],
		],
		"cabin": [
			[-1.05, 0.78, 0.8], [-0.35, 0.72, 1.08], [0.35, 0.7, 1.12], [1.0, 0.72, 1.02], [1.6, 0.76, 0.9],
		],
		"n_body": 6.0, "n_cabin": 4.0, "scoop": false, "round_lights": false, "chrome": false, "wing": true,
	},
}

static func _interp(keys: Array, z: float, k: int) -> float:
	if z <= keys[0][0]:
		return keys[0][k]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if z <= b[0]:
			var t := (z - float(a[0])) / (float(b[0]) - float(a[0]))
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(a[k], b[k], t)
	return keys[keys.size() - 1][k]

static func _se(t: float, n: float) -> Vector2:
	var c := cos(t)
	var s := sin(t)
	return Vector2(signf(c) * pow(absf(c), 2.0 / n), signf(s) * pow(absf(s), 2.0 / n))

static func _loft(st: SurfaceTool, sections: Array, n: float, ring: int, caps: bool) -> void:
	# sections: [z, halfw, y0, y1]
	var rings: Array = []
	for sec in sections:
		var pts := PackedVector3Array()
		var yc := (float(sec[2]) + float(sec[3])) * 0.5
		var hb := (float(sec[3]) - float(sec[2])) * 0.5
		for i in ring:
			var t := TAU * i / ring
			var p := _se(t, n)
			pts.append(Vector3(p.x * float(sec[1]), yc + p.y * hb, sec[0]))
		rings.append(pts)
	for r in rings.size() - 1:
		var A: PackedVector3Array = rings[r]
		var B: PackedVector3Array = rings[r + 1]
		for i in ring:
			var j := (i + 1) % ring
			var u0 := float(i) / ring
			var u1 := float(i + 1) / ring
			for v in [[A[i], u0, r], [B[i], u0, r + 1], [A[j], u1, r], [A[j], u1, r], [B[i], u0, r + 1], [B[j], u1, r + 1]]:
				st.set_uv(Vector2(v[1], float(v[2]) / rings.size()))
				st.add_vertex(v[0])
	if caps:
		for e in [0, rings.size() - 1]:
			var R: PackedVector3Array = rings[e]
			var c := Vector3.ZERO
			for p in R:
				c += p
			c /= R.size()
			for i in ring:
				var j := (i + 1) % ring
				var tri := [c, R[i], R[j]] if e == rings.size() - 1 else [c, R[j], R[i]]
				for p in tri:
					st.set_uv(Vector2(0.5, 0.5))
					st.add_vertex(p)

static func _sections(def: Dictionary) -> Array:
	var keys: Array = def.body
	var z0: float = keys[0][0]
	var z1: float = keys[keys.size() - 1][0]
	var wf: float = def.wheel_front
	var wr: float = def.wheel_rear
	var r: float = def.wheel_r
	var out: Array = []
	var steps := 70
	for i in steps + 1:
		var z := lerpf(z0, z1, float(i) / steps)
		var y0 := _interp(keys, z, 2)
		# Wheel arches: lift the sill around each axle.
		for wz in [wf, wr]:
			var dz: float = (z - float(wz)) / (r + 0.12)
			if absf(dz) < 1.0:
				y0 = maxf(y0, r * 2.0 * sqrt(1.0 - dz * dz) - 0.02)
		out.append([z, _interp(keys, z, 1), y0, _interp(keys, z, 3)])
	return out

## Returns a Node3D with Body/Glass/Trim meshes and Wheel* nodes (like the glb).
static func build(id: String, paint: StandardMaterial3D) -> Node3D:
	var def: Dictionary = BODIES[id]
	var root := Node3D.new()
	root.name = "BodyGen_" + id
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	_loft(st, _sections(def), def.n_body, 40, true)
	st.generate_normals()
	st.generate_tangents()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = st.commit()
	body.material_override = paint
	root.add_child(body)
	# Greenhouse
	var gs := SurfaceTool.new()
	gs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cabin: Array = []
	var ck: Array = def.cabin
	for i in 31:
		var z := lerpf(ck[0][0], ck[ck.size() - 1][0], float(i) / 30.0)
		var base := _interp(def.body, z, 3) - 0.04
		cabin.append([z, _interp(ck, z, 1), base - 0.1, maxf(_interp(ck, z, 2), base + 0.02)])
	_loft(gs, cabin, def.n_cabin, 32, true)
	gs.generate_normals()
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = gs.commit()
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.03, 0.04, 0.05)
	gm.metallic = 0.6
	gm.roughness = 0.04
	gm.clearcoat_enabled = true
	glass.material_override = gm
	root.add_child(glass)
	# Painted roof skin over the glass (leaves windscreen and side windows visible).
	var rs := SurfaceTool.new()
	rs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof: Array = []
	for c in cabin:
		var t: float = (float(c[0]) - float(ck[1][0])) / (float(ck[ck.size() - 2][0]) - float(ck[1][0]))
		if t < 0.0 or t > 1.0:
			continue
		roof.append([c[0], float(c[1]) * 0.92, float(c[3]) - 0.06, float(c[3]) + 0.012])
	if roof.size() > 2:
		_loft(rs, roof, 6.0, 24, true)
		rs.generate_normals()
		var rm := MeshInstance3D.new()
		rm.mesh = rs.commit()
		rm.material_override = paint
		root.add_child(rm)
	# Trim: bumpers, grille, lamps, scoop, mirrors, exhausts
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.9, 0.9, 0.92) if def.chrome else Color(0.05, 0.05, 0.055)
	chrome.metallic = 1.0 if def.chrome else 0.2
	chrome.roughness = 0.08 if def.chrome else 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.02)
	dark.roughness = 0.6
	var keys: Array = def.body
	var zf: float = keys[0][0]
	var zr: float = keys[keys.size() - 1][0]
	var hwf: float = keys[0][1]
	_box(root, Vector3(0, 0.42, zf - 0.03), Vector3(hwf * 2.05, 0.13, 0.12), chrome)
	_box(root, Vector3(0, 0.44, zr + 0.03), Vector3(float(keys[keys.size() - 1][1]) * 2.05, 0.13, 0.12), chrome)
	_box(root, Vector3(0, 0.6, zf + 0.01), Vector3(hwf * 1.3, 0.2, 0.06), dark)
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(0.9, 0.9, 0.85)
	head.emission_enabled = true
	head.emission = Color(1, 0.95, 0.85)
	head.emission_energy_multiplier = 0.3
	head.resource_name = "Headlight"
	var brake := StandardMaterial3D.new()
	brake.albedo_color = Color(0.4, 0.02, 0.02)
	brake.emission_enabled = true
	brake.emission = Color(1, 0.05, 0.02)
	brake.resource_name = "Brakelight"
	var lamp_y := _interp(keys, zf + 0.15, 3) - 0.18
	for sx in [-1.0, 1.0]:
		if def.round_lights:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.11
			cyl.bottom_radius = 0.11
			cyl.height = 0.06
			var l := MeshInstance3D.new()
			l.name = "Headlamp"
			l.mesh = cyl
			l.material_override = head
			l.rotation_degrees = Vector3(90, 0, 0)
			l.position = Vector3(sx * hwf * 0.62, lamp_y, zf + 0.04)
			root.add_child(l)
		else:
			var hl := _box(root, Vector3(sx * hwf * 0.6, lamp_y + 0.04, zf + 0.12), Vector3(0.42, 0.05, 0.1), head)
			hl.name = "Headlamp"
		var tl := _box(root, Vector3(sx * 0.55, _interp(keys, zr - 0.1, 3) - 0.2, zr + 0.02), Vector3(0.5, 0.11, 0.05), brake)
		tl.name = "Taillamp"
		_box(root, Vector3(sx * (_interp(keys, -0.4, 1) + 0.08), _interp(keys, -0.4, 3) + 0.08, -0.45), Vector3(0.16, 0.09, 0.12), chrome)
		var ex := CylinderMesh.new()
		ex.top_radius = 0.045
		ex.bottom_radius = 0.045
		ex.height = 0.25
		var e := MeshInstance3D.new()
		e.mesh = ex
		e.material_override = chrome
		e.rotation_degrees = Vector3(90, 0, 0)
		e.position = Vector3(sx * 0.5, 0.3, zr + 0.05)
		root.add_child(e)
	if def.scoop:
		_box(root, Vector3(0, _interp(keys, -1.2, 3) + 0.06, -1.2), Vector3(0.62, 0.12, 0.8), dark)
	if def.get("wing", false):
		_box(root, Vector3(0, 1.08, zr - 0.25), Vector3(1.7, 0.05, 0.4), paint)
		for sx in [-0.6, 0.6]:
			_box(root, Vector3(sx, 0.98, zr - 0.2), Vector3(0.06, 0.2, 0.25), dark)
	# Wheels: realistic tyres from the merged wheel mesh, chrome or dark rims.
	var wr: float = def.wheel_r
	var wscale := wr / 0.38
	var wheel_mesh := CarMesh.wheel()
	var defs := [["WheelFrontL", -1, def.wheel_front], ["WheelFrontR", 1, def.wheel_front], ["WheelRearL", -1, def.wheel_rear], ["WheelRearR", 1, def.wheel_rear]]
	for d in defs:
		var w := Node3D.new()
		w.name = d[0]
		w.position = Vector3(float(d[1]) * (float(def.track) + 0.17), wr, d[2])
		root.add_child(w)
		var wm := MeshInstance3D.new()
		wm.name = d[0] + "Rim"
		wm.mesh = wheel_mesh
		wm.scale = Vector3(-wscale if d[1] > 0 else wscale, wscale, wscale)
		if def.chrome:
			for i in wheel_mesh.get_surface_count():
				var m := wheel_mesh.surface_get_material(i)
				if m and String(m.resource_name).begins_with("Rim"):
					wm.set_surface_override_material(i, chrome)
		w.add_child(wm)
	return root

static func _box(root: Node3D, c: Vector3, s: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = s
	var m := MeshInstance3D.new()
	m.mesh = b
	m.material_override = mat
	m.position = c
	root.add_child(m)
	return m

static func wheel_layout(id: String) -> Dictionary:
	var def: Dictionary = BODIES[id]
	return {"r": def.wheel_r, "front": def.wheel_front, "rear": def.wheel_rear, "x": float(def.track) + 0.17}
