class_name StreetProps
extends RefCounted
## City street furniture: hydrants, parking meters, bins, benches, bus shelters,
## newspaper boxes, mailboxes, planters, bike racks, kiosks, street-name signs at
## every junction, and manholes / storm drains in the road. Downtown blocks get
## meters, kiosks and news boxes; outer blocks more planters, mailboxes and bike
## racks. Everything is laid out per block side in lines parallel to the kerb and
## kept clear of trees, lamps, signals and the corners (crosswalks).
##
## Rendered as multimeshes per prop type per 240 m chunk, with distance culling.
## No collision: like the lamp posts, they never snag a car mid-chase.

const CHUNK := 240.0
const AVENUES := ["BAYVIEW AVE", "HARBOR AVE", "MISSION AVE", "PALM AVE", "GRAND AVE", "CENTRAL AVE", "FIFTH AVE", "UNION AVE", "LINCOLN AVE", "PACIFIC AVE", "SUMMIT AVE"]
const STREETS := ["OCEAN BLVD", "1ST ST", "2ND ST", "3RD ST", "4TH ST", "MARKET ST", "6TH ST", "7TH ST", "8TH ST", "9TH ST", "NORTH ST"]

static func _mats(world: World) -> Dictionary:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.65, 0.75, 0.8, 0.22)
	glass.roughness = 0.05
	glass.metallic = 0.4
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow := ShaderMaterial.new()
	glow.shader = GasStations.EMISSIVE_VC
	glow.set_shader_parameter("strength", 2.2)
	glow.set_shader_parameter("day_strength", 0.75)
	glow.set_shader_parameter("base", 0.5)
	return {
		"metal": world.prop_material(World.L_PAINTED_METAL, 1.0, 0.5, 0.35),
		"conc": world.prop_material(6.0, 2.0, 0.35, 0.0),
		"glass": glass,
		"glow": glow,
	}

## Builds a multi-surface mesh from {material_key: SurfaceTool}.
static func _commit(parts: Dictionary, mats: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for k in parts:
		var st: SurfaceTool = parts[k]
		st.generate_normals()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[k])
	return mesh

static func _tools(keys: Array) -> Dictionary:
	var out := {}
	for k in keys:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		out[k] = st
	return out

