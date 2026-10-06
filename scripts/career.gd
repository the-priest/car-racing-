class_name Career
extends Node3D
## Contracts (phone calls from your fixer), street races, speed traps and the
## GPS waypoint. Contracts are step lists: goto / wait / heat / evade / race / takedown.

signal message(text: String, seconds: float, key: String)
signal dialogue(lines: Array)
signal dialogue_clear
signal title_card(top: String, title: String, sub: String)
signal story_complete
signal big(text: String, seconds: float)
signal phone_ring(caller: String)
signal finished(result: Dictionary)

const LOC := {
	"home": Vector2(-420, 365), "lot": Vector2(250, -365), "docks": Vector2(0, 1330),
	"harbor_bank": Vector2(-180, 485), "first_bank": Vector2(60, -125), "reserve": Vector2(185, 5),
	"quarry": Vector2(350, -2700), "airfield": Vector2(2300, 760), "farm": Vector2(-2520, 720),
	"overpass": Vector2(1100, 0), "chop_shop": Vector2(485, 300), "pier": Vector2(-750, 1500),
	"depot": Vector2(-480, -480), "west_gate": Vector2(-1610, 0),
}
const LOC_NAMES := {
	"home": "your garage", "lot": "the downtown lot", "docks": "the docks", "harbor_bank": "Harbor Savings",
	"first_bank": "First National", "reserve": "the Federal Reserve", "quarry": "the quarry", "airfield": "the airfield",
	"farm": "the valley farm", "overpass": "the east overpass", "chop_shop": "Dex's chop shop", "pier": "the pier",
	"depot": "the cash depot", "west_gate": "the west highway",
}

## Speaker colours for dialogue ("Name: line").
const SPEAKERS := {
	"Mara": Color(1.0, 0.62, 0.25), "Dex": Color(0.45, 1.0, 0.55), "Sable": Color(0.78, 0.5, 1.0),
	"Kane": Color(0.45, 0.7, 1.0), "Dispatch": Color(0.55, 0.85, 1.0), "Juno": Color(1.0, 0.45, 0.7),
	"Rook": Color(1.0, 0.85, 0.4),
}

const ACTS := ["ACT I  ·  NEW IN TOWN", "ACT II  ·  THE CREW", "ACT III  ·  BURNED", "EPILOGUE  ·  LEGEND"]

const PROLOGUE := [
	"Solano Bay. Neon, money and three hundred kilometres of road.",
	"The Night Kings run the streets. Lieutenant Kane's task force runs the cops.",
	"You just rolled into town with one car and a reputation. Keep your phone close.",
]

