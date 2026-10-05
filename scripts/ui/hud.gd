class_name HUD
extends CanvasLayer
## In-game heads-up display.

const ACCENT := Color(1.0, 0.48, 0.1)
const CYAN := Color(0.1, 0.78, 1.0)
const MAP_TEX := preload("res://assets/world/map.png")

var game: Node
var root: Control
var cash_l: Label
var heat_l: Label
var clock_l: Label
var obj_l: Label
var timer_l: Label
var pursuit_box: VBoxContainer
var pursuit_l: Label
var cooldown_bar: ProgressBar
var race_box: VBoxContainer
var pos_l: Label
var lap_l: Label
var rtime_l: Label
var wrong_l: Label
var big_l: Label
var big_t := 0.0
var toast_box: VBoxContainer
var prompt_l: Label
var phone_panel: PanelContainer
var phone_l: Label
var sub_l: Label
var sub_lines: Array = []
var sub_t := 0.0
var drift_l: Label
var drift_m: Label
var fps_l: Label
var speedo: Speedo
var minimap: Minimap
var vignette: ColorRect

func setup(g: Node) -> void:
	game = g
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = "shader_type canvas_item; uniform float amount = 0.0; void fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.35, 0.85, length(d) * 1.3); COLOR = vec4(0.15, 0.45, 1.0, v * amount * 0.7); }"
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vignette.material = vm
	root.add_child(vignette)

	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 22)
	root.add_child(tl)
	cash_l = _label(34, Color(0.5, 1.0, 0.62))
	heat_l = _label(22, Color(1.0, 0.25, 0.3))
	clock_l = _label(16, Color(1, 1, 1, 0.6))
	tl.add_child(cash_l)
	tl.add_child(heat_l)
	tl.add_child(clock_l)

	var tc := VBoxContainer.new()
	tc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tc.position = Vector2(-300, 18)
	tc.custom_minimum_size = Vector2(600, 0)
	tc.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(tc)
	obj_l = _label(22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	timer_l = _label(30, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	tc.add_child(obj_l)
	tc.add_child(timer_l)
	pursuit_box = VBoxContainer.new()
	pursuit_l = _label(24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	cooldown_bar = ProgressBar.new()
	cooldown_bar.custom_minimum_size = Vector2(320, 8)
	cooldown_bar.show_percentage = false
	cooldown_bar.max_value = 1.0
	cooldown_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.5, 1.0, 0.6)
	cooldown_bar.add_theme_stylebox_override("fill", fill)
	pursuit_box.add_child(pursuit_l)
	pursuit_box.add_child(cooldown_bar)
	tc.add_child(pursuit_box)

	race_box = VBoxContainer.new()
	race_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	race_box.position = Vector2(-260, 18)
	race_box.custom_minimum_size = Vector2(230, 0)
	root.add_child(race_box)
	pos_l = _label(60, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	lap_l = _label(22, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	rtime_l = _label(26, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	wrong_l = _label(26, Color(1, 0.25, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	for l in [pos_l, lap_l, rtime_l, wrong_l]:
		race_box.add_child(l)

	big_l = _label(96, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	big_l.set_anchors_preset(Control.PRESET_CENTER)
	big_l.position = Vector2(-600, -260)
	big_l.custom_minimum_size = Vector2(1200, 120)
	big_l.add_theme_color_override("font_outline_color", ACCENT)
	big_l.add_theme_constant_override("outline_size", 6)
	root.add_child(big_l)

	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER)
	toast_box.position = Vector2(-300, -140)
	toast_box.custom_minimum_size = Vector2(600, 0)
	root.add_child(toast_box)

	drift_l = _label(46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	drift_m = _label(20, Color(1, 0.3, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	var db := VBoxContainer.new()
	db.set_anchors_preset(Control.PRESET_CENTER_TOP)
	db.position = Vector2(-200, 150)
	db.custom_minimum_size = Vector2(400, 0)
	db.add_child(drift_l)
	db.add_child(drift_m)
	root.add_child(db)

	prompt_l = _label(22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_l.position = Vector2(-400, -300)
	prompt_l.custom_minimum_size = Vector2(800, 0)
	root.add_child(prompt_l)

	sub_l = _label(24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	sub_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub_l.position = Vector2(-560, -200)
	sub_l.custom_minimum_size = Vector2(1120, 0)
	sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(sub_l)

	phone_panel = PanelContainer.new()
	phone_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	phone_panel.position = Vector2(-430, -420)
	phone_panel.custom_minimum_size = Vector2(380, 110)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.03, 0.04, 0.07, 0.88)
	ps.border_color = Color(0.3, 1.0, 0.55)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(10)
	ps.set_content_margin_all(14)
	phone_panel.add_theme_stylebox_override("panel", ps)
	phone_l = _label(22, Color.WHITE)
	phone_panel.add_child(phone_l)
	phone_panel.visible = false
	root.add_child(phone_panel)

	speedo = Speedo.new()
	speedo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speedo.position = Vector2(-300, -300)
	speedo.custom_minimum_size = Vector2(280, 280)
	speedo.size = Vector2(280, 280)
	root.add_child(speedo)
	minimap = Minimap.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap.position = Vector2(26, -276)
	minimap.size = Vector2(250, 250)
	minimap.game = g
	root.add_child(minimap)
	fps_l = _label(14, Color(0.6, 1, 0.9))
	fps_l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fps_l.position = Vector2(-160, 2)
	root.add_child(fps_l)

func _label(size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func big(text: String, secs := 1.5) -> void:
	big_l.text = text
	big_t = secs
	big_l.modulate.a = 1.0
	big_l.scale = Vector2(1.3, 1.3)
	big_l.pivot_offset = big_l.custom_minimum_size * 0.5

func message(text: String, secs := 2.5) -> void:
	var l := _label(24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.text = text
	toast_box.add_child(l)
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
	while toast_box.get_child_count() > 4:
		toast_box.get_child(0).queue_free()
		toast_box.remove_child(toast_box.get_child(0))

func show_dialogue(lines: Array) -> void:
	sub_lines = lines.duplicate()
	sub_t = 0.0
	_next_sub()

func _next_sub() -> void:
	if sub_lines.is_empty():
		sub_l.text = ""
		return
	sub_l.text = sub_lines.pop_front()
	sub_t = 3.5 + sub_l.text.length() * 0.04

func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	var car: Car = game.player
	var police: Police = game.police
	var career: Career = game.career
	cash_l.text = "$%s" % _fmt(int(Save.data.cash))
	if police.pursuit or police.heat > 0:
		heat_l.text = "HEAT " + "★".repeat(police.heat) + "☆".repeat(5 - police.heat)
	else:
		heat_l.text = ""
	var h: float = game.daynight.hour
	clock_l.text = "%02d:%02d  %s%s" % [int(h), int(fmod(h, 1.0) * 60.0), "NIGHT" if game.daynight.night > 0.5 else "DAY", "  RAIN" if game.daynight.rain > 0.3 else ""]
	pursuit_box.visible = police.pursuit
	if police.pursuit:
		pursuit_l.text = ("BUSTED IN %.1f" % maxf(0.0, 4.0 - police.bust)) if police.bust > 0.3 else ("EVADING..." if police.cooldown > 0.0 else "PURSUIT")
		cooldown_bar.value = police.cooldown / 10.0
		pursuit_l.modulate = Color(1, 0.3, 0.3) if int(Time.get_ticks_msec() / 300) % 2 == 0 else Color(0.4, 0.6, 1.0)
	# Objective
	if not career.active.is_empty() and career.race == null:
		obj_l.text = career.active.title.to_upper() + "  ·  " + career.waypoint_label
		timer_l.text = _time(career.time_left) if career.time_left < INF else ""
	else:
		obj_l.text = ""
		timer_l.text = ""
	var r: RaceSession = career.race
	race_box.visible = r != null
	if r:
		pos_l.text = "%d/%d" % [r.place, r.rivals.size() + 1]
		lap_l.text = ("LAP %d/%d" % [mini(r.lap + 1, r.laps), r.laps]) if r.path.closed else ("CP %d/%d" % [r.next_cp, r.cps.size()])
		rtime_l.text = _time(r.race_time)
		wrong_l.text = "WRONG WAY" if r.wrong > 1.0 else ""
	if big_t > 0.0:
		big_t -= delta
		big_l.scale = big_l.scale.lerp(Vector2.ONE, 1.0 - exp(-12.0 * delta))
		big_l.modulate.a = clampf(big_t * 2.0, 0.0, 1.0)
	else:
		big_l.text = ""
	if sub_t > 0.0:
		sub_t -= delta
		if sub_t <= 0.0:
			_next_sub()
	phone_panel.visible = career.pending_call >= 0 and career.ringing > 0.0
	if phone_panel.visible:
		phone_l.text = "INCOMING CALL\n%s\n[%s] Answer" % [career._caller(career.pending_call), Settings.glyph("phone")]
	var d: Dictionary = game.drift
	drift_l.text = _fmt(int(d.chain)) if d.chain > 0 else ""
	drift_m.text = ("DRIFT x%d" % d.mult) if d.chain > 0 else ""
	(vignette.material as ShaderMaterial).set_shader_parameter("amount", 1.0 if car.nitro_on else 0.0)
	prompt_l.text = game.prompt_text
	speedo.car = car
	speedo.units_mph = Settings.data.units == "mph"
	speedo.queue_redraw()
	minimap.queue_redraw()
	fps_l.visible = bool(Settings.data.show_fps)
	if fps_l.visible:
		fps_l.text = "%d FPS" % Engine.get_frames_per_second()

static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

static func _time(t: float) -> String:
	if t == INF:
		return "--:--.--"
	var m := int(t / 60.0)
	var sec := t - m * 60.0
	return "%d:%05.2f" % [m, sec]

class Speedo extends Control:
	var car: Car
	var units_mph := false
	func _draw() -> void:
		if car == null:
			return
		var c := size * 0.5 + Vector2(0, 10)
		var R := 118.0
		draw_circle(c, R + 16.0, Color(0.02, 0.03, 0.06, 0.6))
		var red: float = car.stats.red
		var rn := clampf(car.rpm / red, 0.0, 1.05)
		var a0 := PI * 0.75
		var a1 := PI * 2.25
		draw_arc(c, R, a0, a1, 64, Color(1, 1, 1, 0.12), 10.0, true)
		draw_arc(c, R, a0 + (a1 - a0) * 0.85, a1, 16, Color(1, 0.15, 0.25, 0.55), 10.0, true)
		var col := CYAN.lerp(ACCENT, rn) if rn < 0.9 else Color(1, 0.15, 0.25)
		draw_arc(c, R, a0, a0 + (a1 - a0) * minf(rn, 1.0), 64, col, 10.0, true)
		var font := ThemeDB.fallback_font
		var ticks := int(ceil(red / 1000.0))
		for i in ticks + 1:
			var a := a0 + (a1 - a0) * (i * 1000.0 / red)
			if a > a1 + 0.01:
				break
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * (R - 16), c + d * (R - 6), Color(1, 1, 1, 0.6), 2.0)
			draw_string(font, c + d * (R - 30) + Vector2(-5, 6), str(i), HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(1, 1, 1, 0.65))
		# Nitro arc
		draw_arc(c, R - 44, PI * 0.8, PI * 1.2, 24, Color(1, 1, 1, 0.12), 6.0, true)
		draw_arc(c, R - 44, PI * 1.2 - PI * 0.4 * car.nitro, PI * 1.2, 24, Color(0.6, 0.85, 1.0) if car.nitro_on else Color(0.2, 0.55, 1.0), 6.0, true)
		var spd := car.speed * (2.237 if units_mph else 3.6)
		draw_string(font, c + Vector2(-90, 18), str(int(spd)), HORIZONTAL_ALIGNMENT_CENTER, 180, 58, Color.WHITE)
		draw_string(font, c + Vector2(-90, 42), "MPH" if units_mph else "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 180, 15, Color(1, 1, 1, 0.6))
		var gear := "R" if car.reverse else ("N" if car.speed < 0.5 and float(car.input.throttle) < 0.05 else str(car.gear + 1))
		draw_string(font, c + Vector2(-40, 86), gear, HORIZONTAL_ALIGNMENT_CENTER, 80, 32, Color(1, 0.15, 0.25) if rn > 0.92 else ACCENT)

class Minimap extends Control:
	var game: Node
	var map_rect: TextureRect
	func _ready() -> void:
		map_rect = TextureRect.new()
		map_rect.texture = MAP_TEX
		map_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		map_rect.stretch_mode = TextureRect.STRETCH_SCALE
		map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = """shader_type canvas_item;
uniform vec2 center_uv = vec2(0.5);
uniform float rot = 0.0;
uniform float span = 0.05;
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d);
	vec2 rd = vec2(d.x * cos(rot) - d.y * sin(rot), d.x * sin(rot) + d.y * cos(rot));
	vec4 c = texture(TEXTURE, center_uv + rd * span * 2.0);
	float a = 1.0 - smoothstep(0.48, 0.5, r);
	COLOR = vec4(c.rgb * 0.95, a * 0.92);
}"""
		var m := ShaderMaterial.new()
		m.shader = sh
		map_rect.material = m
		add_child(map_rect)
		show_behind_parent = false
	func _draw() -> void:
		if game == null or game.player == null:
			return
		var car: Car = game.player
		var world: World = game.world
		var S := size.x
		var half := S * 0.5
		var center := Vector2(half, half)
		var zoom := 1.6 - clampf(car.speed / 80.0, 0.0, 1.0) * 0.7
		var view_m := 900.0 / zoom # metres across the minimap
		var fwd := -car.global_transform.basis.z
		var yaw := atan2(fwd.x, -fwd.z)
		var pos := Vector2(car.global_position.x, car.global_position.z)
		var mat := map_rect.material as ShaderMaterial
		mat.set_shader_parameter("center_uv", (pos + Vector2(world.HALF, world.HALF)) / (world.HALF * 2.0))
		mat.set_shader_parameter("rot", yaw)
		mat.set_shader_parameter("span", view_m / (world.HALF * 2.0) * 0.5)
		var scale := S / view_m
		var to_map := func(w: Vector2) -> Vector2:
			return center + (w - pos).rotated(-yaw) * scale
		var inside := func(p: Vector2) -> bool:
			return p.distance_to(center) < half - 4.0
		var route: PackedVector2Array = game.gps_route
		for i in range(route.size() - 1):
			var a: Vector2 = to_map.call(route[i])
			var b: Vector2 = to_map.call(route[i + 1])
			if inside.call(a) or inside.call(b):
				draw_line(a, b, Color(1.0, 0.7, 0.15), 4.0, true)
		var dots: Array = []
		var career: Career = game.career
		if career.waypoint != Vector2.INF:
			dots.append([career.waypoint, Color(1.0, 0.75, 0.2), 7.0])
		if career.active.is_empty() and career.race == null:
			dots.append([career.LOC.home, Color(0.3, 1.0, 0.55), 7.0])
			for m2 in career.race_markers:
				dots.append([m2.pos, Color(0.3, 0.75, 1.0), 6.0])
		var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
		for c in game.police.cars():
			dots.append([Vector2(c.global_position.x, c.global_position.z), Color(1, 0.15, 0.2) if blink else Color(0.2, 0.4, 1), 5.0])
		if career.race:
			for r in career.race.rivals:
				dots.append([Vector2(r.car.global_position.x, r.car.global_position.z), Color(1, 0.35, 0.45), 4.5])
		for d in dots:
			var p: Vector2 = to_map.call(d[0])
			if not inside.call(p):
				p = center + (p - center).normalized() * (half - 8.0) # clamp to the rim
			draw_circle(p, d[2], d[1])
		var arrow := PackedVector2Array([center + Vector2(0, -11), center + Vector2(8, 9), center + Vector2(0, 4), center + Vector2(-8, 9)])
		draw_colored_polygon(arrow, Color.WHITE)
		draw_arc(center, half - 1, 0, TAU, 64, Color(1, 1, 1, 0.35), 2.0, true)
		var n := Vector2(0, -1).rotated(-yaw) * (half - 14)
		draw_string(ThemeDB.fallback_font, center + n + Vector2(-5, 6), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 15, ACCENT)