## Prop meshes in their own space: x along the kerb, +z toward the street, y up.
static func _meshes(mats: Dictionary) -> Dictionary:
	var out := {}
	var dark := Color(0.13, 0.13, 0.14)
	var p: Dictionary
	# Fire hydrant
	p = _tools(["metal"])
	var red := Color(0.72, 0.1, 0.07)
	Proc._cylinder(p.metal, Vector3(0, 0, 0), Vector3(0, 0.08, 0), 0.2, 0.2, 10, red.darkened(0.2))
	Proc._cylinder(p.metal, Vector3(0, 0.08, 0), Vector3(0, 0.62, 0), 0.13, 0.12, 10, red)
	Proc._cylinder(p.metal, Vector3(0, 0.62, 0), Vector3(0, 0.75, 0), 0.15, 0.06, 10, red.darkened(0.15))
	for sx in [-1.0, 1.0]:
		Proc._cylinder(p.metal, Vector3(sx * 0.1, 0.45, 0), Vector3(sx * 0.22, 0.45, 0), 0.05, 0.05, 8, red.darkened(0.1))
	Proc._cylinder(p.metal, Vector3(0, 0.42, 0.1), Vector3(0, 0.42, 0.21), 0.07, 0.07, 8, red.darkened(0.1))
	out.hydrant = _commit(p, mats)
	# Parking meter
	p = _tools(["metal", "glow"])
	Proc._cylinder(p.metal, Vector3.ZERO, Vector3(0, 1.05, 0), 0.04, 0.04, 6, Color(0.3, 0.31, 0.33))
	Proc.box(p.metal, Vector3(0, 1.22, 0), Vector3(0.22, 0.34, 0.16), Color(0.45, 0.47, 0.5))
	Proc.box(p.metal, Vector3(0, 1.4, 0), Vector3(0.24, 0.05, 0.18), Color(0.25, 0.26, 0.28))
	Proc.box(p.glow, Vector3(0, 1.27, 0.081), Vector3(0.12, 0.07, 0.01), Color(0.4, 0.9, 0.5))
	out.meter = _commit(p, mats)
	# Litter bin
	p = _tools(["metal"])
	var bin_c := Color(0.12, 0.26, 0.17)
	Proc._cylinder(p.metal, Vector3.ZERO, Vector3(0, 0.9, 0), 0.28, 0.3, 12, bin_c)
	Proc._cylinder(p.metal, Vector3(0, 0.9, 0), Vector3(0, 1.0, 0), 0.32, 0.32, 12, bin_c.darkened(0.3))
	Proc._cylinder(p.metal, Vector3(0, 1.0, 0), Vector3(0, 1.06, 0), 0.32, 0.1, 12, bin_c.darkened(0.3))
	out.bin = _commit(p, mats)
	# Bench: cast iron ends, wooden slats, facing the street
	p = _tools(["metal"])
	var wood := Color(0.42, 0.27, 0.15)
	for sx in [-0.8, 0.8]:
		Proc.box(p.metal, Vector3(sx, 0.22, 0), Vector3(0.06, 0.44, 0.5), dark)
		Proc.box(p.metal, Vector3(sx, 0.62, -0.24), Vector3(0.06, 0.5, 0.06), dark)
		Proc.box(p.metal, Vector3(sx, 0.62, 0.0), Vector3(0.07, 0.05, 0.52), dark)
	for k in 3:
		Proc.box(p.metal, Vector3(0, 0.46, -0.16 + k * 0.15), Vector3(1.8, 0.04, 0.12), wood.lightened(k * 0.04))
	for k in 2:
		Proc.box(p.metal, Vector3(0, 0.66 + k * 0.17, -0.25), Vector3(1.8, 0.11, 0.035), wood)
	out.bench = _commit(p, mats)
	# Bus shelter: roof, glass back and sides, lit ad panel, a bench inside
	p = _tools(["metal", "glass", "glow"])
	var frame := Color(0.32, 0.34, 0.36)
	Proc.box(p.metal, Vector3(0, 2.5, 0), Vector3(4.4, 0.12, 1.7), frame)
	for sx in [-2.1, 2.1]:
		for sz in [-0.75, 0.7]:
			Proc.box(p.metal, Vector3(sx, 1.25, sz), Vector3(0.08, 2.5, 0.08), frame)
	Proc.box(p.metal, Vector3(0, 0.15, -0.75), Vector3(4.2, 0.06, 0.06), frame)
	Proc.box(p.glass, Vector3(-0.3, 1.3, -0.75), Vector3(3.5, 2.1, 0.03), Color.WHITE)
	Proc.box(p.glass, Vector3(-2.1, 1.3, 0.0), Vector3(0.03, 2.1, 1.3), Color.WHITE)
	Proc.box(p.metal, Vector3(2.1, 1.3, -0.05), Vector3(0.14, 2.0, 1.25), frame)
	Proc.box(p.glow, Vector3(2.18, 1.3, -0.05), Vector3(0.02, 1.7, 1.1), Color(1.0, 0.85, 0.55))
	Proc.box(p.glow, Vector3(2.02, 1.3, -0.05), Vector3(0.02, 1.7, 1.1), Color(0.55, 0.8, 1.0))
	Proc.box(p.metal, Vector3(-0.4, 0.45, -0.5), Vector3(2.4, 0.05, 0.35), Color(0.55, 0.56, 0.58))
	for sx in [-1.4, 0.6]:
		Proc.box(p.metal, Vector3(sx, 0.22, -0.5), Vector3(0.05, 0.44, 0.3), frame)
	out.shelter = _commit(p, mats)
	# Bus stop sign
	p = _tools(["metal"])
	Proc._cylinder(p.metal, Vector3.ZERO, Vector3(0, 2.7, 0), 0.04, 0.04, 6, Color(0.55, 0.56, 0.58))
	Proc.box(p.metal, Vector3(0, 2.55, 0), Vector3(0.04, 0.55, 0.45), Color(0.08, 0.3, 0.75))
	Proc.box(p.metal, Vector3(0, 2.38, 0), Vector3(0.045, 0.12, 0.38), Color(0.95, 0.95, 0.95))
	out.busstop = _commit(p, mats)
	# Newspaper boxes (three, different colours)
	p = _tools(["metal"])
	var cols := [Color(0.1, 0.3, 0.7), Color(0.75, 0.12, 0.1), Color(0.9, 0.75, 0.15)]
	for k in 3:
		var x := -0.55 + k * 0.55
		Proc.box(p.metal, Vector3(x, 0.32, 0), Vector3(0.46, 0.64, 0.4), cols[k])
		Proc.box(p.metal, Vector3(x, 0.66, 0), Vector3(0.44, 0.08, 0.38), cols[k].darkened(0.3))
		Proc.box(p.metal, Vector3(x, 0.45, 0.205), Vector3(0.34, 0.22, 0.01), Color(0.75, 0.75, 0.72))
		Proc.box(p.metal, Vector3(x, 0.28, 0.205), Vector3(0.3, 0.03, 0.02), dark)
	out.news = _commit(p, mats)
	# Mailbox
	p = _tools(["metal"])
	var mb := Color(0.1, 0.22, 0.55)
	Proc.box(p.metal, Vector3(0, 0.55, 0), Vector3(0.5, 0.75, 0.5), mb)
	Proc._cylinder(p.metal, Vector3(-0.25, 0.92, 0), Vector3(0.25, 0.92, 0), 0.25, 0.25, 10, mb)
	for sx in [-0.2, 0.2]:
		for sz in [-0.2, 0.2]:
			Proc.box(p.metal, Vector3(sx, 0.09, sz), Vector3(0.06, 0.18, 0.06), dark)
	Proc.box(p.metal, Vector3(0, 0.95, 0.26), Vector3(0.3, 0.04, 0.02), dark)
	out.mailbox = _commit(p, mats)
	# Planter with a clipped shrub
	p = _tools(["conc", "metal"])
	Proc.box(p.conc, Vector3(0, 0.25, 0), Vector3(1.3, 0.5, 1.3), Color(0.62, 0.6, 0.56))
	Proc.box(p.metal, Vector3(0, 0.49, 0), Vector3(1.15, 0.04, 1.15), Color(0.2, 0.14, 0.09))
	var leaf := Color(0.16, 0.32, 0.12)
	Proc._cylinder(p.metal, Vector3(0, 0.5, 0), Vector3(0, 0.95, 0), 0.45, 0.52, 9, leaf)
	Proc._cylinder(p.metal, Vector3(0, 0.95, 0), Vector3(0, 1.25, 0), 0.52, 0.2, 9, leaf.lightened(0.08))
	out.planter = _commit(p, mats)
	# Bike rack: four steel hoops
	p = _tools(["metal"])
	var steel := Color(0.6, 0.62, 0.64)
	for k in 4:
		var x := -0.9 + k * 0.6
		Proc.box(p.metal, Vector3(x, 0.4, -0.3), Vector3(0.05, 0.8, 0.05), steel)
		Proc.box(p.metal, Vector3(x, 0.4, 0.3), Vector3(0.05, 0.8, 0.05), steel)
		Proc.box(p.metal, Vector3(x, 0.8, 0), Vector3(0.05, 0.05, 0.65), steel)
	out.bikes = _commit(p, mats)
	# Info kiosk with a lit map / ad on both faces
	p = _tools(["metal", "glow"])
	Proc.box(p.metal, Vector3(0, 1.1, 0), Vector3(1.0, 2.2, 0.4), Color(0.2, 0.22, 0.25))
	Proc.box(p.metal, Vector3(0, 2.25, 0), Vector3(1.1, 0.1, 0.5), Color(0.15, 0.16, 0.18))
	Proc.box(p.glow, Vector3(0, 1.25, 0.205), Vector3(0.8, 1.5, 0.01), Color(0.95, 0.9, 0.8))
	Proc.box(p.glow, Vector3(0, 1.25, -0.205), Vector3(0.8, 1.5, 0.01), Color(0.9, 0.55, 0.4))
	out.kiosk = _commit(p, mats)
	# Street-name sign pole (blades added per junction, labels separately)
	p = _tools(["metal"])
	var green := Color(0.06, 0.36, 0.18)
	Proc._cylinder(p.metal, Vector3.ZERO, Vector3(0, 3.4, 0), 0.05, 0.045, 8, Color(0.4, 0.42, 0.42))
	Proc.box(p.metal, Vector3(0.65, 3.05, 0), Vector3(1.3, 0.24, 0.025), green)
	Proc.box(p.metal, Vector3(0, 3.33, 0.65), Vector3(0.025, 0.24, 1.3), green)
	out.signpole = _commit(p, mats)
	# Manhole cover and kerb drain grate (flat, sit on the asphalt)
	p = _tools(["metal"])
	Proc._cylinder(p.metal, Vector3(0, 0, 0), Vector3(0, 0.012, 0), 0.38, 0.38, 14, Color(0.16, 0.15, 0.14))
	out.manhole = _commit(p, mats)
	p = _tools(["metal"])
	Proc.box(p.metal, Vector3(0, 0.006, 0), Vector3(0.9, 0.012, 0.4), Color(0.09, 0.09, 0.09))
	for k in 6:
		Proc.box(p.metal, Vector3(-0.375 + k * 0.15, 0.013, 0), Vector3(0.05, 0.004, 0.36), Color(0.2, 0.2, 0.19))
	out.drain = _commit(p, mats)
	return out

