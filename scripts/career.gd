class_name Career
extends Node3D
## Contracts (phone calls from your fixer), street races, speed traps and the
## GPS waypoint. Contracts are step lists: goto / wait / evade / race.

signal message(text: String, seconds: float)
signal big(text: String, seconds: float)
signal phone_ring(caller: String)
signal finished(result: Dictionary)

const LOC := {
	"home": Vector2(-420, 365), "lot": Vector2(250, -365), "docks": Vector2(0, 1330),
	"harbor_bank": Vector2(-180, 485), "first_bank": Vector2(60, -125), "reserve": Vector2(185, 5),
	"quarry": Vector2(350, -2700), "airfield": Vector2(2300, 760), "farm": Vector2(-2520, 720),
	"overpass": Vector2(1100, 0), "chop_shop": Vector2(485, 300), "pier": Vector2(-750, 1500),
}

const CONTRACTS := [
	{"title": "Wheels", "caller": "Mara", "reward": 4000,
		"brief": ["Mara: Heard you can drive. Prove it.", "Pick up a car at the lot downtown and get it to the docks. Clock's ticking."],
		"steps": [{"goto": "lot", "label": "Pick up the car"}, {"goto": "docks", "label": "Deliver to the docks", "time": 150}]},
	{"title": "Proving Ground", "caller": "Mara", "reward": 6000,
		"brief": ["Mara: The street crews don't know your name yet.", "Win their downtown circuit and they will."],
		"steps": [{"race": "downtown", "place": 1}]},
	{"title": "Hot Plates", "caller": "Mara", "reward": 7000,
		"brief": ["Mara: Swing by the chop shop and grab a hot car.", "Cops will be on it the second you roll out. Lose them, then bring it home."],
		"steps": [{"goto": "chop_shop", "label": "Grab the hot car"}, {"heat": 2}, {"evade": true, "label": "Lose the cops"}, {"goto": "home", "label": "Bring it to your garage"}]},
	{"title": "Harbor Savings", "caller": "Mara", "reward": 15000,
		"brief": ["Mara: First real job. Crew's hitting Harbor Savings.", "Park out front, wait for them, then get everyone to the docks in one piece."],
		"steps": [{"goto": "harbor_bank", "label": "Pull up at Harbor Savings"}, {"wait": 12, "label": "Crew is inside...", "alarm": 6}, {"heat": 3}, {"evade": true, "label": "Shake the cops"}, {"goto": "docks", "label": "Drop the crew at the docks"}]},
	{"title": "Mountain Courier", "caller": "Dex", "reward": 12000,
		"brief": ["Dex: Mara says you're good. I need a package up the mountain.", "Quarry at the top of Summit Pass. Don't be late."],
		"steps": [{"goto": "overpass", "label": "Collect the package"}, {"goto": "quarry", "label": "Deliver to the quarry", "time": 240, "heat_mid": 1}]},
	{"title": "Ring King", "caller": "Mara", "reward": 14000,
		"brief": ["Mara: The highway crew thinks they own the ring road.", "Show them otherwise."],
		"steps": [{"race": "ring", "place": 1}]},
	{"title": "First National", "caller": "Mara", "reward": 28000,
		"brief": ["Mara: Downtown. First National. Big score, big heat.", "Wait for the crew, lose the cops, run them to the airfield."],
		"steps": [{"goto": "first_bank", "label": "Pull up at First National"}, {"wait": 15, "label": "Crew is inside...", "alarm": 5}, {"heat": 4}, {"evade": true, "label": "Lose the cops"}, {"goto": "airfield", "label": "Get to the airfield hangar"}]},
	{"title": "Valley Run", "caller": "Dex", "reward": 18000,
		"brief": ["Dex: Plane's landed with cargo. Valley farm wants it yesterday."],
		"steps": [{"goto": "airfield", "label": "Pick up the cargo"}, {"goto": "farm", "label": "Deliver to the valley farm", "time": 260}]},
	{"title": "Summit Showdown", "caller": "Mara", "reward": 22000,
		"brief": ["Mara: There's a crew on the mountain who think nobody's faster.", "Beat them over the summit."],
		"steps": [{"race": "summit", "place": 1}]},
	{"title": "The Reserve", "caller": "Mara", "reward": 60000,
		"brief": ["Mara: This is the one. The Federal Reserve.", "Every cop in the city will come. Get the crew to the pier and we're done."],
		"steps": [{"goto": "reserve", "label": "Pull up at the Reserve"}, {"wait": 18, "label": "Crew is cracking the vault...", "alarm": 4}, {"heat": 5}, {"evade": true, "label": "Lose every cop in the city"}, {"goto": "pier", "label": "Get the crew to the pier"}]},
]

