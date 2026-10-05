extends Node3D
## Main game: owns the world and all systems, routes input and game state.

enum State { LOADING, MENU, PLAY, PAUSED, GARAGE, RESULTS }

var state := State.LOADING
var world: World
var daynight: DayNight
var effects: Effects
var traffic: Traffic
var police: Police
var career: Career
var hud: HUD
var menus: Menus
var audio: AudioManager
var cam: CameraRig
var player: Car
var using_pad := false
var prompt_text := ""
var gps_route := PackedVector2Array()
var drift := {"chain": 0.0, "mult": 1, "time": 0.0, "idle": 0.0, "total": 0.0}
var steer_kb := 0.0
var reset_hold := 0.0
var gps_timer := 0.0
var save_timer := 0.0
var weather_timer := 120.0
var rain_target := 0.0
var air_shown := false
var lights_override := -1
var menu_t := 0.0
var _player_car_id := ""
var shots_spec := ""
var autopilot := false
var kick_strong := 0.0
var kick_weak := 0.0
var kick_time := 0.0
var haptics_on := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_spec = a.substr(8)
		if a == "--autotest":
			shots_spec = "AUTOTEST"
		if a == "--aitest":
			shots_spec = "AITEST"
		if a == "--menutest":
			shots_spec = "MENUTEST"
	audio = AudioManager.new()
	add_child(audio)
	audio.setup()
	menus = Menus.new()
	add_child(menus)
	menus.setup(self)
	menus.play_pressed.connect(_on_play)
	menus.resume_pressed.connect(_on_resume)
	menus.quit_to_menu.connect(_to_menu)
	menus.garage_closed.connect(func(): apply_player_car())
	daynight = DayNight.new()
	add_child(daynight)
	daynight.setup(self)
	cam = CameraRig.new()
	add_child(cam)
	cam.current = true
	world = World.new()
	add_child(world)
	world.progress.connect(func(m, f): menus.set_loading(m, f))
	Settings.apply_graphics(daynight.env, daynight.sun, get_viewport(), cam)
	await world.build(Settings.preset())
	cam.world = world
	daynight.set_draw_distance(cam.far)
	daynight.hour = float(Save.data.hour)
	effects = Effects.new()
	add_child(effects)
	effects.setup(Settings.preset())
	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(world, int(Settings.preset().traffic))
	traffic.hit.connect(_on_traffic_hit)
	police = Police.new()
	add_child(police)
	police.setup(self, world)
	police.pursuit_started.connect(func(reason):
		hud.big("PURSUIT", 1.5)
		hud.message(reason, 3.0))
	police.pursuit_ended.connect(_on_pursuit_ended)
	career = Career.new()
	add_child(career)
	career.setup(self, world)
	career.message.connect(func(t, s): hud.message(t, s))
	career.big.connect(func(t, s): hud.big(t, s))
	career.phone_ring.connect(func(c):
		audio.set_ringing(true)
		hud.message("%s is calling" % c, 3.0))
	career.finished.connect(_on_career_finished)
	hud = HUD.new()
	add_child(hud)
	_spawn_player()
	# Gameplay pauses with the tree; menus, HUD, audio and the game node keep running.
	for n in [world, effects, traffic, police, career, player, daynight]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	hud.setup(self)
	hud.visible = false
	on_settings_changed()
	if shots_spec == "MENUTEST":
		_to_menu()
		await _menutest()
		get_tree().quit()
		return
	if shots_spec == "AITEST":
		await _aitest()
		get_tree().quit()
		return
	if shots_spec == "AUTOTEST":
		await _autotest()
		get_tree().quit()
		return
	if shots_spec != "":
		await _run_shots(shots_spec)
		get_tree().quit()
		return
	_to_menu()