## Story contracts. Steps: goto / wait / heat / evade / race / takedown; any step
## can carry "say" lines played as it starts. "outro" plays on success.
const CONTRACTS := [
	# ---------------------------------------------------------------- ACT I
	{"title": "Wheels", "caller": "Mara", "reward": 4000, "act": 0,
		"brief": ["Mara: So you're the driver everyone keeps whispering about.", "Mara: I'm Mara. I find drivers for people who can't afford to get caught.",
			"Mara: Simple test. There's a car at the downtown lot. Get it to the docks before my buyer gets bored."],
		"steps": [{"goto": "lot", "label": "Pick up the car at the lot"},
			{"goto": "docks", "label": "Deliver it to the docks", "time": 120, "say": ["Mara: Clock's running. Don't scratch it. Well... don't scratch it much."]}],
		"outro": ["Mara: Not bad. Not bad at all.", "Mara: Keep your phone on. I'll have real work soon."]},
	{"title": "Proving Ground", "caller": "Mara", "reward": 6000,
		"brief": ["Mara: Nobody hires a driver they've never heard of.", "Mara: The Night Kings run a circuit downtown. Win it and the whole city hears your name.",
			"Mara: Watch out for Rook. He drives dirty."],
		"steps": [{"race": "downtown", "place": 1, "boss": "rook",
			"say": ["Rook: Fresh meat. Sable's gonna love hearing about this.", "Rook: Try to keep up, tourist."]}],
		"outro": ["Rook: ...Who ARE you?", "Mara: That was Sable's crew you just embarrassed. Good. Let him notice you."]},
	{"title": "Hot Plates", "caller": "Dex", "reward": 7000,
		"brief": ["Dex: Yo. Dex. Mara's mechanic, smuggler, therapist. Mostly mechanic.", "Dex: There's a hot car at my chop shop that needs to disappear into your garage.",
			"Dex: Fair warning: half the cops in the city are looking for it."],
		"steps": [{"goto": "chop_shop", "label": "Grab the hot car at Dex's"},
			{"heat": 2, "say": ["Dispatch: All units, stolen vehicle leaving the east side. Respond."]},
			{"evade": true, "label": "Lose the cops"},
			{"goto": "home", "label": "Hide it in your garage", "say": ["Dex: Smooth. Now bring it home and keep the door shut."]}],
		"outro": ["Dex: Beautiful. Your garage is my garage now. Upgrades, paint, whatever you need.", "Dex: Mara's got big plans for you. Try not to die."]},
	# ---------------------------------------------------------------- ACT II
	{"title": "Harbor Savings", "caller": "Mara", "reward": 15000, "act": 1,
		"brief": ["Mara: First real job. A crew's hitting Harbor Savings.", "Mara: Park out front, wait for them, then get everyone to the docks in one piece."],
		"steps": [{"goto": "harbor_bank", "label": "Pull up at Harbor Savings"},
			{"wait": 12, "label": "The crew is inside...", "alarm": 6, "say": ["Mara: Engine running. Eyes on the mirrors."]},
			{"heat": 3, "say": ["Kane: This is Lieutenant Kane, Heat Task Force.", "Kane: Whoever's driving that car - I'll be seeing you very soon."]},
			{"evade": true, "label": "Shake the cops"},
			{"goto": "docks", "label": "Drop the crew at the docks", "say": ["Mara: That's Kane. She's never lost a driver. Let's not be her first."]}],
		"outro": ["Mara: Everyone's out, everyone's paid. You're officially a getaway driver.", "Mara: Kane's going to remember your car. Paint it if you're nervous."]},
	{"title": "Armored Run", "caller": "Mara", "reward": 22000,
		"brief": ["Mara: There's a cash truck leaving the Reserve for the airfield.", "Mara: Catch it and ram it until it gives up. The crew does the rest.",
			"Mara: It's built like a bank vault on wheels. Hit it hard and hit it often."],
		"steps": [{"goto": "reserve", "label": "Get to the Reserve"},
			{"takedown": "armored", "from": "reserve", "to": "airfield", "hits": 5, "label": "Ram the armored truck",
				"say": ["Mara: There it is! Don't let it reach the airfield!"]},
			{"wait": 8, "label": "Crew is cracking the truck...", "alarm": 3, "here": true},
			{"heat": 3, "say": ["Kane: Cash truck down on the east side. Same car as Harbor Savings. Get me that driver!"]},
			{"evade": true, "label": "Lose the cops"},
			{"goto": "chop_shop", "label": "Bring the cash to Dex's"}],
		"outro": ["Dex: That truck's a pancake. I love it.", "Mara: Best haul in years. People are starting to talk about you."]},
	{"title": "Ring King", "caller": "Mara", "reward": 14000,
		"brief": ["Mara: Juno runs the ring road for the Night Kings. Fastest driver Sable has.", "Mara: Beat her and Sable has nobody left to hide behind."],
		"steps": [{"race": "ring", "place": 1, "boss": "juno",
			"say": ["Juno: So you're Mara's new toy. Let's see what you've got on a real road."]}],
		"outro": ["Juno: ...Fine. You're fast. Sable won't like this.", "Juno: Watch your back. He doesn't lose gracefully."]},
	{"title": "Mountain Courier", "caller": "Dex", "reward": 14000,
		"brief": ["Dex: Package for the quarry at the top of Summit Pass.", "Dex: Don't ask what's in it. Do ask why the cops keep sniffing around it."],
		"steps": [{"goto": "overpass", "label": "Collect the package"},
			{"goto": "quarry", "label": "Deliver it to the quarry", "time": 190, "heat_mid": 2,
				"say": ["Dex: Up the hairpins. Brake late, but brake."]}],
		"outro": ["Dex: Delivered. And nobody died! Personal best for this job."]},
	{"title": "First National", "caller": "Mara", "reward": 30000,
		"brief": ["Mara: Downtown. First National. Big score, big heat.", "Mara: Wait for the crew, lose Kane, run them out to the airfield hangar."],
		"steps": [{"goto": "first_bank", "label": "Pull up at First National"},
			{"wait": 15, "label": "The crew is inside...", "alarm": 5},
			{"heat": 4, "say": ["Kane: All units, First National. This is the one I want. Interceptors, go."]},
			{"evade": true, "label": "Lose the cops"},
			{"goto": "airfield", "label": "Get to the airfield hangar"}],
		"outro": ["Mara: That's the biggest job this city's seen in a decade.", "Mara: One more score like that and we can all retire.", "Mara: ...Which is exactly when things go wrong."]},
	# ---------------------------------------------------------------- ACT III
	{"title": "Valley Run", "caller": "Dex", "reward": 18000, "act": 2,
		"brief": ["Dex: Cargo plane just landed. The valley farm wants it yesterday.", "Dex: And, uh... someone saw Sable having coffee with Kane's people. Just saying."],
		"steps": [{"goto": "airfield", "label": "Pick up the cargo"},
			{"goto": "farm", "label": "Deliver to the valley farm", "time": 250, "heat_mid": 2}],
		"outro": ["Dex: Made it. Mara says she's not worried about Sable.", "Dex: Mara always says that right before she's worried."]},
	{"title": "Summit Showdown", "caller": "Sable", "reward": 24000,
		"brief": ["Sable: You've been busy. Beating my drivers. Stealing my city.", "Sable: Summit Pass. You and me. Winner owns these streets."],
		"steps": [{"race": "summit", "place": 1, "boss": "sable",
			"say": ["Sable: No crew, no Mara. Just you and the mountain."]}],
		"outro": ["Sable: Enjoy it, driver.", "Sable: You won't be driving much longer."]},
	{"title": "Burned", "caller": "Mara", "reward": 20000,
		"brief": ["Mara: GET OUT. Kane's people are on their way to your garage RIGHT NOW.", "Mara: Sable sold us out. He gave them everything.",
			"Mara: Lose them and get to the safehouse at the valley farm."],
		"steps": [{"heat": 4, "kane": true, "say": ["Kane: There you are. Every unit, every road. Nobody leaves the city."]},
			{"evade": true, "label": "Escape Kane's ambush"},
			{"goto": "farm", "label": "Reach the safehouse at the farm", "time": 260}],
		"outro": ["Mara: You made it. Good.", "Mara: Sable has a car stashed at the pier. He's going to run.", "Mara: Let's go have a word with him."]},
	{"title": "Payback", "caller": "Mara", "reward": 26000,
		"brief": ["Mara: Sable's bolting from the pier for the mountain.", "Mara: Run him down. I want him stopped, not escaped."],
		"steps": [{"goto": "pier", "label": "Get to the pier"},
			{"takedown": "sable", "from": "pier", "to": "quarry", "hits": 6, "label": "Take Sable down",
				"say": ["Sable: You?! You should be in a cell by now!", "Mara: Stop him before he reaches the mountain!"]},
			{"wait": 4, "label": "Mara is having a word with Sable...", "here": true,
				"say": ["Sable: Okay! OKAY! Kane's planning a trap at the Reserve...", "Sable: She wants all of you there. I was supposed to bring you in."]},
			{"heat": 3},
			{"evade": true, "label": "Lose the cops"}],
		"outro": ["Mara: So Kane wants a show at the Reserve.", "Mara: Then let's give her one. Biggest vault in Solano Bay.", "Mara: Last job, driver. Then we disappear."]},
	{"title": "The Reserve", "caller": "Mara", "reward": 80000,
		"brief": ["Mara: This is it. The Federal Reserve.", "Mara: Kane will throw everything she has at us: roadblocks, helicopters, interceptors.",
			"Mara: Get the crew in, get the crew out, and get us to the pier. I trust you."],
		"steps": [{"goto": "reserve", "label": "Pull up at the Reserve"},
			{"wait": 18, "label": "The crew is cracking the vault...", "alarm": 4, "say": ["Kane: I knew you couldn't resist. Every unit to the Reserve. NOW."]},
			{"heat": 5, "kane": true, "say": ["Mara: They're out! GO GO GO!"]},
			{"evade": true, "label": "Lose every cop in the city"},
			{"goto": "pier", "label": "Get the crew to the pier"}],
		"outro": ["Kane: ...All units, stand down. They're gone.", "Mara: We did it. We actually did it.", "Mara: Solano Bay is yours, driver. Don't let it get boring."]},
	# ---------------------------------------------------------------- EPILOGUE
	{"title": "Legend", "caller": "Juno", "reward": 50000, "act": 3,
		"brief": ["Juno: Sable's gone. The Night Kings need someone at the top.", "Juno: One last race. The Grand Tour, the whole map. Beat me and the crown is yours."],
		"steps": [{"race": "grand", "place": 1, "boss": "juno", "say": ["Juno: No holding back this time."]}],
		"outro": ["Juno: Long live the king of Solano Bay.", "Mara: Phone's still on, driver. There's always another job."]},
]