const RACES := {
	"downtown": {"name": "Downtown Circuit", "laps": 3, "reward": 7000, "skill": 0.88, "roads": ["city"],
		"pts": [[-240, -240], [240, -240], [240, 240], [-240, 240]], "circuit": true},
	"zigzag": {"name": "Midtown Zigzag", "laps": 1, "reward": 6000, "skill": 0.9, "roads": ["city"],
		"pts": [[-480, 480], [-120, 480], [-120, 120], [240, 120], [240, -240], [480, -240], [480, -480]], "circuit": false},
	"ring": {"name": "Ring Road Rally", "laps": 1, "reward": 12000, "skill": 0.92, "roads": ["hwy"],
		"pts": [[0, -1500], [1600, 0], [0, 1560], [-1610, 0]], "circuit": true},
	"summit": {"name": "Summit Pass", "laps": 1, "reward": 15000, "skill": 0.93, "roads": ["pass", "hwy"],
		"pts": [[800, -1420], [350, -2700], [-750, -1450]], "circuit": false},
	"valley": {"name": "Valley Sprint", "laps": 1, "reward": 11000, "skill": 0.92, "roads": ["country", "hwy"],
		"pts": [[-1620, 450], [-2680, 300], [-1600, -350]], "circuit": false},
	"airstrip": {"name": "Airstrip Drag", "laps": 1, "reward": 9000, "skill": 0.95, "roads": ["runway"],
		"pts": [[2300, -1280], [2300, 1280]], "circuit": false},
	"grand": {"name": "Grand Tour", "laps": 1, "reward": 40000, "skill": 0.97, "roads": ["city", "link", "hwy", "pass", "country"],
		"pts": [[0, 0], [600, 0], [1600, 0], [800, -1420], [350, -2700], [-750, -1450], [-1620, 450], [-2680, 300], [-1600, -350], [-600, 0]], "circuit": false},
}

const SPEED_TRAPS := [Vector2(1580, 400), Vector2(-1350, 1150), Vector2(0, -1050), Vector2(2300, 0), Vector2(750, 1450), Vector2(-1600, -350)]

var game: Node
var world: World
var active: Dictionary = {} # running contract
var step := 0
var step_t := 0.0
var time_left := INF
var waypoint := Vector2.INF
var waypoint_label := ""
var pending_call := -1
var call_timer := 25.0
var ringing := 0.0
var race: RaceSession
var race_markers: Array = []
var beacon: MeshInstance3D
var home_marker: Node3D
var trap_cool := {}

func setup(g: Node, w: World) -> void:
	game = g
	world = w
	beacon = _beam(Color(1.0, 0.75, 0.2), 4.0)
	beacon.visible = false
	add_child(beacon)
	home_marker = _beam(Color(0.2, 1.0, 0.55), 6.0)
	var hp := pos3(LOC.home)
	home_marker.position = hp
	add_child(home_marker)
	for id in RACES:
		var r: Dictionary = RACES[id]
		var m := _beam(Color(0.25, 0.75, 1.0) if r.circuit else Color(1.0, 0.35, 0.6), 2.2)
		var p := Vector2(r.pts[0][0], r.pts[0][1])
		var nid := world.nearest_node(p, r.roads)
		m.position = pos3(world.node_pos[nid])
		add_child(m)
		race_markers.append({"id": id, "node": m, "pos": world.node_pos[nid]})

func pos3(p: Vector2) -> Vector3:
	var y := 0.05 if world.in_city(p.x, p.y) else world.ground(p.x, p.y)
	return Vector3(p.x, y, p.y)

func _beam(c: Color, radius: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 160.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r, c.g, c.b, 0.16)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 1)
	gt.fill_to = Vector2(0, 0)
	m.albedo_texture = gt
	m.disable_fog = true
	cyl.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 80.0
	var root := MeshInstance3D.new()
	root.add_child(mi)
	return root

# ---------------------------------------------------------------- phone
func contract_index() -> int:
	return int(Save.data.contract)

