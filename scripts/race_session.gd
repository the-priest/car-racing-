class_name RaceSession
extends Node3D
## A single race: grid, countdown, checkpoints, AI rivals, standings.

const RIVAL_NAMES := ["Nyx", "Torque", "Vega", "Ash", "Blaze", "Kai", "Diesel"]
const RIVAL_COLORS := [Color(0.9, 0.9, 0.88), Color(0.9, 0.75, 0.05), Color(0.1, 0.5, 0.15), Color(0.3, 0.08, 0.5), Color(0.05, 0.12, 0.55), Color(0.85, 0.12, 0.02)]

var game: Node
var world: World
var id := ""
var def: Dictionary
var path: RacePath
var laps := 1
var cps: Array[int] = []
var next_cp := 0
var lap := 0
var p_idx := 0
var progress := 0.0
var countdown := 4.0
var race_time := 0.0
var rivals: Array = [] # {car, ai, name, finished, time}
var place := 1
var done := false
var result := {}
var need_place := 1
var boss: Dictionary = {} # named story rival (takes grid slot 0)
var wrong := 0.0
var order: Array = [] # [{me, name, boss}] in race order
var back_wraps := 0
var gates: Array[Node3D] = []
var _last_count := 4

func start(g: Node, w: World, race_id: String, d: Dictionary) -> void:
	game = g
	world = w
	id = race_id
	def = d
	laps = int(d.laps)
	var roads: Array = d.roads
	var ids: Array[int] = []
	for p in d.pts:
		ids.append(world.nearest_node(Vector2(p[0], p[1]), roads))
	var legs: Array[int] = ids.duplicate()
	if d.circuit:
		legs.append(ids[0])
	var route := PackedInt32Array()
	for i in legs.size() - 1:
		var leg := world.route(legs[i], legs[i + 1], roads)
		if route.is_empty():
			route.append_array(leg)
		else:
			route.append_array(leg.slice(1))
	if d.circuit:
		route.remove_at(route.size() - 1)
	var pts := PackedVector2Array()
	for nid in route:
		pts.append(world.node_pos[nid])
	path = RacePath.new(pts, bool(d.circuit), world)
	var start_idx := 16
	var step := 55
	var i := start_idx + step
	while i < path.n - (10 if path.closed else 4):
		cps.append(i)
		i += step
	cps.append(path.n - 2 if path.closed else path.n - 4)
	for k in 2:
		var gate := _make_gate(Color(1.0, 0.7, 0.15) if k == 0 else Color(0.2, 0.85, 1.0))
		add_child(gate)
		gates.append(gate)
	# Grid: player on row 1, rivals around.
	var player: Car = game.player
	var slot := func(k: int) -> Transform3D:
		var row := k / 2
		var col := 1.0 if k % 2 == 0 else -1.0
		var pi := start_idx - row * 3
		var c := path.at(pi)
		var dd := path.dir(pi)
		var right := Vector2(-dd.y, dd.x)
		var p := c + right * col * 3.0
		var y := (0.05 if world.in_city(p.x, p.y) else world.ground(p.x, p.y) + 0.1) + 0.4
		return Transform3D(Basis.looking_at(Vector3(dd.x, 0, dd.y), Vector3.UP), Vector3(p.x, y, p.y))
	player.reset_to(slot.call(2))
	player.nitro = 1.0
	p_idx = path.nearest(Vector2(player.global_position.x, player.global_position.z), start_idx, 12, 12)
	var ps: Dictionary = player.stats
	var s := 0
	for k in 5:
		if s == 2:
			s += 1
		var car := Car.new()
		add_child(car)
		var st: Dictionary = ps.duplicate()
		var f := float(d.skill) * randf_range(0.97, 1.03) + 0.06 + float(Settings.diff(-0.07, 0.0, 0.04))
		st.accel = float(st.accel) * f
		st.top = float(st.top) * (0.98 + (f - 1.0) * 0.5)
		var is_boss := k == 0 and not boss.is_empty()
		var base: Dictionary = Data.CARS[boss.car] if is_boss else Data.CARS[Data.CAR_ORDER[randi() % Data.CAR_ORDER.size()]]
		st.cyl = base.cyl
		st.red = base.red
		st.idle = base.idle
		st.body = base.get("body", "concept")
		var skill := float(d.skill) * randf_range(0.97, 1.02) * float(Settings.diff(0.94, 1.0, 1.02))
		if is_boss:
			skill = float(d.skill) + float(boss.skill)
			st.accel = float(st.accel) * (1.0 + float(boss.skill))
		car.setup(st, boss.paint if is_boss else RIVAL_COLORS[k % RIVAL_COLORS.size()], false, false)
		car.reset_to(slot.call(s))
		s += 1
		var ai := AIDriver.new(car, path, skill, float(k % 3 - 1) * 2.2)
		ai.idx = path.nearest(Vector2(car.global_position.x, car.global_position.z), start_idx, 12, 12)
		var rname: String = boss.name if is_boss else RIVAL_NAMES[k % RIVAL_NAMES.size()]
		if is_boss:
			var tag := Label3D.new()
			tag.text = rname
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.no_depth_test = true
			tag.fixed_size = true
			tag.pixel_size = 0.0022
			tag.font_size = 30
			tag.outline_size = 10
			tag.modulate = Color(1.0, 0.4, 0.6)
			tag.position = Vector3(0, 2.6, 0)
			car.add_child(tag)
		rivals.append({"car": car, "ai": ai, "name": rname, "finished": false, "time": INF, "boss": is_boss})
		game.on_car_spawned(car)
	game.on_race_start()
	game.tip("race", "Drive through the checkpoint gates. Tuck in behind rivals for a slipstream - it cuts drag and refills nitrous.")
	game.hud.big(("VS  " + str(boss.name)) if not boss.is_empty() else str(d.name).to_upper(), 1.0)