func _spawn_player() -> void:
	player = Car.new()
	player.is_player = true
	add_child(player)
	_build_player(Save.data.car)
	var p: Array = Save.data.pos
	if p.size() == 4 and absf(float(p[0])) < world.HALF - 60.0 and absf(float(p[2])) < world.HALF - 60.0:
		player.reset_to(Transform3D(Basis(Vector3.UP, float(p[3])), Vector3(p[0], float(p[1]) + 1.0, p[2])))
	else:
		_place_at_home()
	cam.target = player
	effects.attach(player)
	player.impact.connect(_on_impact)
	player.shifted.connect(func(_g): _rumble(0.45, 0.2, 0.07))
	Input.joy_connection_changed.connect(func(dev, connected):
		if connected:
			using_pad = true
			Settings.using_pad = true
			hud.message("Controller connected: %s" % Input.get_joy_name(dev), 3.0)
		else:
			hud.message("Controller disconnected", 3.0))
	using_pad = not Input.get_connected_joypads().is_empty()
	Settings.using_pad = using_pad

func _place_at_home() -> void:
	var h: Vector2 = Career.LOC.home
	player.reset_to(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(h.x, 0.6, h.y)))

func apply_player_car() -> void:
	_build_player(Save.data.car)

func preview_car(id: String) -> void:
	_build_player(id)

## (Re)creates the player car when the body changes, otherwise retunes it in place.
func _build_player(id: String) -> void:
	var stats := Data.stats_for(id, Save.data.upgrades.get(id, {}))
	var paint: Color = Data.CARS[id].paint
	if Save.data.paint.has(id):
		paint = Color.html(Save.data.paint[id])
	var body: String = stats.get("body", "concept")
	var old_body: String = player.stats.get("body", "concept") if not player.stats.is_empty() else ""
	if player.stats.is_empty() or body != old_body:
		var xf := player.global_transform
		var fresh := player.stats.is_empty()
		if not fresh:
			effects.detach(player)
			var old := player
			player = Car.new()
			player.is_player = true
			add_child(player)
			old.queue_free()
		player.setup(stats, paint, false, true, bool(Settings.preset().head_shadows))
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		player.assists = bool(Settings.data.assists)
		player.manual = bool(Settings.data.manual)
		if not fresh:
			player.reset_to(xf)
			effects.attach(player)
			player.impact.connect(_on_impact)
			player.shifted.connect(func(_g): _rumble(0.45, 0.2, 0.07))
			cam.target = player
	else:
		player.stats = stats
		player.mass = stats.mass
		player._setup_engine()
		player.set_paint(paint)
	_player_car_id = id

func reset_career() -> void:
	career.abandon()
	police.clear()
	apply_player_car()
	_place_at_home()

func on_car_spawned(car: Car) -> void:
	effects.attach(car)

func on_car_removed(car: Car) -> void:
	effects.detach(car)

func on_race_start() -> void:
	cam.snap = true
	effects.clear_skids()
	drift.chain = 0.0

func on_settings_changed() -> void:
	Settings.apply_graphics(daynight.env, daynight.sun, get_viewport(), cam)
	daynight.set_draw_distance(cam.far)
	cam.base_fov = float(Settings.data.fov)
	audio.apply_volumes()
	if traffic:
		traffic.set_count(int(Settings.preset().traffic * float(Settings.data.traffic)))
	if player:
		player.assists = bool(Settings.data.assists)
		player.manual = bool(Settings.data.manual)
	cam.mode = int(Settings.data.camera) as CameraRig.Mode

func player_at_home() -> bool:
	var h: Vector2 = Career.LOC.home
	return Vector2(player.global_position.x, player.global_position.z).distance_to(h) < 18.0

func skip_time() -> void:
	daynight.hour = 10.0 if daynight.night > 0.5 else 22.0
	persist()

func reset_to_road() -> void:
	player.reset_to(world.respawn_at(player.global_position))
	cam.snap = true

func persist() -> void:
	if player == null:
		return
	var p := player.global_position
	var f := -player.global_transform.basis.z
	Save.data.pos = [p.x, p.y, p.z, atan2(-f.x, -f.z)]
	Save.data.hour = daynight.hour
	Save.save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		persist()

