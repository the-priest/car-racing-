class_name Police
extends Node3D
## Patrols and pursuits with 5 heat levels: rammers, roadblocks, elite
## interceptors, an air unit with a searchlight and radio chatter. Cops push and
## box you in but never physically stop the car; you're only busted if you stop.

signal pursuit_started(reason: String)
signal pursuit_ended(escaped: bool, bounty: int)
signal radio(text: String)
signal cop_down(bonus: int)

const TAKEDOWN_BONUS := 750
const KANE_BONUS := 6000

var game: Node
var world: World
var cops: Array = [] # {car, mode, route, ri, repath, stuck, patrol_node, last_node, down, side, block_t, elite}
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
var takedowns := 0
var bonus := 0 # extra bounty (Kane)
var roadblock_timer := 25.0
var heli: Node3D
var heli_light: SpotLight3D
var heli_rotors: Array[Node3D] = []
var heli_vel := Vector3.ZERO
var heli_sees := false
var heli_lost_t := 0.0
var last_heat := 0
var radio_cool := 0.0
var sight_timer := 0.0
var heli_fuel := 0.0
var heli_away := 0.0
var engaged := false # a cop (or Air One) has made contact this pursuit

func setup(g: Node, w: World) -> void:
	game = g
	world = w

# ---------------------------------------------------------------- helpers
func area_name(p: Vector3) -> String:
	if world.in_city(p.x, p.z):
		return "downtown"
	var t := world.node_type_name(world.nearest_node(Vector2(p.x, p.z)))
	match t:
		"hwy":
			return "the ring highway"
		"pass":
			return "Summit Pass"
		"country":
			return "the valley road"
		"runway":
			return "the airfield"
		"link":
			return "the expressway"
	return "the outskirts"

func heading_name(v: Vector3) -> String:
	if v.length() < 3.0:
		return "stationary"
	var a := fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)
	return ["northbound", "eastbound", "southbound", "westbound"][int(round(a / 90.0)) % 4]

func say(text: String, force := false) -> void:
	if radio_cool > 0.0 and not force:
		return
	radio_cool = 4.0
	radio.emit(text)

func bounty() -> int:
	return int(1500 * heat + pursuit_time * 40.0 + takedowns * TAKEDOWN_BONUS + bonus)

## A road node ahead of the player's travel direction, facing back toward them.
func _ahead_spot(min_d: float, max_d: float) -> Transform3D:
	var pc: Car = game.player
	var p2 := Vector2(pc.global_position.x, pc.global_position.z)
	var vdir := Vector2(pc.linear_velocity.x, pc.linear_velocity.z).normalized()
	var best := -1
	var bs := -INF
	for _t in 120:
		var id := randi() % world.node_pos.size()
		var np := world.node_pos[id]
		var d := np.distance_to(p2)
		if d < min_d or d > max_d or world.adj[id].is_empty():
			continue
		var sc := (np - p2).normalized().dot(vdir)
		if sc > bs:
			bs = sc
			best = id
	if best < 0:
		return Transform3D()
	var np2 := world.node_pos[best]
	var dir := Vector3(p2.x - np2.x, 0, p2.y - np2.y).normalized()
	var y := 0.1 if world.in_city(np2.x, np2.y) else world.ground(np2.x, np2.y) + 0.6
	return Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(np2.x, y + 0.5, np2.y))

## Lt. Kane's personal interceptor: faster, named, needs three hard rams.
func spawn_kane() -> void:
	for c in cops:
		if c.get("kane", false):
			return
	var before := cops.size()
	spawn_near(160.0, 320.0, "chase")
	if cops.size() == before:
		return
	var c: Dictionary = cops[cops.size() - 1]
	c.kane = true
	c.elite = true
	c.hp = 3
	var car: Car = c.car
	car.stats.accel = float(car.stats.accel) * 1.15
	car.stats.top = float(car.stats.top) * 1.1
	car._setup_engine()
	car.set_paint(Color(0.92, 0.92, 0.95))
	var tag := Label3D.new()
	tag.text = "LT. KANE"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0022
	tag.font_size = 22
	tag.outline_size = 8
	tag.modulate = Color(0.45, 0.7, 1.0)
	tag.position = Vector3(0, 2.4, 0)
	car.add_child(tag)
	c.tag = tag
	say("Kane: I'm taking this one personally. Nobody touches the driver but me.", true)

