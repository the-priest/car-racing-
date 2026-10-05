class_name Police
extends Node3D
## Patrols, pursuits with heat levels, evasion and busts. Cops push and box you
## in but can never physically stop the car; you're only busted if you stop.

signal pursuit_started(reason: String)
signal pursuit_ended(escaped: bool, bounty: int)

var game: Node
var world: World
var cops: Array = [] # {car, mode, route, ri, repath, stuck, patrol_node, last_node}
var heat := 0
var pursuit := false
var pursuit_time := 0.0
var cooldown := 0.0
var bust := 0.0
var patrol_timer := 8.0
var reinforce := 0.0
var enabled := true
var min_heat := 0 # contracts can force a minimum heat level
var night := 0.0

func setup(g: Node, w: World) -> void:
	game = g
	world = w

func _make_cop(t: Transform3D, mode: String) -> Dictionary:
	var car := Car.new()
	add_child(car)
	car.setup(Data.stats_for("vanta", {}).merged(Data.POLICE, true), Color.BLACK, true, false)
	car.reset_to(t)
	car.set_police_active(mode == "chase")
	var c := {"car": car, "mode": mode, "route": PackedInt32Array(), "ri": 0, "repath": 0.0, "stuck": 0.0, "patrol_node": -1, "last_node": -1}
	cops.append(c)
	game.on_car_spawned(car)
	return c

func _remove(c: Dictionary) -> void:
	game.on_car_removed(c.car)
	c.car.queue_free()
	cops.erase(c)

func clear() -> void:
	for c in cops.duplicate():
		_remove(c)
	pursuit = false
	heat = 0
	cooldown = 0.0
	bust = 0.0

func spawn_near(min_d: float, max_d: float, mode: String) -> void:
	var p: Vector3 = game.player.global_position
	for _t in 40:
		var id := randi() % world.node_pos.size()
		var np := world.node_pos[id]
		var d := np.distance_to(Vector2(p.x, p.z))
		if d < min_d or d > max_d or world.adj[id].is_empty():
			continue
		var nb := world.node_pos[world.adj[id][0]]
		var y := 0.1 if world.in_city(np.x, np.y) else world.ground(np.x, np.y) + 0.6
		var dir := Vector3(nb.x - np.x, 0, nb.y - np.y).normalized()
		var c := _make_cop(Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(np.x, y + 0.5, np.y)), mode)
		if mode == "chase":
			c.car.linear_velocity = dir * 18.0
		return

func start_pursuit(reason: String, at_heat := 1) -> void:
	heat = maxi(heat, at_heat)
	if pursuit:
		return
	pursuit = true
	pursuit_time = 0.0
	cooldown = 0.0
	for c in cops:
		c.mode = "chase"
		c.car.set_police_active(true)
	pursuit_started.emit(reason)

func end_pursuit(escaped: bool) -> void:
	var bounty := 0
	if escaped:
		bounty = int(1500 * heat + pursuit_time * 40.0)
	pursuit = false
	heat = 0
	min_heat = 0
	for c in cops.duplicate():
		_remove(c)
	pursuit_ended.emit(escaped, bounty)