# ---------------------------------------------------------------- states
func _to_menu() -> void:
	state = State.MENU
	hud.visible = false
	get_tree().paused = false
	menus.close_all()
	menus.show_screen("main", false)
	menu_t = 0.0

func _on_play() -> void:
	menus.close_all()
	state = State.PLAY
	hud.visible = true
	cam.snap = true
	if float(Save.data.playtime) < 1.0:
		hud.show_dialogue(["Your phone buzzes. Unknown number.", "Mara: \"You're the driver everyone's talking about? Stay by your phone.\""])

func _on_resume() -> void:
	state = State.PLAY
	hud.visible = true
	get_tree().paused = false
	cam.snap = true

func _pause() -> void:
	state = State.PAUSED
	get_tree().paused = true
	menus.show_screen("pause", false)

func _on_career_finished(res: Dictionary) -> void:
	audio.play_oneshot("reward")
	if res.get("contract_next", false):
		hud.big("VICTORY", 2.0)
		return
	state = State.RESULTS
	get_tree().paused = true
	menus.show_results(res)
	persist()

func _on_pursuit_ended(escaped: bool, bounty: int) -> void:
	if escaped:
		Save.add_cash(bounty)
		Save.data.heat_escapes = int(Save.data.heat_escapes) + 1
		hud.big("ESCAPED", 2.0)
		hud.message("Bounty +$%s" % HUD._fmt(bounty), 3.0)
		audio.play_oneshot("reward")
	else:
		var fine := mini(int(Save.data.cash), 2500 * maxi(police.heat, 1))
		Save.add_cash(-fine)
		hud.big("BUSTED", 2.5)
		hud.message("Fine -$%s" % HUD._fmt(fine), 3.0)
		if not career.active.is_empty():
			career.abandon()
	persist()

func _on_impact(strength: float) -> void:
	if strength > 4.0:
		cam.shake = minf(1.0, strength / 25.0)
		audio.play_oneshot("impact", randf_range(0.85, 1.1), linear_to_db(clampf(strength / 30.0, 0.1, 1.0)))
		_rumble(clampf(strength / 20.0, 0.2, 1.0), 0.6, 0.25)
		if strength > 8.0 and drift.chain > 0.0:
			hud.message("DRIFT CHAIN LOST", 1.2)
			drift.chain = 0.0
			drift.mult = 1

func _on_traffic_hit(strength: float) -> void:
	_on_impact(strength * 0.5 + 4.0)

func _rumble(strong: float, weak: float, secs: float) -> void:
	# One-shot haptic kick (impacts, landings, gear shifts); layered on top of the
	# continuous haptics computed in _update_haptics.
	if not using_pad:
		return
	kick_strong = maxf(kick_strong, strong)
	kick_weak = maxf(kick_weak, weak)
	kick_time = maxf(kick_time, secs)

## Continuous controller haptics: engine near redline, tyre slip, ABS pulse,
## rough surfaces, nitrous, burnouts, plus decaying one-shot kicks.
func _update_haptics(delta: float) -> void:
	if not using_pad or Input.get_connected_joypads().is_empty():
		return
	var gain := float(Settings.data.vibration)
	var p := player
	var weak := 0.0
	var strong := 0.0
	var rpm_n := clampf(p.rpm / float(p.stats.red), 0.0, 1.05)
	weak += pow(rpm_n, 4.0) * 0.18 * float(p.input.throttle)
	var slip := 0.0
	for w in p.wheels:
		slip = maxf(slip, float(w.skid))
	weak += slip * 0.5
	if p.surface == "terrain" and p.speed > 4.0:
		strong += clampf(p.speed / 35.0, 0.0, 0.55) * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.05))
	if float(p.input.brake) > 0.75 and p.speed > 12.0 and not p.reverse:
		# ABS pulse
		strong += 0.28 if int(Time.get_ticks_msec() / 60) % 2 == 0 else 0.05
	if p.nitro_on:
		strong += 0.18
		weak += 0.25
	if p.burnout:
		strong += 0.3
		weak += 0.55
	if p.on_ground == false:
		weak *= 0.2
		strong *= 0.2
	if kick_time > 0.0:
		kick_time -= delta
		strong = maxf(strong, kick_strong)
		weak = maxf(weak, kick_weak)
	else:
		kick_strong = 0.0
		kick_weak = 0.0
	strong = clampf(strong * gain, 0.0, 1.0)
	weak = clampf(weak * gain, 0.0, 1.0)
	if strong + weak < 0.02:
		if haptics_on:
			for d in Input.get_connected_joypads():
				Input.stop_joy_vibration(d)
			haptics_on = false
		return
	haptics_on = true
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, weak, strong, 0.15)

# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false
	Settings.using_pad = using_pad
	if state != State.PLAY:
		return
	if event.is_action_pressed("pause"):
		_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map"):
		hud.big_map.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera"):
		cam.cycle()
		Settings.data.camera = cam.mode
	elif event.is_action_pressed("phone"):
		var lines := career.answer_phone()
		if not lines.is_empty():
			audio.set_ringing(false)
			hud.show_dialogue(lines)
	elif event.is_action_pressed("interact"):
		var rid := career.race_near(Vector2(player.global_position.x, player.global_position.z))
		if rid != "" and not police.pursuit:
			career.start_race(rid)
		elif player_at_home() and not police.pursuit and career.active.is_empty():
			_open_garage()
	elif event.is_action_pressed("headlights"):
		lights_override = 0 if player.lights_on else 1
	elif event.is_action_pressed("shift_up"):
		player.input.shift_up = true
	elif event.is_action_pressed("shift_down"):
		player.input.shift_down = true

func _open_garage() -> void:
	state = State.GARAGE
	hud.visible = false
	player.linear_velocity = Vector3.ZERO
	menus.garage_sel = Save.data.car
	menus.show_screen("garage", false)
	persist()

func _read_driving_input(delta: float) -> void:
	var raw_steer := Input.get_axis("steer_left", "steer_right")
	if using_pad:
		var dz := float(Settings.data.deadzone)
		var a := absf(raw_steer)
		var s := 0.0 if a < dz else signf(raw_steer) * pow((a - dz) / (1.0 - dz), float(Settings.data.steer_curve))
		s = clampf(s * float(Settings.data.steer_sens), -1.0, 1.0)
		steer_kb = move_toward(steer_kb, s, delta * 12.0)
	else:
		var target := signf(raw_steer) if absf(raw_steer) > 0.5 else 0.0
		var rate := (6.5 if target == 0.0 or signf(target) != signf(steer_kb) else 3.4) / (1.0 + player.speed / 55.0)
		steer_kb = move_toward(steer_kb, target, delta * rate)
	player.input.steer = steer_kb
	player.input.throttle = Input.get_action_strength("throttle")
	player.input.brake = Input.get_action_strength("brake")
	player.input.handbrake = Input.get_action_strength("handbrake")
	player.input.nitro = Input.is_action_pressed("nitro")
	if Input.is_action_pressed("reset"):
		reset_hold += delta
		if reset_hold > (0.8 if using_pad else 0.0) and reset_hold < 100.0:
			reset_to_road()
			reset_hold = 1000.0
	else:
		reset_hold = 0.0
	cam.look_back = Input.is_action_pressed("look_back")

# ---------------------------------------------------------------- frame
func _physics_process(delta: float) -> void:
	if state != State.PLAY or player == null:
		return
	if not autopilot:
		_read_driving_input(delta)
	var others: Array = []
	if career.race:
		for r in career.race.rivals:
			others.append(r.car)
	others.append_array(police.cars())
	_soft_contacts([player] + others)
	traffic.collide(player)
	for o in others:
		traffic.collide(o, false)