## Visibility range per prop type (small things pop in close, shelters further out).
const RANGE := {"hydrant": 140.0, "meter": 110.0, "bin": 150.0, "bench": 150.0, "shelter": 320.0, "busstop": 200.0,
	"news": 120.0, "mailbox": 130.0, "planter": 180.0, "bikes": 110.0, "kiosk": 200.0, "signpole": 220.0, "manhole": 90.0, "drain": 80.0}
const SHADOWS := ["shelter", "bench", "kiosk", "planter"]

static func build(world: World, root: Node3D) -> void:
	var mats := _mats(world)
	var meshes := _meshes(mats)
	var hw: float = world.d.streetHw
	var streets: Array = world.streets
	var park_set := {}
	for pk in world.d.parks:
		park_set["%d,%d" % [int(pk[0]), int(pk[1])]] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var inst := {} # type -> chunk key -> Array[Transform3D]
	for k in meshes:
		inst[k] = {}
	var add := func(kind: String, xf: Transform3D) -> void:
		var key := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
		if not inst[kind].has(key):
			inst[kind][key] = []
		inst[kind][key].append(xf)
	# Things already on the pavement, to keep clear of (4 m grid).
	var taken := {}
	var take := func(p: Vector2) -> void:
		var k := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
		if not taken.has(k):
			taken[k] = []
		taken[k].append(p)
	for t in world.street_trees:
		take.call(Vector2(t.x, t.z))
	for lp in world.lamp_bases:
		take.call(lp)
	var free := func(p: Vector2, r: float) -> bool:
		var k := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for q in taken.get(k + Vector2i(dx, dz), []):
					if (q as Vector2).distance_to(p) < r:
						return false
		return true
	var setback := _setbacks(world)
	for a in streets.size() - 1:
		for b in streets.size() - 1:
			var x0: float = streets[a] + hw
			var x1: float = streets[a + 1] - hw
			var z0: float = streets[b] + hw
			var z1: float = streets[b + 1] - hw
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			var park: bool = park_set.has("%d,%d" % [int(x0), int(z0)])
			var downtown: bool = absf(cx) < 300.0 and absf(cz) < 300.0
			# Four sides: start corner at the kerb, direction along it, inward normal.
			var sides := [
				[Vector2(x0, z0), Vector2(1, 0), Vector2(0, 1), x1 - x0],
				[Vector2(x1, z1), Vector2(-1, 0), Vector2(0, -1), x1 - x0],
				[Vector2(x1, z0), Vector2(0, 1), Vector2(-1, 0), z1 - z0],
				[Vector2(x0, z1), Vector2(0, -1), Vector2(1, 0), z1 - z0],
			]
			for si in 4:
				var sd: Array = sides[si]
				var o: Vector2 = sd[0]
				var dir: Vector2 = sd[1]
				var inn: Vector2 = sd[2]
				var L: float = sd[3]
				var depth: float = setback.get("%d,%d,%d" % [int(x0), int(z0), si], 6.0)
				var at := func(t: float, dd: float) -> Vector2:
					return o + dir * t + inn * dd
				# Facing the street: local +z = -inn.
				var bas := Basis.looking_at(Vector3(inn.x, 0, inn.y), Vector3.UP)
				var place := func(kind: String, t: float, dd: float, r: float, yaw := 0.0) -> bool:
					var p: Vector2 = at.call(t, dd)
					if not free.call(p, r):
						return false
					take.call(p)
					add.call(kind, Transform3D(bas.rotated(Vector3.UP, yaw), Vector3(p.x, 0.18, p.y)))
					return true
				# Try a few spots near t (the first free one wins).
				var near := func(kind: String, t: float, dd: float, r: float) -> bool:
					for off in [0.0, 1.5, -1.5, 3.0, -3.0, 4.5, -4.5]:
						var tt: float = t + off
						if tt > 8.0 and tt < L - 8.0 and place.call(kind, tt, dd, r):
							return true
					return false
				near.call("hydrant", rng.randf_range(14.0, L - 14.0), 0.6, 1.6)
				if park:
					near.call("bench", L * 0.3, 2.4, 1.8)
					near.call("bench", L * 0.7, 2.4, 1.8)
					near.call("bin", L * 0.5, 2.4, 1.2)
					continue
				var shelter := rng.randf() < 0.16 and depth > 5.0
				if shelter:
					var ts := 42.0 if rng.randf() < 0.5 else 64.0
					var p0: Vector2 = at.call(ts, 3.4)
					var ok := true
					for e in [-2.4, 0.0, 2.4]:
						if not free.call(at.call(ts + e, 3.4), 1.3):
							ok = false
					if ok:
						take.call(p0)
						take.call(at.call(ts - 1.8, 3.4))
						take.call(at.call(ts + 1.8, 3.4))
						add.call("shelter", Transform3D(bas, Vector3(p0.x, 0.18, p0.y)))
						near.call("busstop", ts - 3.5, 0.5, 1.0)
					else:
						shelter = false
				if not shelter and rng.randf() < 0.55:
					near.call("bench", 42.0 if rng.randf() < 0.5 else 64.0, 2.4, 1.6)
				near.call("bin", 20.0, 2.4, 1.0)
				if rng.randf() < 0.6:
					near.call("bin", L - 20.0, 2.4, 1.0)
				if downtown and rng.randf() < 0.7:
					var t := 13.0
					while t < L - 13.0:
						place.call("meter", t, 0.45, 1.0)
						t += 6.5
				if depth > 5.2:
					if (downtown and rng.randf() < 0.5) or rng.randf() < 0.15:
						near.call("news", 12.0, depth - 1.0, 1.5)
					if downtown and rng.randf() < 0.18:
						near.call("kiosk", L * 0.5, depth - 1.2, 1.4)
					if not downtown and rng.randf() < 0.35:
						for t in [25.0, 50.0, 75.0]:
							near.call("planter", t, depth - 1.1, 1.6)
					if rng.randf() < 0.2:
						near.call("bikes", L * 0.35, depth - 1.0, 1.6)
				if rng.randf() < 0.3:
					near.call("mailbox", L - 12.0, 0.7, 1.2)
	# Street-name signs: one pole per junction, on the corner diagonal from the signals.
	for a in streets.size():
		for b in streets.size():
			var sx: float = streets[a]
			var sz: float = streets[b]
			if absf(sx) > 590 or absf(sz) > 590:
				continue
			var p := Vector2(sx + hw + 3.4, sz + hw + 0.7)
			add.call("signpole", Transform3D(Basis.IDENTITY, Vector3(p.x, 0.18, p.y)))
			# Blade along x names the street running along x (constant z), and vice versa.
			var ns: String = AVENUES[a % AVENUES.size()]
			var ew: String = STREETS[b % STREETS.size()]
			for f in [-1.0, 1.0]:
				_label(root, Vector3(p.x + 0.65, 3.05, p.y + f * 0.016), Vector3(0, 0, f), ew)
				_label(root, Vector3(p.x + f * 0.016, 3.33, p.y + 0.65), Vector3(f, 0, 0), ns)
	# Manholes in the lanes and drains along the kerbs, on every street segment.
	for a in streets.size():
		for b in streets.size() - 1:
			var s0: float = streets[a]
			var t0: float = streets[b] + hw + 4.0
			var t1: float = streets[b + 1] - hw - 4.0
			for k in 2:
				var t := rng.randf_range(t0, t1)
				var lane: float = [-7.5, -2.5, 2.5, 7.5][rng.randi() % 4]
				add.call("manhole", Transform3D(Basis.IDENTITY, Vector3(s0 + lane, 0.031, t)))
				add.call("manhole", Transform3D(Basis.IDENTITY, Vector3(t, 0.031, s0 + lane)))
			for sgn in [-1.0, 1.0]:
				var t := t0 + 6.0
				while t < t1:
					add.call("drain", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(s0 + sgn * (hw - 0.25), 0.031, t)))
					add.call("drain", Transform3D(Basis.IDENTITY, Vector3(t, 0.031, s0 + sgn * (hw - 0.25))))
					t += 45.0
	for kind in inst:
		for key in inst[kind]:
			var list: Array = inst[kind][key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[kind]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = RANGE[kind]
			mmi.visibility_range_end_margin = 15.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if kind not in SHADOWS:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)