func _make_cop(t: Transform3D, mode: String, elite := false) -> Dictionary:
	var car := Car.new()
	add_child(car)
	var st := Data.stats_for("vanta", {}).merged(Data.POLICE, true)
	if elite:
		st.accel = float(st.accel) * 1.3
		st.top = float(st.top) * 1.22
		st.grip = float(st.grip) * 1.1
		st.cyl = 10
	car.setup(st, Color(0.9, 0.9, 0.92) if elite else Color.BLACK, true, false)
	car.reset_to(t)
	car.set_police_active(mode != "patrol")
	var c := {"car": car, "mode": mode, "route": PackedInt32Array(), "ri": 0, "repath": 0.0, "stuck": 0.0,
		"patrol_node": -1, "last_node": -1, "down": 0.0, "side": 1.0 if randf() < 0.5 else -1.0, "block_t": 0.0, "elite": elite, "contact": false}
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
	takedowns = 0
	_remove_heli()

func spawn_near(min_d: float, max_d: float, mode: String) -> void:
	var pc: Car = game.player
	var p: Vector3 = pc.global_position
	var p2 := Vector2(p.x, p.z)
	var vdir := Vector2(pc.linear_velocity.x, pc.linear_velocity.z)
	var fast := vdir.length() > 15.0
	vdir = vdir.normalized()
	# Chasers prefer roads ahead of you (head-on / cut-off), falling back to anywhere.
	var cands: Array = []
	for _t in 160:
		var id := randi() % world.node_pos.size()
		var np := world.node_pos[id]
		var d := np.distance_to(p2)
		if d < min_d or d > max_d * 1.3 or world.adj[id].is_empty():
			continue
		var score := randf()
		if mode == "chase" and fast:
			score += (np - p2).normalized().dot(vdir) * 2.0
		cands.append([score, id])
		if cands.size() >= 12:
			break
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a[0] > b[0])
	for pick in cands.slice(0, 1):
		var id: int = pick[1]
		var np := world.node_pos[id]
		# Face toward the player along the road.
		var nb := world.node_pos[world.adj[id][0]]
		var bestd := INF
		for k in world.adj[id]:
			var dd := world.node_pos[k].distance_to(p2)
			if dd < bestd:
				bestd = dd
				nb = world.node_pos[k]
		var y := 0.1 if world.in_city(np.x, np.y) else world.ground(np.x, np.y) + 0.6
		var dir := Vector3(nb.x - np.x, 0, nb.y - np.y).normalized()
		var elite := mode == "chase" and heat >= 4 and randf() < 0.6
		var c := _make_cop(Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(np.x, y + 0.5, np.y)), mode, elite)
		if mode == "chase":
			c.car.linear_velocity = dir * 22.0
			if elite and radio_cool <= 0.0:
				say("Dispatch: Interceptor unit joining the pursuit.")
		return

func start_pursuit(reason: String, at_heat := 1) -> void:
	heat = maxi(heat, at_heat)
	if pursuit:
		return
	pursuit = true
	pursuit_time = 0.0
	cooldown = 0.0
	bust = 0.0
	takedowns = 0
	bonus = 0
	engaged = false
	reinforce = 0.0
	last_heat = heat
	roadblock_timer = 20.0
	for c in cops:
		c.mode = "chase"
		c.car.set_police_active(true)
	pursuit_started.emit(reason)
	var p: Car = game.player
	say("Dispatch: All units, suspect vehicle %s on %s. Pursuit is a go." % [heading_name(p.linear_velocity), area_name(p.global_position)], true)

func end_pursuit(escaped: bool) -> void:
	var b := 0
	if escaped:
		b = bounty()
		say("Dispatch: All units, we've lost the suspect. Resume patrol.", true)
	else:
		say("Dispatch: Suspect in custody. Good work.", true)
	pursuit = false
	heat = 0
	min_heat = 0
	takedowns = 0
	bust = 0.0
	cooldown = 0.0
	for c in cops.duplicate():
		_remove(c)
	_remove_heli()
	pursuit_ended.emit(escaped, b)

