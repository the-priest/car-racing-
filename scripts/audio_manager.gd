class_name AudioManager
extends Node
## Engine/tyre/wind/nitro layers for the player, 3D engines for nearby AI,
## sirens, one-shots and music with pursuit crossfade.

const DIR := "res://assets/audio/"

var streams := {}
var eng_on: AudioStreamPlayer
var eng_off: AudioStreamPlayer
var tire: AudioStreamPlayer
var gravel: AudioStreamPlayer
var wind: AudioStreamPlayer
var nitro: AudioStreamPlayer
var siren: AudioStreamPlayer
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var ring: AudioStreamPlayer
var cyl := -1
var last_throttle := 0.0
var pop_timer := 0.0
var chase_mix := 0.0
var ai_players := {}

func setup() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
	for n in ["tire_squeal", "wind", "gravel", "nitro", "siren", "music_night", "music_chase", "phone_ring"]:
		streams[n] = _loop(n)
	for n in ["impact", "blowoff", "backfire", "beep", "whoosh", "reward"]:
		streams[n] = load(DIR + n + ".wav")
	for c in [0, 4, 6, 8, 10, 12]:
		streams["engine_%d_on" % c] = _loop("engine_%d_on" % c)
		streams["engine_%d_off" % c] = _loop("engine_%d_off" % c)
	eng_on = _player(null)
	eng_off = _player(null)
	tire = _player(streams.tire_squeal)
	gravel = _player(streams.gravel)
	wind = _player(streams.wind)
	nitro = _player(streams.nitro)
	siren = _player(streams.siren)
	ring = _player(streams.phone_ring)
	ring.volume_db = -80.0
	music_a = _player(streams.music_night, "Music")
	music_b = _player(streams.music_chase, "Music")
	music_b.volume_db = -80.0
	apply_volumes()

func _loop(n: String) -> AudioStreamWAV:
	var s: AudioStreamWAV = load(DIR + n + ".wav")
	if s:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s

func _player(stream: AudioStream, bus := "SFX") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	if stream:
		p.play()
	return p

func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(float(Settings.data.music), 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(float(Settings.data.sfx), 0.0001)))

func set_engine(c: int) -> void:
	if c == cyl:
		return
	cyl = c
	eng_on.stream = streams["engine_%d_on" % c]
	eng_off.stream = streams["engine_%d_off" % c]
	eng_on.play()
	eng_off.play()

func play_oneshot(n: String, pitch := 1.0, vol_db := 0.0) -> void:
	if not streams.has(n):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[n]
	p.bus = "SFX"
	p.pitch_scale = pitch
	p.volume_db = vol_db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func set_ringing(on: bool) -> void:
	ring.volume_db = -6.0 if on else -80.0

func _db(lin: float) -> float:
	return linear_to_db(maxf(lin, 0.0001))

func update_player(car: Car, active: bool, delta: float) -> void:
	set_engine(int(car.stats.cyl))
	var st := car.stats
	var red: float = st.red
	var rpm_n := clampf(car.rpm / red, 0.05, 1.05)
	var pitch := clampf(car.rpm / 3000.0, 0.25, 3.4) if st.cyl > 0 else clampf(0.4 + car.speed / 40.0, 0.4, 3.0)
	eng_on.pitch_scale = pitch
	eng_off.pitch_scale = pitch
	var thr := clampf(float(car.input.throttle), 0.0, 1.0)
	if car.burnout:
		thr = 1.0
	var base := 0.0 if not active else 0.55 + rpm_n * 0.45
	eng_on.volume_db = _db(base * (0.25 + thr * 0.75))
	eng_off.volume_db = _db(base * (1.0 - thr) * 0.7)
	var skid := 0.0
	for w in car.wheels:
		if w.surface != "terrain":
			skid = maxf(skid, float(w.skid))
	tire.volume_db = _db(skid * 0.75 if active else 0.0)
	tire.pitch_scale = 0.9 + skid * 0.2
	gravel.volume_db = _db(clampf(car.speed / 30.0, 0.0, 1.0) * 0.6 if active and car.surface == "terrain" else 0.0)
	wind.volume_db = _db(pow(clampf(car.speed / 90.0, 0.0, 1.0), 2.0) * 0.6 if active else 0.0)
	nitro.volume_db = _db(0.35 if active and car.nitro_on else 0.0)
	# Lift-off effects: turbo flutter for small engines, pops & bangs for big ones.
	if active and last_throttle > 0.8 and thr < 0.2 and rpm_n > 0.6:
		if int(st.cyl) <= 6 and int(st.cyl) > 0:
			play_oneshot("blowoff", randf_range(0.95, 1.1), -6.0)
		else:
			pop_timer = 0.6
	if pop_timer > 0.0:
		pop_timer -= delta
		if randf() < delta * 14.0:
			play_oneshot("backfire", randf_range(0.8, 1.3), -4.0)
	last_throttle = thr

func update_siren(intensity: float) -> void:
	siren.volume_db = _db(intensity * 0.5)

func update_music(pursuit: bool, delta: float) -> void:
	chase_mix = move_toward(chase_mix, 1.0 if pursuit else 0.0, delta * 0.5)
	music_a.volume_db = _db(1.0 - chase_mix)
	music_b.volume_db = _db(chase_mix)

## Positional engine sound for AI cars near the listener.
func update_ai(cars: Array, listener: Vector3) -> void:
	var near: Array = cars.filter(func(c): return is_instance_valid(c) and c.global_position.distance_to(listener) < 120.0)
	near.sort_custom(func(a, b): return a.global_position.distance_squared_to(listener) < b.global_position.distance_squared_to(listener))
	near = near.slice(0, 4)
	for c in ai_players.keys():
		if not near.has(c) or not is_instance_valid(c):
			var ap = ai_players[c]
			if is_instance_valid(ap):
				ap.queue_free()
			ai_players.erase(c)
	for c in near:
		var car: Car = c
		if not ai_players.has(car):
			var p := AudioStreamPlayer3D.new()
			p.stream = streams["engine_%d_on" % int(car.stats.cyl)]
			p.bus = "SFX"
			p.unit_size = 8.0
			p.max_distance = 140.0
			car.add_child(p)
			p.play()
			ai_players[car] = p
		var ap: AudioStreamPlayer3D = ai_players[car]
		ap.pitch_scale = clampf(car.rpm / 3000.0, 0.25, 3.4)
		ap.volume_db = -4.0 + float(car.input.throttle) * 4.0
