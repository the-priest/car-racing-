extends Node
## Player settings, graphics quality presets and input bindings.

signal changed

const PATH := "user://settings.cfg"
const OVERRIDE := "user://override.cfg"

const PRESETS := {
	"low": {
		"renderer": "gl_compatibility", "scale": 0.8, "msaa": 0, "taa": false, "fxaa": true,
		"shadow_size": 2048, "shadow_dist": 140.0, "shadow_splits": 2, "soft_shadows": 0,
		"ssao": false, "ssr": false, "ssil": false, "sdfgi": false, "vfog": false, "glow": true,
		"draw": 1300.0, "trees": 0.35, "tree_dist": 450.0, "grass": 0, "lamp_lights": 6,
		"lamp_shadows": false, "head_shadows": false, "lod_bias": 2.0, "traffic": 10,
	},
	"medium": {
		"renderer": "forward_plus", "scale": 0.85, "msaa": 0, "taa": false, "fxaa": true,
		"shadow_size": 2048, "shadow_dist": 220.0, "shadow_splits": 2, "soft_shadows": 1,
		"ssao": true, "ssr": false, "ssil": false, "sdfgi": false, "vfog": false, "glow": true,
		"draw": 2200.0, "trees": 0.6, "tree_dist": 700.0, "grass": 0, "lamp_lights": 12,
		"lamp_shadows": false, "head_shadows": false, "lod_bias": 1.5, "traffic": 16,
	},
	"high": {
		"renderer": "forward_plus", "scale": 1.0, "msaa": 0, "taa": true, "fxaa": false,
		"shadow_size": 4096, "shadow_dist": 400.0, "shadow_splits": 4, "soft_shadows": 2,
		"ssao": true, "ssr": true, "ssil": false, "sdfgi": false, "vfog": false, "glow": true,
		"draw": 3500.0, "trees": 1.0, "tree_dist": 1100.0, "grass": 1, "lamp_lights": 24,
		"lamp_shadows": false, "head_shadows": true, "lod_bias": 1.0, "traffic": 22,
	},
	"ultra": {
		"renderer": "forward_plus", "scale": 1.0, "msaa": 2, "taa": true, "fxaa": false,
		"shadow_size": 8192, "shadow_dist": 700.0, "shadow_splits": 4, "soft_shadows": 4,
		"ssao": true, "ssr": true, "ssil": true, "sdfgi": true, "vfog": true, "glow": true,
		"draw": 6000.0, "trees": 1.0, "tree_dist": 2000.0, "grass": 2, "lamp_lights": 48,
		"lamp_shadows": true, "head_shadows": true, "lod_bias": 0.5, "traffic": 30,
	},
}
const QUALITY_NAMES := ["low", "medium", "high", "ultra"]

var data := {
	"quality": "", "fullscreen": true, "vsync": true, "render_scale": 0.0, "fov": 72.0,
	"music": 0.5, "sfx": 0.85, "assists": true, "manual": false, "units": "kmh",
	"show_fps": false, "route_arrows": true, "traffic": 1.0, "camera": 0, "sensitivity": 1.0,
	"vibration": 1.0, "steer_sens": 1.0, "deadzone": 0.08, "steer_curve": 1.3,
	"speed_fx": true, "cam_shake": 1.0, "time_mode": "dynamic", "weather": "dynamic", "difficulty": "normal",
	"radio": false, "radio_shuffle": true,
	"bindings": {}, # action -> {"key": physical keycode, "pad": joy button} overrides
}

## Actions the player can rebind (keyboard: all; controller: button actions).
const REBINDABLE := ["throttle", "brake", "steer_left", "steer_right", "handbrake", "nitro", "camera", "look_back",
	"reset", "interact", "phone", "map", "shift_up", "shift_down", "horn", "headlights", "radio"]
const PAD_REBINDABLE := ["handbrake", "nitro", "camera", "look_back", "reset", "interact", "phone", "map",
	"shift_up", "shift_down", "horn", "headlights", "radio"]
const ACTION_NAMES := {"throttle": "Accelerate", "brake": "Brake / reverse", "steer_left": "Steer left", "steer_right": "Steer right",
	"handbrake": "Handbrake", "nitro": "Nitrous", "camera": "Change camera", "look_back": "Look back", "reset": "Reset to road",
	"interact": "Interact / next line", "phone": "Phone", "map": "Map", "shift_up": "Shift up", "shift_down": "Shift down",
	"horn": "Horn", "headlights": "Headlights", "radio": "Radio"}