## Messages that arrive in free roam after a chapter, before the next job call.
const FLAVOR := {
	0: ["Unknown: Saw you at the docks. Smooth. The Night Kings noticed. - R"],
	2: ["Dex: Pro tip: jobs at night pay a quarter more. The cops are meaner, but... money."],
	3: ["Kane: (voicemail) This is Lieutenant Kane. I've seen your car.", "Kane: I never forget a car."],
	5: ["Juno: You drive like you've got nothing to lose.", "Juno: Careful. That's exactly the kind of driver Sable likes to use."],
	7: ["Mara: Lay low for a bit. Kane has the whole task force out tonight.", "Mara: Go cruise the mountain. Clear your head."],
	9: ["Dex: Sable looked rattled after that race. Rattled people do stupid things."],
	11: ["Juno: Heard what you did to Sable.", "Juno: The Night Kings are... reconsidering who they follow."],
}

## Named rivals for story races.
const BOSSES := {
	"rook": {"name": "ROOK", "car": "stallion", "paint": Color(0.85, 0.65, 0.1), "skill": 0.02, "taunt": "Rook: Ha! Go home, tourist."},
	"juno": {"name": "JUNO", "car": "vanta_r", "paint": Color(0.95, 0.2, 0.55), "skill": 0.04, "taunt": "Juno: Cute. Come back when you're serious."},
	"sable": {"name": "SABLE", "car": "wedge", "paint": Color(0.22, 0.04, 0.36), "skill": 0.06, "taunt": "Sable: This city's mine. It always was."},
}

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