static func _label(root: Node3D, pos: Vector3, facing: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.0045
	l.outline_size = 0
	l.modulate = Color(0.95, 0.97, 0.95)
	l.double_sided = false
	l.visibility_range_end = 90.0
	l.transform = Transform3D(Basis.looking_at(-facing, Vector3.UP), pos)
	root.add_child(l)

## Pavement depth (kerb to the nearest building face) per block side, so things
## meant to stand by the shopfronts don't end up inside a building.
static func _setbacks(world: World) -> Dictionary:
	var hw: float = world.d.streetHw
	var streets: Array = world.streets
	var out := {}
	for a in streets.size() - 1:
		for b in streets.size() - 1:
			var x0: float = streets[a] + hw
			var x1: float = streets[a + 1] - hw
			var z0: float = streets[b] + hw
			var z1: float = streets[b + 1] - hw
			var dmin := [50.0, 50.0, 50.0, 50.0]
			for bd in world.d.buildings:
				var r: Array = bd.b
				if r[0] < x0 - 1 or r[2] > x1 + 1 or r[1] < z0 - 1 or r[3] > z1 + 1:
					continue
				dmin[0] = minf(dmin[0], float(r[1]) - z0)
				dmin[1] = minf(dmin[1], z1 - float(r[3]))
				dmin[2] = minf(dmin[2], x1 - float(r[2]))
				dmin[3] = minf(dmin[3], float(r[0]) - x0)
			for si in 4:
				out["%d,%d,%d" % [int(x0), int(z0), si]] = dmin[si]
	return out