func update(dt: float) -> void:
	var p: Car = game.player
	var pp := Vector2(p.global_position.x, p.global_position.z)
	home_marker.visible = active.is_empty() and race == null
	for m in race_markers:
		m.node.visible = active.is_empty() and race == null
	# Incoming calls when idle
	if active.is_empty() and race == null and pending_call < 0:
		call_timer -= dt
		if call_timer <= 0.0:
			pending_call = contract_index() if contract_index() < CONTRACTS.size() else 100 + randi() % 3
			ringing = 20.0
			phone_ring.emit(_caller(pending_call))
	if pending_call >= 0 and ringing > 0.0:
		ringing -= dt
		if ringing <= 0.0:
			message.emit("Missed call - press Phone to call back", 4.0)
	# Speed traps
	for i in SPEED_TRAPS.size():
		var tp: Vector2 = SPEED_TRAPS[i]
		if pp.distance_to(tp) < 14.0 and trap_cool.get(i, 0.0) <= 0.0:
			trap_cool[i] = 5.0
			var kmh := int(p.kmh)
			var best: int = Save.data.best.get("trap%d" % i, 0)
			if kmh > best:
				Save.data.best["trap%d" % i] = kmh
				var cash := int(kmh * 15)
				Save.add_cash(cash)
				big.emit("SPEED TRAP  %d km/h" % kmh, 2.0)
				message.emit("New record! +$%d" % cash, 2.5)
				game.audio.play_oneshot("reward")
			else:
				message.emit("Speed trap %d km/h  (best %d)" % [kmh, best], 2.5)
	for k in trap_cool.keys():
		trap_cool[k] -= dt
	if race:
		race.update(dt)
		waypoint = Vector2.INF
		if race.done:
			_race_finished(race.result)
		return
	if not active.is_empty():
		_update_contract(dt, pp)
	beacon.visible = waypoint != Vector2.INF
	if beacon.visible:
		beacon.position = pos3(waypoint)

func _caller(idx: int) -> String:
	if idx >= 100:
		return ["Mara", "Dex", "Unknown"][idx - 100]
	return CONTRACTS[idx].caller

func answer_phone() -> Array:
	## Returns briefing lines (or empty if no call).
	if pending_call < 0 or not active.is_empty() or race != null:
		return []
	var c: Dictionary = CONTRACTS[pending_call] if pending_call < CONTRACTS.size() else _random_contract(pending_call)
	pending_call = -1
	ringing = 0.0
	_start_contract(c)
	return c.brief

func _random_contract(seed_idx: int) -> Dictionary:
	var keys := LOC.keys()
	keys.erase("home")
	var a: String = keys[randi() % keys.size()]
	var b: String = keys[randi() % keys.size()]
	while b == a:
		b = keys[randi() % keys.size()]
	var kind := randi() % 3
	if kind == 0:
		var banks := ["harbor_bank", "first_bank", "reserve"]
		var bank: String = banks[randi() % 3]
		return {"title": "Bank Job", "caller": "Mara", "reward": 12000 + randi() % 12000, "brief": ["Mara: Another crew needs a driver. Same drill."],
			"steps": [{"goto": bank, "label": "Pull up at the bank"}, {"wait": 12, "label": "Crew is inside...", "alarm": 5}, {"heat": 3 + randi() % 2}, {"evade": true, "label": "Lose the cops"}, {"goto": b, "label": "Drop off the crew"}]}
	elif kind == 1:
		var d := pos_of(a).distance_to(pos_of(b))
		return {"title": "Hot Delivery", "caller": "Dex", "reward": 5000 + int(d * 2.5), "brief": ["Dex: Got a package that can't wait."],
			"steps": [{"goto": a, "label": "Collect the package"}, {"goto": b, "label": "Deliver it", "time": int(40 + d / 22.0)}]}
	var rid: String = RACES.keys()[randi() % RACES.size()]
	return {"title": "Street Race", "caller": "Unknown", "reward": RACES[rid].reward, "brief": ["Someone wants to race you. %s." % RACES[rid].name], "steps": [{"race": rid, "place": 1}]}

func pos_of(key: String) -> Vector2:
	return LOC[key]

func _start_contract(c: Dictionary) -> void:
	active = c
	step = -1
	_next_step()
	big.emit(c.title.to_upper(), 2.5)