const PAD_NAMES_XBOX := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_BACK: "View",
	JOY_BUTTON_START: "Menu", JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓", JOY_BUTTON_DPAD_LEFT: "D-pad ←",
	JOY_BUTTON_DPAD_RIGHT: "D-pad →", JOY_BUTTON_TOUCHPAD: "Touchpad", JOY_BUTTON_GUIDE: "Guide"}
const PAD_NAMES_PS := {JOY_BUTTON_A: "✕", JOY_BUTTON_B: "○", JOY_BUTTON_X: "□", JOY_BUTTON_Y: "△", JOY_BUTTON_LEFT_SHOULDER: "L1",
	JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_BACK: "Create",
	JOY_BUTTON_START: "Options", JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓", JOY_BUTTON_DPAD_LEFT: "D-pad ←",
	JOY_BUTTON_DPAD_RIGHT: "D-pad →", JOY_BUTTON_TOUCHPAD: "Touchpad", JOY_BUTTON_GUIDE: "PS"}

## Rebinds one action for keyboard (InputEventKey) or controller (InputEventJoypadButton).
func rebind(action: String, ev: InputEvent) -> void:
	if ev is InputEventKey and (ev as InputEventKey).physical_keycode == 0:
		return
	# Free the key/button from any other driving action that used it (no double triggers).
	for other in REBINDABLE:
		if other == action:
			continue
		for e in InputMap.action_get_events(other):
			var same := (ev is InputEventKey and e is InputEventKey and (e as InputEventKey).physical_keycode == (ev as InputEventKey).physical_keycode) \
				or (ev is InputEventJoypadButton and e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == (ev as InputEventJoypadButton).button_index)
			if same:
				InputMap.action_erase_event(other, e)
				var ob: Dictionary = data.bindings.get(other, {}).duplicate()
				ob["key" if ev is InputEventKey else "pad"] = -1 # unbound (persisted)
				data.bindings[other] = ob
	var b: Dictionary = data.bindings.get(action, {}).duplicate()
	if ev is InputEventKey:
		b["key"] = int((ev as InputEventKey).physical_keycode)
	elif ev is InputEventJoypadButton:
		b["pad"] = int((ev as InputEventJoypadButton).button_index)
	data.bindings[action] = b
	_apply_binding(action)
	save_settings()

func reset_bindings() -> void:
	data.bindings = {}
	for a in _default_map():
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
	_default_events()
	save_settings()

func _apply_binding(action: String) -> void:
	var b: Dictionary = data.bindings.get(action, {})
	if b.has("key"):
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				InputMap.action_erase_event(action, e)
		if int(b.key) >= 0:
			InputMap.action_add_event(action, _key(int(b.key) as Key))
	if b.has("pad"):
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton:
				InputMap.action_erase_event(action, e)
		if int(b.pad) >= 0:
			InputMap.action_add_event(action, _btn(int(b.pad) as JoyButton))

## Current label of an action's binding on keyboard or pad.
func binding_text(action: String, pad: bool) -> String:
	for e in InputMap.action_get_events(action):
		if pad and e is InputEventJoypadButton:
			var names := PAD_NAMES_PS if pad_style() == "playstation" else PAD_NAMES_XBOX
			return names.get((e as InputEventJoypadButton).button_index, "Button %d" % (e as InputEventJoypadButton).button_index)
		if not pad and e is InputEventKey:
			return OS.get_keycode_string((e as InputEventKey).physical_keycode)
	if pad:
		return (PLAYSTATION if pad_style() == "playstation" else XBOX).get(action, "-")
	return "-"

# ---------------------------------------------------------------- controller glyphs
const XBOX := {"handbrake": "X", "nitro": "A", "camera": "Y", "reset": "B (hold)", "interact": "D-pad ↑", "phone": "D-pad ↓",
	"pause": "Menu", "map": "View", "throttle": "RT", "brake": "LT", "shift_up": "RB", "shift_down": "LB", "look_back": "R3",
	"headlights": "D-pad →", "horn": "D-pad ←", "accept": "A", "back": "B", "radio": "L3"}