# ---------------------------------------------------------------- driving
func _drive_cop(c: Dictionary, dt: float) -> void:
	var car: Car = c.car
	var p: Car = game.player
	var pos := car.global_position
	if c.down > 0.0:
		# Taken out: spin to a stop, lights off, then out of the chase.
		c.down -= dt
		car.input.throttle = 0.0
		car.input.brake = 1.0
		car.input.handbrake = 1.0
		car.input.nitro = false
		return
	if c.mode == "block":
		car.input.throttle = 0.0
		car.input.brake = 1.0
		car.input.handbrake = 1.0
		c.block_t += dt
		var behind := (pos - p.global_position).dot(-p.global_transform.basis.z) < -30.0
		if c.block_t > 45.0 or (behind and c.block_t > 2.0):
			c.mode = "chase"
		return
	var dp := pos.distance_to(p.global_position)
	var target: Vector3
	var max_speed := 60.0
	if c.mode == "chase":
		if dp < 90.0:
			var lead := clampf(dp / 40.0, 0.0, 1.2)
			target = p.global_position + p.linear_velocity * lead
			max_speed = maxf(p.speed + (18.0 if c.elite else 14.0), 25.0)
			if dp < 28.0:
				# Ram / PIT: aim for the player's rear quarter.
				var pf := -p.global_transform.basis.z
				var pr := p.global_transform.basis.x
				target = p.global_position - pf * 1.6 + pr * float(c.side) * 1.1 + p.linear_velocity * 0.25
				max_speed = p.speed + (9.0 if c.elite else 6.0)
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
			var ri2 := mini(c.ri, c.route.size() - 1)
			var n2 := world.node_pos[c.route[ri2]]
			target = Vector3(n2.x, pos.y, n2.y)
			max_speed = 85.0 if c.elite else 75.0
			# Brake for the turn at the next junction.
			if ri2 > 0 and ri2 < c.route.size() - 1:
				var na := world.node_pos[c.route[ri2 - 1]]
				var nc := world.node_pos[c.route[ri2 + 1]]
				var turn := absf((n2 - na).angle_to(nc - n2))
				var dn := Vector2(pos.x, pos.z).distance_to(n2)
				var v_turn := lerpf(max_speed, 16.0, smoothstep(0.2, 1.3, turn))
				max_speed = minf(max_speed, sqrt(v_turn * v_turn + 2.0 * 9.0 * maxf(dn - 8.0, 0.0)))
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
	if c.mode == "chase" and dp < 28.0:
		turn_limit = 999.0
	var vt := minf(max_speed, turn_limit)
	car.input.steer = clampf(ang * 2.2, -1.0, 1.0)
	car.input.throttle = 1.0 if car.speed < vt else 0.0
	car.input.brake = clampf((car.speed - vt) / 8.0, 0.0, 1.0) if car.speed > vt + 2.0 else 0.0
	car.input.handbrake = 0.0
	car.input.nitro = c.mode == "chase" and dp > 50.0 and absf(ang) < 0.15
	car.power_mul = 1.0 + heat * 0.05 + (0.15 if dp > 200.0 else 0.0) + (0.1 if c.elite else 0.0)
	if car.speed < 1.5 and car.input.throttle > 0.0:
		c.stuck += dt
	else:
		c.stuck = 0.0
	if c.stuck > 2.5:
		c.stuck = 0.0
		car.reset_to(world.respawn_at(pos))

## Ramming a cop hard enough (you being the faster car) takes it out of the chase.
func _check_takedown(c: Dictionary) -> void:
	var car: Car = c.car
	var p: Car = game.player
	var dv := car.global_position - p.global_position
	dv.y = 0.0
	var d := dv.length()
	var touching := d < 3.8
	if touching and not c.contact and c.down <= 0.0 and pursuit:
		var n := dv / maxf(d, 0.01)
		var rel := (p.linear_velocity - car.linear_velocity).dot(n)
		if rel > 11.0 and p.speed > car.speed and c.get("hp", 1) > 1:
			c.hp -= 1
			car.apply_central_impulse(n * car.mass * minf(rel, 25.0) * 0.25)
			say(["Kane: Is that all you've got?", "Kane: You'll have to hit harder than that."][c.hp % 2], true)
			game.hud.message("KANE HIT  %d / 3" % (3 - c.hp), 1.5)
			c.contact = touching
			return
		if rel > 11.0 and p.speed > car.speed:
			c.down = 7.0
			takedowns += 1
			car.set_police_active(false)
			car.apply_central_impulse(n * car.mass * minf(rel, 25.0) * 0.35 + Vector3.UP * car.mass * 2.0)
			car.apply_torque_impulse(Vector3.UP * (1.0 if randf() < 0.5 else -1.0) * car.mass * 6.0)
			if c.get("kane", false):
				bonus += KANE_BONUS
				if c.has("tag"):
					c.tag.text = "LT. KANE - DOWN"
				cop_down.emit(KANE_BONUS)
				say("Kane: I'm hit! I'm out! ...Don't you DARE lose them!", true)
				game.hud.big("KANE TAKEN DOWN", 2.0)
			else:
				cop_down.emit(TAKEDOWN_BONUS)
				say(["Dispatch: Unit down! Unit down!", "Dispatch: We've lost a car. Suspect is ramming units.", "Kane: Stop letting that car walk through you!"][randi() % 3], true)
			heat = mini(5, heat + (1 if takedowns % 3 == 0 else 0))
	c.contact = touching