## Drift zones: drive from start to end scoring drift points within the time limit.
const DRIFT_ZONES := [
	{"name": "Summit Switchbacks", "a": Vector2(620, -1950), "b": Vector2(350, -2700), "roads": ["pass"], "time": 120.0},
	{"name": "Midtown Slide", "a": Vector2(480, 480), "b": Vector2(-480, -120), "roads": ["city"], "time": 90.0},
	{"name": "Valley Sweepers", "a": Vector2(-2050, 420), "b": Vector2(-2680, 300), "roads": ["country"], "time": 100.0},
]

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
var target: MissionTarget
var wait_pos := Vector2.INF
var away_warned := 0.0
var last_failed: Dictionary = {}
var kane_pending := 0.0
var alarm_sent := false
var wait_left := -1.0
var drift_markers: Array = [] # {i, a, b, node}
var billboards: Array = [] # {i, pos: Vector3, node}
const BILLBOARD_COUNT := 20
var drift_zone := -1 # active zone index
var drift_zone_t := 0.0
var drift_zone_base := 0.0

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
	for i in DRIFT_ZONES.size():
		var z: Dictionary = DRIFT_ZONES[i]
		var a2: Vector2 = world.node_pos[world.nearest_node(z.a, z.roads)]
		var b2: Vector2 = world.node_pos[world.nearest_node(z.b, z.roads)]
		var dm := _beam(Color(1.0, 0.55, 0.1), 2.6)
		dm.position = pos3(a2)
		add_child(dm)
		drift_markers.append({"i": i, "a": a2, "b": b2, "node": dm})
	_build_billboards()
	# Speed camera poles at each trap.
	var pole_m := StandardMaterial3D.new()
	pole_m.albedo_color = Color(0.25, 0.26, 0.28)
	pole_m.metallic = 0.6
	var cam_m := StandardMaterial3D.new()
	cam_m.albedo_color = Color(0.95, 0.95, 1.0)
	cam_m.emission_enabled = true
	cam_m.emission = Color(0.9, 0.95, 1.0)
	cam_m.emission_energy_multiplier = 2.5
	for tp in SPEED_TRAPS:
		var nid2 := world.nearest_node(tp)
		var np: Vector2 = world.node_pos[nid2]
		var rd: Vector2 = (world.node_pos[world.adj[nid2][0]] - np).normalized()
		var base := pos3(tp + Vector2(-rd.y, rd.x) * (10.0 if world.in_city(tp.x, tp.y) else 12.5))
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.09
		cyl.bottom_radius = 0.12
		cyl.height = 5.0
		pole.mesh = cyl
		pole.material_override = pole_m
		pole.position = base + Vector3(0, 2.5, 0)
		add_child(pole)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.4, 0.7)
		box.mesh = bm
		box.material_override = cam_m
		box.position = base + Vector3(0, 5.1, 0)
		add_child(box)

func pos3(p: Vector2) -> Vector3:
	var y := world.drive_y(p.x, p.y)
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

func story_done() -> bool:
	return contract_index() >= CONTRACTS.size()

func idle() -> bool:
	return active.is_empty() and race == null

func update(dt: float) -> void:
	var p: Car = game.player
	var pp := Vector2(p.global_position.x, p.global_position.z)
	home_marker.visible = idle()
	for m in race_markers:
		m.node.visible = idle()
	for dm in drift_markers:
		dm.node.visible = idle() and drift_zone < 0
	_update_drift_zone(dt, pp)
	_update_billboards()
	# Incoming calls when idle (not mid-pursuit: the fixer waits until you're clean).
	if idle() and pending_call < 0 and not game.police.pursuit:
		call_timer -= dt
		if call_timer <= 0.0:
			pending_call = contract_index() if not story_done() else 100 + randi() % 3
			ringing = 20.0
			phone_ring.emit(_caller(pending_call))
	if pending_call >= 0 and ringing > 0.0:
		ringing -= dt
		if ringing <= 0.0:
			message.emit("Missed call - press [%s] to call back" % Settings.glyph("phone"), 4.0, "")
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
				message.emit("New record! +$%d" % cash, 2.5, "")
				game.audio.play_oneshot("reward")
			else:
				message.emit("Speed trap %d km/h  (best %d)" % [kmh, best], 2.5, "")
	for k in trap_cool.keys():
		trap_cool[k] -= dt
	if race:
		race.update(dt)
		waypoint = Vector2.INF
		if race.done:
			_race_finished(race.result)
		return
	if kane_pending > 0.0:
		kane_pending -= dt
		if kane_pending <= 0.0 and game.police.pursuit:
			game.police.spawn_kane()
	if not active.is_empty():
		_update_contract(dt, pp)
	beacon.visible = waypoint != Vector2.INF and target == null
	if beacon.visible:
		beacon.position = pos3(waypoint)