func _next_step() -> void:
	step += 1
	step_t = 0.0
	time_left = INF
	waypoint = Vector2.INF
	if step >= active.steps.size():
		_complete_contract(true)
		return
	var s: Dictionary = active.steps[step]
	if s.has("goto"):
		waypoint = pos_of(s.goto)
		waypoint_label = s.label
		if s.has("time"):
			time_left = float(s.time)
		message.emit(s.label, 4.0)
	elif s.has("wait"):
		waypoint_label = s.label
		message.emit(s.label, 4.0)
	elif s.has("heat"):
		game.police.min_heat = int(s.heat)
		game.police.start_pursuit("THE COPS ARE COMING", int(s.heat))
		_next_step()
	elif s.has("evade"):
		waypoint_label = s.label
		message.emit(s.label, 4.0)
	elif s.has("race"):
		start_race(s.race, s.get("place", 1))

func _update_contract(dt: float, pp: Vector2) -> void:
	if step < 0 or step >= active.steps.size():
		return
	var s: Dictionary = active.steps[step]
	step_t += dt
	if time_left < INF:
		time_left -= dt
		if time_left <= 0.0:
			_complete_contract(false, "Out of time")
			return
	if s.has("goto"):
		if s.has("heat_mid") and step_t > 40.0 and not game.police.pursuit:
			game.police.start_pursuit("COPS SPOTTED THE PACKAGE", int(s.heat_mid))
		var need_clean: bool = s.goto == "home" or s.goto == "pier" or s.goto == "docks" or s.goto == "airfield"
		if pp.distance_to(waypoint) < 14.0:
			if game.police.pursuit and need_clean and step > 0:
				message.emit("Lose the cops first!", 2.0)
			elif game.player.speed < 12.0 or not need_clean:
				game.audio.play_oneshot("beep")
				_next_step()
			else:
				message.emit("Slow down to stop here", 1.0)
	elif s.has("wait"):
		var at: Vector2 = waypoint if waypoint != Vector2.INF else pp
		if s.has("alarm") and step_t > float(s.alarm) and not game.police.pursuit:
			game.police.start_pursuit("ALARM TRIGGERED", 1)
		if step_t >= float(s.wait):
			message.emit("Crew's in - GO GO GO!", 3.0)
			_next_step()
	elif s.has("evade"):
		if not game.police.pursuit:
			_next_step()

func _complete_contract(ok: bool, why := "") -> void:
	var c := active
	active = {}
	waypoint = Vector2.INF
	game.police.min_heat = 0
	var res := {"kind": "contract", "title": c.title, "ok": ok, "reward": 0, "why": why}
	if ok:
		var reward: int = c.reward
		if game.daynight.night > 0.5:
			reward = int(reward * 1.25)
		res.reward = reward
		Save.add_cash(reward)
		Save.data.rep = int(Save.data.rep) + 1
		if contract_index() < CONTRACTS.size() and c.title == CONTRACTS[contract_index()].title:
			Save.data.contract = contract_index() + 1
		Save.save_game()
	call_timer = 45.0
	finished.emit(res)

func abandon() -> void:
	if race:
		race.cleanup()
		race = null
	if not active.is_empty():
		_complete_contract(false, "Abandoned")

# ---------------------------------------------------------------- races
func race_near(p: Vector2) -> String:
	if not active.is_empty() or race != null:
		return ""
	for m in race_markers:
		if p.distance_to(m.pos) < 14.0:
			return m.id
	return ""

func start_race(id: String, need_place := 1) -> void:
	race = RaceSession.new()
	race.need_place = need_place
	add_child(race)
	race.start(game, world, id, RACES[id])

func _race_finished(r: Dictionary) -> void:
	race.cleanup()
	race.queue_free()
	race = null
	var place: int = r.place
	var def: Dictionary = RACES[r.id]
	var mult: float = [1.0, 0.5, 0.3, 0.15, 0.1, 0.08][clampi(place - 1, 0, 5)]
	var reward := int(def.reward * mult)
	if game.daynight.night > 0.5:
		reward = int(reward * 1.25)
	Save.add_cash(reward)
	if place == 1:
		Save.data.races_won = int(Save.data.races_won) + 1
		var best: float = Save.data.best.get(r.id, INF)
		if r.time < best:
			Save.data.best[r.id] = r.time
	Save.save_game()
	var res := {"kind": "race", "title": def.name, "place": place, "total": r.total, "time": r.time, "reward": reward, "ok": place <= r.need}
	if not active.is_empty():
		var s: Dictionary = active.steps[step]
		if s.has("race"):
			if place <= int(s.get("place", 1)):
				res.contract_next = true
				finished.emit(res)
				_next_step()
				return
			else:
				finished.emit(res)
				_complete_contract(false, "Lost the race")
				return
	finished.emit(res)
