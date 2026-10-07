class_name GasStations
extends RefCounted
## Roadside gas stations: canopy over two pump islands, a lit price sign and a shop.
## Stop under the canopy to repair the car and refill nitrous (see game.gd).

## Where they go: [road name, position along it (0..1), brand colour, name].
const SITES := [
	["Coastal Highway", 0.07, Color(0.9, 0.12, 0.1), "Bayline Fuel"],
	["Coastal Highway", 0.31, Color(0.1, 0.45, 0.95), "Pacific Gas"],
	["Coastal Highway", 0.56, Color(0.95, 0.65, 0.05), "SunStop"],
	["Coastal Highway", 0.81, Color(0.1, 0.75, 0.35), "Evergreen Fuel"],
	["Summit Pass", 0.48, Color(0.9, 0.12, 0.1), "Summit Fuel"],
	["Valley Road", 0.55, Color(0.95, 0.65, 0.05), "Valley Gas & Go"],
	["Airfield Access", 0.5, Color(0.1, 0.45, 0.95), "Runway Fuel"],
	["North Expressway", 0.55, Color(0.1, 0.75, 0.35), "Northgate Gas"],
	["Harbor Expressway", 0.6, Color(0.9, 0.12, 0.1), "Harbor Fuel"],
	["West Expressway", 0.6, Color(0.95, 0.65, 0.05), "Westside Gas"],
]

## Returns [{pos: Vector3 (pad centre), basis: Basis (z along the road, x away from it), name}].
static func place(world: World) -> Array:
	var out: Array = []
	var roads: Array = world.d.roads
	for site in SITES:
		var ri := -1
		for k in roads.size():
			if str(roads[k].name) == site[0]:
				ri = k
		if ri < 0:
			continue
		var road: Dictionary = roads[ri]
		var pts: Array = road.pts
		var n := pts.size() / 3
		var hw: float = road.hw
		var best: Dictionary = {}
		var best_err := INF
		# Try spots around the requested one, both sides; keep the flattest clear one.
		for df in [0.0, 0.02, -0.02, 0.04, -0.04, 0.07, -0.07]:
			var i := clampi(int((float(site[1]) + df) * n), 4, n - 5)
			var a := Vector3(pts[(i - 4) * 3], 0, pts[(i - 4) * 3 + 2])
			var b := Vector3(pts[(i + 4) * 3], 0, pts[(i + 4) * 3 + 2])
			var c := Vector3(pts[i * 3], float(pts[i * 3 + 1]), pts[i * 3 + 2])
			var along := (b - a).normalized()
			# Straight stretches only: the canopy is a straight box.
			var bend := (c - (a + b) * 0.5)
			bend.y = 0.0
			if bend.length() > 2.0:
				continue
			var side := along.cross(Vector3.UP).normalized()
			for sgn in [1.0, -1.0]:
				var x_axis: Vector3 = side * sgn
				var center: Vector3 = c + x_axis * (hw + 7.5)
				if world.in_city(center.x, center.z) or c.y < 2.0:
					continue
				if _near_other_road(roads, ri, center + x_axis * 6.0, 30.0):
					continue
				var err := 0.0
				for off in [2.0, 10.0, 18.0, 28.0]:
					for dz in [-15.0, 0.0, 15.0]:
						var q: Vector3 = center + x_axis * (off - 7.5) + along * dz
						var g := world.ground(q.x, q.z)
						if g < 1.0:
							err = INF
						err = maxf(err, absf(g - c.y))
				err += absf(df) * 40.0
				if err < best_err:
					best_err = err
					center.y = c.y
					best = {"pos": center, "basis": Basis(x_axis, Vector3.UP, x_axis.cross(Vector3.UP)), "name": site[3], "color": site[2], "road_y": c.y}
		if not best.is_empty():
			out.append(best)
	return out

## True if any other road's centreline passes within reach of p (plus its half width).
static func _near_other_road(roads: Array, skip: int, p: Vector3, reach: float) -> bool:
	for k in roads.size():
		if k == skip:
			continue
		var pts: Array = roads[k].pts
		var m: float = reach + float(roads[k].hw)
		for i in pts.size() / 3:
			if absf(pts[i * 3] - p.x) < m and absf(pts[i * 3 + 2] - p.z) < m:
				if Vector2(pts[i * 3] - p.x, pts[i * 3 + 2] - p.z).length() < m:
					return true
	return false