# ---------------------------------------------------------------- roadblocks
func _try_roadblock() -> void:
	var p: Car = game.player
	if p.speed < 18.0:
		return
	var ahead := p.global_position + p.linear_velocity.normalized() * clampf(p.speed * 7.0, 220.0, 420.0)
	var id := world.nearest_node(Vector2(ahead.x, ahead.z))
	if id < 0 or world.adj[id].is_empty():
		return
	var np := world.node_pos[id]
	if np.distance_to(Vector2(p.global_position.x, p.global_position.z)) < 160.0:
		return
	# Road direction: the neighbour most aligned with the player's travel.
	var vel2 := Vector2(p.linear_velocity.x, p.linear_velocity.z).normalized()
	var dir := Vector2.ZERO
	var best := -INF
	for k in world.adj[id]:
		var dd: Vector2 = (world.node_pos[k] - np).normalized()
		var al := absf(dd.dot(vel2))
		if al > best:
			best = al
			dir = dd
	if dir == Vector2.ZERO:
		return
	var right := Vector2(-dir.y, dir.x)
	var n := 3 if heat < 5 else 4
	for i in n:
		var off := (float(i) - (n - 1) * 0.5) * 4.6
		var q := np + right * off
		var y := 0.1 if world.in_city(q.x, q.y) else world.ground(q.x, q.y) + 0.6
		# Parked across the road, nose angled.
		var face := Vector3(right.x, 0, right.y).rotated(Vector3.UP, 0.35 * (1.0 if i % 2 == 0 else -1.0))
		var c := _make_cop(Transform3D(Basis.looking_at(face, Vector3.UP), Vector3(q.x, y + 0.4, q.y)), "block")
		c.block_t = 0.0
	say("Dispatch: Roadblock in position on %s. Box them in!" % area_name(Vector3(np.x, 0, np.y)), true)
	game.hud.message("ROADBLOCK AHEAD", 2.0)