## Hidden smashable billboards beside roads across the map (same layout every game).
func _build_billboards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var frame_m := StandardMaterial3D.new()
	frame_m.albedo_color = Color(0.2, 0.21, 0.23)
	frame_m.metallic = 0.5
	var colors := [Color(1.0, 0.45, 0.1), Color(0.1, 0.8, 1.0), Color(1.0, 0.2, 0.6), Color(0.6, 1.0, 0.2)]
	var found: Array = Save.data.get("billboards", []).map(func(x): return int(x))
	var placed := 0
	var tries := 0
	while placed < BILLBOARD_COUNT and tries < 2000:
		tries += 1
		var id := rng.randi() % world.node_pos.size()
		var np := world.node_pos[id]
		var t := world.node_type_name(id)
		if t == "runway" or world.adj[id].is_empty():
			continue
		var too_close := false
		for b in billboards:
			if Vector2(b.pos.x, b.pos.z).distance_to(np) < 450.0:
				too_close = true
		if too_close:
			continue
		var nb := world.node_pos[world.adj[id][0]]
		var dir := (nb - np).normalized()
		var side := Vector2(-dir.y, dir.x) * (11.0 if t == "city" else 13.0)
		var p2 := np + side
		var base := pos3(p2)
		var root := Node3D.new()
		root.position = base
		# Face the road, angled toward oncoming drivers.
		var face := (-side.normalized() - dir).normalized()
		root.rotation.y = atan2(face.x, face.y)
		add_child(root)
		var panel_m := StandardMaterial3D.new()
		var col: Color = colors[placed % colors.size()]
		panel_m.albedo_color = col.darkened(0.3)
		panel_m.emission_enabled = true
		panel_m.emission = col
		panel_m.emission_energy_multiplier = 1.4
		for spec in [[Vector3(-1.6, 2.2, 0), Vector3(0.18, 4.4, 0.18), frame_m], [Vector3(1.6, 2.2, 0), Vector3(0.18, 4.4, 0.18), frame_m],
				[Vector3(0, 4.6, 0), Vector3(4.6, 2.2, 0.2), panel_m], [Vector3(0, 3.42, 0.12), Vector3(4.6, 0.16, 0.05), frame_m]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = spec[1]
			mi.mesh = bm
			mi.material_override = spec[2]
			mi.position = spec[0]
			root.add_child(mi)
		var ads := ["HEAT FM 101.7", "DEX'S GARAGE", "SOLANO BAY\nNEVER SLEEPS", "NIGHT KINGS", "DRIVE FAST\nLIVE FASTER", "VANTA\nMOTORS", "STALLION\nSINCE '69", "HARBOR\nSAVINGS"]
		var lbl := Label3D.new()
		lbl.text = ads[placed % ads.size()]
		lbl.font_size = 96
		lbl.pixel_size = 0.007
		lbl.outline_size = 12
		lbl.modulate = Color.WHITE
		lbl.position = Vector3(0, 4.6, 0.12)
		root.add_child(lbl)
		var lbl2 := lbl.duplicate() as Label3D
		lbl2.position = Vector3(0, 4.6, -0.12)
		lbl2.rotation.y = PI
		root.add_child(lbl2)
		root.visible = not found.has(placed)
		billboards.append({"i": placed, "pos": base, "node": root})
		placed += 1

func _update_billboards() -> void:
	var p: Car = game.player
	if p.speed < 12.0:
		return
	for b in billboards:
		if not b.node.visible:
			continue
		if p.global_position.distance_to(b.pos + Vector3(0, 1.0, 0)) < 5.0:
			b.node.visible = false
			_shatter(b.node, p.linear_velocity)
			var found: Array = Save.data.get("billboards", []).map(func(x): return int(x))
			if not found.has(b.i):
				found.append(b.i)
				Save.data.billboards = found
			Save.add_cash(2000)
			Save.save_game()
			game.audio.play_oneshot("impact", 1.3)
			game.audio.play_oneshot("reward")
			game.cam.shake = maxf(game.cam.shake, 0.4)
			big.emit("BILLBOARD  %d / %d" % [found.size(), BILLBOARD_COUNT], 1.8)
			message.emit("+$2,000", 2.0, "")

## Debris burst: copies of the billboard panel pieces fly off and fade.
func _shatter(node: Node3D, vel: Vector3) -> void:
	var mat: Material = null
	for c in node.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D and ((c as MeshInstance3D).material_override as StandardMaterial3D).emission_enabled:
			mat = (c as MeshInstance3D).material_override
	for i in 10:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.5, 1.4), randf_range(0.4, 1.0), 0.08)
		mi.mesh = bm
		mi.material_override = mat
		add_child(mi)
		var start := node.global_position + Vector3(randf_range(-2.0, 2.0), randf_range(3.6, 5.6), 0)
		mi.global_position = start
		var fly := vel * randf_range(0.25, 0.5) + Vector3(randf_range(-6, 6), randf_range(4, 9), randf_range(-6, 6))
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "global_position", start + fly * 0.6 + Vector3(0, -2.0, 0), 0.6).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "rotation", Vector3(randf() * 8.0, randf() * 8.0, randf() * 8.0), 1.4)
		tw.chain().tween_property(mi, "global_position", start + fly * 0.9 + Vector3(0, -start.y + node.global_position.y, 0), 0.8).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)

func drift_zone_score() -> int:
	return maxi(0, int(game.drift.total + game.drift.chain - drift_zone_base))