const EMISSIVE_VC := preload("res://shaders/emissive_vc.gdshader")
const SHOP_WALLS := [Color(0.82, 0.79, 0.72), Color(0.7, 0.71, 0.72), Color(0.62, 0.36, 0.28), Color(0.86, 0.84, 0.8)]
const PRICES := [[3.79, 4.19, 4.05], [3.89, 4.29, 4.09], [3.69, 4.09, 3.99], [3.99, 4.39, 4.19]]

## Footprint in station space (x away from the road, z along it).
const PAD_X0 := -8.0
const PAD_X1 := 22.0
const PAD_Z := 16.0
## The canopy: stop anywhere under it to get serviced.
const CANOPY_X0 := -5.0
const CANOPY_X1 := 9.0
const CANOPY_Z := 11.0

static func _emissive(strength: float, day: float, base := 0.25, rough := 0.3, metal := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = EMISSIVE_VC
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("day_strength", day)
	m.set_shader_parameter("base", base)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	return m

static func _label(root: Node3D, xf: Transform3D, pos: Vector3, facing: Vector3, text: String, size: int, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 0
	l.modulate = col
	l.double_sided = false
	l.shaded = false
	l.no_depth_test = false
	l.visibility_range_end = 420.0
	# Label3D faces +z; turn it to face `facing` (station space).
	l.transform = xf * Transform3D(Basis.looking_at(-facing, Vector3.UP), pos)
	root.add_child(l)

static func build(world: World, root: Node3D, stations: Array) -> void:
	var metal := world.prop_material(World.L_PAINTED_METAL, 1.5, 0.5, 0.35)
	var conc := world.prop_material(6.0, 3.0, 0.35, 0.0)
	var wall := world.prop_material(9.0, 3.0, 0.62, 0.0)
	var lights := _emissive(2.2, 1.1, 0.6)
	var glass := _emissive(1.6, 0.06, 0.12, 0.06, 0.6)
	var screens := _emissive(2.0, 0.9, 0.2, 0.2)
	for si in stations.size():
		var st: Dictionary = stations[si]
		var xf := Transform3D(st.basis, st.pos)
		var brand: Color = st.color
		var white := Color(0.9, 0.9, 0.91)
		var dark := Color(0.12, 0.12, 0.13)
		var body := StaticBody3D.new()
		body.collision_layer = World.LAYER_WORLD
		body.set_meta("surface", "building")
		body.transform = xf
		root.add_child(body)
		var m := SurfaceTool.new()
		m.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pad := SurfaceTool.new()
		pad.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wl := SurfaceTool.new()
		wl.begin(Mesh.PRIMITIVE_TRIANGLES)
		var lit := SurfaceTool.new()
		lit.begin(Mesh.PRIMITIVE_TRIANGLES)
		var gl := SurfaceTool.new()
		gl.begin(Mesh.PRIMITIVE_TRIANGLES)
		var scr := SurfaceTool.new()
		scr.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Forecourt slab from the road edge to behind the shop; top sits just above the ground.
		Proc.box(pad, Vector3((PAD_X0 + PAD_X1) * 0.5, -0.04, 0), Vector3(PAD_X1 - PAD_X0, 0.12, PAD_Z * 2.0), Color(0.36, 0.36, 0.35))
		# Darker, oil-stained strips along the pump lanes.
		for lx in [-2.6, 3.0, 8.0]:
			Proc.box(pad, Vector3(lx, -0.03, 0), Vector3(1.6, 0.12, 9.0), Color(0.27, 0.27, 0.26))
		# Parking bays beside the shop.
		for k in 3:
			Proc.box(m, Vector3(15.0, 0.025, 9.6 + k * 2.9), Vector3(5.0, 0.02, 0.12), white)
		# ---- Canopy: white roof, tall brand fascia all round, light grey ceiling with light panels.
		var cx := (CANOPY_X0 + CANOPY_X1) * 0.5
		var cw := CANOPY_X1 - CANOPY_X0
		var cl := CANOPY_Z * 2.0
		Proc.box(m, Vector3(cx, 5.85, 0), Vector3(cw - 0.3, 0.2, cl - 0.3), white)
		Proc.box(m, Vector3(cx, 5.12, 0), Vector3(cw - 0.3, 0.06, cl - 0.3), Color(0.8, 0.8, 0.8))
		for sx in [-1.0, 1.0]:
			Proc.box(m, Vector3(cx + sx * cw * 0.5, 5.5, 0), Vector3(0.14, 0.9, cl), brand)
			Proc.box(m, Vector3(cx + sx * (cw * 0.5 + 0.01), 5.1, 0), Vector3(0.14, 0.1, cl), white)
			Proc.box(m, Vector3(cx, 5.5, sx * cl * 0.5), Vector3(cw, 0.9, 0.14), brand)
			Proc.box(m, Vector3(cx, 5.1, sx * (cl * 0.5 + 0.01)), Vector3(cw, 0.1, 0.14), white)
		for ix in [-1.5, 1.5]:
			for iz in [-7.5, -2.5, 2.5, 7.5]:
				Proc.box(lit, Vector3(cx + ix * 2.6, 5.08, iz), Vector3(1.4, 0.03, 0.8), Color(1.0, 0.97, 0.9))
		var nm := str(st.name).to_upper()
		var ink := Color(0.08, 0.08, 0.1) if brand.get_luminance() > 0.55 else Color(1, 1, 1) # text on the brand colour
		_label(root, xf, Vector3(CANOPY_X0 - 0.09, 5.5, 0), Vector3(-1, 0, 0), nm, 110, ink)
		_label(root, xf, Vector3(CANOPY_X1 + 0.09, 5.5, 0), Vector3(1, 0, 0), nm, 110, ink)
		_label(root, xf, Vector3(cx, 5.5, CANOPY_Z + 0.09), Vector3(0, 0, 1), nm, 90, ink)
		_label(root, xf, Vector3(cx, 5.5, -CANOPY_Z - 0.09), Vector3(0, 0, -1), nm, 90, ink)
		# ---- Two pump islands (along the road), pillars rising from them.
		for ix in [0.2, 5.8]:
			Proc.box(pad, Vector3(ix, 0.1, 0), Vector3(1.3, 0.22, 9.0), Color(0.62, 0.62, 0.6))
			_collider(body, Vector3(ix, 0.5, 0), Vector3(1.3, 1.0, 9.0))
			for e in [-1.0, 1.0]:
				# Yellow nose and bollards at both ends.
				Proc.box(m, Vector3(ix, 0.12, e * 4.6), Vector3(1.32, 0.24, 0.3), Color(0.95, 0.75, 0.1))
				Proc.box(m, Vector3(ix, 0.55, e * 4.95), Vector3(0.22, 1.1, 0.22), Color(0.95, 0.75, 0.1))
				Proc.box(m, Vector3(ix, 0.85, e * 4.95), Vector3(0.24, 0.12, 0.24), dark)
				_collider(body, Vector3(ix, 0.55, e * 4.95), Vector3(0.22, 1.1, 0.22))
				# Canopy pillar.
				Proc.box(m, Vector3(ix, 2.6, e * 3.0), Vector3(0.5, 5.0, 0.5), Color(0.78, 0.78, 0.8))
				Proc.box(m, Vector3(ix, 0.45, e * 3.0), Vector3(0.6, 0.7, 0.6), brand)
			for pz in [-1.5, 1.5]:
				# Pump: plinth, body, brand cap, screens on both lane sides, hoses and nozzles.
				Proc.box(m, Vector3(ix, 0.28, pz), Vector3(0.7, 0.16, 1.0), dark)
				Proc.box(m, Vector3(ix, 1.15, pz), Vector3(0.55, 1.6, 0.95), Color(0.93, 0.93, 0.94))
				Proc.box(m, Vector3(ix, 2.05, pz), Vector3(0.6, 0.3, 1.0), brand)
				Proc.box(m, Vector3(ix, 0.7, pz), Vector3(0.57, 0.18, 0.97), Color(0.25, 0.25, 0.27))
				for sx in [-1.0, 1.0]:
					Proc.box(scr, Vector3(ix + sx * 0.285, 1.55, pz), Vector3(0.02, 0.32, 0.55), Color(0.55, 0.9, 1.0))
					Proc.box(m, Vector3(ix + sx * 0.29, 1.15, pz - 0.25), Vector3(0.02, 0.22, 0.3), dark)
					Proc.box(m, Vector3(ix + sx * 0.33, 1.0, pz + 0.38), Vector3(0.08, 0.28, 0.12), Color(0.15, 0.15, 0.15))
					Proc.box(m, Vector3(ix + sx * 0.3, 0.75, pz + 0.38), Vector3(0.05, 0.9, 0.05), Color(0.08, 0.08, 0.08))
			# Bin and windscreen-wash bucket at the island end.
			Proc.box(m, Vector3(ix, 0.65, -4.15), Vector3(0.5, 0.85, 0.5), Color(0.2, 0.3, 0.22))
			Proc.box(m, Vector3(ix, 0.45, 4.2), Vector3(0.35, 0.45, 0.35), Color(0.15, 0.4, 0.8))
		# ---- Shop: walls, dark glass storefront facing the pumps, door, brand band, roof gear.
		var wcol: Color = SHOP_WALLS[si % SHOP_WALLS.size()]
		var sx0 := 13.0
		var sx1 := 21.0
		var sz := 8.0
		var scx := (sx0 + sx1) * 0.5
		Proc.box(wl, Vector3(scx, 2.1, 0), Vector3(sx1 - sx0, 4.2, sz * 2.0), wcol)
		Proc.box(wl, Vector3(scx, 4.45, 0), Vector3(sx1 - sx0 + 0.3, 0.5, sz * 2.0 + 0.3), wcol.darkened(0.15))
		_collider(body, Vector3(scx, 2.2, 0), Vector3(sx1 - sx0, 4.4, sz * 2.0))
		Proc.box(gl, Vector3(sx0 - 0.03, 1.55, -1.5), Vector3(0.06, 2.3, 10.0), Color(1.0, 0.92, 0.75))
		for mz in [-6.5, -4.0, -1.5, 1.0, 3.5]:
			Proc.box(m, Vector3(sx0 - 0.07, 1.55, mz), Vector3(0.08, 2.4, 0.12), Color(0.3, 0.3, 0.32))
		Proc.box(m, Vector3(sx0 - 0.07, 0.35, -1.5), Vector3(0.1, 0.12, 10.0), Color(0.3, 0.3, 0.32))
		Proc.box(m, Vector3(sx0 - 0.07, 2.75, -1.5), Vector3(0.1, 0.12, 10.0), Color(0.3, 0.3, 0.32))
		# Door with a frame.
		Proc.box(gl, Vector3(sx0 - 0.03, 1.2, 5.6), Vector3(0.06, 2.3, 1.8), Color(1.0, 0.92, 0.75))
		Proc.box(m, Vector3(sx0 - 0.08, 2.4, 5.6), Vector3(0.1, 0.12, 2.0), Color(0.3, 0.3, 0.32))
		for dz in [4.65, 6.55]:
			Proc.box(m, Vector3(sx0 - 0.08, 1.2, dz), Vector3(0.1, 2.4, 0.1), Color(0.3, 0.3, 0.32))
		Proc.box(m, Vector3(sx0 - 0.06, 3.5, 0), Vector3(0.12, 0.85, sz * 2.0), brand)
		_label(root, xf, Vector3(sx0 - 0.14, 3.5, 0), Vector3(-1, 0, 0), "FOOD MART  ·  OPEN 24H", 80, ink)
		# Awning-free entrance step and things people leave by the door.
		Proc.box(pad, Vector3(sx0 - 0.9, 0.08, 0), Vector3(1.8, 0.16, sz * 2.0), Color(0.55, 0.55, 0.53))
		Proc.box(m, Vector3(sx0 - 0.6, 0.6, -7.3), Vector3(0.8, 1.1, 1.3), Color(0.95, 0.96, 0.98)) # ice chest
		Proc.box(m, Vector3(sx0 - 0.19, 0.85, -7.3), Vector3(0.02, 0.25, 1.0), Color(0.1, 0.4, 0.85))
		Proc.box(m, Vector3(sx0 - 0.5, 0.75, 7.4), Vector3(0.6, 1.5, 0.6), Color(0.8, 0.12, 0.1)) # air & water
		Proc.box(m, Vector3(sx0 - 0.81, 1.1, 7.4), Vector3(0.02, 0.3, 0.4), dark)
		Proc.box(m, Vector3(sx0 - 0.45, 0.5, 2.4), Vector3(0.5, 1.0, 0.5), Color(0.2, 0.3, 0.22)) # bin
		_collider(body, Vector3(sx0 - 0.6, 0.6, -7.3), Vector3(0.8, 1.2, 1.3))
		# Propane cage on the side wall.
		Proc.box(m, Vector3(scx, 0.9, -sz - 0.5), Vector3(2.4, 1.8, 0.9), Color(0.6, 0.62, 0.64))
		# Roof: AC units and a vent.
		Proc.box(m, Vector3(scx + 1.5, 4.95, -3.0), Vector3(1.6, 0.9, 1.2), Color(0.72, 0.73, 0.72))
		Proc.box(m, Vector3(scx - 1.0, 4.85, 2.5), Vector3(1.2, 0.7, 1.0), Color(0.72, 0.73, 0.72))
		Proc.box(m, Vector3(scx + 2.0, 4.9, 4.5), Vector3(0.4, 0.8, 0.4), Color(0.5, 0.5, 0.5))
		# ---- Price pylon by the entrance, readable from both directions along the road.
		var pz0 := 14.0
		var px0 := -6.3
		for ex in [-0.85, 0.85]:
			Proc.box(m, Vector3(px0 + ex, 2.5, pz0), Vector3(0.25, 5.0, 0.25), Color(0.6, 0.6, 0.62))
			_collider(body, Vector3(px0 + ex, 2.5, pz0), Vector3(0.25, 5.0, 0.25))
		Proc.box(m, Vector3(px0, 6.6, pz0), Vector3(2.3, 3.6, 0.5), brand)
		Proc.box(m, Vector3(px0, 0.25, pz0), Vector3(2.4, 0.5, 0.7), Color(0.55, 0.55, 0.53))
		for fz in [-1.0, 1.0]:
			Proc.box(lit, Vector3(px0, 5.75, pz0 + fz * 0.26), Vector3(2.0, 1.75, 0.02), Color(0.98, 0.98, 0.96))
			var pr: Array = PRICES[si % PRICES.size()]
			_label(root, xf, Vector3(px0, 5.75, pz0 + fz * 0.28), Vector3(0, 0, fz), "REG   %.2f\nPLUS  %.2f\nDSL   %.2f" % [pr[0], pr[1], pr[2]], 52, Color(0.08, 0.08, 0.1))
			_label(root, xf, Vector3(px0, 7.75, pz0 + fz * 0.26), Vector3(0, 0, fz), nm.split(" ")[0], 60, ink)
		for pair in [[m, metal], [pad, conc], [wl, wall], [lit, lights], [gl, glass], [scr, screens]]:
			var tool: SurfaceTool = pair[0]
			tool.generate_normals()
			var mi := MeshInstance3D.new()
			mi.mesh = tool.commit()
			mi.material_override = pair[1]
			mi.transform = xf
			mi.visibility_range_end = 1400.0 if pair[0] != scr else 300.0
			root.add_child(mi)
		# Forecourt light under the canopy (Forward+ only; the lit panels carry it otherwise).
		if world.compat:
			continue
		var l := OmniLight3D.new()
		l.position = xf * Vector3(cx, 4.6, 0)
		l.light_color = Color(1, 0.96, 0.88)
		l.light_energy = 1.6
		l.omni_range = 18.0
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 350.0
		l.distance_fade_length = 100.0
		root.add_child(l)

static func _collider(body: StaticBody3D, c: Vector3, s: Vector3) -> void:
	var bs := BoxShape3D.new()
	bs.size = s
	var cs := CollisionShape3D.new()
	cs.shape = bs
	cs.position = c
	body.add_child(cs)
