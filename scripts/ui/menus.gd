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
	box.add_child(b)
	return b

func show_screen(name: String, push := true) -> void:
	# Refreshing the same screen keeps focus on the same button (pad users).
	if name != "main":
		confirm_new = false
	var keep := -1
	if name == current and screens.has(name):
		var f := get_viewport().gui_get_focus_owner()
		if f is Button:
			keep = _buttons(screens[name].box).find(f)
	if current != "" and screens.has(current):
		screens[current].root.visible = false
		if push and current != name:
			stack.append(current)
	current = name
	_rebuild(name)
	screens[name].root.visible = true
	await get_tree().process_frame
	var btns := _buttons(screens[name].box)
	if keep >= 0 and not btns.is_empty():
		var k := mini(keep, btns.size() - 1)
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
	_text(box, "Tip: tap the handbrake or brake mid-corner to start a drift. Hold throttle + brake while stopped for a burnout.", 16)
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

func _build_main(box: VBoxContainer) -> void:
	box.add_theme_constant_override("separation", 12)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	box.add_child(spacer)
	_title(box, "VELOCITY\nHEAT", 68)
	_text(box, "GETAWAY DRIVER  ·  OPEN WORLD", 18, ACCENT)
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 14)
	box.add_child(sp2)
	var started: bool = int(Save.data.contract) > 0 or float(Save.data.playtime) > 30.0
	_button(box, "CONTINUE" if started else "START CAREER", func(): play_pressed.emit())
	if started:
		_button(box, "STORY", func(): show_screen("story"))
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
	_button(box, "QUIT", func(): get_tree().quit())
	_text(box, "\nBank  $%s   ·   Story %d / %d" % [HUD._fmt(int(Save.data.cash)), mini(int(Save.data.contract), Career.CONTRACTS.size()), Career.CONTRACTS.size()], 18)

func _build_pause(box: VBoxContainer) -> void:
	_title(box, "PAUSED")
	var career: Career = game.career
	_button(box, "RESUME", func(): back())
	_button(box, "STORY", func(): show_screen("story"))
	if career.race != null or not career.active.is_empty():
		_button(box, "ABANDON " + ("RACE" if career.race else "JOB"), func():
			close_all()
			game._on_resume()
			career.abandon())
	var at_home: bool = game.player_at_home()
	_button(box, "GARAGE" + ("" if at_home else "  (drive home to use)"), func():
		close_all()
		game._open_garage(), not at_home or game.police.pursuit)
	_button(box, "SKIP TO " + ("DAY" if game.daynight.night > 0.5 else "NIGHT"), func():
		game.skip_time()
		show_screen("pause", false), game.police.pursuit)
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
	_text(box, "\n%s  ·  %s  ·  %d cyl  ·  %d km/h top  ·  PI %d" % [sel.name, "AWD" if sel.awd else "RWD", sel.cyl, int(st.top * 3.6 * 0.97), Data.perf_index(st)], 18, Color.WHITE)
	_text(box, "0-100 approx %.1fs   Grip %.2fg   Nitrous %.0fs" % [27.8 / (st.accel * 0.72), st.grip / 9.81, st.nitro_cap], 16)
	if not owned.has(garage_sel):
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
	_button(box, "BACK", func(): back())

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
	_text(box, "Low uses the lightweight OpenGL renderer for older laptops. Ultra enables real-time global illumination, screen-space reflections & GI, volumetric fog, 8K shadows and dense grass.", 15)
	_button(box, "BACK", func(): back())

func _build_controls(box: VBoxContainer) -> void:
	_title(box, "CONTROLS")
	var ps := Settings.pad_style() == "playstation"
	var G: Dictionary = Settings.PLAYSTATION if ps else Settings.XBOX
	_text(box, ("PlayStation" if ps else "Xbox / generic") + " controller layout" + ("  -  " + Input.get_joy_name(Input.get_connected_joypads()[0]) if not Input.get_connected_joypads().is_empty() else "  -  no controller detected"), 16, ACCENT)
	var rows := [
		["Accelerate / Brake-Reverse", "W / S", G.throttle + " / " + G.brake], ["Steer", "A / D", "Left stick"], ["Handbrake (start a drift)", "Space", G.handbrake],
		["Nitrous", "Shift / N", G.nitro + " or L3"], ["Burnout / donuts", "W + S while stopped", G.throttle + " + " + G.brake], ["Camera", "C", G.camera],
		["Look back / around", "B", "R3 / right stick"], ["Answer / make call", "Tab", G.phone], ["Full map", "M", G.map], ["Start race / garage", "E / Enter", G.interact],
		["Reset to road", "R", G.reset], ["Shift up / down (manual)", "X / Z", G.shift_up + " / " + G.shift_down], ["Headlights", "L", G.headlights],
		["Pause", "Esc", G.pause], ["Menu select / back", "Enter / Esc", G.accept + " / " + G.back],
	]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	for r in rows:
		for k in 3:
			var l := Label.new()
			l.text = r[k]
			l.add_theme_font_size_override("font_size", 18)
			l.add_theme_color_override("font_color", Color(1, 1, 1, 0.65) if k == 0 else Color.WHITE)
			grid.add_child(l)
	box.add_child(grid)
	_text(box, "Controller vibration: engine near redline, tyre slip, ABS pulse, rough ground, gear shifts, landings, impacts, nitrous and burnouts. Adjust strength, steering sensitivity, deadzone and response curve in Settings.", 15)
	_button(box, "BACK", func(): back())

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

func _build_credits(box: VBoxContainer) -> void:
	_title(box, "CREDITS")
	_text(box, "Velocity Heat", 22, Color.WHITE)
	_text(box, "Made with the Godot Engine (MIT licence) - godotengine.org", 16)
	_text(box, "Car model: \"Car Concept\" by Eric Chadwick / Darmstadt Graphics Group GmbH, from the Khronos glTF Sample Assets, licensed CC BY 4.0. Based on a public-domain model by Unity Fan.", 16)
	_text(box, "World, textures, sounds and music are procedurally generated for this game.", 16)
	_button(box, "BACK", func(): back())

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
	else:
		_title(box, "JOB DONE" if res.ok else "JOB FAILED", 60)
		_text(box, res.title.to_upper(), 20, ACCENT)
		if not res.ok and res.why != "":
			_text(box, res.why, 20, Color.WHITE)
		if res.ok and res.get("story", false):
			var cur := int(Save.data.contract)
			if cur < Career.CONTRACTS.size():
				_text(box, "Story  %d / %d   ·   Next: %s calls soon" % [cur, Career.CONTRACTS.size(), Career.CONTRACTS[cur].caller], 18, Color.WHITE)
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
	await get_tree().process_frame
	var f := _first_focus(box)
	if f:
		f.grab_focus()
