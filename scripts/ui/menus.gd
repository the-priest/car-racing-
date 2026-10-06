class_name Menus
extends CanvasLayer
## Main menu, pause, garage, settings, controls, credits, results and loading.
## Everything is focus-navigable for gamepads.

signal play_pressed
signal resume_pressed
signal quit_to_menu
signal garage_closed

const ACCENT := Color(1.0, 0.48, 0.1)

var game: Node
var theme_ui: Theme
var screens := {}
var current := ""
var stack: Array[String] = []
var garage_sel := "vanta"
var confirm_new := false
var listening := "" # action being rebound on the remap screen
var _screen_shown_ms := 0
var focus_hint := "" # focus the button starting with this text after the next rebuild
var loading_bar: ProgressBar
var loading_label: Label

func setup(g: Node) -> void:
	game = g
	layer = 10
	theme_ui = _make_theme()
	_build_loading()

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.045)
	normal.border_color = Color(1, 1, 1, 0.0)
	normal.border_width_left = 4
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 24
	normal.content_margin_right = 18
	normal.content_margin_top = 13
	normal.content_margin_bottom = 13
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(1.0, 0.48, 0.1, 0.28)
	focus.border_color = ACCENT
	focus.shadow_color = Color(1.0, 0.45, 0.1, 0.25)
	focus.shadow_size = 8
	var pressed := focus.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1.0, 0.48, 0.1, 0.5)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(1, 1, 1, 0.02)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", focus)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", Color(0.9, 0.92, 0.96))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.03, 0.035, 0.06, 0.9)
	panel.border_color = Color(1.0, 0.48, 0.1, 0.55)
	panel.border_width_top = 3
	panel.set_corner_radius_all(8)
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 24
	panel.set_content_margin_all(34)
	t.set_stylebox("panel", "PanelContainer", panel)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.1)
	bar_bg.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.25)
	sb.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t

func _screen(name: String, side := false, scroll_h := 0) -> VBoxContainer:
	var bg := Control.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.theme = theme_ui
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Soft gradient shade behind the panel (left-heavy for side menus).
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.012, 0.025, 0.92 if side else 0.7))
	g.set_color(1, Color(0.01, 0.012, 0.025, 0.0 if side else 0.7))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(0.75, 0.5)
	shade.texture = gt
	if not side:
		# Centred menus blur and darken the game behind them.
		var blur := ColorRect.new()
		blur.set_anchors_preset(Control.PRESET_FULL_RECT)
		blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blur.material = _blur_material()
		bg.add_child(blur)
		g.set_color(0, Color(0.01, 0.012, 0.025, 0.45))
		g.set_color(1, Color(0.01, 0.012, 0.025, 0.45))
	bg.add_child(shade)
	var panel := PanelContainer.new()
	var holder: Control
	if side:
		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		margin.custom_minimum_size = Vector2(700, 0)
		margin.add_theme_constant_override("margin_left", 70)
		margin.add_theme_constant_override("margin_top", 60)
		margin.add_theme_constant_override("margin_bottom", 60)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(margin)
		margin.add_child(panel)
		holder = margin
	else:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(center)
		center.add_child(panel)
		panel.custom_minimum_size = Vector2(760, 0)
		holder = center
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	var scroll: ScrollContainer = null
	if scroll_h > 0 or side:
		scroll = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.custom_minimum_size = Vector2(0, scroll_h)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(scroll)
		scroll.add_child(box)
	else:
		panel.add_child(box)
	bg.visible = false
	add_child(bg)
	screens[name] = {"root": bg, "box": box, "scroll": scroll}
	return box

var _blur_mat: ShaderMaterial