func _soft_contacts(list: Array) -> void:
	# Cars never block each other: overlapping cars get a soft separating impulse
	# and lose only a sliver of their closing speed.
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Car = list[i]
			var b: Car = list[j]
			var dv := b.global_position - a.global_position
			dv.y = 0.0
			var d := dv.length()
			if d > 2.6 or d < 0.01:
				continue
			var n := dv / d
			var depth := 2.6 - d
			var rel := (b.linear_velocity - a.linear_velocity).dot(n)
			var j_imp := depth * 6.0 + maxf(-rel, 0.0) * 0.25
			a.apply_central_impulse(-n * j_imp * a.mass * 0.5 * get_physics_process_delta_time() * 10.0)
			b.apply_central_impulse(n * j_imp * b.mass * 0.5 * get_physics_process_delta_time() * 10.0)
			if (a == player or b == player) and rel < -3.0:
				_on_impact(absf(rel) * 0.6)

func _process(delta: float) -> void:
	if state == State.LOADING or player == null:
		return
	var playing := state == State.PLAY
	if playing:
		Save.data.playtime = float(Save.data.playtime) + delta
		daynight.hour = fmod(daynight.hour + delta / 45.0, 24.0)
		_update_weather(delta)
	daynight.update(delta)
	var night := daynight.night
	world.update_lamps(delta, cam.global_position, night)
	traffic.set_night(night)
	world.set_wetness(clampf(daynight.rain * 1.2 + night * 0.25, 0.0, 1.0))
	effects.update_rain(daynight.rain, cam.global_position, player.linear_velocity)
	var lights := night > 0.25 or daynight.rain > 0.4
	if lights_override >= 0:
		lights = lights_override == 1
	player.set_lights(lights, night)
	if state == State.MENU:
		_menu_camera(delta)
		audio.update_player(player, false, delta)
		audio.update_music(false, delta)
		return
	if state == State.GARAGE:
		_garage_camera(delta)
		audio.update_player(player, true, delta)
		return
	if not playing:
		audio.update_player(player, false, delta)
		return
	cam.process_mode = Node.PROCESS_MODE_INHERIT
	traffic.update(delta, player, police.cars())
	police.update(delta)
	career.update(delta)
	_update_drift(delta)
	_update_prompt()
	_update_gps(delta)
	# Nitrous refills: near misses, big air and high speed.
	var misses := traffic.near_misses(player)
	if misses > 0:
		player.nitro = minf(1.0, player.nitro + 0.12 * misses)
		hud.message("NEAR MISS  +N2O", 1.0)
		if drift.chain > 0.0:
			drift.chain += 500.0 * drift.mult
	if player.air_time > 0.7 and not air_shown:
		air_shown = true
		hud.message("BIG AIR  +N2O", 1.2)
		player.nitro = minf(1.0, player.nitro + 0.15)
	if player.on_ground:
		air_shown = false
	if player.speed > 50.0 and not player.nitro_on:
		player.nitro = minf(1.0, player.nitro + delta * 0.012)
	audio.update_player(player, true, delta)
	var siren := 0.0
	for c in police.cars():
		if police.pursuit:
			siren = maxf(siren, clampf(1.0 - c.global_position.distance_to(player.global_position) / 260.0, 0.0, 1.0))
	audio.update_siren(siren)
	audio.update_music(police.pursuit or career.race != null, delta)
	var ai_cars: Array = police.cars()
	if career.race:
		for r in career.race.rivals:
			ai_cars.append(r.car)
	audio.update_ai(ai_cars, cam.global_position)
	_update_haptics(delta)
	if player.landing_impact > 0.0:
		_rumble(clampf(player.landing_impact / 8.0, 0.2, 1.0), 0.4, 0.18)
		cam.shake = maxf(cam.shake, clampf(player.landing_impact / 15.0, 0.0, 0.8))
		player.landing_impact = 0.0
	save_timer += delta
	if save_timer > 15.0:
		save_timer = 0.0
		persist()
	if player.global_position.y < -20.0:
		reset_to_road()

func _update_weather(delta: float) -> void:
	weather_timer -= delta
	if weather_timer <= 0.0:
		weather_timer = randf_range(150.0, 400.0)
		rain_target = randf_range(0.5, 1.0) if randf() < 0.3 else 0.0
	daynight.rain = move_toward(daynight.rain, rain_target, delta * 0.02)

