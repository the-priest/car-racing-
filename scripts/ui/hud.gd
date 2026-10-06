class_name HUD
extends CanvasLayer
## In-game heads-up display.

const ACCENT := Color(1.0, 0.48, 0.1)
const CYAN := Color(0.1, 0.78, 1.0)
const ROUTE_COL := Color(0.62, 0.45, 1.0) # GPS route: violet, distinct from the orange highway
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
var pursuit_stats: Label
var radio_panel: PanelContainer
var radio_l: Label
var radio_t := 0.0
var np_panel: PanelContainer
var np_title: Label
var np_artist: Label
var np_t := 0.0
var tip_panel: PanelContainer
var tip_l: Label
var tip_t := 0.0
var ach_queue: Array = []
var cooldown_bar: ProgressBar
var race_box: VBoxContainer
var pos_l: Label
var lap_l: Label
var rtime_l: Label
var wrong_l: Label
var standings_l: RichTextLabel
var standings_t := 0.0
var big_l: Label
var big_t := 0.0
var big_queue: Array = [] # [text, secs] waiting for the current banner to finish
var title_busy := 0.0 # a job title card is on screen: other banners/toasts wait
var msg_hold: Array = []
var cash_shown := -1.0
var cash_delta := 0
var cash_delta_t := 0.0
var cash_delta_l: Label
var toast_box: VBoxContainer
var prompt_l: Label
var phone_panel: PanelContainer
var phone_l: Label
var sub_l: Label
var sub_name: Label
var sub_hint: Label
var sub_panel: PanelContainer
var sub_style: StyleBoxFlat
var sub_lines: Array = []
var sub_t := 0.0
var drift_l: Label
var drift_m: Label
var slip_l: Label
var fps_l: Label
var speedo: Speedo
var minimap: Minimap
var big_map: BigMap
var vignette: ColorRect
var nitro_fx := 0.0
var last_beep := -1
var last_place := 0
var free_t := 0.0

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
	# Speed effect: radial blur toward the screen edges plus a blue nitrous vignette.
	vs.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