func _update_drift_zone(dt: float, pp: Vector2) -> void:
	if drift_zone < 0:
		if not idle() or game.police.pursuit:
			return
		for dm in drift_markers:
			if pp.distance_to(dm.a) < 14.0 and game.player.speed > 5.0:
				drift_zone = dm.i
				drift_zone_t = float(DRIFT_ZONES[dm.i].time)
				# Score starts fresh at the gate: bank nothing from a chain already running.
				game.drift.chain = 0.0
				game.drift.mult = 1
				game.drift.time = 0.0
				drift_zone_base = game.drift.total
				waypoint = dm.b
				waypoint_label = "Drift to the end of " + str(DRIFT_ZONES[dm.i].name)
				big.emit("DRIFT ZONE", 1.5)
				game.tip("drift", "Drift zone: score drift points before you reach the end gate. While steering, lift off the throttle and stab it again to start a drift.")
				message.emit("%s - drift all the way to the end" % DRIFT_ZONES[dm.i].name, 3.0, "")
				game.audio.play_oneshot("beep", 1.5)
				return
		return
	var dmk: Dictionary = drift_markers[drift_zone]
	drift_zone_t -= dt
	if not idle() or game.police.pursuit:
		message.emit("Drift zone cancelled", 2.0, "")
		_end_drift_zone()
		return
	if drift_zone_t <= 0.0:
		message.emit("Drift zone: out of time", 2.5, "")
		_end_drift_zone()
		return
	if pp.distance_to(dmk.b) < 16.0:
		var score := drift_zone_score()
		var key := "drift%d" % drift_zone
		var best: int = int(Save.data.best.get(key, 0))
		var cash := score / 15
		Save.add_cash(cash)
		big.emit("DRIFT ZONE  %s" % HUD._fmt(score), 2.5)
		message.emit(("NEW BEST! " if score > best else "Best %s  ·  " % HUD._fmt(best)) + "+$%s" % HUD._fmt(cash), 3.5, "")
		if score > best:
			Save.data.best[key] = score
		Save.save_game()
		game.audio.play_oneshot("reward")
		_end_drift_zone()

func _end_drift_zone() -> void:
	# Only clear the waypoint if it's still ours (a job may have set its own).
	if drift_zone >= 0 and waypoint == drift_markers[drift_zone].b:
		waypoint = Vector2.INF
	drift_zone = -1

func _caller(idx: int) -> String:
	if idx >= 100:
		return ["Mara", "Dex", "Unknown number"][idx - 100]
	return CONTRACTS[idx].caller

func call_title(idx: int) -> String:
	return CONTRACTS[idx].title if idx < CONTRACTS.size() else "Side job"

func answer_phone() -> Array:
	## Returns briefing lines (or empty if no call). With no call waiting, you
	## ring your contact yourself and they call back in a moment.
	if not idle():
		return []
	if pending_call < 0:
		if game.police.pursuit:
			message.emit("Lose the cops before making calls", 2.5, "")
			return []
		call_timer = minf(call_timer, 2.5)
		message.emit("Calling %s..." % _caller(contract_index() if not story_done() else 100), 2.5, "")
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
	var kind := randi() % 4
	if kind == 0:
		var banks := ["harbor_bank", "first_bank", "reserve"]
		var bank: String = banks[randi() % 3]
		return {"title": "Bank Job", "caller": "Mara", "reward": 14000 + randi() % 14000,
			"brief": ["Mara: Another crew needs a driver. Same drill as always.", "Mara: %s, then drop them at %s." % [LOC_NAMES[bank].capitalize(), LOC_NAMES[b]]],
			"steps": [{"goto": bank, "label": "Pull up at " + LOC_NAMES[bank]}, {"wait": 12, "label": "The crew is inside...", "alarm": 5}, {"heat": 3 + randi() % 3}, {"evade": true, "label": "Lose the cops"}, {"goto": b, "label": "Drop the crew at " + LOC_NAMES[b]}],
			"outro": ["Mara: Clean work. As always."]}
	elif kind == 1:
		var d := pos_of(a).distance_to(pos_of(b))
		return {"title": "Hot Delivery", "caller": "Dex", "reward": 5000 + int(d * 2.5),
			"brief": ["Dex: Got a package that can't wait. Pick-up at %s, drop at %s." % [LOC_NAMES[a], LOC_NAMES[b]]],
			"steps": [{"goto": a, "label": "Collect the package at " + LOC_NAMES[a]}, {"goto": b, "label": "Deliver it to " + LOC_NAMES[b], "time": int(45 + d / 22.0), "heat_mid": 1 + randi() % 2}],
			"outro": ["Dex: Right on time. You're spoiling me."]}
	elif kind == 2:
		var far: Array = keys.filter(func(k): return pos_of(k).distance_to(pos_of(a)) > 1200.0)
		if not far.is_empty():
			b = far[randi() % far.size()]
		return {"title": "Cash Truck", "caller": "Mara", "reward": 20000 + randi() % 10000,
			"brief": ["Mara: Cash truck rolling out of %s. Stop it, the crew does the rest." % LOC_NAMES[a]],
			"steps": [{"goto": a, "label": "Get to " + LOC_NAMES[a]}, {"takedown": "armored", "from": a, "to": b, "hits": 5, "label": "Ram the armored truck"},
				{"wait": 6, "label": "Crew is cracking the truck...", "alarm": 2, "here": true}, {"heat": 3}, {"evade": true, "label": "Lose the cops"}],
			"outro": ["Mara: Another truck, another payday."]}
	var rid: String = RACES.keys()[randi() % RACES.size()]
	return {"title": "Street Race", "caller": "Unknown number", "reward": RACES[rid].reward,
		"brief": ["Unknown: Heard you're the one to beat. %s. Show up or shut up." % RACES[rid].name], "steps": [{"race": rid, "place": 1}]}

func pos_of(key: String) -> Vector2:
	return LOC[key]