func _make_gate(c: Color) -> Node3D:
	var root := Node3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 4.0
	for k in 3:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 9.0, 0.5) if k < 2 else Vector3(1, 0.4, 0.4)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	root.visible = false
	return root

func _place_gate(gate: Node3D, i: int) -> void:
	var c := path.at(i)
	var dd := path.dir(i)
	var right := Vector2(-dd.y, dd.x)
	var hw := 12.0
	var y := path.heights[path.idx(i)] if not path.heights.is_empty() else 0.0
	if world.in_city(c.x, c.y):
		y = 0.0
		hw = 11.0
	gate.global_transform = Transform3D(Basis.looking_at(Vector3(dd.x, 0, dd.y), Vector3.UP), Vector3(c.x, y, c.y))
	var kids := gate.get_children()
	(kids[0] as Node3D).position = Vector3(hw, 4.5, 0)
	(kids[1] as Node3D).position = Vector3(-hw, 4.5, 0)
	(kids[2] as Node3D).position = Vector3(0, 9.0, 0)
	(kids[2] as Node3D).scale = Vector3(hw * 2.0, 1, 1)
	gate.visible = true

func update(dt: float) -> void:
	var player: Car = game.player
	var all_cars: Array = [player]
	for r in rivals:
		all_cars.append(r.car)
	var frozen := countdown > 0.0
	for r in rivals:
		var ai: AIDriver = r.ai
		ai.update(dt, all_cars, frozen)
		var gap := progress - ai.progress
		r.car.power_mul = 1.0 + clampf(gap / 500.0, -0.08, 0.12)
	if countdown > 0.0:
		countdown -= dt
		var c := int(ceil(countdown))
		if c != _last_count:
			_last_count = c
			if c > 0 and c <= 3:
				game.hud.big(str(c), 0.9)
				game.audio.play_oneshot("beep")
			elif c <= 0:
				game.hud.big("GO!", 1.0)
				game.audio.play_oneshot("beep", 2.0)
		# Hold the player on the line (engine can still rev).
		player.linear_velocity = Vector3(0, player.linear_velocity.y, 0)
		return
	if done:
		return
	race_time += dt
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var prev := p_idx
	p_idx = path.nearest(pp, p_idx, 12, 60)
	if path.closed and prev < path.n * 0.15 and p_idx > path.n * 0.85:
		back_wraps += 1 # reversed over the line
	elif path.closed and prev > path.n * 0.85 and p_idx < path.n * 0.15:
		if back_wraps > 0:
			back_wraps -= 1 # crossing forward again after reversing over it
		elif next_cp >= cps.size():
			lap += 1
			next_cp = 0
			if lap == laps - 1:
				game.hud.big("FINAL LAP", 1.6)
				game.audio.play_oneshot("beep", 1.2)
			elif lap < laps:
				game.hud.message("LAP %d / %d" % [lap + 1, laps], 2.0)
		else:
			p_idx = prev
	progress = (lap - back_wraps) * path.length + path.cum[p_idx]
	if next_cp < cps.size():
		var ci: int = cps[next_cp]
		if pp.distance_to(path.at(ci)) < 24.0 or (p_idx >= ci and p_idx - ci < 40):
			next_cp += 1
			game.audio.play_oneshot("beep", 1.5)
	# Gates: next checkpoint (amber) and the one after (cyan)
	if next_cp < cps.size():
		_place_gate(gates[0], cps[next_cp])
		if next_cp + 1 < cps.size():
			_place_gate(gates[1], cps[next_cp + 1])
		else:
			gates[1].visible = false
	elif path.closed:
		_place_gate(gates[0], cps[0])
		gates[1].visible = false
	var d := path.dir(p_idx)
	var fwd := -player.global_transform.basis.z
	wrong = wrong + dt if (fwd.x * d.x + fwd.z * d.y) < -0.4 and player.speed > 6.0 else 0.0
	var finished_me := lap >= laps if path.closed else (next_cp >= cps.size() and p_idx >= path.n - 5)
	for r in rivals:
		var ai: AIDriver = r.ai
		if not r.finished and ((path.closed and ai.lap >= laps) or (not path.closed and ai.idx >= path.n - 5)):
			r.finished = true
			r.time = race_time
	var entries := [{"me": true, "p": progress + (1e7 if finished_me else 0.0), "name": "You", "boss": false}]
	for r in rivals:
		entries.append({"me": false, "p": (1e7 + 1e5 - r.time) if r.finished else (r.ai as AIDriver).progress, "name": r.name, "boss": r.get("boss", false)})
	entries.sort_custom(func(a, b): return a.p > b.p)
	order = entries
	for k in entries.size():
		if entries[k].me:
			place = k + 1
	if finished_me:
		done = true
		result = {"id": id, "place": place, "total": rivals.size() + 1, "time": race_time, "need": need_place,
			"order": order.map(func(e): return "YOU" if e.me else str(e.name))}

func cleanup() -> void:
	for r in rivals:
		game.on_car_removed(r.car)
		r.car.queue_free()
	rivals.clear()
	for g in gates:
		g.visible = false

func standings_text() -> String:
	return "%d/%d" % [place, rivals.size() + 1]