uniform float blur = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r = length(d);
	float edge = smoothstep(0.12, 0.62, r);
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (blur > 0.001) {
		float k = blur * edge * 0.055;
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			acc += texture(screen_tex, uv - d * k * float(i) / 7.0).rgb;
		}
		col = acc / 8.0;
		a = edge * min(blur * 1.6, 1.0);
	}
	float v = smoothstep(0.35, 0.85, r * 1.3) * amount * 0.6;
	col = mix(col, vec3(0.15, 0.45, 1.0), v / max(a + v, 0.001));
	COLOR = vec4(col, clamp(a + v, 0.0, 1.0));
}"""
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vignette.material = vm
	root.add_child(vignette)

	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 22)
	root.add_child(tl)
	var cash_row := HBoxContainer.new()
	cash_row.add_theme_constant_override("separation", 14)
	tl.add_child(cash_row)
	cash_l = _label(30, Color(0.5, 1.0, 0.62))
	cash_row.add_child(cash_l)
	cash_delta_l = _label(22, Color(0.5, 1.0, 0.62))
	cash_delta_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cash_delta_l.modulate.a = 0.0
	cash_row.add_child(cash_delta_l)
	heat_l = _label(22, Color(1.0, 0.25, 0.3))
	clock_l = _label(16, Color(1, 1, 1, 0.6))
	tl.add_child(heat_l)
	tl.add_child(clock_l)

	var tc := VBoxContainer.new()
	tc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tc.position = Vector2(-450, 18)
	tc.custom_minimum_size = Vector2(900, 0)
	tc.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(tc)
	obj_l = _label(24, Color(1, 0.88, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
	obj_l.add_theme_constant_override("outline_size", 6)
	obj_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
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
	pursuit_stats = _label(18, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	pursuit_box.add_child(pursuit_l)
	pursuit_box.add_child(pursuit_stats)
	pursuit_box.add_child(cooldown_bar)
	tc.add_child(pursuit_box)

	# Police radio ticker (left column, under the cash/now-playing; clear of race standings).
	radio_panel = PanelContainer.new()
	radio_panel.position = Vector2(24, 250)
	radio_panel.custom_minimum_size = Vector2(440, 0)
	radio_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0.02, 0.04, 0.09, 0.72)
	rs.border_width_left = 4
	rs.border_color = Color(0.3, 0.6, 1.0)
	rs.content_margin_left = 14
	rs.content_margin_right = 12
	rs.content_margin_top = 8
	rs.content_margin_bottom = 10
	radio_panel.add_theme_stylebox_override("panel", rs)
	var rv := VBoxContainer.new()
	radio_panel.add_child(rv)
	var rh := _label(13, Color(0.45, 0.7, 1.0))
	rh.text = "POLICE RADIO"
	rv.add_child(rh)
	radio_l = _label(17, Color(0.85, 0.92, 1.0))
	radio_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	rv.add_child(radio_l)
	radio_panel.modulate.a = 0.0
	root.add_child(radio_panel)

	np_panel = PanelContainer.new()
	np_panel.position = Vector2(24, 150)
	np_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ns := StyleBoxFlat.new()
	ns.bg_color = Color(0.04, 0.02, 0.08, 0.6)
	ns.border_width_left = 3
	ns.border_color = Color(0.75, 0.45, 1.0)
	ns.content_margin_left = 12
	ns.content_margin_right = 16
	ns.content_margin_top = 5
	ns.content_margin_bottom = 7
	np_panel.add_theme_stylebox_override("panel", ns)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	np_panel.add_child(nv)
	var nh := _label(11, Color(0.78, 0.55, 1.0))
	nh.text = "NOW PLAYING"
	nv.add_child(nh)
	np_title = _label(19, Color.WHITE)
	nv.add_child(np_title)
	np_artist = _label(14, Color(1, 1, 1, 0.65))
	nv.add_child(np_artist)
	np_panel.modulate.a = 0.0
	root.add_child(np_panel)

	tip_panel = PanelContainer.new()
	tip_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tip_panel.position = Vector2(24, -540)
	tip_panel.custom_minimum_size = Vector2(420, 0)
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.02, 0.03, 0.06, 0.8)
	ts.border_width_top = 3
	ts.border_color = CYAN
	ts.content_margin_left = 14
	ts.content_margin_right = 14
	ts.content_margin_top = 8
	ts.content_margin_bottom = 10
	tip_panel.add_theme_stylebox_override("panel", ts)
	var tv := VBoxContainer.new()
	tip_panel.add_child(tv)
	var th := _label(13, CYAN)
	th.text = "TIP"
	tv.add_child(th)
	tip_l = _label(17, Color.WHITE)
	tip_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	tip_l.custom_minimum_size = Vector2(390, 0)
	tv.add_child(tip_l)
	tip_panel.visible = false
	root.add_child(tip_panel)

	race_box = VBoxContainer.new()
	race_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	race_box.position = Vector2(-260, 18)
	race_box.custom_minimum_size = Vector2(230, 0)
	root.add_child(race_box)
	pos_l = _label(60, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	lap_l = _label(22, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	rtime_l = _label(26, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	wrong_l = _label(26, Color(1, 0.25, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	standings_l = RichTextLabel.new()
	standings_l.bbcode_enabled = true
	standings_l.fit_content = true
	standings_l.scroll_active = false
	standings_l.custom_minimum_size = Vector2(230, 0)
	standings_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	standings_l.add_theme_font_size_override("normal_font_size", 17)
	standings_l.add_theme_color_override("default_color", Color(1, 1, 1, 0.8))
	standings_l.add_theme_constant_override("outline_size", 4)
	standings_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	for l in [pos_l, lap_l, rtime_l, wrong_l, standings_l]:
		race_box.add_child(l)

	big_l = _label(96, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	big_l.set_anchors_preset(Control.PRESET_CENTER)
	big_l.position = Vector2(-600, -235)
	big_l.custom_minimum_size = Vector2(1200, 120)
	big_l.add_theme_color_override("font_outline_color", ACCENT)
	big_l.add_theme_constant_override("outline_size", 6)
	root.add_child(big_l)

	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER)
	toast_box.position = Vector2(-340, -70)
	toast_box.custom_minimum_size = Vector2(680, 0)
	toast_box.add_theme_constant_override("separation", 6)
	root.add_child(toast_box)

	drift_l = _label(46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	drift_m = _label(20, Color(1, 0.3, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	# Drift score on the right, clear of the objective, the pursuit box and the car.
	var db := VBoxContainer.new()
	db.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	db.position = Vector2(-450, 500)
	db.custom_minimum_size = Vector2(400, 0)
	db.add_child(drift_l)
	db.add_child(drift_m)
	slip_l = _label(18, CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	slip_l.text = "»  SLIPSTREAM  «"
	slip_l.visible = false
	db.add_child(slip_l)
	root.add_child(db)

	prompt_l = _label(22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_l.position = Vector2(-400, -300)
	prompt_l.custom_minimum_size = Vector2(800, 0)
	root.add_child(prompt_l)

	# Dialogue box: speaker name in their colour, typewriter text.
	sub_panel = PanelContainer.new()
	sub_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub_panel.position = Vector2(-430, -236)
	sub_panel.custom_minimum_size = Vector2(860, 0)
	sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_style = StyleBoxFlat.new()
	sub_style.bg_color = Color(0.02, 0.03, 0.06, 0.78)
	sub_style.border_width_left = 6
	sub_style.border_color = ACCENT
	sub_style.content_margin_left = 22
	sub_style.content_margin_right = 22
	sub_style.content_margin_top = 12
	sub_style.content_margin_bottom = 14
	sub_style.corner_radius_top_right = 6
	sub_style.corner_radius_bottom_right = 6
	sub_panel.add_theme_stylebox_override("panel", sub_style)
	var sv := VBoxContainer.new()
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.add_child(sv)
	var name_row := HBoxContainer.new()
	sv.add_child(name_row)
	sub_name = _label(18, ACCENT)
	sub_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(sub_name)
	sub_hint = _label(13, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_RIGHT)
	name_row.add_child(sub_hint)
	sub_l = _label(24, Color.WHITE)
	sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	sv.add_child(sub_l)
	sub_panel.visible = false
	root.add_child(sub_panel)

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
	minimap.position = Vector2(24, -344)
	minimap.size = Vector2(320, 320)
	minimap.game = g
	root.add_child(minimap)
	big_map = BigMap.new()
	big_map.game = g
	root.add_child(big_map)
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

## Big centre banner. Banners queue behind each other (and behind a job title
## card) so nothing important is overwritten; urgent ones (countdown) show at once.
func big(text: String, secs := 1.5, urgent := false) -> void:
	if urgent:
		big_queue.clear()
		_show_big(text, secs)
		return
	if text == big_l.text and big_t > 0.0:
		big_t = maxf(big_t, secs)
		return
	for q in big_queue:
		if q[0] == text:
			return
	if (big_t > 0.35 and big_l.text != "") or title_busy > 0.0:
		if big_queue.size() < 3:
			big_queue.append([text, secs])
		return
	_show_big(text, secs)

func _show_big(text: String, secs: float) -> void:
	big_l.text = text
	big_t = secs
	big_l.modulate.a = 1.0
	big_l.scale = Vector2(1.3, 1.3)
	big_l.pivot_offset = big_l.custom_minimum_size * 0.5

## Short toast under the banner. Repeats of the same message (or the same key)
## merge into one ("NEAR MISS  x3") instead of stacking up.
func message(text: String, secs := 2.5, key := "") -> void:
	if key == "":
		key = text
	if title_busy > 0.0:
		for m in msg_hold:
			if m[2] == key:
				m[0] = text
				return
		msg_hold.append([text, secs, key])
		return
	for c in toast_box.get_children():
		if c.is_queued_for_deletion() or str(c.get_meta("key", "")) != key:
			continue
		var l0 := c as Label
		if str(l0.get_meta("base", "")) == text:
			var n := int(l0.get_meta("count", 1)) + 1
			l0.set_meta("count", n)
			l0.text = "%s  x%d" % [text, n]
		else:
			l0.set_meta("base", text)
			l0.set_meta("count", 1)
			l0.text = text
		_toast_timer(l0, secs)
		return
	var l := _label(24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(680, 0)
	l.text = text
	l.set_meta("key", key)
	l.set_meta("base", text)
	l.set_meta("count", 1)
	toast_box.add_child(l)
	l.modulate.a = 0.0
	_toast_timer(l, secs)
	while toast_box.get_child_count() > 3:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()

func _toast_timer(l: Label, secs: float) -> void:
	var prev = l.get_meta("tw", null)
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_interval(secs)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
	l.set_meta("tw", tw)

## Cinematic title card for a new job: act line, big title, subtitle; fades out.
func title_card(top: String, title: String, sub: String) -> void:
	var box := VBoxContainer.new()
	# Created at runtime: anchor to the centre with explicit offsets.
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -500
	box.offset_right = 500
	box.offset_top = -200
	box.offset_bottom = -40
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := _label(20, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	a.text = top
	var b := _label(84, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	b.text = title
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	var line := ColorRect.new()
	line.color = ACCENT
	line.custom_minimum_size = Vector2(0, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var c := _label(18, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	c.text = sub
	for n in [a, b, line, c]:
		box.add_child(n)
	root.add_child(box)
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(line, "custom_minimum_size:x", 420.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.6)
	tw.tween_property(box, "modulate:a", 0.0, 0.6)
	tw.tween_callback(box.queue_free)
	big_t = 0.0
	big_l.text = ""
	title_busy = 3.4

## Gold achievement card that slides in at the top right; queued if several unlock at once.
func achievement(title: String, desc: String) -> void:
	ach_queue.append([title, desc])
	if ach_queue.size() == 1:
		_show_ach()

func _show_ach() -> void:
	if ach_queue.is_empty():
		return
	var a: Array = ach_queue[0]
	var p := PanelContainer.new()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.offset_left = -470
	p.offset_right = -30
	p.offset_top = 390 # below the race standings, above the speedometer
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.05, 0.02, 0.9)
	st.border_width_left = 5
	st.border_color = Color(1.0, 0.78, 0.2)
	st.content_margin_left = 16
	st.content_margin_right = 14
	st.content_margin_top = 8
	st.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	p.add_child(v)
	var h := _label(13, Color(1.0, 0.78, 0.2))
	h.text = "★  ACHIEVEMENT UNLOCKED"
	var t := _label(22, Color.WHITE)
	t.text = a[0]
	var d := _label(15, Color(1, 1, 1, 0.7))
	d.text = a[1]
	for n in [h, t, d]:
		v.add_child(n)
	root.add_child(p)
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.3)
	tw.tween_interval(3.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		p.queue_free()
		ach_queue.pop_front()
		_show_ach())

## Tip card above the minimap.
var tip_queue: Array[String] = []

func tip(text: String) -> void:
	if tip_t > 0.8 and tip_panel.visible:
		if not tip_queue.has(text):
			tip_queue.append(text)
		return
	tip_l.text = text
	tip_panel.visible = true
	tip_panel.modulate.a = 1.0
	tip_t = 9.0

## Track card under the cash readout when a free-roam song starts.
func now_playing(title: String, artist: String) -> void:
	np_title.text = title
	np_artist.text = artist
	np_t = 6.0

func radio(text: String) -> void:
	radio_l.text = text
	radio_t = 5.0 + text.length() * 0.03
	radio_panel.modulate.a = 1.0

## Finish the typewriter, or move to the next line if it's already complete.
func skip_line() -> void:
	if sub_l.visible_ratio < 1.0:
		sub_l.visible_ratio = 1.0
	else:
		_next_sub()

func clear_dialogue() -> void:
	sub_lines.clear()
	sub_t = 0.0
	sub_panel.visible = false

func show_dialogue(lines: Array) -> void:
	## Queues lines ("Speaker: text" or narration) after anything already showing.
	var was_idle := sub_lines.is_empty() and not sub_panel.visible
	sub_lines.append_array(lines)
	if was_idle:
		_next_sub()

func _next_sub() -> void:
	if sub_lines.is_empty():
		sub_l.text = ""
		sub_panel.visible = false
		return
	var line: String = sub_lines.pop_front()
	var who := ""
	var colon := line.find(": ")
	if colon > 0 and colon < 14:
		who = line.substr(0, colon)
		line = line.substr(colon + 2)
	var col: Color = Career.SPEAKERS.get(who, Color(0.85, 0.85, 0.9))
	sub_name.text = who.to_upper() if who != "" else ""
	sub_hint.text = "[%s] next" % Settings.glyph("interact")
	sub_name.add_theme_color_override("font_color", col)
	sub_style.border_color = col if who != "" else Color(1, 1, 1, 0.3)
	sub_l.text = line
	sub_l.add_theme_color_override("font_color", Color.WHITE if who != "" else Color(0.85, 0.88, 0.95))
	sub_l.visible_ratio = 0.0
	sub_panel.visible = true
	sub_t = 2.6 + line.length() * 0.045
	game.audio.play_oneshot("beep", 2.4, -18.0)

## Cash readout counts toward the new balance, with a "+$2,000" chip beside it.
func _update_cash(delta: float) -> void:
	var cash := float(Save.data.cash)
	if cash_shown < 0.0:
		cash_shown = cash
	var diff := cash - cash_shown
	if absf(diff) >= 1.0:
		if cash_delta_t <= 0.0:
			cash_delta = 0
		cash_delta += int(round(diff))
		cash_delta_t = 2.6
		cash_delta_l.text = ("+$%s" if cash_delta > 0 else "-$%s") % _fmt(absi(cash_delta))
		cash_delta_l.add_theme_color_override("font_color", Color(0.5, 1.0, 0.62) if cash_delta > 0 else Color(1.0, 0.4, 0.4))
		cash_shown = cash
	if cash_delta_t > 0.0:
		cash_delta_t -= delta
		cash_delta_l.modulate.a = clampf(cash_delta_t * 2.0, 0.0, 1.0)
	var target_disp := cash - (float(cash_delta) * clampf((cash_delta_t - 1.6) / 1.0, 0.0, 1.0) if cash_delta_t > 0.0 else 0.0)
	cash_l.text = "$%s" % _fmt(int(target_disp))

func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	var _t0 := Time.get_ticks_usec()
	_update(delta)
	game._pt("hud", _t0)

func _update(delta: float) -> void:
	var car: Car = game.player
	var police: Police = game.police
	var career: Career = game.career
	_update_cash(delta)
	if police.pursuit or police.heat > 0:
		heat_l.text = "HEAT " + "★".repeat(police.heat) + "☆".repeat(5 - police.heat)
	else:
		heat_l.text = ""
	var h: float = game.daynight.hour
	clock_l.text = "%02d:%02d  %s%s" % [int(h), int(fmod(h, 1.0) * 60.0), ("NIGHT" if game.daynight.night > 0.75 else ("DUSK" if h > 12.0 else "DAWN") if game.daynight.night > 0.15 else "DAY"), "  RAIN" if game.daynight.rain > 0.3 else ""]
	pursuit_box.visible = police.pursuit
	if police.pursuit:
		pursuit_l.text = ("BUSTED IN %.1f" % maxf(0.0, police.bust_time() - police.bust)) if police.bust > 0.3 else ("EVADING..." if police.cooldown > 0.0 else "PURSUIT")
		var air := ""
		if police.heli:
			air = "   ·   AIR UNIT: " + ("TRACKING" if police.heli_sees else "SEARCHING")
		pursuit_stats.text = "COPS %d   ·   TAKEDOWNS %d   ·   BOUNTY $%s%s" % [police.active_count(), police.takedowns, _fmt(police.bounty()), air]
		cooldown_bar.value = police.cooldown / 10.0
		pursuit_l.modulate = Color(1, 0.3, 0.3) if int(Time.get_ticks_msec() / 300) % 2 == 0 else Color(0.4, 0.6, 1.0)
	# Objective
	var pp2 := Vector2(car.global_position.x, car.global_position.z)
	if not (career.active.is_empty() and career.race == null and not police.pursuit and career.drift_zone < 0 and game.custom_wp == Vector2.INF):
		free_t = 0.0
		obj_l.modulate.a = 1.0
	if not career.active.is_empty() and career.race == null:
		var dtxt := ""
		if career.waypoint != Vector2.INF:
			var to := career.waypoint - pp2
			var cf := -car.global_transform.basis.z
			var rel := wrapf(atan2(to.x, -to.y) - atan2(cf.x, -cf.z), -PI, PI)
			var arrows := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
			dtxt = "   %s %s" % [arrows[posmod(int(round(rel / (PI / 4.0))), 8)], dist_text(to.length())]
		obj_l.text = "▶ " + career.active.title.to_upper() + "\n" + career.waypoint_label + dtxt
		if career.target:
			obj_l.text += "\n" + career.target_text()
		timer_l.text = _time(career.time_left) if career.time_left < INF else ""
		var tl: float = career.time_left
		if tl < 20.0:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
			timer_l.add_theme_color_override("font_color", Color(1, 0.2, 0.25).lerp(Color.WHITE, pulse * 0.4))
			if tl < 10.0 and int(ceil(tl)) != last_beep:
				last_beep = int(ceil(tl))
				game.audio.play_oneshot("beep", 1.9, -8.0)
		else:
			timer_l.add_theme_color_override("font_color", ACCENT)
		if career.wait_left >= 0.0:
			timer_l.text = "%d" % int(ceil(career.wait_left))
	elif career.drift_zone >= 0:
		obj_l.text = "▶ DRIFT ZONE  ·  %s\n%s pts   %s" % [Career.DRIFT_ZONES[career.drift_zone].name.to_upper(), _fmt(career.drift_zone_score()), dist_text(career.waypoint.distance_to(pp2))]
		timer_l.text = _time(career.drift_zone_t)
	elif career.race == null and not police.pursuit and game.custom_wp != Vector2.INF:
		obj_l.text = "WAYPOINT  ·  %s" % dist_text(game.custom_wp.distance_to(pp2))
		timer_l.text = ""
	elif career.race == null and not police.pursuit:
		free_t += delta
		var ci := int(Save.data.contract)
		if ci < Career.CONTRACTS.size():
			var c: Dictionary = Career.CONTRACTS[ci]
			obj_l.text = "NEXT  ·  CH.%d %s  ·  [%s] Call %s" % [ci + 1, str(c.title).to_upper(), Settings.glyph("phone"), c.caller]
		else:
			obj_l.text = "FREE ROAM  ·  drive to a race marker or wait for a call  ·  [%s] Map" % Settings.glyph("map")
		obj_l.modulate.a = clampf((15.0 - free_t) / 1.5, 0.0, 1.0)
		timer_l.text = ""
	else:
		obj_l.text = ""
		timer_l.text = ""
	var r: RaceSession = career.race
	race_box.visible = r != null
	if r:
		pos_l.text = "%d/%d" % [r.place, r.rivals.size() + 1]
		if r.place != last_place and r.countdown <= 0.0:
			var better := r.place < last_place
			last_place = r.place
			pos_l.pivot_offset = pos_l.size * Vector2(1.0, 0.5)
			pos_l.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55) if better else Color(1.0, 0.35, 0.35))
			var tw := create_tween()
			tw.tween_property(pos_l, "scale", Vector2(1.35, 1.35), 0.08)
			tw.tween_property(pos_l, "scale", Vector2.ONE, 0.25)
			tw.tween_callback(func(): pos_l.add_theme_color_override("font_color", Color.WHITE))
		elif r.countdown > 0.0:
			last_place = r.place
		lap_l.text = ("LAP %d/%d" % [mini(r.lap + 1, r.laps), r.laps]) if r.path.closed else ("CP %d/%d" % [r.next_cp, r.cps.size()])
		rtime_l.text = _time(r.race_time)
		wrong_l.text = "WRONG WAY" if r.wrong > 1.0 else ""
		standings_t -= delta
		if standings_t <= 0.0:
			standings_t = 0.25
			var txt := ""
			for k in r.order.size():
				var e: Dictionary = r.order[k]
				var col := "#ffffff" if e.me else ("#ff6aa8" if e.boss else "#c8ccd6")
				txt += "[right][color=%s]%d  %s[/color][/right]\n" % [col, k + 1, "YOU" if e.me else str(e.name).to_upper()]
			standings_l.text = txt
	if title_busy > 0.0:
		title_busy -= delta
		if title_busy <= 0.0:
			var held := msg_hold.duplicate()
			msg_hold.clear()
			for m in held:
				message(m[0], m[1], m[2])
	if big_t > 0.0:
		big_t -= delta
		big_l.scale = big_l.scale.lerp(Vector2.ONE, 1.0 - exp(-12.0 * delta))
		big_l.modulate.a = clampf(big_t * 2.0, 0.0, 1.0)
	else:
		big_l.text = ""
		if not big_queue.is_empty() and title_busy <= 0.0:
			var nb: Array = big_queue.pop_front()
			_show_big(nb[0], nb[1])
	var talking: bool = game.is_playing()
	if talking and sub_panel.visible and sub_l.visible_ratio < 1.0:
		sub_l.visible_ratio = minf(1.0, sub_l.visible_ratio + delta * 55.0 / maxf(sub_l.text.length(), 1.0))
	if tip_t > 0.0:
		tip_t -= delta
		tip_panel.modulate.a = clampf(tip_t * 1.5, 0.0, 1.0)
		if tip_t <= 0.0:
			tip_panel.visible = false
			if not tip_queue.is_empty():
				tip(tip_queue.pop_front())
	if radio_t > 0.0:
		radio_t -= delta
		radio_panel.modulate.a = clampf(radio_t * 2.0, 0.0, 1.0)
	if np_t > 0.0:
		np_t -= delta
		np_panel.modulate.a = clampf(minf(np_t, 6.0 - np_t) * 2.0, 0.0, 1.0)
	if sub_t > 0.0 and talking:
		sub_t -= delta
		if sub_t <= 0.0:
			_next_sub()
	phone_panel.visible = career.pending_call >= 0 and career.ringing > 0.0
	if phone_panel.visible:
		var blink := int(Time.get_ticks_msec() / 400) % 2 == 0
		phone_l.text = "%s INCOMING CALL\n%s  ·  %s\n[%s] Answer" % ["☎" if blink else "  ", career._caller(career.pending_call).to_upper(), career.call_title(career.pending_call), Settings.glyph("phone")]
	var d: Dictionary = game.drift
	drift_l.text = _fmt(int(d.chain)) if d.chain > 0 else ""
	slip_l.visible = game.slip_t > 0.0
	if slip_l.visible:
		slip_l.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.015)
	drift_m.text = ("DRIFT x%d" % d.mult) if d.chain > 0 else ""
	var vm2 := vignette.material as ShaderMaterial
	nitro_fx = move_toward(nitro_fx, 1.0 if car.nitro_on else 0.0, delta * 3.0)
	var blur := 0.0
	if bool(Settings.data.speed_fx):
		blur = smoothstep(42.0, 95.0, car.speed) * 0.7 + nitro_fx * 0.45
	vm2.set_shader_parameter("amount", nitro_fx)
	vm2.set_shader_parameter("blur", blur)
	vignette.visible = blur > 0.01 or nitro_fx > 0.01
	prompt_l.text = game.prompt_text
	speedo.car = car
	speedo.units_mph = Settings.data.units == "mph"
	speedo.queue_redraw()
	minimap.refresh()
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

static func map_markers(game: Node, full: bool) -> Array:
	## [world_pos, color, kind, label]; kinds: mission, home, race, cop, rival
	var out: Array = []
	var career: Career = game.career
	var free: bool = career.active.is_empty() and career.race == null
	if free or full:
		out.append([career.LOC.home, Color(0.3, 1.0, 0.55), "home", "HOME"])
		for m2 in career.race_markers:
			out.append([m2.pos, Color(0.3, 0.75, 1.0), "race", str(Career.RACES[m2.id].name)])
	if free or full:
		for dm in career.drift_markers:
			out.append([dm.a, Color(1.0, 0.55, 0.1), "drift", str(Career.DRIFT_ZONES[dm.i].name) if full else ""])
		for tp in Career.SPEED_TRAPS:
			out.append([tp, Color(0.95, 0.95, 0.95), "trap", "Speed trap" if full else ""])
	if career.race:
		for r in career.race.rivals:
			out.append([Vector2(r.car.global_position.x, r.car.global_position.z), Color(1, 0.35, 0.45), "rival", ""])
	var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
	for c in game.police.cars():
		out.append([Vector2(c.global_position.x, c.global_position.z), Color(1, 0.15, 0.2) if blink else Color(0.25, 0.45, 1), "cop", ""])
	if game.custom_wp != Vector2.INF:
		out.append([game.custom_wp, Color(1.0, 0.3, 0.85), "pin", "Your waypoint" if full else ""])
	if career.waypoint != Vector2.INF:
		var lbl: String = career.waypoint_label if career.waypoint_label != "" else "OBJECTIVE"
		out.append([career.waypoint, Color(1.0, 0.82, 0.1), "mission", lbl])
	return out

static func draw_marker(ci: CanvasItem, p: Vector2, col: Color, kind: String, sz: float) -> void:
	var dark := Color(0, 0, 0, 0.9)
	match kind:
		"mission":
			var pulse := 1.0 + 0.18 * sin(Time.get_ticks_msec() * 0.008)
			var r := sz * 1.6 * pulse
			var dia := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			var dia2 := PackedVector2Array([p + Vector2(0, -r - 3), p + Vector2(r + 3, 0), p + Vector2(0, r + 3), p + Vector2(-r - 3, 0)])
			ci.draw_colored_polygon(dia2, dark)
			ci.draw_colored_polygon(dia, col)
			ci.draw_circle(p, r * 0.3, dark)
		"home":
			var r2 := sz * 1.2
			ci.draw_rect(Rect2(p - Vector2(r2 + 2, r2 + 2), Vector2(r2 + 2, r2 + 2) * 2), dark)
			ci.draw_rect(Rect2(p - Vector2(r2, r2), Vector2(r2, r2) * 2), col)
			ci.draw_string(ThemeDB.fallback_font, p + Vector2(-r2, r2 * 0.6), "H", HORIZONTAL_ALIGNMENT_CENTER, r2 * 2, int(r2 * 1.7), dark)
		"pin":
			ci.draw_line(p, p + Vector2(0, -sz * 2.2), dark, 4.0)
			ci.draw_line(p, p + Vector2(0, -sz * 2.2), col, 2.0)
			ci.draw_circle(p + Vector2(0, -sz * 2.2), sz * 0.9 + 2.0, dark)
			ci.draw_circle(p + Vector2(0, -sz * 2.2), sz * 0.9, col)
		"trap":
			var r3 := sz * 0.8
			var tri := PackedVector2Array([p + Vector2(0, -r3 - 2), p + Vector2(r3 + 2, r3 + 1), p + Vector2(-r3 - 2, r3 + 1)])
			ci.draw_colored_polygon(tri, dark)
			tri = PackedVector2Array([p + Vector2(0, -r3), p + Vector2(r3, r3 - 1), p + Vector2(-r3, r3 - 1)])
			ci.draw_colored_polygon(tri, col)
		"race":
			ci.draw_circle(p, sz + 2.5, dark)
			ci.draw_circle(p, sz, col)
			ci.draw_circle(p, sz * 0.4, Color.WHITE)
		_:
			ci.draw_circle(p, sz * 0.8 + 2.0, dark)
			ci.draw_circle(p, sz * 0.8, col)

static func draw_player(ci: CanvasItem, c: Vector2, ang: float, sz: float) -> void:
	var pts := [Vector2(0, -1.25), Vector2(0.85, 0.95), Vector2(0, 0.45), Vector2(-0.85, 0.95)]
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for q in pts:
		outer.append(c + (q * (sz + 4.0)).rotated(ang))
		inner.append(c + (q * sz).rotated(ang))
	ci.draw_circle(c, sz * 1.9, Color(0.1, 0.8, 1.0, 0.25))
	ci.draw_colored_polygon(outer, Color(0, 0, 0, 0.95))
	ci.draw_colored_polygon(inner, Color(0.15, 0.9, 1.0))

static func dist_text(m: float) -> String:
	# Coarse steps keep labels from re-shaping text every frame.
	return ("%.1f km" % (m / 1000.0)) if m >= 1000.0 else ("%d m" % (int(m / 10.0) * 10))

class Minimap extends Control:
	var game: Node
	var map_rect: TextureRect
	var overlay: Control
	var font := ThemeDB.fallback_font
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
	COLOR = vec4(c.rgb * 0.75, a * 0.9);
}"""
		var m := ShaderMaterial.new()
		m.shader = sh
		map_rect.material = m
		add_child(map_rect)
		# Markers are drawn on a child ABOVE the map texture (parent _draw would be covered).
		overlay = Control.new()
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.draw.connect(_paint)
		add_child(overlay)
	func refresh() -> void:
		overlay.queue_redraw()
	func _paint() -> void:
		if game == null or game.player == null:
			return
		var ci := overlay
		var car: Car = game.player
		var world: World = game.world
		var S := size.x
		var half := S * 0.5
		var center := Vector2(half, half)
		var zoom := 1.5 - clampf(car.speed / 80.0, 0.0, 1.0) * 0.6
		var view_m := 800.0 / zoom # metres across the minimap
		var fwd := -car.global_transform.basis.z
		var yaw := atan2(fwd.x, -fwd.z)
		var pos := Vector2(car.global_position.x, car.global_position.z)
		var mat := map_rect.material as ShaderMaterial
		mat.set_shader_parameter("center_uv", (pos + Vector2(world.HALF, world.HALF)) / (world.HALF * 2.0))
		mat.set_shader_parameter("rot", yaw)
		mat.set_shader_parameter("span", view_m / (world.HALF * 2.0) * 0.5)
		var scale := S / view_m
		var rim := half - 14.0
		var to_map := func(w: Vector2) -> Vector2:
			return center + (w - pos).rotated(-yaw) * scale
		# Police search zone while evading.
		var pol: Police = game.police
		if pol.pursuit and pol.cooldown > 0.0 and pol.last_seen != Vector2.INF:
			var zc: Vector2 = to_map.call(pol.last_seen)
			var zr := Police.SEARCH_RADIUS * scale
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			# Clip the zone to the round minimap: points outside are pulled onto the rim.
			var poly := PackedVector2Array()
			for k in 48:
				var q := zc + Vector2(cos(TAU * k / 48.0), sin(TAU * k / 48.0)) * zr
				if q.distance_to(center) > half - 2.0:
					q = center + (q - center).normalized() * (half - 2.0)
				poly.append(q)
			if Geometry2D.triangulate_polygon(poly).size() > 0:
				ci.draw_colored_polygon(poly, Color(1, 0.1, 0.15, 0.12 + 0.06 * pulse))
			var ring := poly.duplicate()
			ring.append(poly[0])
			ci.draw_polyline(ring, Color(1, 0.2, 0.25, 0.7), 2.0, true)
		# GPS route: dark casing + bright line
		var route: PackedVector2Array = game.gps_route
		var pts := PackedVector2Array()
		for q in route:
			pts.append(to_map.call(q))
		for i in range(pts.size() - 1):
			if pts[i].distance_to(center) < half + 60.0 or pts[i + 1].distance_to(center) < half + 60.0:
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				if a.distance_to(center) > rim:
					a = center + (a - center).limit_length(rim)
				if b.distance_to(center) > rim:
					b = center + (b - center).limit_length(rim)
				ci.draw_line(a, b, Color(0, 0, 0, 0.85), 9.0, true)
				ci.draw_line(a, b, ROUTE_COL, 5.0, true)
		for mk in HUD.map_markers(game, false):
			var p: Vector2 = to_map.call(mk[0])
			var clamped := p.distance_to(center) > rim
			if clamped:
				p = center + (p - center).normalized() * rim
			var sz := 9.0 if mk[2] == "mission" else (7.0 if mk[2] in ["home", "race"] else 6.0)
			HUD.draw_marker(ci, p, mk[1], mk[2], sz)
			if mk[2] == "mission":
				var d: float = (mk[0] as Vector2).distance_to(pos)
				var tp := center + (p - center) * (0.78 if clamped else 1.0) + Vector2(-50, 30 if p.y < center.y + 40 else -22)
				ci.draw_string_outline(font, tp, HUD.dist_text(d), HORIZONTAL_ALIGNMENT_CENTER, 100, 17, 5, Color.BLACK)
				ci.draw_string(font, tp, HUD.dist_text(d), HORIZONTAL_ALIGNMENT_CENTER, 100, 17, Color(1, 0.85, 0.2))
		HUD.draw_player(ci, center, 0.0, 13.0)
		ci.draw_arc(center, half - 1, 0, TAU, 96, Color(0, 0, 0, 0.8), 5.0, true)
		ci.draw_arc(center, half - 3, 0, TAU, 96, Color(1, 1, 1, 0.55), 2.0, true)
		var n := Vector2(0, -1).rotated(-yaw) * (half - 16)
		ci.draw_circle(center + n, 11, Color(0, 0, 0, 0.85))
		ci.draw_string(font, center + n + Vector2(-8, 6), "N", HORIZONTAL_ALIGNMENT_CENTER, 16, 16, ACCENT)