func _start_contract(c: Dictionary) -> void:
	if drift_zone >= 0:
		_end_drift_zone()
	active = c
	step = -1
	var idx := -1
	for i in CONTRACTS.size():
		if CONTRACTS[i].title == c.title:
			idx = i
	if idx >= 0:
		var act := 0
		for i in idx + 1:
			if CONTRACTS[i].has("act"):
				act = int(CONTRACTS[i].act)
		title_card.emit(ACTS[act], c.title.to_upper(), "CHAPTER %d  ·  %s" % [idx + 1, c.caller.to_upper()])
	else:
		title_card.emit("SIDE JOB", c.title.to_upper(), "FOR %s  ·  $%s" % [str(c.caller).to_upper(), HUD._fmt(int(c.reward))])
	_next_step()

func _next_step() -> void:
	step += 1
	step_t = 0.0
	time_left = INF
	waypoint = Vector2.INF
	wait_pos = Vector2.INF
	alarm_sent = false
	wait_left = -1.0
	if step >= active.steps.size():
		_complete_contract(true)
		return
	var s: Dictionary = active.steps[step]
	if s.has("say"):
		dialogue.emit(s.say)
	if s.has("goto"):
		waypoint = pos_of(s.goto)
		waypoint_label = s.label
		if s.has("time"):
			time_left = float(s.time) * float(Settings.diff(1.3, 1.0, 0.9))
	elif s.has("wait"):
		waypoint_label = s.label
		if not s.get("here", false) and step > 0 and active.steps[step - 1].has("goto"):
			wait_pos = pos_of(active.steps[step - 1].goto)
	elif s.has("heat"):
		game.police.min_heat = int(s.heat)
		game.police.start_pursuit("THE COPS ARE COMING", int(s.heat))
		if s.get("kane", false):
			kane_pending = 6.0
		_next_step()
	elif s.has("evade"):
		waypoint_label = s.label
	elif s.has("race"):
		start_race(s.race, s.get("place", 1), s.get("boss", ""))
	elif s.has("takedown"):
		waypoint_label = s.label
		target = MissionTarget.new()
		add_child(target)
		target.start(game, world, s.takedown, pos_of(s.from), pos_of(s.to), int(s.hits) + int(Settings.diff(-1, 0, 1)))
		target.was_hit.connect(_on_target_hit)
		game.tip("takedown", "Ram the target hard and often. The bar under your objective shows the hits left before it's disabled.")
		waypoint = target.pos2()

func _on_target_hit(hits: int, need: int) -> void:
	game.audio.play_oneshot("impact", 0.8)
	game.cam.shake = maxf(game.cam.shake, 0.5)
	game._rumble(0.9, 0.6, 0.3)
	if hits == 2 and target.def.name == "ARMORED TRUCK" and not game.police.pursuit:
		message.emit("The guards called it in - cops are on the way", 2.5, "")
		game.police.say("Dispatch: Armored car under attack on %s! All units, respond!" % game.police.area_name(target.car.global_position), true)
	if hits >= need:
		game.slowmo(0.8)
		big.emit("%s DISABLED" % target.def.name, 2.0)
		game.audio.play_oneshot("reward")
	else:
		message.emit("HIT!  %d / %d" % [hits, need], 1.2, "hit")

func target_text() -> String:
	if target == null:
		return ""
	return "%s  %s" % [target.def.name, "■".repeat(target.need - target.hits) + "□".repeat(target.hits)]

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
		if s.has("heat_mid") and step_t > 35.0 and not game.police.pursuit and step_t < 36.0:
			game.police.start_pursuit("COPS SPOTTED THE PACKAGE", int(s.heat_mid))
		var need_clean: bool = s.goto in ["home", "pier", "docks", "airfield", "farm", "chop_shop"]
		if pp.distance_to(waypoint) < 16.0:
			if game.police.pursuit and need_clean and step > 0:
				if away_warned <= 0.0:
					message.emit("Lose the cops first - don't lead them here!", 2.0, "")
					away_warned = 2.5
			elif game.player.speed < 14.0 or not need_clean:
				game.audio.play_oneshot("beep")
				_next_step()
			elif away_warned <= 0.0:
				message.emit("Slow down to stop here", 1.0, "")
				away_warned = 1.2
		away_warned -= dt
	elif s.has("wait"):
		if wait_pos != Vector2.INF and pp.distance_to(wait_pos) > 45.0:
			# Waiting for the crew means staying put.
			step_t -= dt
			waypoint = wait_pos
			if away_warned <= 0.0:
				message.emit("Get back to the pick-up - the crew needs you there!", 2.0, "")
				away_warned = 2.5
			away_warned -= dt
		else:
			waypoint = Vector2.INF
		if s.has("alarm") and step_t > float(s.alarm) and not alarm_sent:
			# Cops are inbound but arrive as the crew comes out (the heat step).
			alarm_sent = true
			big.emit("SILENT ALARM", 1.5)
			message.emit("Cops inbound - %d seconds" % int(float(s.wait) - step_t), 2.5, "")
			game.police.say("Dispatch: Silent alarm triggered. All units, respond code three.", true)
			game.audio.play_oneshot("beep", 0.7)
		wait_left = maxf(0.0, float(s.wait) - step_t)
		if step_t >= float(s.wait):
			wait_left = -1.0
			if not s.get("here", false):
				message.emit("Crew's in - GO GO GO!", 3.0, "")
			_next_step()
	elif s.has("evade"):
		if not game.police.pursuit:
			_next_step()
	elif s.has("takedown"):
		if target == null:
			return
		waypoint = target.pos2()
		if target.disabled:
			_end_target()
			_next_step()
		elif target.escaped:
			_end_target()
			_complete_contract(false, "The target got away")
		elif pp.distance_to(target.pos2()) > 1400.0:
			_end_target()
			_complete_contract(false, "You lost the target")