func _blur_material() -> ShaderMaterial:
	if _blur_mat:
		return _blur_mat
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 7.0;
	vec3 acc = vec3(0.0);
	float w = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float k = exp(-float(x * x + y * y) / 8.0);
			acc += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px).rgb * k;
			w += k;
		}
	}
	COLOR = vec4(acc / w, 1.0);
}"""
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = sh
	return _blur_mat

func _title(box: Container, text: String, size := 44) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(l)

func _text(box: Container, text: String, size := 18, color := Color(1, 1, 1, 0.65)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l

func _button(box: Container, text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = disabled
	b.pressed.connect(func():
		game.audio.play_oneshot("beep", 1.4, -12.0)
		cb.call())
	# Soft tick when moving between buttons (not on the automatic first focus).
	b.focus_entered.connect(func():
		if Time.get_ticks_msec() - _screen_shown_ms > 150:
			game.audio.play_oneshot("beep", 2.4, -24.0))
	box.add_child(b)
	return b

func show_screen(name: String, push := true) -> void:
	# Refreshing the same screen keeps focus on the same button (pad users).
	if name != "main":
		confirm_new = false
	var keep := -1
	var keep_key := ""
	if name == current and screens.has(name):
		var f := get_viewport().gui_get_focus_owner()
		if f is Button:
			keep = _buttons(screens[name].box).find(f)
			keep_key = (f as Button).text.split(":")[0]
	if current != "" and screens.has(current):
		screens[current].root.visible = false
		if push and current != name:
			stack.append(current)
	var fresh := name != current
	_screen_shown_ms = Time.get_ticks_msec()
	current = name
	_rebuild(name)
	screens[name].root.visible = true
	if fresh:
		var r: Control = screens[name].root
		r.modulate.a = 0.0
		create_tween().tween_property(r, "modulate:a", 1.0, 0.16)
	await get_tree().process_frame
	var btns := _buttons(screens[name].box)
	if focus_hint != "":
		for x in btns:
			if (x as Button).text.begins_with(focus_hint):
				(x as Button).grab_focus()
				focus_hint = ""
				return
		focus_hint = ""
	if keep >= 0 and not btns.is_empty():
		var k := mini(keep, btns.size() - 1)
		# Prefer the button with the same label (settings rows keep their name).
		for j in btns.size():
			if keep_key != "" and (btns[j] as Button).text.split(":")[0] == keep_key:
				k = j
				break
		while k < btns.size() - 1 and (btns[k] as Button).disabled:
			k += 1
		var b: Button = btns[k]
		if confirm_new:
			for x in btns:
				if x.text.begins_with("CONFIRM"):
					b = x
		b.grab_focus()
		return
	var first := _first_focus(screens[name].box)
	if first:
		first.grab_focus()

func _buttons(box: Node) -> Array:
	return box.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree())

func back() -> void:
	if current == "":
		return
	screens[current].root.visible = false
	if current == "garage":
		garage_closed.emit()
	if stack.is_empty():
		current = ""
		resume_pressed.emit()
		return
	var prev: String = stack.pop_back()
	current = ""
	show_screen(prev, false)

func close_all() -> void:
	for s in screens.values():
		s.root.visible = false
	current = ""
	stack.clear()

func is_open() -> bool:
	return current != ""

func _first_focus(n: Node) -> Control:
	for c in n.get_children():
		if c is Button and not c.disabled:
			return c
		var r := _first_focus(c)
		if r:
			return r
	return null

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if _credits_root and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		credits_done.emit()
		get_viewport().set_input_as_handled()
		return
	if current == "" or current == "loading":
		return
	if event.is_action_pressed("ui_cancel") or (event.is_action_pressed("pause") and current != "main"):
		if current != "main":
			back()
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- loading
func _build_loading() -> void:
	var box := _screen("loading")
	_title(box, "VELOCITY HEAT", 64)
	_text(box, "Open-world getaway driving", 20, ACCENT)
	loading_bar = ProgressBar.new()
	loading_bar.max_value = 1.0
	loading_bar.show_percentage = false
	loading_bar.custom_minimum_size = Vector2(560, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	loading_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(loading_bar)
	loading_label = _text(box, "Loading...")
	var tips := [
		"Cars grip by default. To drift: while steering into a corner, lift off the throttle and stab it again. Steer to set the angle, ease off to straighten. The handbrake is for tight hairpins.",
		"Ram a cop hard while you're the faster car to take it out of the chase - it adds to your bounty.",
		"The police helicopter can't see you between tall buildings. Head downtown to break its line of sight.",
		"Roadblocks are just parked cars. Hit them flat out.",
		"Air One runs out of fuel eventually. Survive long enough and it has to leave.",
		"No call coming? Press the phone button to ring your contact yourself.",
		"Near misses, big air and drifting all refill your nitrous.",
		"Night jobs pay 25% more.",
		"Hold throttle + brake while stopped for a burnout.",
		"Open the full map with M / View / Touchpad to see every race and your next job.",
	]
	_text(box, "TIP: " + str(tips[randi() % tips.size()]), 16)
	screens.loading.root.visible = true
	current = "loading"

func set_loading(msg: String, f: float) -> void:
	loading_label.text = msg
	loading_bar.value = f

# ---------------------------------------------------------------- screens
func _rebuild(name: String) -> void:
	if not screens.has(name):
		match name:
			"main": _screen("main", true)
			"pause": _screen("pause")
			"garage": _screen("garage", true)
			"settings": _screen("settings", false, 760)
			"controls": _screen("controls")
			"credits": _screen("credits")
			"story": _screen("story")
			"records": _screen("records", false, 760)
			"remap": _screen("remap", false, 760)
			"results": _screen("results")
	var box: VBoxContainer = screens[name].box
	_clear(box)
	match name:
		"main": _build_main(box)
		"pause": _build_pause(box)
		"garage": _build_garage(box)
		"settings": _build_settings(box)
		"controls": _build_controls(box)
		"credits": _build_credits(box)
		"story": _build_story(box)
		"records": _build_records(box)
		"remap": _build_remap(box)

func _build_main(box: VBoxContainer) -> void:
	box.add_theme_constant_override("separation", 8)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	box.add_child(spacer)
	_title(box, "VELOCITY\nHEAT", 68)
	_text(box, "GETAWAY DRIVER  ·  OPEN WORLD", 18, ACCENT)
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 6)
	box.add_child(sp2)
	var started: bool = int(Save.data.contract) > 0 or float(Save.data.playtime) > 30.0
	_button(box, "CONTINUE" if started else "START CAREER", func(): play_pressed.emit())
	if started:
		_button(box, "STORY", func(): show_screen("story"))
		_button(box, "RECORDS", func(): show_screen("records"))
	_button(box, "SETTINGS", func(): show_screen("settings"))
	_button(box, "CONTROLS", func(): show_screen("controls"))
	_button(box, "CREDITS", func(): show_screen("credits"))
	if started:
		_button(box, "NEW CAREER" if not confirm_new else "CONFIRM: ERASE ALL PROGRESS?", func():
			if not confirm_new:
				confirm_new = true
				show_screen("main", false)
				return
			confirm_new = false
			Save.wipe()
			game.reset_career()
			show_screen("main", false))
	_button(box, "QUIT", func():
		Save.save_game()
		get_tree().quit())
	var done_ch := int(Save.data.contract)
	var total_ch := Career.CONTRACTS.size()
	_text(box, "Bank  $%s   ·   %s" % [HUD._fmt(int(Save.data.cash)), ("Chapter %d of %d" % [done_ch + 1, total_ch]) if done_ch < total_ch else "Story complete"], 18)

func _build_pause(box: VBoxContainer) -> void:
	_title(box, "PAUSED")
	var career: Career = game.career
	_button(box, "RESUME", func(): back())
	if career.race != null:
		_button(box, "RESTART RACE", func():
			close_all()
			game._on_resume()
			game.police.clear()
			career.restart_race())
	_button(box, "STORY", func(): show_screen("story"))
	_button(box, "RECORDS", func(): show_screen("records"))
	if career.race != null or not career.active.is_empty():
		_button(box, "ABANDON " + ("RACE" if career.race else "JOB"), func():
			close_all()
			game._on_resume()
			career.abandon())
	var at_home: bool = game.player_at_home()
	_button(box, "GARAGE" + ("" if at_home else "  (drive home to use)"), func():
		close_all()
		game._open_garage(), not at_home or game.police.pursuit)
	if str(Settings.data.time_mode) == "dynamic":
		_button(box, "SKIP TO " + ("DAY" if game.daynight.night > 0.5 else "NIGHT"), func():
			game.skip_time()
			show_screen("pause", false), game.police.pursuit)
	_button(box, "PHOTO MODE", func(): game.enter_photo())
	_button(box, "RESET CAR TO ROAD", func():
		game.reset_to_road()
		back())
	_button(box, "SETTINGS", func(): show_screen("settings"))
	_button(box, "CONTROLS", func(): show_screen("controls"))
	_button(box, "MAIN MENU", func():
		close_all()
		quit_to_menu.emit())
	_button(box, "QUIT TO DESKTOP", func():
		game.persist()
		get_tree().quit())

func _build_garage(box: VBoxContainer) -> void:
	_title(box, "GARAGE")
	_text(box, "Bank  $%s" % HUD._fmt(int(Save.data.cash)), 22, Color(0.5, 1.0, 0.62))
	var owned: Array = Save.data.owned
	for id in Data.CAR_ORDER:
		var c: Dictionary = Data.CARS[id]
		var label := "[%s]  %s" % [c.tier, c.name]
		if owned.has(id):
			label += "   -  DRIVING" if Save.data.car == id else "   -  OWNED"
		elif not Data.unlocked(id, int(Save.data.contract)):
			label += "   -  LOCKED"
		else:
			label += "   -  $%s" % HUD._fmt(int(c.price))
		var b := _button(box, label, func():
			garage_sel = id
			game.preview_car(id)
			show_screen("garage", false))
		if id == garage_sel:
			b.add_theme_color_override("font_color", ACCENT)
	var sel: Dictionary = Data.CARS[garage_sel]
	var up: Dictionary = Save.data.upgrades.get(garage_sel, {})
	var st := Data.stats_for(garage_sel, up)
	_text(box, "\n%s  ·  %s  ·  %d cyl  ·  PI %d" % [sel.name, "AWD" if sel.awd else "RWD", sel.cyl, Data.perf_index(st)], 20, Color.WHITE)
	_text(box, Data.DESC.get(garage_sel, ""), 15, Color(1, 1, 1, 0.6))
	var base := Data.stats_for(garage_sel, {})
	for row in [["TOP SPEED", st.top, base.top, 150.0, "%d km/h" % int(st.top * 3.6 * 0.97)],
			["ACCELERATION", st.accel, base.accel, 30.0, "0-100 %.1fs" % (27.8 / (st.accel * 0.72))],
			["HANDLING", st.grip, base.grip, 30.0, "%.2fg" % (st.grip / 9.81)],
			["NITROUS", st.nitro * st.nitro_cap, base.nitro * base.nitro_cap, 160.0, "%.0fs" % st.nitro_cap]]:
		box.add_child(_stat_bar(row[0], float(row[1]) / float(row[3]), float(row[2]) / float(row[3]), row[4]))
	if not owned.has(garage_sel) and not Data.unlocked(garage_sel, int(Save.data.contract)):
		var need := int(Data.TIER_UNLOCK.get(sel.tier, 0))
		_text(box, "LOCKED - finish story chapter %d (%s) to unlock tier %s." % [need, Career.CONTRACTS[need - 1].title, sel.tier], 17, ACCENT)
	elif not owned.has(garage_sel):
		_button(box, "BUY  $%s" % HUD._fmt(int(sel.price)), func():
			if int(Save.data.cash) >= int(sel.price):
				Save.add_cash(-int(sel.price))
				Save.data.owned.append(garage_sel)
				Save.data.car = garage_sel
				Save.save_game()
				game.apply_player_car()
				game.audio.play_oneshot("reward")
			show_screen("garage", false), int(Save.data.cash) < int(sel.price))
	else:
		if Save.data.car != garage_sel:
			_button(box, "DRIVE THIS CAR", func():
				Save.data.car = garage_sel
				Save.save_game()
				game.apply_player_car()
				show_screen("garage", false))
		for k in Data.UPGRADES:
			var u: Dictionary = Data.UPGRADES[k]
			var lvl: int = up.get(k, 0)
			var levels: int = u.cost.size()
			var maxed := lvl >= levels
			var cost: int = 0 if maxed else u.cost[lvl]
			_button(box, "%s  %s   %s" % [u.name, "■".repeat(lvl) + "□".repeat(levels - lvl), "MAXED" if maxed else "$" + HUD._fmt(cost)], func():
				if not maxed and int(Save.data.cash) >= cost:
					Save.add_cash(-cost)
					var nu: Dictionary = Save.data.upgrades.get(garage_sel, {}).duplicate()
					nu[k] = lvl + 1
					Save.data.upgrades[garage_sel] = nu
					Save.save_game()
					game.apply_player_car()
					game.audio.play_oneshot("reward")
				show_screen("garage", false), maxed or int(Save.data.cash) < cost)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		for pc in Data.PAINTS:
			var sw := Button.new()
			sw.custom_minimum_size = Vector2(44, 44)
			var sb := StyleBoxFlat.new()
			sb.bg_color = pc
			sb.set_corner_radius_all(22)
			var sf := sb.duplicate() as StyleBoxFlat
			sf.set_border_width_all(3)
			sf.border_color = Color.WHITE
			sw.add_theme_stylebox_override("normal", sb)
			sw.add_theme_stylebox_override("hover", sf)
			sw.add_theme_stylebox_override("focus", sf)
			sw.add_theme_stylebox_override("pressed", sf)
			sw.pressed.connect(func():
				Save.data.paint[garage_sel] = pc.to_html()
				Save.save_game()
				game.preview_car(garage_sel))
			row.add_child(sw)
		_text(box, "Paint", 18)
		box.add_child(row)
		var rims: Dictionary = Save.data.get("rims", {})
		var ri := int(rims.get(garage_sel, 0))
		_button(box, "Rims:  ‹ %s ›" % Data.RIMS[ri][0], func():
			var nr: Dictionary = Save.data.get("rims", {}).duplicate()
			nr[garage_sel] = (ri + 1) % Data.RIMS.size()
			Save.data.rims = nr
			Save.save_game()
			game.preview_car(garage_sel)
			show_screen("garage", false))
		var gi := int(Save.data.get("glow", {}).get(garage_sel, 0))
		_button(box, "Underglow:  ‹ %s ›" % Data.GLOWS[gi][0], func():
			var ng: Dictionary = Save.data.get("glow", {}).duplicate()
			ng[garage_sel] = (gi + 1) % Data.GLOWS.size()
			Save.data.glow = ng
			Save.save_game()
			game.preview_car(garage_sel)
			show_screen("garage", false))
	_button(box, "BACK", func(): back())

## Stat bar: stock value in white, upgrade gain in accent colour.
func _stat_bar(label: String, val: float, stock: float, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(130, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	row.add_child(l)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(150, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.draw.connect(func():
		var w := bar.size.x
		bar.draw_rect(Rect2(0, 0, w, 8), Color(1, 1, 1, 0.1))
		bar.draw_rect(Rect2(0, 0, w * clampf(val, 0.0, 1.0), 8), ACCENT)
		bar.draw_rect(Rect2(0, 0, w * clampf(minf(stock, val), 0.0, 1.0), 8), Color(0.92, 0.92, 0.95)))
	row.add_child(bar)
	var v := Label.new()
	v.text = text
	v.add_theme_font_size_override("font_size", 14)
	row.add_child(v)
	return row

const SETTINGS := [
	["quality", "Graphics preset", ["low", "medium", "high", "ultra"], ["Low (laptops)", "Medium", "High", "Ultra"]],
	["render_scale", "Render scale", [0.0, 0.5, 0.67, 0.77, 0.85, 1.0, 1.25], ["Preset", "50%", "67%", "77%", "85%", "100%", "125%"]],
	["fullscreen", "Fullscreen", [true, false], ["On", "Off"]],
	["vsync", "V-Sync", [true, false], ["On", "Off"]],
	["fov", "Field of view", [60.0, 66.0, 72.0, 78.0, 85.0, 95.0], ["60", "66", "72", "78", "85", "95"]],
	["assists", "Driving assists", [true, false], ["Traction + stability", "Off (raw)"]],
	["manual", "Gearbox", [false, true], ["Automatic", "Manual"]],
	["units", "Units", ["kmh", "mph"], ["km/h", "mph"]],
	["traffic", "Traffic density", [0.0, 0.5, 1.0, 1.5], ["Off", "Light", "Normal", "Heavy"]],
	["music", "Music volume", [0.0, 0.25, 0.5, 0.75, 1.0], ["Off", "25%", "50%", "75%", "100%"]],
	["sfx", "Effects volume", [0.0, 0.25, 0.5, 0.85, 1.0], ["Off", "25%", "50%", "85%", "100%"]],
	["radio", "Radio (your music)", [false, true], ["Off - soundtrack", "On"]],
	["radio_shuffle", "Radio order", [true, false], ["Shuffle", "In order"]],
	["difficulty", "Difficulty", ["easy", "normal", "hard"], ["Easy", "Normal", "Hard"]],
	["time_mode", "Time of day", ["dynamic", "day", "dusk", "night"], ["Dynamic cycle", "Always day", "Always dusk", "Always night"]],
	["weather", "Weather", ["dynamic", "clear", "rain"], ["Dynamic", "Always clear", "Always rain"]],
	["speed_fx", "Speed blur", [true, false], ["On", "Off"]],
	["cam_shake", "Camera shake", [0.0, 0.5, 1.0], ["Off", "Low", "Full"]],
	["show_fps", "Show FPS", [false, true], ["Off", "On"]],
	["vibration", "Controller vibration", [0.0, 0.5, 0.75, 1.0, 1.5], ["Off", "Low", "Medium", "Full", "Extreme"]],
	["steer_sens", "Steering sensitivity", [0.7, 0.85, 1.0, 1.15, 1.3], ["70%", "85%", "100%", "115%", "130%"]],
	["deadzone", "Stick deadzone", [0.03, 0.05, 0.08, 0.12, 0.18], ["3%", "5%", "8%", "12%", "18%"]],
	["steer_curve", "Steering response", [1.0, 1.3, 1.6, 2.0], ["Linear", "Smooth", "Precise centre", "Very precise"]],
]

func _build_settings(box: VBoxContainer) -> void:
	_title(box, "SETTINGS")
	if Settings.needs_restart():
		_text(box, "This preset uses a different renderer. Restart to apply it fully.", 17, ACCENT)
		_button(box, "RESTART NOW", func():
			game.persist()
			OS.set_restart_on_exit(true)
			get_tree().quit())
	for row in SETTINGS:
		var key: String = row[0]
		var values: Array = row[2]
		var names: Array = row[3]
		var cur := values.find(Settings.data[key])
		if cur < 0:
			cur = 0
		var b := _button(box, "", func(): pass)
		var update_text := func(i: int): b.text = "%s:  ‹ %s ›" % [row[1], names[i]]
		update_text.call(cur)
		var cycle := func(dir: int):
			var i := (values.find(Settings.data[key]) + dir + values.size()) % values.size()
			Settings.set_value(key, values[i])
			update_text.call(i)
			game.on_settings_changed()
			if key == "radio" and Settings.data.radio != values[i]:
				b.text = "Radio: no MP3s found - use OPEN RADIO FOLDER below"
				return
			if key == "radio_shuffle":
				game.audio._radio_shuffle()
			update_text.call(maxi(values.find(Settings.data[key]), 0))
			if key == "quality":
				show_screen("settings", false)
		b.pressed.connect(func(): cycle.call(1))
		b.gui_input.connect(func(ev: InputEvent):
			if ev.is_action_pressed("ui_left"):
				cycle.call(-1)
				b.accept_event()
			elif ev.is_action_pressed("ui_right"):
				cycle.call(1)
				b.accept_event())
	_button(box, "OPEN RADIO FOLDER", func():
		var dir := AudioManager.radio_folder()
		DirAccess.make_dir_recursive_absolute(dir)
		if not FileAccess.file_exists(dir.path_join(".gdignore")):
			var gi := FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE)
			if gi:
				gi.close()
		OS.shell_open(dir)
		game.audio.radio_scan())
	_text(box, "Radio: drop MP3 files into %s, then press %s while driving (tap: on / next song, hold: off)." % [AudioManager.radio_folder(), Settings.glyph("radio")], 14)
	if not Input.get_connected_joypads().is_empty():
		_button(box, "TEST VIBRATION", func():
			var g := float(Settings.data.vibration)
			for d in Input.get_connected_joypads():
				Input.start_joy_vibration(d, clampf(0.6 * g, 0.0, 1.0), clampf(0.8 * g, 0.0, 1.0), 0.5))
	_text(box, "Low uses the lightweight OpenGL renderer for older laptops. Ultra enables real-time global illumination, screen-space reflections & GI, volumetric fog, 8K shadows and dense grass.", 15)
	_button(box, "BACK", func(): back())

func _build_controls(box: VBoxContainer) -> void:
	_title(box, "CONTROLS")
	var ps := Settings.pad_style() == "playstation"
	var G: Dictionary = Settings.PLAYSTATION if ps else Settings.XBOX
	_text(box, ("PlayStation" if ps else "Xbox / generic") + " controller layout" + ("  -  " + Input.get_joy_name(Input.get_connected_joypads()[0]) if not Input.get_connected_joypads().is_empty() else "  -  no controller detected"), 16, ACCENT)
	var rows := []
	for a in Settings.REBINDABLE:
		var pad := Settings.binding_text(a, true)
		if a.begins_with("steer_"):
			pad = "Left stick"
		rows.append([Settings.ACTION_NAMES[a], Settings.binding_text(a, false), pad + (" (hold)" if a == "reset" else "")])
	rows.append(["Burnout / donuts", "Throttle + brake stopped", G.throttle + " + " + G.brake])
	rows.append(["Look around", "-", "Right stick"])
	rows.append(["Pause", "Esc", G.pause])
	rows.append(["Menu select / back", "Enter / Esc", G.accept + " / " + G.back])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	for r in rows:
		for k in 3:
			var l := Label.new()
			l.text = r[k]
			l.add_theme_font_size_override("font_size", 17)
			l.add_theme_color_override("font_color", Color(1, 1, 1, 0.65) if k == 0 else Color.WHITE)
			grid.add_child(l)
	box.add_child(grid)
	_button(box, "REMAP CONTROLS", func(): show_screen("remap"))
	_text(box, "Vibration strength, steering sensitivity, deadzone and response curve are in Settings.", 15)
	_button(box, "BACK", func(): back())

func _build_remap(box: VBoxContainer) -> void:
	_title(box, "REMAP CONTROLS")
	if listening != "":
		_text(box, "Press a key or controller button for:", 18)
		_text(box, str(Settings.ACTION_NAMES[listening]).to_upper(), 30, ACCENT)
		_text(box, "Esc or Start / Options cancels." + ("" if Settings.PAD_REBINDABLE.has(listening) else "  (Keyboard only - this one uses an analog trigger or stick on controllers.)"), 15)
		return
	_text(box, "Select an action, then press the new key or button.", 16)
	for a in Settings.REBINDABLE:
		var pad := "Left stick" if a.begins_with("steer_") else Settings.binding_text(a, true)
		_button(box, "%s:  %s   ·   %s" % [Settings.ACTION_NAMES[a], Settings.binding_text(a, false), pad], func():
			listening = a
			show_screen("remap", false))
	_button(box, "RESET TO DEFAULTS", func():
		Settings.reset_bindings()
		show_screen("remap", false))
	_button(box, "BACK", func(): back())

func _input(event: InputEvent) -> void:
	if listening == "" or current != "remap":
		return
	var done := false
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode != KEY_ESCAPE:
			Settings.rebind(listening, event)
		done = true
	elif event is InputEventJoypadButton and event.pressed:
		var b := (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_START:
			done = true
		elif Settings.PAD_REBINDABLE.has(listening):
			Settings.rebind(listening, event)
			done = true
	elif event is InputEventJoypadMotion or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		return
	if done:
		get_viewport().set_input_as_handled()
		focus_hint = str(Settings.ACTION_NAMES[listening]) + ":"
		listening = ""
		# Wait a frame so the same press doesn't also activate the focused button.
		await get_tree().process_frame
		show_screen("remap", false)
	elif event is InputEventKey or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()

func _build_story(box: VBoxContainer) -> void:
	_title(box, "STORY")
	var cur := int(Save.data.contract)
	var total := Career.CONTRACTS.size()
	_text(box, ("Chapter %d of %d" % [cur + 1, total]) if cur < total else "Story complete - side jobs keep coming", 18, ACCENT)
	var flow: HFlowContainer = null
	for i in total:
		var c: Dictionary = Career.CONTRACTS[i]
		if c.has("act"):
			_text(box, Career.ACTS[int(c.act)], 16, Color(1, 1, 1, 0.5))
			flow = HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 8)
			flow.add_theme_constant_override("v_separation", 8)
			box.add_child(flow)
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 17)
		if i < cur:
			l.text = "✓ " + c.title
			sb.bg_color = Color(0.2, 0.55, 0.3, 0.35)
			l.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
		elif i == cur:
			l.text = "▶ " + c.title
			sb.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3)
			sb.border_color = ACCENT
			sb.set_border_width_all(2)
			l.add_theme_color_override("font_color", Color.WHITE)
		else:
			l.text = "? ? ?"
			sb.bg_color = Color(1, 1, 1, 0.05)
			l.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		chip.add_theme_stylebox_override("panel", sb)
		chip.add_child(l)
		flow.add_child(chip)
	if cur < total:
		var c2: Dictionary = Career.CONTRACTS[cur]
		var brief: Array = c2.brief
		_text(box, "\nNEXT:  %s  ·  call from %s" % [c2.title.to_upper(), c2.caller], 18, ACCENT)
		_text(box, str(brief[0]), 16, Color(1, 1, 1, 0.75))
		_text(box, "Wait for the call in free roam, or press %s to call your contact." % Settings.glyph("phone"), 15)
	_button(box, "BACK", func(): back())

func _build_records(box: VBoxContainer) -> void:
	_title(box, "RECORDS")
	var best: Dictionary = Save.data.best
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	var row := func(a: String, b: String, col := Color.WHITE) -> void:
		for t in [a, b]:
			var l := Label.new()
			l.text = t
			l.add_theme_font_size_override("font_size", 17)
			l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6) if t == a else col)
			grid.add_child(l)
	for id in Career.RACES:
		var t: float = float(best.get(id, INF))
		row.call(str(Career.RACES[id].name), HUD._time(t) if t < INF else "-", ACCENT if t < INF else Color(1, 1, 1, 0.35))
	for i in Career.DRIFT_ZONES.size():
		var v := int(best.get("drift%d" % i, 0))
		row.call("Drift: " + str(Career.DRIFT_ZONES[i].name), (HUD._fmt(v) + " pts") if v > 0 else "-", ACCENT if v > 0 else Color(1, 1, 1, 0.35))
	for i in Career.SPEED_TRAPS.size():
		var k := int(best.get("trap%d" % i, 0))
		row.call("Speed trap %d" % (i + 1), ("%d km/h" % k) if k > 0 else "-", ACCENT if k > 0 else Color(1, 1, 1, 0.35))
	row.call("Billboards smashed", "%d / %d" % [Save.data.get("billboards", []).size(), Career.BILLBOARD_COUNT])
	row.call("Races won", str(int(Save.data.races_won)))
	row.call("Police escapes", str(int(Save.data.heat_escapes)))
	row.call("Time played", HUD._time(float(Save.data.playtime)).split(".")[0])
	box.add_child(grid)
	var got: Array = Save.data.get("ach", [])
	_text(box, "\nACHIEVEMENTS  %d / %d" % [got.size(), Achievements.LIST.size()], 18, ACCENT)
	var ag := GridContainer.new()
	ag.columns = 2
	ag.add_theme_constant_override("h_separation", 30)
	for a in Achievements.LIST:
		var l := Label.new()
		var done: bool = got.has(a[0])
		l.text = ("★ " if done else "☆ ") + str(a[1]) + "  -  " + str(a[2])
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3) if done else Color(1, 1, 1, 0.4))
		ag.add_child(l)
	box.add_child(ag)
	_button(box, "BACK", func(): back())

func _build_credits(box: VBoxContainer) -> void:
	_title(box, "CREDITS")
	_text(box, "Velocity Heat", 22, Color.WHITE)
	_text(box, "Made with the Godot Engine (MIT licence) - godotengine.org", 16)
	_text(box, "Car model: \"Car Concept\" by Eric Chadwick / Darmstadt Graphics Group GmbH, from the Khronos glTF Sample Assets, licensed CC BY 4.0. Based on a public-domain model by Unity Fan.", 16)
	_text(box, "World, textures, sounds and music are procedurally generated for this game.", 16)
	_button(box, "BACK", func(): back())

## Full-screen scrolling end credits. Any confirm/back press skips. Returns when done.
signal credits_done
var _credits_root: Control

func rolling_credits() -> bool:
	return _credits_root != null

func roll_credits() -> void:
	close_all()
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.012, 0.02, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.theme = theme_ui
	add_child(bg)
	_credits_root = bg
	var v := VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.offset_left = -500
	v.offset_right = 500
	v.offset_top = 1100
	v.add_theme_constant_override("separation", 14)
	bg.add_child(v)
	var line := func(t: String, size: int, col: Color) -> void:
		var l := Label.new()
		l.text = t
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", col)
		v.add_child(l)
	line.call("THE END", 72, Color.WHITE)
	line.call("", 20, Color.WHITE)
	line.call("VELOCITY HEAT", 54, ACCENT)
	line.call("A getaway story in Solano Bay", 22, Color(1, 1, 1, 0.7))
	line.call("", 40, Color.WHITE)
	line.call("THE CAST", 26, ACCENT)
	for c in ["Mara  -  the fixer", "Dex  -  mechanic, smuggler, therapist", "Sable  -  king of the Night Kings", "Juno  -  fastest driver on the ring",
			"Rook  -  drives dirty", "Lt. Kane  -  Heat Task Force", "Air One  -  always watching", "You  -  the driver"]:
		line.call(c, 22, Color(1, 1, 1, 0.85))
	line.call("", 40, Color.WHITE)
	line.call("BUILT WITH", 26, ACCENT)
	line.call("Godot Engine (MIT licence)", 22, Color(1, 1, 1, 0.85))
	line.call("\"Car Concept\" model by Eric Chadwick / Darmstadt Graphics Group GmbH", 18, Color(1, 1, 1, 0.7))
	line.call("Khronos glTF Sample Assets, CC BY 4.0", 18, Color(1, 1, 1, 0.7))
	line.call("World, sounds and music generated for this game", 18, Color(1, 1, 1, 0.7))
	line.call("", 40, Color.WHITE)
	line.call("SOUNDTRACK", 26, ACCENT)
	for t in AudioManager.CRUISE + AudioManager.THEMES.values().slice(0, 3):
		line.call("%s  -  %s" % [t[1], t[2]], 20, Color(1, 1, 1, 0.85))
	line.call("", 60, Color.WHITE)
	line.call("Thanks for playing.", 30, Color.WHITE)
	line.call("The city is yours.", 22, ACCENT)
	await get_tree().process_frame
	var tw := create_tween()
	tw.tween_property(v, "offset_top", -v.size.y - 80.0, 38.0)
	tw.tween_callback(func(): credits_done.emit())
	await credits_done
	tw.kill()
	bg.queue_free()
	_credits_root = null

func show_results(res: Dictionary) -> void:
	if not screens.has("results"):
		_screen("results")
	var box: VBoxContainer = screens.results.box
	_clear(box)
	var title := ""
	if res.kind == "race":
		var ord: String = ["1ST", "2ND", "3RD", "4TH", "5TH", "6TH"][clampi(int(res.place) - 1, 0, 5)]
		title = "VICTORY" if int(res.place) == 1 else ord + " PLACE"
		_title(box, title, 60)
		_text(box, res.title.to_upper(), 20, ACCENT)
		_text(box, "Position  %s / %d\nTime  %s" % [ord, int(res.total), HUD._time(float(res.time))], 22, Color.WHITE)
		var order: Array = res.get("order", [])
		if not order.is_empty():
			var lines := []
			for k in order.size():
				lines.append("%d.  %s" % [k + 1, order[k]])
			_text(box, "   ".join(lines), 16, Color(1, 1, 1, 0.7))
	else:
		_title(box, "JOB DONE" if res.ok else "JOB FAILED", 60)
		_text(box, res.title.to_upper(), 20, ACCENT)
		if not res.ok and res.why != "":
			_text(box, res.why, 20, Color.WHITE)
		if res.ok and res.get("story", false):
			var cur := int(Save.data.contract)
			if cur < Career.CONTRACTS.size():
				_text(box, "Up next: chapter %d of %d, %s  ·  %s calls soon" % [cur + 1, Career.CONTRACTS.size(), Career.CONTRACTS[cur].title, Career.CONTRACTS[cur].caller], 18, Color.WHITE)
			else:
				_text(box, "STORY COMPLETE", 22, ACCENT)
	if res.ok or res.kind == "race":
		_text(box, "Reward  +$%s" % HUD._fmt(int(res.reward)), 26, Color(0.5, 1.0, 0.62))
	if not res.ok and res.kind == "contract" and not game.career.last_failed.is_empty():
		_button(box, "RETRY JOB", func():
			screens.results.root.visible = false
			current = ""
			resume_pressed.emit()
			game.career.retry())
	_button(box, "CONTINUE", func():
		screens.results.root.visible = false
		current = ""
		resume_pressed.emit())
	if current != "" and screens.has(current):
		screens[current].root.visible = false
	current = "results"
	screens.results.root.visible = true
	# Ignore input briefly so a held/tapped nitrous (A / Cross) doesn't skip the results.
	var btns := _buttons(box)
	for b in btns:
		(b as Button).disabled = true
	await get_tree().create_timer(0.6, true, false, true).timeout
	for b in btns:
		if is_instance_valid(b):
			(b as Button).disabled = false
	var f := _first_focus(box)
	if f:
		f.grab_focus()