func _update_drift(delta: float) -> void:
	var ang := absf(player.slip_angle)
	var drifting := player.on_ground and player.speed > 11.0 and ang > 0.24 and ang < 1.6 and player.forward_speed > 0.0
	if drifting:
		drift.idle = 0.0
		drift.time += delta
		drift.mult = mini(5, 1 + int(drift.time / 2.5))
		drift.chain += delta * player.speed * minf(ang, 1.1) * 30.0 * drift.mult
		player.nitro = minf(1.0, player.nitro + delta * 0.08)
	elif drift.chain > 0.0:
		drift.idle += delta
		if drift.idle > 1.8:
			var pts := int(drift.chain)
			drift.total += pts
			if pts > 400:
				var cash := pts / 40
				Save.add_cash(cash)
				hud.message("DRIFT %s  +$%d" % [HUD._fmt(pts), cash], 1.8)
			drift.chain = 0.0
			drift.mult = 1
			drift.time = 0.0

func _update_prompt() -> void:
	prompt_text = ""
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var key := Settings.glyph("interact")
	var rid := career.race_near(pp)
	if rid != "" and not police.pursuit:
		var r: Dictionary = Career.RACES[rid]
		prompt_text = "%s  ·  $%s\n[%s] Start race" % [r.name, HUD._fmt(int(r.reward)), key]
	elif player_at_home() and career.active.is_empty():
		prompt_text = "HOME\n[%s] Enter garage" % key if not police.pursuit else "Lose the cops before going home"

func _update_gps(delta: float) -> void:
	gps_timer -= delta
	if gps_timer > 0.0:
		return
	gps_timer = 1.0
	var target: Vector2 = career.waypoint
	if target == Vector2.INF and career.race:
		gps_route = PackedVector2Array()
		var r := career.race
		for k in range(0, 160, 4):
			gps_route.append(r.path.at(r.p_idx + k))
		return
	if target == Vector2.INF:
		gps_route = PackedVector2Array()
		return
	var a := world.nearest_node(Vector2(player.global_position.x, player.global_position.z))
	var b := world.nearest_node(target)
	var route := world.route(a, b)
	gps_route = PackedVector2Array([Vector2(player.global_position.x, player.global_position.z)])
	for id in route:
		gps_route.append(world.node_pos[id])
	gps_route.append(target)

func _menu_camera(delta: float) -> void:
	menu_t += delta
	var a := menu_t * 0.04
	cam.process_mode = Node.PROCESS_MODE_DISABLED
	cam.global_position = Vector3(sin(a) * 900.0, 230.0, cos(a) * 900.0)
	cam.look_at(Vector3(0, 60, 0))
	cam.fov = 55.0

func _garage_camera(delta: float) -> void:
	menu_t += delta
	var a := menu_t * 0.3
	var p := player.global_position
	cam.process_mode = Node.PROCESS_MODE_DISABLED
	cam.global_position = p + Vector3(sin(a) * 6.5, 1.5, cos(a) * 6.5)
	cam.look_at(p + Vector3(0, 0.6, 0))
	cam.fov = 50.0

