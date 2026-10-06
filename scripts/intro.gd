class_name Intro
extends Node
## Opening cinematic for a new career: Solano Bay from the air, your car tearing
## down the Coastal Highway at sunset, then back home behind the wheel.
## The prologue plays as captions. Hold accept / pause to skip.

signal finished

const COAST_FROM := 186 # Coastal Highway points: down from the hills to the sea
const COAST_TO := 320
const FADE := 0.55

var game: Node
var shots: Array = [] # {dur, kind, caption, title}
var shot := -1
var t := 0.0
var hold := 0.0
var ending := false
var home_xf: Transform3D
var bot: AIDriver
var layer: CanvasLayer
var bars: Array[ColorRect] = []
var caption: Label
var title: Label
var skip_l: Label
var fade: ColorRect
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _orbit_c := Vector3.ZERO

func start(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	home_xf = game.player.global_transform
	_build_overlay()
	shots = [
		{"dur": 8.0, "kind": "city", "caption": Career.PROLOGUE[0]},
		{"dur": 7.5, "kind": "pass", "caption": Career.PROLOGUE[1]},
		{"dur": 6.5, "kind": "drone", "title": true},
		{"dur": 6.0, "kind": "home", "caption": Career.PROLOGUE[2]},
	]
	game.traffic.set_count(0)
	game.cam.process_mode = Node.PROCESS_MODE_DISABLED
	game.cam.fov = 55.0
	var g2: Vector2 = Vector2.ZERO
	_orbit_c = Vector3(g2.x, game.world.ground(g2.x, g2.y) + 45.0, g2.y)
	_next()

func _build_overlay() -> void:
	layer = CanvasLayer.new()
	layer.layer = 18
	add_child(layer)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else -110.0
		bar.offset_bottom = 110.0 if top else 0.0
		layer.add_child(bar)
		bars.append(bar)
	title = game.hud._label(118, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "VELOCITY HEAT"
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.offset_left = -900
	title.offset_right = 900
	title.offset_top = -120
	title.offset_bottom = 40
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	title.modulate.a = 0.0
	layer.add_child(title)
	caption = game.hud._label(28, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	caption.anchor_left = 0.5
	caption.anchor_right = 0.5
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_left = -720
	caption.offset_right = 720
	caption.offset_top = -92
	caption.offset_bottom = -20
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(caption)
	skip_l = game.hud._label(15, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_RIGHT)
	skip_l.anchor_left = 1.0
	skip_l.anchor_right = 1.0
	skip_l.offset_left = -520
	skip_l.offset_right = -32
	skip_l.offset_top = 42
	skip_l.offset_bottom = 70
	layer.add_child(skip_l)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)

func _next() -> void:
	shot += 1
	t = 0.0
	if shot >= shots.size():
		_finish()
		return
	var s: Dictionary = shots[shot]
	caption.text = str(s.get("caption", ""))
	caption.visible_ratio = 0.0
	var p: Car = game.player
	match str(s.kind):
		"pass":
			# Put the car on the coast road at speed; an AI driver takes it from there.
			var pts: Array = game.world.d.roads[0].pts
			var line := PackedVector2Array()
			for i in range(COAST_FROM, COAST_TO):
				line.append(Vector2(float(pts[i * 3]), float(pts[i * 3 + 2])))
			var path := RacePath.new(line, false, game.world)
			var a := path.at(4)
			var dir := path.dir(4)
			var fwd := Vector3(dir.x, 0, dir.y)
			var y: float = game.world.drive_y(a.x, a.y) + 0.7
			p.reset_to(Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(a.x, y, a.y)))
			p.linear_velocity = fwd * 36.0
			p.reset_physics_interpolation()
			bot = AIDriver.new(p, path, 0.72, 0.0)
			bot.idx = 4
		"home":
			bot = null
			_release_input()
			p.reset_to(home_xf)
			p.reset_physics_interpolation()
	_pos = _shot_pos(0.0)
	_look = _shot_look(0.0)

func _release_input() -> void:
	var p: Car = game.player
	p.input.throttle = 0.0
	p.input.brake = 0.0
	p.input.steer = 0.0
	p.input.handbrake = 0.0
	p.input.nitro = false

func _car() -> Array:
	## Interpolated car origin and its horizontal heading (by velocity when moving).
	var p: Car = game.player
	var xf := p.get_global_transform_interpolated()
	var f := -xf.basis.z
	var v := p.linear_velocity
	if v.length() > 4.0:
		f = v
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	return [xf.origin, f, f.cross(Vector3.UP).normalized()]

static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

func _shot_pos(u: float) -> Vector3:
	var e := _ease(u)
	match str(shots[shot].kind):
		"city":
			var ang := lerpf(0.75, 1.3, u)
			var r := lerpf(820.0, 640.0, e)
			return _orbit_c + Vector3(sin(ang) * r, lerpf(230.0, 170.0, e), cos(ang) * r)
		"pass":
			var c := _car()
			return c[0] + c[2] * 5.0 + c[1] * lerpf(16.0, -7.0, e) + Vector3.UP * lerpf(0.9, 1.6, e)
		"drone":
			var c := _car()
			return c[0] - c[1] * lerpf(12.0, 30.0, e) + c[2] * lerpf(-4.0, 7.0, e) + Vector3.UP * lerpf(3.5, 24.0, e)
		"home":
			var c := _car()
			var far: Vector3 = c[0] - c[1] * 34.0 + c[2] * 18.0 + Vector3.UP * 26.0
			var chase: Vector3 = c[0] - c[1] * 6.2 + Vector3.UP * 2.05
			return far.lerp(chase, e)
	return Vector3.ZERO

func _shot_look(u: float) -> Vector3:
	var e := _ease(u)
	match str(shots[shot].kind):
		"city":
			return _orbit_c
		"pass":
			var c := _car()
			return c[0] + Vector3.UP * 0.7
		"drone":
			var c := _car()
			return c[0] + c[1] * lerpf(6.0, 45.0, e) + Vector3.UP * 0.5
		"home":
			var c := _car()
			return c[0] + Vector3.UP * lerpf(0.4, 1.1, e) + c[1] * lerpf(0.0, 4.0, e)
	return Vector3.ZERO

func _physics_process(delta: float) -> void:
	if bot and shot >= 0 and shot < shots.size():
		bot.update(delta, [game.player], false)
		game.player.input.nitro = false

func _process(delta: float) -> void:
	if shot < 0 or shot >= shots.size() or ending:
		return
	var s: Dictionary = shots[shot]
	var dur := float(s.dur)
	t += delta
	var u := clampf(t / dur, 0.0, 1.0)
	# The pass-by and drone shots follow a moving car: smooth the camera a little.
	var k := 1.0 if str(s.kind) == "city" else 1.0 - exp(-14.0 * delta)
	_pos = _pos.lerp(_shot_pos(u), k)
	_look = _look.lerp(_shot_look(u), k)
	var cam: Camera3D = game.cam
	var gy: float = game.world.ground(_pos.x, _pos.z) + 0.8
	cam.global_position = Vector3(_pos.x, maxf(_pos.y, gy), _pos.z)
	if not cam.global_position.is_equal_approx(_look):
		cam.look_at(_look)
	cam.fov = lerpf(55.0, 72.0, _ease(u)) if str(s.kind) == "home" else 55.0
	# Fades between shots; the last one hands over to the chase camera without a cut.
	var a_in := 1.0 - clampf(t / (1.2 if shot == 0 else FADE), 0.0, 1.0)
	var a_out := 0.0 if shot == shots.size() - 1 else clampf((t - (dur - FADE)) / FADE, 0.0, 1.0)
	fade.color.a = maxf(a_in, a_out)
	caption.visible_ratio = clampf((t - 0.6) / maxf(caption.text.length() * 0.03, 0.5), 0.0, 1.0)
	caption.modulate.a = clampf((dur - 0.4 - t) / 0.5, 0.0, 1.0)
	if s.get("title", false):
		title.modulate.a = clampf((t - 0.8) / 0.8, 0.0, 1.0) * clampf((dur - 0.6 - t) / 0.6, 0.0, 1.0)
	else:
		title.modulate.a = 0.0
	# Letterbox slides away during the last shot.
	var lb := 1.0 if shot < shots.size() - 1 else 1.0 - _ease(clampf((u - 0.55) / 0.45, 0.0, 1.0))
	bars[0].offset_bottom = 110.0 * lb
	bars[1].offset_top = -110.0 * lb
	# Skip: hold accept / pause.
	var held := Input.is_action_pressed("ui_accept") or Input.is_action_pressed("pause") or Input.is_action_pressed("interact")
	hold = hold + delta if held else 0.0
	skip_l.text = ("Skipping..." if hold > 0.0 else "Hold [%s] to skip" % Settings.glyph("accept"))
	if hold > 0.6:
		_skip()
		return
	if t >= dur:
		_next()

func _skip() -> void:
	ending = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.3)
	await tw.finished
	_finish()

func _finish() -> void:
	ending = true
	bot = null
	_release_input()
	var p: Car = game.player
	p.reset_to(home_xf)
	p.reset_physics_interpolation()
	game.traffic.set_count(int(Settings.preset().traffic * float(Settings.data.traffic)))
	for n in bars + [caption, title, skip_l]:
		n.visible = false
	game.cam.process_mode = Node.PROCESS_MODE_INHERIT
	game.cam.snap = true
	finished.emit()
	if fade.color.a > 0.05:
		var tw := create_tween()
		tw.tween_property(fade, "color:a", 0.0, 0.5)
		await tw.finished
	queue_free()