func _drive_cop(c: Dictionary, dt: float) -> void:
	var car: Car = c.car
	var p: Car = game.player
	var pos := car.global_position
	var dp := pos.distance_to(p.global_position)
	var target: Vector3
	var max_speed := 60.0
	if c.mode == "chase":
		if dp < 90.0:
			var lead := clampf(dp / 40.0, 0.0, 1.2)
			target = p.global_position + p.linear_velocity * lead
			max_speed = maxf(p.speed + 14.0, 25.0)
		else:
			c.repath -= dt
			if c.repath <= 0.0 or c.route.is_empty():
				var a := world.nearest_node(Vector2(pos.x, pos.z))
				var b := world.nearest_node(Vector2(p.global_position.x, p.global_position.z))
				c.route = world.route(a, b)
				c.ri = 0
				c.repath = 1.5
			while c.ri < c.route.size() - 1:
				var np := world.node_pos[c.route[c.ri]]
				if np.distance_to(Vector2(pos.x, pos.z)) < 14.0 + car.speed * 0.3:
					c.ri += 1
				else:
					break
			var n2 := world.node_pos[c.route[mini(c.ri, c.route.size() - 1)]]
			target = Vector3(n2.x, pos.y, n2.y)
			max_speed = 75.0
	else:
		if c.patrol_node < 0:
			c.patrol_node = world.nearest_node(Vector2(pos.x, pos.z))
			c.last_node = c.patrol_node
		var n3 := world.node_pos[c.patrol_node]
		if n3.distance_to(Vector2(pos.x, pos.z)) < 12.0:
			var opts: Array = []
			for k in world.adj[c.patrol_node]:
				if k != c.last_node:
					opts.append(k)
			c.last_node = c.patrol_node
			c.patrol_node = opts[randi() % opts.size()] if not opts.is_empty() else world.adj[c.patrol_node][0]
			n3 = world.node_pos[c.patrol_node]
		var ln := world.node_pos[c.last_node]
		var dirv := (n3 - ln).normalized()
		target = Vector3(n3.x - dirv.y * 4.5, pos.y, n3.y + dirv.x * 4.5)
		max_speed = 14.0 if world.node_type_name(c.patrol_node) == "city" else 24.0
	var local := car.global_transform.basis.inverse() * (target - pos)
	var ang := atan2(local.x, -local.z)
	var turn_limit := 14.0 if absf(ang) > 0.6 else (30.0 if absf(ang) > 0.3 else 999.0)
	var vt := minf(max_speed, turn_limit)
	car.input.steer = clampf(ang * 2.2, -1.0, 1.0)
	car.input.throttle = 1.0 if car.speed < vt else 0.0
	car.input.brake = clampf((car.speed - vt) / 8.0, 0.0, 1.0) if car.speed > vt + 2.0 else 0.0
	car.input.nitro = c.mode == "chase" and dp > 60.0 and absf(ang) < 0.15
	car.power_mul = 1.0 + heat * 0.05 + (0.15 if dp > 200.0 else 0.0)
	if car.speed < 1.5 and car.input.throttle > 0.0:
		c.stuck += dt
	else:
		c.stuck = 0.0
	if c.stuck > 2.5:
		c.stuck = 0.0
		car.reset_to(world.respawn_at(pos))

func update(dt: float) -> void:
	var p: Car = game.player
	if not enabled:
		if not cops.is_empty():
			clear()
		return
	for c in cops:
		_drive_cop(c, dt)
	if not pursuit:
		patrol_timer -= dt
		if patrol_timer <= 0.0 and cops.size() < 3:
			patrol_timer = 12.0
			spawn_near(220.0, 480.0, "patrol")
		for c in cops.duplicate():
			var d: float = c.car.global_position.distance_to(p.global_position)
			if d > 750.0:
				_remove(c)
				continue
			if d < 75.0 and p.speed > 33.0:
				start_pursuit("SPEEDING - POLICE IN PURSUIT")
			elif d < 4.5:
				start_pursuit("YOU HIT A COP")
		if min_heat > 0:
			start_pursuit("COPS ARE ON YOU", min_heat)
		return
	# Pursuit
	pursuit_time += dt
	heat = clampi(maxi(min_heat, 1 + int(pursuit_time / 35.0)), 1, 5)
	var want := mini(1 + heat, 7)
	# No reinforcements once you've broken line of contact (cooldown running).
	if cops.size() < want and cooldown <= 0.0:
		reinforce -= dt
		if reinforce <= 0.0:
			reinforce = 5.0
			spawn_near(200.0, 380.0, "chase")
	var nearest := INF
	for c in cops.duplicate():
		var d2: float = c.car.global_position.distance_to(p.global_position)
		if d2 > 900.0:
			_remove(c)
			continue
		nearest = minf(nearest, d2)
	if nearest > 260.0:
		cooldown += dt
		if cooldown > 10.0:
			end_pursuit(true)
	else:
		cooldown = maxf(0.0, cooldown - dt * 2.0)
	if nearest < 14.0 and p.speed < 2.5:
		bust += dt
		if bust > 4.0:
			end_pursuit(false)
	else:
		bust = maxf(0.0, bust - dt * 2.0)

func cars() -> Array:
	return cops.map(func(c): return c.car)
