class_name MissionTarget
extends Node3D
## A fleeing car for takedown missions (armoured truck, rival). It drives a road
## route to its destination; the player rams it until it's disabled.

signal was_hit(hits: int, need: int)

const DEFS := {
	"armored": {"name": "ARMORED TRUCK", "body": "van", "paint": Color(0.32, 0.34, 0.37), "mass": 2600.0,
		"accel": 7.0, "top": 46.0, "grip": 12.5, "speed": 31.0, "boost": 1.1},
	"sable": {"name": "SABLE", "body": "wedge", "paint": Color(0.22, 0.04, 0.36), "mass": 1380.0,
		"accel": 13.0, "top": 90.0, "grip": 17.0, "speed": 50.0, "boost": 1.25, "nitro": true},
}

var game: Node
var world: World
var car: Car
var def: Dictionary
var route := PackedInt32Array()
var ri := 1
var hits := 0
var need := 5
var disabled := false
var escaped := false
var hit_cool := 0.0
var contact := false
var stuck := 0.0
var tag: Label3D

func start(g: Node, w: World, kind: String, from: Vector2, to: Vector2, need_hits: int) -> void:
	game = g
	world = w
	def = DEFS[kind]
	need = need_hits
	var a := world.nearest_node(from)
	var b := world.nearest_node(to)
	route = world.route(a, b)
	if route.size() < 3:
		route = PackedInt32Array([a, b])
	car = Car.new()
	add_child(car)
	var st := Data.stats_for("vanta", {})
	for k in ["mass", "accel", "top", "grip", "body"]:
		st[k] = def[k]
	st.cyl = 8
	st.idle = 700.0
	st.red = 6200.0 if kind == "armored" else 8000.0
	car.setup(st, def.paint, false, false)
	var si := mini(2, route.size() - 2)
	var p0 := world.node_pos[route[si]]
	var p1 := world.node_pos[route[si + 1]]
	var y := 0.6 if world.in_city(p0.x, p0.y) else world.ground(p0.x, p0.y) + 0.8
	var dir := Vector3(p1.x - p0.x, 0, p1.y - p0.y).normalized()
	car.reset_to(Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(p0.x, y, p0.y)))
	car.linear_velocity = dir * 12.0
	ri = si + 1
	tag = Label3D.new()
	tag.text = def.name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0022
	tag.font_size = 22
	tag.outline_size = 8
	tag.modulate = Color(1.0, 0.82, 0.2)
	tag.position = Vector3(0, 3.4, 0)
	car.add_child(tag)
	game.on_car_spawned(car)

func pos2() -> Vector2:
	return Vector2(car.global_position.x, car.global_position.z)

func cleanup() -> void:
	if car and is_instance_valid(car):
		game.on_car_removed(car)
		car.queue_free()
	car = null

func _physics_process(dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var p: Car = game.player
	hit_cool -= dt
	# Ram detection: a fresh contact with real closing speed counts as a hit.
	var dv := car.global_position - p.global_position
	dv.y = 0.0
	var d := dv.length()
	var touching := d < 3.9
	if touching and not contact and hit_cool <= 0.0 and not disabled:
		var rel := (p.linear_velocity - car.linear_velocity).dot(dv / maxf(d, 0.01))
		if rel > 2.5:
			hits += 1
			hit_cool = 0.7
			car.apply_central_impulse((dv / maxf(d, 0.01)) * car.mass * minf(rel, 12.0) * 0.15)
			car.apply_torque_impulse(Vector3.UP * randf_range(-1.0, 1.0) * car.mass * 2.0)
			was_hit.emit(hits, need)
			if hits >= need:
				disabled = true
	contact = touching
	if disabled:
		car.input.throttle = 0.0
		car.input.brake = 1.0
		car.input.handbrake = 1.0
		car.input.steer = 0.0
		car.input.nitro = false
		tag.text = def.name + " - DISABLED"
		return
	_drive(dt, d)

func _drive(dt: float, d_player: float) -> void:
	var pos := car.global_position
	var p2 := Vector2(pos.x, pos.z)
	while ri < route.size() - 1 and world.node_pos[route[ri]].distance_to(p2) < 12.0 + car.speed * 0.3:
		ri += 1
	var last := world.node_pos[route[route.size() - 1]]
	if ri >= route.size() - 1 and p2.distance_to(last) < 25.0:
		escaped = true
	var n := world.node_pos[route[ri]]
	var target := Vector3(n.x, pos.y, n.y)
	var vmax: float = def.speed
	# Slow for sharp turns coming up.
	if ri > 0 and ri < route.size() - 1:
		var a := world.node_pos[route[ri - 1]]
		var c := world.node_pos[route[ri + 1]]
		var turn := absf((n - a).angle_to(c - n))
		var dist := p2.distance_to(n)
		if dist < car.speed * 1.8 + 20.0:
			vmax = minf(vmax, lerpf(vmax, 13.0, smoothstep(0.25, 1.3, turn)))
	var local := car.global_transform.basis.inverse() * (target - pos)
	var ang := atan2(local.x, -local.z)
	if absf(ang) > 0.5:
		vmax = minf(vmax, 14.0)
	car.input.steer = clampf(ang * 2.0, -1.0, 1.0)
	car.input.throttle = 1.0 if car.speed < vmax else 0.0
	car.input.brake = clampf((car.speed - vmax) / 8.0, 0.0, 1.0) if car.speed > vmax + 2.0 else 0.0
	car.input.handbrake = 0.0
	car.input.nitro = def.get("nitro", false) and d_player < 60.0 and absf(ang) < 0.12
	car.power_mul = float(def.boost) if d_player < 80.0 else 1.0
	if car.speed < 1.5:
		stuck += dt
	else:
		stuck = 0.0
	if stuck > 3.0:
		stuck = 0.0
		var nb := world.node_pos[route[mini(ri + 1, route.size() - 1)]]
		var y := 0.6 if world.in_city(n.x, n.y) else world.ground(n.x, n.y) + 0.8
		var dir := Vector3(nb.x - n.x, 0, nb.y - n.y).normalized()
		if dir.length() < 0.5:
			dir = Vector3.FORWARD
		car.reset_to(Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(n.x, y, n.y)))