# ---------------------------------------------------------------- air unit
func _make_heli() -> void:
	heli = Node3D.new()
	add_child(heli)
	var body_m := StandardMaterial3D.new()
	body_m.albedo_color = Color(0.08, 0.09, 0.12)
	body_m.metallic = 0.4
	body_m.roughness = 0.35
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.9, 0.9, 0.92)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.2, 0.3)
	glass.metallic = 0.8
	glass.roughness = 0.05
	var parts := [
		[CapsuleMesh.new(), Vector3(0, 0, 0), Vector3(1.0, 1.0, 1.0), body_m, Vector3(90, 0, 0)],
		[BoxMesh.new(), Vector3(0, 0.35, 4.2), Vector3(0.35, 0.35, 5.0), body_m, Vector3.ZERO],
		[BoxMesh.new(), Vector3(0, 1.0, 6.4), Vector3(0.12, 1.4, 0.8), stripe, Vector3.ZERO],
		[SphereMesh.new(), Vector3(0, 0.15, -1.3), Vector3(1.3, 1.1, 1.3), glass, Vector3.ZERO],
		[BoxMesh.new(), Vector3(0.9, -1.25, 0), Vector3(0.1, 0.1, 3.4), stripe, Vector3.ZERO],
		[BoxMesh.new(), Vector3(0, -0.2, 0.2), Vector3(2.34, 0.32, 2.6), stripe, Vector3.ZERO],
		[BoxMesh.new(), Vector3(-0.9, -1.25, 0), Vector3(0.1, 0.1, 3.4), stripe, Vector3.ZERO],
	]
	var cap := parts[0][0] as CapsuleMesh
	cap.radius = 1.15
	cap.height = 4.4
	var sph := parts[3][0] as SphereMesh
	sph.radius = 0.9
	sph.height = 1.6
	for pt in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = pt[0]
		if pt[0] is BoxMesh:
			(pt[0] as BoxMesh).size = pt[2]
		else:
			mi.scale = pt[2]
		mi.material_override = pt[3]
		mi.position = pt[1]
		mi.rotation_degrees = pt[4]
		heli.add_child(mi)
	for spec in [[Vector3(0, 1.45, 0), 11.0, Vector3.UP], [Vector3(0.25, 1.0, 6.4), 2.6, Vector3.RIGHT]]:
		var hub := Node3D.new()
		hub.position = spec[0]
		heli.add_child(hub)
		for k in 2:
			var blade := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(float(spec[1]), 0.04, 0.3) if spec[2] == Vector3.UP else Vector3(0.04, float(spec[1]), 0.2)
			blade.mesh = bm
			blade.material_override = body_m
			blade.rotation = (spec[2] as Vector3) * (PI * 0.5 * k)
			hub.add_child(blade)
		hub.set_meta("axis", spec[2])
		heli_rotors.append(hub)
	heli_light = SpotLight3D.new()
	heli_light.light_color = Color(0.85, 0.9, 1.0)
	heli_light.light_energy = 40.0
	heli_light.spot_range = 160.0
	heli_light.spot_angle = 9.0
	heli_light.spot_attenuation = 0.4
	heli_light.shadow_enabled = false
	heli_light.position = Vector3(0, -1.3, -1.0)
	heli.add_child(heli_light)
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(1, 0.1, 0.1)
	beacon.light_energy = 2.0
	beacon.omni_range = 6.0
	beacon.position = Vector3(0, -1.3, 1.5)
	heli.add_child(beacon)
	var pc: Car = game.player
	var p: Vector3 = pc.global_position
	var from := p - pc.linear_velocity.normalized() * 300.0
	heli.global_position = Vector3(from.x, p.y + 80.0, from.z)
	heli_vel = Vector3.ZERO
	heli_lost_t = 0.0
	say("Air One: Air unit on station. I have eyes on the suspect.", true)

func _remove_heli() -> void:
	if heli:
		heli.queue_free()
		heli = null
		heli_rotors.clear()
	heli_sees = false

func _update_heli(dt: float) -> void:
	var p: Car = game.player
	var pp := p.global_position
	var goal := pp + p.linear_velocity * 1.2 + Vector3(0, 55.0, 0)
	if not world.in_city(pp.x, pp.z):
		goal.y = maxf(goal.y, world.ground(goal.x, goal.z) + 55.0)
	var to := goal - heli.global_position
	var desired := to.limit_length(62.0) if to.length() > 1.0 else Vector3.ZERO
	heli_vel = heli_vel.move_toward(desired, dt * 18.0)
	heli.global_position += heli_vel * dt
	# Nose into travel, bank with velocity.
	var flat := Vector3(heli_vel.x, 0, heli_vel.z)
	if flat.length() > 2.0:
		var yaw := atan2(-flat.x, -flat.z)
		heli.rotation.y = lerp_angle(heli.rotation.y, yaw, 1.0 - exp(-2.0 * dt))
		heli.rotation.x = lerpf(heli.rotation.x, -clampf(flat.length() / 62.0, 0.0, 1.0) * 0.25, 1.0 - exp(-2.0 * dt))
	for r in heli_rotors:
		r.rotate(r.get_meta("axis"), dt * 38.0)
	heli_light.look_at(pp, Vector3.UP)
	# Line of sight: buildings hide you from the air unit.
	sight_timer -= dt
	if sight_timer <= 0.0:
		sight_timer = 0.25
		var hd := Vector2(heli.global_position.x - pp.x, heli.global_position.z - pp.z).length()
		var seen := hd < 170.0
		if seen:
			var q := PhysicsRayQueryParameters3D.create(heli.global_position, pp + Vector3.UP, 4)
			seen = world.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		if heli_sees and not seen:
			say("Air One: Lost visual! Suspect is under cover.")
		elif not heli_sees and seen and heli_lost_t > 3.0:
			say("Air One: Eyes back on the suspect.")
		heli_sees = seen
	heli_lost_t = 0.0 if heli_sees else heli_lost_t + dt
	heli_light.visible = heli_sees or heli_lost_t < 1.0