const PLAYSTATION := {"handbrake": "□", "nitro": "✕", "camera": "△", "reset": "○ (hold)", "interact": "D-pad ↑", "phone": "D-pad ↓",
	"pause": "Options", "map": "Touchpad", "throttle": "R2", "brake": "L2", "shift_up": "R1", "shift_down": "L1", "look_back": "R3",
	"headlights": "D-pad →", "horn": "D-pad ←", "accept": "✕", "back": "○", "radio": "L3"}
const KEYS := {"handbrake": "Space", "nitro": "Shift", "camera": "C", "reset": "R", "interact": "E", "phone": "Tab",
	"pause": "Esc", "map": "M", "throttle": "W", "brake": "S", "shift_up": "X", "shift_down": "Z", "look_back": "B",
	"headlights": "L", "horn": "H", "accept": "Enter", "back": "Esc", "radio": "Q"}

var using_pad := false

## "playstation", "xbox" (default for other pads) based on the connected controller.
func pad_style() -> String:
	for d in Input.get_connected_joypads():
		var n := Input.get_joy_name(d).to_lower()
		if n.contains("dualsense") or n.contains("ps5") or n.contains("ps4") or n.contains("dualshock") or n.contains("sony") or n.contains("playstation") or n == "wireless controller":
			return "playstation"
	return "xbox"

## Button/key label for an action on the device the player is currently using.
func glyph(action: String) -> String:
	if REBINDABLE.has(action) and data.bindings.has(action):
		var t := binding_text(action, using_pad)
		return t + (" (hold)" if action == "reset" and using_pad else "")
	if not using_pad:
		return KEYS.get(action, action)
	return (PLAYSTATION if pad_style() == "playstation" else XBOX).get(action, action)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_input()
	load_settings()
	for a in data.bindings:
		if InputMap.has_action(a):
			_apply_binding(a)
	if data.quality == "":
		# Default to High; the player's chosen preset is always respected afterwards.
		data.quality = "high"
		save_settings()
	apply_window()

func preset() -> Dictionary:
	return PRESETS.get(data.quality, PRESETS.high)

## Picks a starting preset from the GPU type: integrated -> low/medium, discrete -> high.
func detect_quality() -> String:
	var t := RenderingServer.get_video_adapter_type()
	var name := RenderingServer.get_video_adapter_name().to_lower()
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return "low"
	if t == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		if name.contains("rtx") or name.contains("rx 6") or name.contains("rx 7") or name.contains("arc"):
			return "high"
		return "medium"
	if t == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return "low"
	return "medium"

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in data.keys():
		data[k] = cfg.get_value("settings", k, data[k])

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value("settings", k, data[k])
	cfg.save(PATH)
	# Renderer choice must be known before the engine starts, so it lives in override.cfg.
	var ov := ConfigFile.new()
	ov.set_value("rendering", "renderer/rendering_method", preset().renderer)
	ov.save(OVERRIDE)

## Picks a value for the current difficulty.
func diff(easy, normal, hard):
	match str(data.get("difficulty", "normal")):
		"easy": return easy
		"hard": return hard
	return normal

func set_value(key: String, value) -> void:
	data[key] = value
	save_settings()
	if key == "fullscreen" or key == "vsync":
		apply_window()
	changed.emit()

## True when the running renderer differs from the preset (restart needed).
func needs_restart() -> bool:
	return RenderingServer.get_current_rendering_method() != preset().renderer

func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if data.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if data.vsync else DisplayServer.VSYNC_DISABLED)

