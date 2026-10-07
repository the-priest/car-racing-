class_name Tutorial
extends Node
## Interactive first-drive tutorial. Each step waits until the player actually does
## the thing (accelerate, brake, steer, nitrous, drift, handbrake, map, phone).
## No cops and no incoming calls until it's done; can be skipped from the pause menu.

signal finished(skipped: bool)

var game: Node
var step := -1
var progress := 0.0
var done_t := -1.0 # brief pause on a completed step before the next one
var acc := {}
var map_opened := false
var step_t := 0.0 # time spent on the current step

func _steps() -> Array:
	var g := func(k: String) -> String: return Settings.glyph(k)
	var steer := "the left stick" if Settings.using_pad else "%s / %s" % [Settings.binding_text("steer_left", false), Settings.binding_text("steer_right", false)]
	return [
		["ACCELERATE", "Hold %s to accelerate. Get up to 60 km/h." % g.call("throttle")],
		["BRAKE", "Press %s to brake. Slow right down, under 20 km/h." % g.call("brake")],
		["STEER", "Steer with %s. Weave left and right." % steer],
		["NITROUS", "Hold %s for a nitrous boost. Near misses, drifts and big air refill it." % g.call("nitro")],
		["DRIFT", "Above 60 km/h, steer hard into a turn and give %s a quick tap while staying on %s. Steer to hold the slide; centre the wheel or lift off to straighten up." % [g.call("brake"), g.call("throttle")]],
		["HANDBRAKE", "For tight hairpins: steer hard and tap %s to swing the car around." % g.call("handbrake")],
		["MAP", "Press %s to open the map. You can zoom, set waypoints and fast travel there. Close it again." % g.call("map")],
		["PHONE", "Mara has your first job. Press %s to call her." % g.call("phone")],
	]

func start(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	step = -1
	_next()

func _next() -> void:
	step += 1
	progress = 0.0
	done_t = -1.0
	acc = {}
	map_opened = false
	step_t = 0.0
	var steps := _steps()
	if step >= steps.size():
		_finish(false)
		return
	if steps[step][0] == "NITROUS":
		game.player.nitro = maxf(game.player.nitro, 0.7)
	if steps[step][0] == "PHONE":
		game.career.call_timer = 1.5 # Mara rings straight away
	_show()

func _show() -> void:
	var steps := _steps()
	if step >= 0 and step < steps.size():
		game.hud.tutorial_card(step + 1, steps.size(), steps[step][0], steps[step][1], progress, done_t >= 0.0)

func skip() -> void:
	_finish(true)

## Drop the tutorial without finishing it (new career started over it).
func cancel() -> void:
	step = 99
	game.hud.tutorial_card(0, 0, "", "", 0.0, false)
	queue_free()

func allows_phone() -> bool:
	return step >= 0 and step < _steps().size() and _steps()[step][0] == "PHONE"

func _finish(skipped: bool) -> void:
	step = 99
	game.hud.tutorial_card(0, 0, "", "", 0.0, false)
	finished.emit(skipped)
	queue_free()

func _process(delta: float) -> void:
	if game == null or step < 0 or step > 50:
		return
	var steps := _steps()
	var name: String = steps[step][0]
	# The map pauses the game, so check it before anything else.
	if name == "MAP":
		if game.hud.big_map.visible:
			map_opened = true
			progress = 0.5
		elif map_opened and game.is_playing():
			progress = 1.0
	if not game.is_playing():
		return
	# Keep the world quiet while learning.
	game.career.call_timer = maxf(game.career.call_timer, 5.0) if name != "PHONE" else game.career.call_timer
	var p: Car = game.player
	step_t += delta
	if done_t >= 0.0:
		done_t += delta
		if done_t > 1.1:
			_next()
		return
	match name:
		"ACCELERATE":
			progress = clampf(p.kmh / 60.0, 0.0, 1.0)
		"BRAKE":
			if p.kmh < 20.0:
				progress = 1.0
			else:
				progress = clampf(1.0 - (p.kmh - 20.0) / 50.0, 0.0, 0.95)
		"STEER":
			if p.speed > 4.0:
				var yr: float = p.angular_velocity.y
				if yr > 0.15:
					acc.left = float(acc.get("left", 0.0)) + yr * delta
				elif yr < -0.15:
					acc.right = float(acc.get("right", 0.0)) - yr * delta
			progress = (minf(float(acc.get("left", 0.0)), 0.7) + minf(float(acc.get("right", 0.0)), 0.7)) / 1.4
		"NITROUS":
			if p.nitro_on:
				acc.t = float(acc.get("t", 0.0)) + delta
			if p.nitro < 0.15:
				p.nitro = 0.6
			progress = clampf(float(acc.get("t", 0.0)) / 1.2, 0.0, 1.0)
		"DRIFT":
			if p.drift_mode:
				acc.t = float(acc.get("t", 0.0)) + delta
			progress = clampf(float(acc.get("t", 0.0)) / 1.5, 0.0, 1.0)
		"HANDBRAKE":
			if float(p.input.handbrake) > 0.5 and absf(float(p.input.steer)) > 0.3 and p.speed > 6.0:
				acc.t = float(acc.get("t", 0.0)) + delta
			progress = clampf(float(acc.get("t", 0.0)) / 0.35, 0.0, 1.0)
		"PHONE":
			if not game.career.active.is_empty():
				progress = 1.0
	if progress >= 1.0:
		done_t = 0.0
		game.audio.play_oneshot("reward", 1.5, -6.0)
	_show()

## A short hint for the current step when the player seems stuck (shown under the card).
func hint() -> String:
	if step < 0 or step > 50:
		return ""
	var name: String = _steps()[step][0]
	var p: Car = game.player
	if name == "DRIFT" and p.kmh < 60.0:
		return "Speed up a little first."
	if name == "DRIFT" and step_t > 18.0:
		return "Keep the gas down, steer hard to one side, then tap the brake quickly (don't hold it)."
	if name == "STEER" and step_t > 15.0 and p.kmh < 10.0:
		return "Keep a little speed on while you steer."
	if name == "HANDBRAKE" and p.kmh < 25.0:
		return "Get moving, then steer and tap the handbrake."
	return ""