# ---------------------------------------------------------------- update
func update(dt: float) -> void:
	var p: Car = game.player
	radio_cool -= dt
	if not enabled:
		if not cops.is_empty():
			clear()
		return
	for c in cops:
		_drive_cop(c, dt)
		_check_takedown(c)
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
	heat = clampi(maxi(heat, maxi(min_heat, 1 + int(pursuit_time / 35.0))), 1, 5)
	if heat > last_heat:
		last_heat = heat
		game.hud.big("HEAT %d" % heat, 1.4)
		match heat:
			2: say("Dispatch: Suspect is not stopping. Additional units, respond.", true)
			3: say("Kane: This is Kane. Set up roadblocks, I want this car boxed.", true)
			4: say("Kane: Send the interceptors and put Air One in the sky.", true)
			5: say("Kane: Every unit in Solano Bay. I don't care what it costs.", true)
	var want := mini(1 + heat, 7)
	# Taken-out cops leave the chase once they've stopped spinning.
	for c in cops.duplicate():
		if c.down > 0.0 and c.down < 0.5:
			_remove(c)
	var chasing := 0
	for c in cops:
		if c.mode == "chase" and c.down <= 0.0:
			chasing += 1
	# No reinforcements once you've broken line of contact (cooldown running).
	if chasing < want and cooldown <= 0.0:
		reinforce -= dt
		if reinforce <= 0.0:
			reinforce = 5.0 if heat < 4 else 3.5
			if not engaged:
				reinforce = 1.5
			spawn_near(140.0 if not engaged else 200.0, 320.0 if not engaged else 380.0, "chase")
	if heat >= 3 and cooldown <= 0.0:
		roadblock_timer -= dt
		if roadblock_timer <= 0.0:
			roadblock_timer = randf_range(35.0, 55.0) - heat * 4.0
			_try_roadblock()
	heli_away -= dt
	if heat >= 4 and heli == null and heli_away <= 0.0:
		_make_heli()
		heli_fuel = randf_range(80.0, 110.0)
	if heli:
		heli_fuel -= dt
		if heli_fuel <= 0.0:
			say("Air One: Bingo fuel, returning to base. You're on your own down there.", true)
			_remove_heli()
			heli_away = 60.0
	if heli:
		_update_heli(dt)
	var nearest := INF
	for c in cops.duplicate():
		var d2: float = c.car.global_position.distance_to(p.global_position)
		# Units left far behind get recycled ahead of the player.
		c.far_t = c.get("far_t", 0.0) + dt if (d2 > 600.0 and c.mode == "chase") else 0.0
		if c.far_t > 15.0:
			c.far_t = 0.0
			if c.get("kane", false):
				var t := _ahead_spot(260.0, 420.0)
				if t != Transform3D():
					c.car.reset_to(t)
					c.car.linear_velocity = -t.basis.z * 20.0
					say("Kane: You think you can outrun me? I know these roads.", true)
				continue
			_remove(c)
			continue
		if d2 > 900.0 and not c.get("kane", false):
			_remove(c)
			continue
		if c.down <= 0.0 and c.mode != "block":
			nearest = minf(nearest, d2)
	var spotted := nearest < 260.0 or heli_sees
	if spotted:
		engaged = true
	# Units are still converging: you can't "evade" cops that haven't arrived yet.
	if not engaged and pursuit_time < 30.0:
		spotted = true
	if not spotted:
		if cooldown == 0.0:
			say("Dispatch: Lost visual on the suspect. All units, search the area.")
		cooldown += dt
		if cooldown > 10.0:
			end_pursuit(true)
			return
	else:
		cooldown = maxf(0.0, cooldown - dt * 2.0)
	if nearest < 14.0 and p.speed < 2.5:
		if bust == 0.0:
			say("Dispatch: Suspect is boxed in! Move in, move in!")
		bust += dt
		if bust > 4.0:
			end_pursuit(false)
	else:
		bust = maxf(0.0, bust - dt * 2.0)

func cars() -> Array:
	return cops.map(func(c): return c.car)

func active_count() -> int:
	var n := 0
	for c in cops:
		if c.down <= 0.0:
			n += 1
	return n