## Applies the active preset to the environment, sun and viewport.
func apply_graphics(env: Environment, sun: DirectionalLight3D, vp: Viewport, cam: Camera3D) -> void:
	var p := preset()
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var scale: float = data.render_scale if data.render_scale > 0.0 else p.scale
	vp.scaling_3d_scale = scale
	if compat:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	elif scale < 0.99:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if p.taa else Viewport.SCALING_3D_MODE_FSR
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	match int(p.msaa):
		2: vp.msaa_3d = Viewport.MSAA_2X
		4: vp.msaa_3d = Viewport.MSAA_4X
		_: vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.use_taa = p.taa and not compat
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if p.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = p.lod_bias
	vp.use_occlusion_culling = true
	vp.positional_shadow_atlas_size = 4096 if p.lamp_shadows or p.head_shadows else 1024

	RenderingServer.directional_shadow_atlas_set_size(p.shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p.soft_shadows)
	RenderingServer.positional_soft_shadow_filter_set_quality(p.soft_shadows)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = p.shadow_dist
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if p.shadow_splits == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

	if not compat:
		env.ssao_enabled = p.ssao
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if data.quality == "ultra" else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50, 300)
		env.ssr_enabled = p.ssr
		env.ssr_max_steps = 128 if data.quality == "ultra" else 48
		env.ssil_enabled = p.ssil
		env.sdfgi_enabled = p.sdfgi
		if p.sdfgi:
			env.sdfgi_cascades = 6
			env.sdfgi_min_cell_size = 0.4
			env.sdfgi_use_occlusion = true
			env.sdfgi_energy = 0.9
		env.volumetric_fog_enabled = p.vfog
		if p.vfog:
			RenderingServer.environment_set_volumetric_fog_volume_size(160 if data.quality == "ultra" else 64, 128 if data.quality == "ultra" else 48)
			RenderingServer.environment_set_volumetric_fog_filter_active(data.quality == "ultra")
	env.glow_enabled = p.glow
	cam.far = p.draw
	cam.fov = data.fov

func setup_input() -> void:
	_default_events()
	# Gamepad confirm/back in menus (A / Cross, B / Circle) and D-pad navigation.
	InputMap.action_add_event("ui_accept", _btn(JOY_BUTTON_A))
	InputMap.action_add_event("ui_cancel", _btn(JOY_BUTTON_B))
	InputMap.action_add_event("ui_up", _btn(JOY_BUTTON_DPAD_UP))
	InputMap.action_add_event("ui_down", _btn(JOY_BUTTON_DPAD_DOWN))
	InputMap.action_add_event("ui_left", _btn(JOY_BUTTON_DPAD_LEFT))
	InputMap.action_add_event("ui_right", _btn(JOY_BUTTON_DPAD_RIGHT))
	# Menu navigation also follows the left stick.
	InputMap.action_add_event("ui_up", _axis(JOY_AXIS_LEFT_Y, -1.0))
	InputMap.action_add_event("ui_down", _axis(JOY_AXIS_LEFT_Y, 1.0))
	InputMap.action_add_event("ui_left", _axis(JOY_AXIS_LEFT_X, -1.0))
	InputMap.action_add_event("ui_right", _axis(JOY_AXIS_LEFT_X, 1.0))

func _default_events() -> void:
	var map := _default_map()
	for action in map:
		if not InputMap.has_action(action):
			# Steering uses the player's own deadzone setting only.
			InputMap.add_action(action, 0.0 if action.begins_with("steer_") else 0.12)
		for ev in map[action]:
			InputMap.action_add_event(action, ev)

func _default_map() -> Dictionary:
	return {
		"throttle": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"brake": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"steer_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"steer_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"handbrake": [_key(KEY_SPACE), _btn(JOY_BUTTON_X)],
		"nitro": [_key(KEY_SHIFT), _key(KEY_N), _btn(JOY_BUTTON_A)],
		"camera": [_key(KEY_C), _btn(JOY_BUTTON_Y)],
		"look_back": [_key(KEY_B), _btn(JOY_BUTTON_RIGHT_STICK)],
		"look_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
		"look_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
		"reset": [_key(KEY_R), _btn(JOY_BUTTON_B)],
		"interact": [_key(KEY_E), _key(KEY_ENTER), _btn(JOY_BUTTON_DPAD_UP)],
		"phone": [_key(KEY_TAB), _btn(JOY_BUTTON_DPAD_DOWN)],
		"map": [_key(KEY_M), _btn(JOY_BUTTON_BACK), _btn(JOY_BUTTON_TOUCHPAD)],
		"pause": [_key(KEY_ESCAPE), _key(KEY_P), _btn(JOY_BUTTON_START)],
		"shift_up": [_key(KEY_X), _btn(JOY_BUTTON_RIGHT_SHOULDER)],
		"shift_down": [_key(KEY_Z), _btn(JOY_BUTTON_LEFT_SHOULDER)],
		"horn": [_key(KEY_H), _btn(JOY_BUTTON_DPAD_LEFT)],
		"headlights": [_key(KEY_L), _btn(JOY_BUTTON_DPAD_RIGHT)],
		"radio": [_key(KEY_Q), _btn(JOY_BUTTON_LEFT_STICK)],
	}

func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e

func _btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.device = -1
	return e

func _axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	e.device = -1
	return e