class BigMap extends Control:
	## Full-screen world map (pauses the game). Toggle with the Map button.
	var game: Node
	var font := ThemeDB.fallback_font
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visible = false
	var map_origin := Vector2.ZERO
	var map_side := 1.0
	var cursor := Vector2(-1, -1)
	func open() -> void:
		visible = true
		get_tree().paused = true
		cursor = Vector2(-1, -1)
		queue_redraw()
	func _to_world(sp: Vector2) -> Vector2:
		var world: World = game.world
		return (sp - map_origin) / map_side * (world.HALF * 2.0) - Vector2(world.HALF, world.HALF)
	func _set_pin() -> void:
		if cursor.x < 0.0:
			return
		var wp := _to_world(cursor)
		var world: World = game.world
		if absf(wp.x) > world.HALF or absf(wp.y) > world.HALF:
			return
		if game.custom_wp != Vector2.INF and game.custom_wp.distance_to(wp) < 120.0:
			game.custom_wp = Vector2.INF # clicking the pin again removes it
		else:
			game.custom_wp = world.node_pos[world.nearest_node(wp)]
		game.gps_timer = 0.0
		game.audio.play_oneshot("beep", 1.7, -10.0)
	func close() -> void:
		visible = false
		if game.is_playing():
			get_tree().paused = false
	func _input(event: InputEvent) -> void:
		if not visible:
			return
		if event.is_action_pressed("map") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			close()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion:
			cursor = get_local_mouse_position()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			cursor = get_local_mouse_position()
			_set_pin()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_set_pin()
			get_viewport().set_input_as_handled()
	func _process(d: float) -> void:
		if not visible:
			return
		# Left stick / D-pad moves the waypoint cursor.
		var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
		if v.length() < 0.2:
			v = Vector2.ZERO
		v += Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down")) if v == Vector2.ZERO else Vector2.ZERO
		if v != Vector2.ZERO:
			if cursor.x < 0.0:
				var car: Car = game.player
				cursor = map_origin + (Vector2(car.global_position.x, car.global_position.z) + Vector2(game.world.HALF, game.world.HALF)) / (game.world.HALF * 2.0) * map_side
			cursor += v.limit_length(1.0) * 520.0 * d
			cursor = cursor.clamp(map_origin, map_origin + Vector2(map_side, map_side))
		queue_redraw()
	func _draw() -> void:
		if game == null or game.player == null:
			return
		var world: World = game.world
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.04, 0.92))
		var side := minf(size.x - 380.0, size.y - 80.0)
		var origin := Vector2((size.x - 340.0 - side) * 0.5, (size.y - side) * 0.5)
		map_origin = origin
		map_side = side
		var rect := Rect2(origin, Vector2(side, side))
		draw_texture_rect(MAP_TEX, rect, false, Color(0.85, 0.85, 0.85))
		draw_rect(rect.grow(2), Color(1, 1, 1, 0.4), false, 2.0)
		var to_map := func(w: Vector2) -> Vector2:
			return origin + (w + Vector2(world.HALF, world.HALF)) / (world.HALF * 2.0) * side
		var pol: Police = game.police
		if pol.pursuit and pol.cooldown > 0.0 and pol.last_seen != Vector2.INF:
			var zc: Vector2 = to_map.call(pol.last_seen)
			var zr := Police.SEARCH_RADIUS / (world.HALF * 2.0) * side
			draw_circle(zc, zr, Color(1, 0.1, 0.15, 0.18))
			draw_arc(zc, zr, 0, TAU, 48, Color(1, 0.2, 0.25, 0.8), 2.0, true)
		var route: PackedVector2Array = game.gps_route
		for i in range(route.size() - 1):
			draw_line(to_map.call(route[i]), to_map.call(route[i + 1]), Color(0, 0, 0, 0.85), 8.0, true)
		for i in range(route.size() - 1):
			draw_line(to_map.call(route[i]), to_map.call(route[i + 1]), ROUTE_COL, 4.0, true)
		var car: Car = game.player
		var pos := Vector2(car.global_position.x, car.global_position.z)
		for mk in HUD.map_markers(game, true):
			var p: Vector2 = to_map.call(mk[0])
			var sz := 11.0 if mk[2] == "mission" else (8.0 if mk[2] in ["home", "race"] else 6.0)
			HUD.draw_marker(self, p, mk[1], mk[2], sz)
			if mk[3] != "":
				var txt: String = mk[3]
				if mk[2] == "mission":
					txt += "  (" + HUD.dist_text((mk[0] as Vector2).distance_to(pos)) + ")"
				var fs := 20 if mk[2] == "mission" else 16
				var tp := p + Vector2(sz + 8, -12 if mk[2] == "mission" else 6)
				draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color.BLACK)
				draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, mk[1])
		var fwd := -car.global_transform.basis.z
		var pp: Vector2 = to_map.call(pos)
		HUD.draw_player(self, pp, atan2(fwd.x, -fwd.z), 14.0)
		draw_string_outline(font, pp + Vector2(-20, 36), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
		draw_string(font, pp + Vector2(-20, 36), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.15, 0.9, 1.0))
		# Legend
		var lx := size.x - 330.0
		var ly := 90.0
		draw_string(font, Vector2(lx, ly - 30), "MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color.WHITE)
		var career: Career = game.career
		var obj := "Free roam: wait for a phone call, or drive to a race marker."
		if not career.active.is_empty():
			obj = str(career.active.title) + ": " + career.waypoint_label
		elif career.race:
			obj = "Race in progress"
		draw_multiline_string(font, Vector2(lx, ly + 10), obj, HORIZONTAL_ALIGNMENT_LEFT, 300, 18, -1, Color(1, 0.85, 0.3))
		ly += 110.0
		var legend := [["mission", Color(1.0, 0.82, 0.1), "Mission / waypoint"], ["home", Color(0.3, 1.0, 0.55), "Home / garage"], ["race", Color(0.3, 0.75, 1.0), "Street race"], ["cop", Color(1, 0.15, 0.2), "Police"], ["trap", Color(0.95, 0.95, 0.95), "Speed trap"], ["drift", Color(1.0, 0.55, 0.1), "Drift zone"]]
		for e in legend:
			HUD.draw_marker(self, Vector2(lx + 12, ly), e[1], e[0], 8.0)
			draw_string(font, Vector2(lx + 36, ly + 6), e[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
			ly += 34.0
		HUD.draw_player(self, Vector2(lx + 12, ly), 0.0, 9.0)
		draw_string(font, Vector2(lx + 36, ly + 6), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		ly += 34.0
		draw_line(Vector2(lx + 2, ly), Vector2(lx + 24, ly), ROUTE_COL, 4.0)
		draw_string(font, Vector2(lx + 36, ly + 6), "GPS route", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		ly += 60.0
		draw_string(font, Vector2(lx, ly), "[%s] Close" % Settings.glyph("map"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.7))
		draw_string(font, Vector2(lx, ly + 28), "[%s / click] Set or clear waypoint" % ("✕" if Settings.pad_style() == "playstation" else "A") if Settings.using_pad else "[Click] Set or clear waypoint", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
		if cursor.x >= 0.0:
			draw_line(cursor + Vector2(-14, 0), cursor + Vector2(14, 0), Color.WHITE, 2.0)
			draw_line(cursor + Vector2(0, -14), cursor + Vector2(0, 14), Color.WHITE, 2.0)
			draw_arc(cursor, 9.0, 0, TAU, 24, Color(1, 1, 1, 0.8), 2.0)