# ---------------------------------------------------------------- screenshots
## Automated scenes for README screenshots / visual tests.
func _run_shots(spec: String) -> void:
	state = State.PLAY
	menus.close_all()
	hud.visible = true
	traffic.set_count(0) if OS.has_environment("NO_TRAFFIC") else null
	if OS.has_environment("SHOT_MISSION"):
		career.call_timer = 0.0
		await _frames(3)
		career.answer_phone()
	for item in spec.split(";"):
		var p := item.split(":")
		# name:x:z:yaw:hour:cammode:rain:speed
		var x := float(p[1])
		var z := float(p[2])
		var y := 0.6 if world.in_city(x, z) else world.ground(x, z) + 0.8
		player.reset_to(Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[3]))), Vector3(x, y, z)))
		daynight.hour = float(p[4])
		cam.mode = int(p[5]) as CameraRig.Mode
		daynight.rain = float(p[6])
		rain_target = daynight.rain
		cam.snap = true
		var spd := float(p[7]) if p.size() > 7 else 0.0
		if p.size() > 8:
			_build_player(p[8])
			player.reset_to(Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[3]))), Vector3(x, y, z)))
		var showcase := int(p[5]) == 4
		state = State.GARAGE if showcase else State.PLAY
		hud.visible = not showcase
		if showcase:
			cam.mode = CameraRig.Mode.CHASE
			menu_t = 2.2
		for i in 90:
			if spd > 0.0:
				player.linear_velocity = -player.global_transform.basis.z * spd
			player.input.throttle = 0.6 if spd > 0.0 else 0.0
			await get_tree().process_frame
		if OS.has_environment("SHOT_MAP"):
			hud.big_map.open()
			await get_tree().process_frame
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(OS.get_environment("SHOT_DIR") + "/" + p[0] + ".png")
		if hud.big_map.visible:
			hud.big_map.close()
		print("shot ", p[0])

# ---------------------------------------------------------------- automated playtest
func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _autotest() -> void:
	print("[test] start cash=", Save.data.cash, " contract=", Save.data.contract)
	_on_play()
	# 1) Contract via phone: teleport through the goto steps.
	career.call_timer = 0.0
	await _frames(5)
	print("[test] pending call=", career.pending_call)
	var lines := career.answer_phone()
	print("[test] brief: ", lines)
	for guard in 40:
		if career.active.is_empty():
			break
		var s: Dictionary = career.active.steps[career.step]
		if s.has("goto"):
			var t: Vector2 = career.waypoint
			player.reset_to(Transform3D(Basis(), career.pos3(t) + Vector3(0, 0.8, 0)))
		elif s.has("evade"):
			player.reset_to(Transform3D(Basis(), career.pos3(Vector2(-2500, 700)) + Vector3(0, 1.5, 0)))
			police.clear()
		await _frames(30)
		print("[test] step ", career.step, " ", career.waypoint_label, " pursuit=", police.pursuit)
	print("[test] after contract cash=", Save.data.cash, " contract=", Save.data.contract)
	_on_resume()
	# 2) Race with the player driven by an AI.
	career.start_race("downtown")
	autopilot = true
	var bot := AIDriver.new(player, career.race.path, 0.95, 0.0)
	bot.idx = career.race.p_idx
	var t := 0
	while career.race and t < 60 * 60 * 2:
		var all: Array = [player]
		for r in career.race.rivals:
			all.append(r.car)
		bot.update(1.0 / 60.0, all, career.race.countdown > 0.0)
		player.input.steer = player.input.steer
		await get_tree().physics_frame
		t += 1
		if t % 1200 == 0 and career.race:
			print("[test] race t=", t / 60, "s pos=", career.race.place, " lap=", career.race.lap, " cp=", career.race.next_cp, "/", career.race.cps.size(), " kmh=", int(player.kmh), " rivals=", career.race.rivals.map(func(r): return int(r.ai.progress)))
	print("[test] race stopped after ", t / 60, "s cash=", Save.data.cash)
	career.abandon()
	autopilot = false
	_on_resume()
	# 3) Bank job with a police chase: escape by distance.
	Save.data.contract = 3
	career.pending_call = 3
	career.ringing = 10.0
	career.answer_phone()
	for guard in 60:
		if career.active.is_empty():
			break
		var s2: Dictionary = career.active.steps[career.step]
		if s2.has("goto"):
			player.reset_to(Transform3D(Basis(), career.pos3(career.waypoint) + Vector3(0, 0.8, 0)))
			await _frames(30)
		elif s2.has("wait"):
			await _frames(60 * 14)
			print("[test] after wait: pursuit=", police.pursuit, " heat=", police.heat, " cops=", police.cops.size())
		elif s2.has("evade"):
			await _frames(60 * 6)
			print("[test] cops chasing: ", police.cops.size(), " nearest=", police.cops.map(func(c): return int(c.car.global_position.distance_to(player.global_position))))
			player.reset_to(Transform3D(Basis(), Vector3(-2550, world.ground(-2550, 650) + 1.5, 650)))
			await _frames(60 * 13)
			print("[test] evade: pursuit=", police.pursuit)
	print("[test] end cash=", Save.data.cash, " contract=", Save.data.contract, " state=", state)

