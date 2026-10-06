class_name Traffic
extends Node3D
## Ambient traffic on the road graph. Civilians never stop the player: contact
## knocks them aside while the player keeps nearly all of their speed.

signal hit(strength: float)

const SPEED := {"city": 13.0, "link": 20.0, "hwy": 27.0, "pass": 14.0, "country": 16.0, "runway": 18.0}
const MAX_POOL := 45
const COLORS := [Color(0.85, 0.85, 0.84), Color(0.05, 0.05, 0.06), Color(0.45, 0.05, 0.05), Color(0.08, 0.16, 0.35),
	Color(0.4, 0.42, 0.45), Color(0.55, 0.48, 0.32), Color(0.12, 0.25, 0.15), Color(0.95, 0.95, 0.95)]

var world: World
var cars: Array = []
var active_count := 0
var candidates: Array[int] = []
var paints: Array[StandardMaterial3D] = []
var light_mat: StandardMaterial3D

func setup(w: World, count: int) -> void:
	world = w
	for i in w.node_pos.size():
		var t := w.node_type_name(i)
		if t != "pass" and t != "runway":
			candidates.append(i)
	for c in COLORS:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = 0.5
		m.roughness = 0.35
		m.clearcoat_enabled = true
		m.clearcoat = 0.7
		paints.append(m)
	light_mat = StandardMaterial3D.new()
	light_mat.albedo_color = Color(0.9, 0.9, 0.85)
	light_mat.emission_enabled = true
	light_mat.emission = Color(1, 0.95, 0.85)
	# Pool enough cars for Ultra + heavy density; set_count activates a subset.
	for i in maxi(count, MAX_POOL):
		# Mix of body styles: mostly modern cars, plus vans and classics.
		var style: String = ["concept", "concept", "delivery", "concept", "stallion", "concept", "delivery", "wedge"][i % 8]
		var vis: Node3D
		if style == "concept":
			vis = CarMesh.instance(paints[i % paints.size()], light_mat)
		else:
			vis = BodyGen.build(style, paints[(i * 3 + 1) % paints.size()])
			for n in vis.find_children("*", "MeshInstance3D", true, false):
				(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if String(n.name).ends_with("Rim") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(vis)
		vis.visible = false
		cars.append({"node": vis, "a": 0, "b": 0, "t": 0.0, "speed": 0.0, "yaw": 0.0, "pos": Vector3.ZERO,
			"knock": 0.0, "vel": Vector3.ZERO, "spin": 0.0, "active": false, "len": 10.0, "missed": false})
	active_count = count

func set_count(n: int) -> void:
	active_count = mini(n, cars.size())
	for i in cars.size():
		if i >= active_count:
			cars[i].active = false
			cars[i].node.visible = false

func set_night(n: float) -> void:
	light_mat.emission_energy_multiplier = 0.3 + n * 5.0

func _spawn(c: Dictionary, around: Vector3, min_d: float, max_d: float) -> void:
	for _try in 30:
		var id: int = candidates[randi() % candidates.size()]
		var p := world.node_pos[id]
		var d := p.distance_to(Vector2(around.x, around.z))
		if d < min_d or d > max_d or world.adj[id].is_empty():
			continue
		c.a = id
		c.b = world.adj[id][randi() % world.adj[id].size()]
		c.t = randf() * 0.8
		c.speed = SPEED.get(world.node_type_name(id), 14.0)
		c.knock = 0.0
		c.active = true
		_place(c, true)
		c.node.visible = true
		return
	c.active = false
	c.node.visible = false

func _place(c: Dictionary, snap: bool) -> void:
	var A := world.node_pos[c.a]
	var B := world.node_pos[c.b]
	var dv := B - A
	var L := maxf(dv.length(), 0.1)
	var u := dv / L
	var tp := world.node_type_name(c.a)
	var lane := (5.0 if tp == "city" or tp == "link" else (8.0 if tp == "hwy" else 3.0)) + float(c.get("pull", 0.0)) * 2.6
	var right := Vector2(-u.y, u.x)
	var p := A + dv * float(c.t) + right * lane
	var y := 0.0 if world.in_city(p.x, p.y) else world.ground(p.x, p.y) + 0.07
	c.pos = Vector3(p.x, y, p.y)
	var yaw := atan2(-u.x, -u.y)
	c.yaw = yaw if snap else lerp_angle(c.yaw, yaw, 0.15)
	c.len = L

func update(delta: float, player: Car, others: Array) -> void:
	var pp := player.global_position
	for i in active_count:
		var c: Dictionary = cars[i]
		if not c.active or (c.pos as Vector3).distance_to(pp) > 560.0:
			_spawn(c, pp, 180.0, 480.0)
			continue
		if c.knock > 0.0:
			c.knock -= delta
			c.pos += c.vel * delta
			c.vel *= exp(-1.4 * delta)
			c.yaw += c.spin * delta
			c.spin *= exp(-2.0 * delta)
			var gy := 0.0 if world.in_city(c.pos.x, c.pos.z) else world.ground(c.pos.x, c.pos.z) + 0.07
			c.pos.y = gy
			if c.knock <= 0.0:
				if (c.pos as Vector3).distance_to(pp) < 70.0:
					_spawn(c, pp, 180.0, 480.0)
				else:
					var id := world.nearest_node(Vector2(c.pos.x, c.pos.z), ["city", "link", "hwy", "country"])
					c.a = id
					c.b = world.adj[id][randi() % world.adj[id].size()]
					c.t = 0.0
					_place(c, true)
		else:
			var fwd := Vector3(-sin(c.yaw), 0, -cos(c.yaw))
			var target: float = SPEED.get(world.node_type_name(c.a), 14.0)
			for o in [player] + others:
				var dv: Vector3 = (o as Node3D).global_position - c.pos
				var ahead := dv.dot(fwd)
				var side := absf(dv.dot(Vector3(-fwd.z, 0, fwd.x)))
				if ahead > 0.0 and ahead < 20.0 and side < 2.6:
					target = minf(target, maxf(0.0, (ahead - 8.0) * 1.2))
			for j in active_count:
				if j == i or not cars[j].active:
					continue
				var dv2: Vector3 = cars[j].pos - c.pos
				var ah := dv2.dot(fwd)
				if ah > 0.0 and ah < 16.0 and absf(dv2.dot(Vector3(-fwd.z, 0, fwd.x))) < 2.2:
					target = minf(target, maxf(0.0, (ah - 8.0) * 1.4))
			if c.t > 0.6 and world.node_type_name(c.a) == "city":
				target = minf(target, 8.0)
			# Pull over for police cars running lights behind us.
			var pull_to := 0.0
			for o in others:
				var cop := o as Car
				if cop == null or not cop.is_police or cop.police_lights.is_empty() or not cop.police_lights[0].visible:
					continue
				var dvc: Vector3 = cop.global_position - c.pos
				var behind := -dvc.dot(fwd)
				if behind > 0.0 and behind < 70.0 and absf(dvc.dot(Vector3(-fwd.z, 0, fwd.x))) < 7.0:
					pull_to = 1.0
					target = minf(target, 5.0)
			c.pull = move_toward(float(c.get("pull", 0.0)), pull_to, delta * 0.9)
			c.speed = lerpf(c.speed, target, 1.0 - exp(-2.0 * delta))
			c.t += c.speed * delta / maxf(c.len, 1.0)
			while c.t >= 1.0:
				c.t -= 1.0
				var opts: Array = []
				for k in world.adj[c.b]:
					var tn := world.node_type_name(k)
					if k != c.a and tn != "pass" and tn != "runway":
						opts.append(k)
				var nxt: int = opts[randi() % opts.size()] if not opts.is_empty() else c.a
				c.a = c.b
				c.b = nxt
			_place(c, false)
		var node: Node3D = c.node
		node.global_transform = Transform3D(Basis(Vector3.UP, c.yaw), c.pos)

## Soft contact with a physics car: civilians are shoved, the car barely slows.
func collide(car: Car, report := true) -> void:
	var cp := car.global_position
	for i in active_count:
		var c: Dictionary = cars[i]
		if not c.active:
			continue
		var dv: Vector3 = c.pos - cp
		dv.y = 0.0
		var d := dv.length()
		if d > 3.2 or absf(c.pos.y - cp.y) > 3.0:
			continue
		var n := dv / maxf(d, 0.01)
		var own_vel: Vector3 = c.vel if c.knock > 0.0 else Vector3(-sin(c.yaw), 0, -cos(c.yaw)) * float(c.speed)
		var rel := (car.linear_velocity - own_vel).dot(n)
		if rel <= 0.0 and c.knock > 0.0:
			continue
		c.knock = 3.0
		c.near = false
		c.missed = true
		c.vel = car.linear_velocity * 0.85 + n * (4.0 + maxf(rel, 0.0) * 0.4)
		c.vel.y = 0.0
		c.spin = randf_range(-6.0, 6.0)
		c.pos = cp + n * 3.25
		car.linear_velocity *= 0.97
		if report:
			hit.emit(maxf(rel, 0.0))

## Counts fresh near misses (for nitrous rewards).
func near_misses(car: Car) -> int:
	var count := 0
	for i in active_count:
		var c: Dictionary = cars[i]
		if not c.active or c.knock > 0.0:
			continue
		var d := (c.pos as Vector3).distance_to(car.global_position)
		# A near miss only counts once you're clear of the car without hitting it.
		if d < 4.8 and d > 3.2 and car.speed > 25.0:
			if not c.missed:
				c.near = true
		elif d > 6.0:
			if c.get("near", false) and not c.missed:
				c.missed = true
				count += 1
			c.near = false
			if d > 12.0:
				c.missed = false
	return count