func _end_target() -> void:
	if target:
		var t := target
		target = null
		if not t.disabled:
			t.cleanup()
			t.queue_free()
			return
		# Leave a disabled truck sitting there for a few seconds before cleanup.
		get_tree().create_timer(12.0).timeout.connect(func():
			if is_instance_valid(t):
				t.cleanup()
				t.queue_free())

func _complete_contract(ok: bool, why := "") -> void:
	var c := active
	active = {}
	wait_left = -1.0
	waypoint = Vector2.INF
	game.police.min_heat = 0
	kane_pending = 0.0
	if target:
		_end_target()
	var res := {"kind": "contract", "title": c.title, "ok": ok, "reward": 0, "why": why}
	var story_idx := -1
	if contract_index() < CONTRACTS.size() and c.title == CONTRACTS[contract_index()].title:
		story_idx = contract_index()
	if ok:
		var reward: int = c.reward
		if game.daynight.night > 0.5:
			reward = int(reward * 1.25)
		res.reward = reward
		Save.add_cash(reward)
		Save.data.rep = int(Save.data.rep) + 1
		if story_idx >= 0:
			Save.data.contract = story_idx + 1
			for tier in Data.TIER_UNLOCK:
				if int(Data.TIER_UNLOCK[tier]) == story_idx + 1:
					get_tree().create_timer(4.0, true).timeout.connect(func(): message.emit("NEW CARS UNLOCKED: tier %s - visit your garage" % tier, 4.0, ""))
			if not Save.data.contracts_done.has(c.title):
				Save.data.contracts_done.append(c.title)
		Save.save_game()
		if c.has("outro"):
			dialogue.emit(c.outro)
		call_timer = 50.0
		if story_idx >= 0 and FLAVOR.has(story_idx):
			var lines: Array = FLAVOR[story_idx]
			get_tree().create_timer(24.0, false).timeout.connect(func():
				if idle():
					message.emit("New message from %s" % lines[0].split(":")[0], 2.5, "")
					game.audio.play_oneshot("beep", 1.6)
					dialogue.emit(lines))
		if story_idx == CONTRACTS.size() - 1:
			story_complete.emit()
	else:
		last_failed = c
		dialogue_clear.emit()
		var who: String = c.get("caller", "Mara")
		dialogue.emit(["%s: %s. Call me when you're ready to go again." % [who, why if why != "" else "That fell apart"]])
		call_timer = 20.0
	res.story = story_idx >= 0
	if ok:
		last_failed = {}
	finished.emit(res)

func retry() -> void:
	if last_failed.is_empty() or not idle():
		return
	var c := last_failed
	last_failed = {}
	pending_call = -1
	ringing = 0.0
	game.police.clear()
	_start_contract(c)

func abandon(why := "Abandoned") -> void:
	if race:
		race.cleanup()
		race.queue_free()
		race = null
	if not active.is_empty():
		_complete_contract(false, why)

# ---------------------------------------------------------------- races
func race_near(p: Vector2) -> String:
	if not idle():
		return ""
	for m in race_markers:
		if p.distance_to(m.pos) < 14.0:
			return m.id
	return ""

## Restarts the current race from the grid (same rivals setup, same story step).
func restart_race() -> void:
	if race == null:
		return
	var id := race.id
	var need := race.need_place
	var bk := race_boss_key
	race.cleanup()
	race.queue_free()
	race = null
	start_race(id, need, bk)

var race_boss_key := ""

func start_race(id: String, need_place := 1, boss := "") -> void:
	race_boss_key = boss
	if drift_zone >= 0:
		_end_drift_zone()
	race = RaceSession.new()
	race.need_place = need_place
	if boss != "":
		race.boss = BOSSES[boss]
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
	var in_contract: bool = not active.is_empty() and active.steps[step].has("race")
	if in_contract:
		reward = 0 # the contract pays instead
	Save.add_cash(reward)
	if place == 1:
		Save.data.races_won = int(Save.data.races_won) + 1
		var best: float = Save.data.best.get(r.id, INF)
		if r.time < best:
			Save.data.best[r.id] = r.time
	Save.save_game()
	var res := {"kind": "race", "title": def.name, "place": place, "total": r.total, "time": r.time, "reward": reward, "ok": place <= r.need, "order": r.get("order", [])}
	if not active.is_empty():
		var s: Dictionary = active.steps[step]
		if s.has("race"):
			if place <= int(s.get("place", 1)):
				res.contract_next = true
				finished.emit(res)
				_next_step()
				return
			else:
				var boss: String = s.get("boss", "")
				_complete_contract(false, "You lost the race (%s)" % ["1st", "2nd", "3rd", "4th", "5th", "6th"][clampi(place - 1, 0, 5)])
				if boss != "":
					dialogue_clear.emit()
					dialogue.emit([BOSSES[boss].taunt, "Mara: Shake it off. Call me when you want a rematch."])
				return
	finished.emit(res)