func _aitest() -> void:
	_on_play()
	traffic.set_count(0)
	police.enabled = false
	career.start_race("downtown")
	var r := career.race
	player.reset_to(Transform3D(Basis(), Vector3(-2000, 300, -2000)))
	for k in range(1, r.rivals.size()):
		r.rivals[k].car.reset_to(Transform3D(Basis(), Vector3(-2000 + k * 20, 300, -2000)))
	var c: Car = r.rivals[0].car
	var ai: AIDriver = r.rivals[0].ai
	for t in 60 * 70:
		await get_tree().physics_frame
		if t % 60 == 0:
			var pp := Vector2(c.global_position.x, c.global_position.z)
			print("[ai] t=", t / 60, " kmh=", int(c.kmh), " vt=", int(ai.profile[ai.idx] * 3.6), " thr=", snappedf(c.input.throttle, 0.1), " brk=", snappedf(c.input.brake, 0.1), " st=", snappedf(c.input.steer, 0.1), " idx=", ai.idx, " off=", snappedf(r.path.at(ai.idx).distance_to(pp), 0.1), " y=", snappedf(c.global_position.y, 0.01), " gnd=", c.wheels_on_ground, " surf=", c.surface, " slip=", snappedf(c.slip_angle, 0.01), " stuck=", snappedf(ai.stuck, 0.1))

# ---------------------------------------------------------------- UI test (mouse + gamepad)
func _snap(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	var dir := OS.get_environment("SHOT_DIR")
	if dir != "":
		get_viewport().get_texture().get_image().save_png(dir + "/" + name + ".png")
	print("[ui] snap ", name, " screen=", menus.current, " state=", state, " focus=", _focus_text())

func _focus_text() -> String:
	var f := get_viewport().gui_get_focus_owner()
	return f.text if f is Button else str(f)

func _click_button(label: String) -> bool:
	for b in menus.find_children("*", "Button", true, false):
		var btn := b as Button
		if btn.is_visible_in_tree() and btn.text.begins_with(label):
			var pos := btn.get_global_rect().get_center()
			var win_pos := get_viewport().get_final_transform() * pos
			var mv := InputEventMouseMotion.new()
			mv.position = win_pos
			mv.global_position = win_pos
			Input.parse_input_event(mv)
			await get_tree().process_frame
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = pressed
				ev.position = win_pos
				ev.global_position = win_pos
				Input.parse_input_event(ev)
				await get_tree().process_frame
			print("[ui] clicked ", label, " at ", pos)
			return true
	print("[ui] button not found: ", label)
	return false

func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.device = 0
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame

func _menutest() -> void:
	await _snap("01_main")
	await _click_button("SETTINGS")
	await _snap("02_settings_mouse")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _snap("03_settings_pad_down")
	await _pad(JOY_BUTTON_B)
	await _snap("04_back_to_main")
	await _click_button("CONTROLS")
	await _snap("05_controls")
	await _pad(JOY_BUTTON_B)
	await _pad(JOY_BUTTON_A)
	await _snap("06_pad_A_play")
	await _pad(JOY_BUTTON_START)
	await _snap("07_pause_start")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _snap("08_pause_down")
	await _click_button("SETTINGS")
	await _snap("09_pause_settings")
	await _pad(JOY_BUTTON_B)
	await _pad(JOY_BUTTON_B)
	await _snap("10_resumed")
	# Drive home and open the garage with the pad.
	_place_at_home()
	await get_tree().physics_frame
	await _pad(JOY_BUTTON_DPAD_UP)
	await _snap("11_garage")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	await _snap("12_garage_select")
	await _pad(JOY_BUTTON_B)
	await _snap("13_garage_closed")
