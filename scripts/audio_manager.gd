class_name AudioManager
extends Node
## Engine/tyre/wind/nitro layers for the player, 3D engines for nearby AI,
## sirens, one-shots and the soundtrack: a free-roam playlist plus pursuit, race
## and menu themes that crossfade with the game state.

const DIR := "res://assets/audio/"
## Engines are recorded at these rpm points (tools/audio/gen_engines.py); the two
## nearest are crossfaded and pitch-shifted only slightly, so the exhaust note keeps
## its body instead of turning into a whine at high revs.
const ENG_DIR := "res://assets/audio/engines/"
const ENG_RPMS := [1000, 2000, 3000, 4000, 5000, 6500, 8000, 9500]
const MUSIC_DIR := "res://assets/music/"
## [file, title, artist]. Cruise tracks play through and rotate; themes loop.
const CRUISE := [
	["solano_nights", "Solano Nights", "Midnight Grid"],
	["coast_road", "Coast Road", "Palm Static"],
	["afterhours", "Afterhours", "Neon Ward"],
]
const THEMES := {
	"chase": ["heat_index", "Heat Index", "Kill Switch"],
	"race": ["redline", "Redline", "Overdrive 84"],
	"menu": ["garage", "Dex's Garage", "Low Tide"],
	"credits": ["solano_nights", "Solano Nights", "Midnight Grid"],
}

signal now_playing(title: String, artist: String)

# ---------------------------------------------------------------- radio (your MP3s)
## Folders scanned for MP3/OGG/WAV files: "Radio" next to the game executable
## (the project folder when run from the editor), the user data folder, and
## res://assets/radio (bundled into the build).
var radio_tracks: Array[String] = []
var radio_order: Array[int] = []
var radio_pos := -1
var radio_on := false
var radio_player: AudioStreamPlayer
var radio_level := 0.0
var radio_title := ""
var radio_artist := ""

var streams := {}
var eng_on: AudioStreamPlayer # electric drivetrain only
var eng_off: AudioStreamPlayer
var eng_layers_on: Array[AudioStreamPlayer] = []
var eng_layers_off: Array[AudioStreamPlayer] = []
var tire: AudioStreamPlayer
var road: AudioStreamPlayer # tyre roar on tarmac
var gravel: AudioStreamPlayer
var wind: AudioStreamPlayer
var nitro: AudioStreamPlayer
var siren: AudioStreamPlayer
var music := {}  # mode -> AudioStreamPlayer
var music_level := {}  # mode -> 0..1 crossfade level
var cruise_idx := 0
var cruise_pos := 0.0
var music_duck := 1.0
var ring: AudioStreamPlayer
var rotor: AudioStreamPlayer
var horn: AudioStreamPlayer
var turbo: AudioStreamPlayer
var rain: AudioStreamPlayer
var scrape: AudioStreamPlayer
var spool := 0.0
var cyl := -1
var last_throttle := 0.0
var pop_timer := 0.0
var load_s := 0.0
var ai_players := {}

func setup() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
	for n in ["tire_squeal", "wind", "gravel", "nitro", "siren", "phone_ring", "road"]:
		streams[n] = _loop(n)
	for n in ["impact", "impact_heavy", "blowoff", "backfire", "beep", "whoosh", "reward", "repair"]:
		streams[n] = load(DIR + n + ".wav")
	for c in [0, 4, 6, 8, 10, 12]:
		streams["engine_%d_on" % c] = _loop("engine_%d_on" % c)
		streams["engine_%d_off" % c] = _loop("engine_%d_off" % c)
	eng_on = _player(null)
	eng_off = _player(null)
	for i in ENG_RPMS.size():
		eng_layers_on.append(_player(null))
		eng_layers_off.append(_player(null))
	tire = _player(streams.tire_squeal)
	gravel = _player(streams.gravel)
	wind = _player(streams.wind)
	road = _player(streams.road)
	nitro = _player(streams.nitro)
	siren = _player(streams.siren)
	ring = _player(streams.phone_ring)
	ring.volume_db = -80.0
	streams["rotor"] = _gen_rotor()
	streams["radio"] = _gen_radio()
	streams["horn"] = _gen_horn()
	horn = _player(streams.horn)
	streams["turbo"] = _gen_turbo()
	turbo = _player(streams.turbo)
	streams["rain"] = _gen_rain()
	streams["thunder"] = _gen_thunder()
	rain = _player(streams.rain)
	streams["scrape"] = _gen_scrape()
	scrape = _player(streams.scrape)
	rotor = _player(streams.rotor)
	for mode in ["cruise", "chase", "race", "menu", "credits"]:
		var mp := _player(null, "Music")
		mp.volume_db = -80.0
		music[mode] = mp
		music_level[mode] = 0.0
		if mode != "cruise":
			var st: AudioStreamOggVorbis = load(MUSIC_DIR + THEMES[mode][0] + ".ogg").duplicate()
			st.loop = mode != "credits"
			mp.stream = st
	music.cruise.finished.connect(_next_cruise)
	radio_player = _player(null, "Music")
	radio_player.finished.connect(radio_next)
	radio_scan()
	cruise_idx = randi() % CRUISE.size()
	_load_cruise()
	apply_volumes()

## Engine loop for `cyl` cylinders at layer `i` (cached).
func eng_stream(c: int, on: bool, i: int) -> AudioStreamWAV:
	var key := "e%d_%s_%d" % [c, "on" if on else "off", ENG_RPMS[i]]
	if not streams.has(key):
		streams[key] = _loop("engines/" + key)
	return streams[key]

## Layer index below `rpm` and the blend toward the next one.
static func eng_layer(rpm: float) -> Array:
	var r := clampf(rpm, ENG_RPMS[0], ENG_RPMS[ENG_RPMS.size() - 1])
	for i in ENG_RPMS.size() - 1:
		if r <= ENG_RPMS[i + 1]:
			return [i, (r - ENG_RPMS[i]) / float(ENG_RPMS[i + 1] - ENG_RPMS[i])]
	return [ENG_RPMS.size() - 2, 1.0]

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
	if c == 0:
		eng_on.stream = streams["engine_0_on"]
		eng_off.stream = streams["engine_0_off"]
		eng_on.play()
		eng_off.play()
		for p in eng_layers_on + eng_layers_off:
			p.stop()
		return
	eng_on.stop()
	eng_off.stop()
	for i in ENG_RPMS.size():
		eng_layers_on[i].stream = eng_stream(c, true, i)
		eng_layers_off[i].stream = eng_stream(c, false, i)
		# Stagger start points so layers never phase-lock into a comb.
		eng_layers_on[i].play(randf() * 0.5)
		eng_layers_off[i].play(randf() * 0.5)

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
	var thr := clampf(float(car.input.throttle), 0.0, 1.0)
	if car.burnout:
		thr = 1.0
	# Smooth the load so tapping the throttle doesn't click between layers.
	load_s = move_toward(load_s, thr, delta * 8.0)
	var base := 0.0 if not active else 0.6 + rpm_n * 0.4
	if int(st.cyl) == 0:
		var pitch := clampf(0.4 + car.speed / 40.0, 0.4, 3.0)
		eng_on.pitch_scale = pitch
		eng_off.pitch_scale = pitch
		eng_on.volume_db = _db(base * (0.25 + load_s * 0.75))
		eng_off.volume_db = _db(base * (1.0 - load_s) * 0.7)
	else:
		var rpm := maxf(float(car.rpm), 700.0)
		var lb := eng_layer(rpm)
		var li: int = lb[0]
		var t: float = lb[1]
		for i in ENG_RPMS.size():
			var w := 0.0
			if i == li:
				w = cos(t * PI * 0.5)
			elif i == li + 1:
				w = sin(t * PI * 0.5)
			var pitch := clampf(rpm / float(ENG_RPMS[i]), 0.5, 2.0)
			eng_layers_on[i].pitch_scale = pitch
			eng_layers_off[i].pitch_scale = pitch
			eng_layers_on[i].volume_db = _db(base * w * (0.3 + load_s * 0.7))
			eng_layers_off[i].volume_db = _db(base * w * (1.0 - load_s) * 0.75)
	var skid := 0.0
	for w in car.wheels:
		if w.surface != "terrain":
			skid = maxf(skid, float(w.skid))
	tire.volume_db = _db(skid * 0.75 if active else 0.0)
	tire.pitch_scale = 0.9 + skid * 0.2
	gravel.volume_db = _db(clampf(car.speed / 30.0, 0.0, 1.0) * 0.6 if active and car.surface == "terrain" else 0.0)
	wind.volume_db = _db(pow(clampf(car.speed / 90.0, 0.0, 1.0), 2.0) * 0.6 if active else 0.0)
	wind.pitch_scale = 0.8 + clampf(car.speed / 120.0, 0.0, 0.6)
	var roll := pow(clampf(car.speed / 45.0, 0.0, 1.0), 0.8) if active and car.on_ground and car.surface != "terrain" else 0.0
	road.volume_db = _db(roll * (0.32 + 0.6 * (1.0 - Car.wet_grip)))
	road.pitch_scale = 0.75 + clampf(car.speed / 90.0, 0.0, 0.6)
	nitro.volume_db = _db(0.35 if active and car.nitro_on else 0.0)
	# Turbo spools with revs under throttle (turbo upgrade only).
	var want := thr * rpm_n * rpm_n if active and bool(st.get("turbo", false)) else 0.0
	spool = move_toward(spool, want, delta * (1.6 if want > spool else 4.0))
	turbo.volume_db = _db(spool * 0.12)
	turbo.pitch_scale = 0.6 + spool * 0.7
	# Lift-off effects: turbo flutter for small engines, pops & bangs for big ones.
	if active and last_throttle > 0.8 and thr < 0.2 and rpm_n > 0.6:
		if (int(st.cyl) <= 6 and int(st.cyl) > 0) or bool(st.get("turbo", false)):
			play_oneshot("blowoff", randf_range(0.95, 1.1), -6.0)
		else:
			pop_timer = 0.6
	if pop_timer > 0.0:
		pop_timer -= delta
		if randf() < delta * 14.0:
			play_oneshot("backfire", randf_range(0.8, 1.3), -4.0)
			car.pop_flash = 0.06
	last_throttle = thr

## Synthesised helicopter rotor loop: blade-pass thumps over filtered noise.
func _gen_rotor() -> AudioStreamWAV:
	var rate := 22050
	var n := rate
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / rate
		var env := pow(maxf(0.0, sin(TAU * 17.0 * t)), 6.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		var v := (lp * 1.6 * (0.25 + env) + sin(TAU * 51.0 * t) * 0.35 * env) * 0.7
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s

## Radio squelch: click, short tone, band-limited static.
func _gen_radio() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.32)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + noise - prev)
		prev = noise
		var v := hp * 0.5 * exp(-t * 9.0)
		if t < 0.06:
			v += (1.0 if fmod(t * 1400.0, 1.0) < 0.5 else -1.0) * 0.25
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s

## Two-tone car horn loop (slightly detuned square waves, softened).
func _gen_horn() -> AudioStreamWAV:
	var rate := 22050
	var n := rate / 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var a := 1.0 if fmod(t * 420.0, 1.0) < 0.5 else -1.0
		var b := 1.0 if fmod(t * 524.0, 1.0) < 0.5 else -1.0
		lp += ((a + b) * 0.5 - lp) * 0.35
		data.encode_s16(i * 2, int(clampf(lp * 0.55, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s

## Turbo whistle loop: a soft high sine with a little airy noise.
func _gen_turbo() -> AudioStreamWAV:
	var rate := 22050
	var n := rate / 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3
		var v := sin(TAU * 1800.0 * t) * 0.35 + sin(TAU * 3600.0 * t) * 0.08 + lp * 0.12
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s

## Rain ambience: soft filtered hiss with scattered droplet ticks (2 s loop).
func _gen_rain() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lp := 0.0
	var hp_prev := 0.0
	var drop := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.45
		var hiss := lp - hp_prev * 0.6
		hp_prev = lp
		if rng.randf() < 0.0025:
			drop = rng.randf_range(0.3, 0.8)
		drop *= 0.93
		var v := hiss * 0.35 + drop * rng.randf_range(-1.0, 1.0)
		# Fade the loop ends together so the seam is inaudible.
		var edge := minf(1.0, minf(float(i), float(n - i)) / 400.0)
		data.encode_s16(i * 2, int(clampf(v * edge + hiss * 0.35 * (1.0 - edge), -1.0, 1.0) * 24000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s

## Metal grinding: noise through narrow inharmonic resonators with gritty amplitude bursts.
func _gen_scrape() -> AudioStreamWAV:
	var rate := 32000
	var n := int(rate * 1.6)
	var fade := 1600
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var freqs := [1460.0, 2390.0, 3710.0, 5170.0, 870.0]
	var gains := [1.0, 0.8, 0.6, 0.35, 0.5]
	var lows := [0.0, 0.0, 0.0, 0.0, 0.0]
	var bands := [0.0, 0.0, 0.0, 0.0, 0.0]
	var grit := 0.5
	var grit_t := 0.5
	for i in n + fade:
		if rng.randf() < 0.004:
			grit_t = rng.randf_range(0.2, 1.0)
		grit += (grit_t - grit) * 0.002
		var x := rng.randf_range(-1.0, 1.0) * (grit + (0.8 if rng.randf() < 0.002 else 0.0))
		var v := 0.0
		for k in freqs.size():
			var f := 2.0 * sin(PI * freqs[k] * (1.0 + 0.02 * sin(float(i) * 0.0007 * (k + 1))) / rate)
			var hi: float = x - lows[k] - 0.06 * bands[k]
			bands[k] += f * hi
			lows[k] += f * bands[k]
			v += bands[k] * gains[k]
		buf[i] = v * 0.1 + x * 0.09
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := buf[i]
		if i < fade:
			var t := float(i) / fade
			v = v * t + buf[n + i] * (1.0 - t)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n
	return st

var scrape_lvl := 0.0

func update_scrape(level: float) -> void:
	# Smoothed so contacts flickering on and off don't click.
	scrape_lvl = move_toward(scrape_lvl, clampf(level, 0.0, 1.0), 0.06)
	scrape.volume_db = _db(scrape_lvl * 0.7)
	scrape.pitch_scale = 0.85 + scrape_lvl * 0.3

## Rolling thunder: brown noise with a crack at the start and a long decay.
func _gen_thunder() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 3.5)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var brown := 0.0
	for i in n:
		var t := float(i) / rate
		brown = clampf(brown + rng.randf_range(-1.0, 1.0) * 0.06, -1.0, 1.0)
		var env := (1.0 - exp(-t * 12.0)) * exp(-t * 1.1) * (0.8 + 0.2 * sin(t * 9.0))
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 18.0) * 0.5
		data.encode_s16(i * 2, int(clampf((brown * 1.8 * env + crack), -1.0, 1.0) * 28000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s

func update_rain(amount: float) -> void:
	rain.volume_db = _db(clampf(amount, 0.0, 1.0) * 0.45)

func set_horn(on: bool) -> void:
	horn.volume_db = -6.0 if on else -80.0

func update_rotor(dist: float) -> void:
	rotor.volume_db = _db(clampf(1.0 - dist / 260.0, 0.0, 1.0) * 0.8)

func update_siren(intensity: float) -> void:
	siren.volume_db = _db(intensity * 0.5)

func _load_cruise() -> void:
	var st: AudioStreamOggVorbis = load(MUSIC_DIR + CRUISE[cruise_idx][0] + ".ogg")
	st.loop = false
	music.cruise.stream = st
	cruise_pos = 0.0

func _next_cruise() -> void:
	cruise_idx = (cruise_idx + 1) % CRUISE.size()
	_load_cruise()
	if music_level.cruise > 0.0:
		music.cruise.play()
		now_playing.emit(CRUISE[cruise_idx][1], CRUISE[cruise_idx][2])

static func radio_dirs() -> Array[String]:
	var dirs: Array[String] = []
	if not OS.has_feature("editor"):
		dirs.append(OS.get_executable_path().get_base_dir().path_join("Radio"))
	else:
		dirs.append(ProjectSettings.globalize_path("res://").path_join("Radio"))
	dirs.append(ProjectSettings.globalize_path("user://radio"))
	dirs.append("res://assets/radio")
	return dirs

## Folder shown to the player (and opened from Settings).
static func radio_folder() -> String:
	return radio_dirs()[0]

func radio_scan() -> void:
	radio_tracks.clear()
	for dir in radio_dirs():
		var files := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
		for f in files:
			var ext := f.get_extension().to_lower()
			# Bundled files appear as name.mp3.import in exports; load by original name.
			if ext == "import":
				f = f.get_basename()
				ext = f.get_extension().to_lower()
			if ext in ["mp3", "ogg", "wav"] and not radio_tracks.has(dir.path_join(f)):
				radio_tracks.append(dir.path_join(f))
	radio_tracks.sort()
	_radio_shuffle()

func _radio_shuffle() -> void:
	radio_order.clear()
	for i in radio_tracks.size():
		radio_order.append(i)
	if bool(Settings.data.get("radio_shuffle", true)):
		radio_order.shuffle()
	radio_pos = -1

func _radio_load(path: String) -> AudioStream:
	if path.begins_with("res://"):
		return load(path) as AudioStream
	var ext := path.get_extension().to_lower()
	if ext == "mp3":
		var mp := AudioStreamMP3.new()
		mp.data = FileAccess.get_file_as_bytes(path)
		return mp if mp.data.size() > 0 else null
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	if ext == "wav":
		return AudioStreamWAV.load_from_file(path)
	return null

signal radio_failed

## Next song (also starts the radio if it's off). Returns false if there's no music;
## then the radio switches itself off so the soundtrack comes back.
func radio_next() -> bool:
	if radio_tracks.is_empty():
		radio_scan()
	if radio_tracks.is_empty() or not _radio_try_next():
		radio_scan() # files may have moved: look again next time
		if radio_on:
			radio_on = false
			radio_failed.emit()
		radio_player.stop()
		radio_player.stream = null
		return false
	return true

func _radio_try_next() -> bool:
	for attempt in radio_tracks.size():
		radio_pos += 1
		if radio_pos >= radio_order.size():
			_radio_shuffle()
			radio_pos = 0
		var path := radio_tracks[radio_order[radio_pos]]
		var st := _radio_load(path)
		if st == null:
			continue
		radio_player.stream = st
		radio_player.play()
		var tags := _read_tags(path)
		radio_title = tags[0]
		radio_artist = tags[1]
		if radio_on:
			now_playing.emit(radio_title, radio_artist)
		return true
	return false

func set_radio(on: bool) -> bool:
	if on and not radio_on:
		if radio_player.stream == null:
			if not radio_next(): # radio still off here, so no failure signal
				return false
			radio_on = true
			now_playing.emit(radio_title, radio_artist)
		else:
			radio_on = true
			radio_player.stream_paused = false
			if not radio_player.playing:
				return radio_next()
			now_playing.emit(radio_title, radio_artist)
	elif not on:
		radio_on = false
	return radio_on

## Title and artist from ID3v2 tags, falling back to "Artist - Title" file names.
func _read_tags(path: String) -> Array:
	var name := path.get_file().get_basename()
	var title := name
	var artist := ""
	if " - " in name:
		artist = name.get_slice(" - ", 0).strip_edges()
		title = name.substr(name.find(" - ") + 3).strip_edges()
	if path.get_extension().to_lower() != "mp3":
		return [title, artist]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return [title, artist]
	var head := f.get_buffer(10)
	if head.size() < 10 or head.slice(0, 3).get_string_from_ascii() != "ID3":
		return [title, artist]
	var ver := head[3]
	var size := (head[6] << 21) | (head[7] << 14) | (head[8] << 7) | head[9]
	var tag := f.get_buffer(mini(size, 512 * 1024))
	if ver < 3:
		return [title, artist] # ID3v2.2 uses 3-letter frames: fall back to the file name
	var i := 0
	if head[5] & 0x40 and tag.size() >= 4: # skip the extended header
		var ext := (tag[0] << 24) | (tag[1] << 16) | (tag[2] << 8) | tag[3]
		if ver >= 4:
			ext = (tag[0] << 21) | (tag[1] << 14) | (tag[2] << 7) | tag[3]
		else:
			ext += 4
		i = clampi(ext, 0, tag.size())
	while i + 10 <= tag.size():
		var id := tag.slice(i, i + 4).get_string_from_ascii()
		if id.is_empty() or tag[i] == 0:
			break
		var fs := 0
		if ver >= 4:
			fs = (tag[i + 4] << 21) | (tag[i + 5] << 14) | (tag[i + 6] << 7) | tag[i + 7]
		else:
			fs = (tag[i + 4] << 24) | (tag[i + 5] << 16) | (tag[i + 6] << 8) | tag[i + 7]
		if fs <= 0 or i + 10 + fs > tag.size():
			break
		if id == "TIT2" or id == "TPE1":
			var body := tag.slice(i + 10, i + 10 + fs)
			var text := _id3_text(body)
			if not text.is_empty():
				if id == "TIT2":
					title = text
				else:
					artist = text
		i += 10 + fs
	return [title, artist]

func _id3_text(body: PackedByteArray) -> String:
	if body.size() < 2:
		return ""
	var enc := body[0]
	var raw := body.slice(1)
	var text := ""
	match enc:
		1:
			text = raw.get_string_from_utf16()
		2: # UTF-16 big-endian without BOM: swap to little-endian
			var sw := raw.duplicate()
			for k in range(0, sw.size() - 1, 2):
				var t := sw[k]
				sw[k] = sw[k + 1]
				sw[k + 1] = t
			text = sw.get_string_from_utf16()
		3:
			text = raw.get_string_from_utf8()
		_:
			text = raw.get_string_from_ascii()
	return text.replace(char(0), "").strip_edges()

## mode: "cruise", "chase", "race" or "menu". duck < 1 lowers everything (pause menu).
## With the radio on, your music plays instead of the soundtrack whenever you drive.
func update_music(mode: String, delta: float, duck := 1.0) -> void:
	music_duck = move_toward(music_duck, duck, delta * 2.0)
	var radio_live := radio_on and mode in ["cruise", "chase", "race"]
	radio_level = move_toward(radio_level, 1.0 if radio_live else 0.0, delta * (0.8 if radio_live else 0.6))
	radio_player.volume_db = _db(radio_level * music_duck)
	radio_player.stream_paused = radio_level <= 0.0 and radio_player.stream != null
	for m in music:
		var mp: AudioStreamPlayer = music[m]
		var target := 1.0 if m == mode and not (radio_live and m != "menu") else 0.0
		# Quick fade in for action themes, slower fade out so transitions overlap.
		var rate := (1.2 if m in ["chase", "race", "credits"] else 0.5) if target > music_level[m] else 0.45
		music_level[m] = move_toward(music_level[m], target, delta * rate)
		mp.volume_db = _db(music_level[m] * music_duck)
		if music_level[m] > 0.0 and not mp.playing:
			if m == "cruise":
				mp.play(cruise_pos)
				if cruise_pos < 1.0:
					now_playing.emit(CRUISE[cruise_idx][1], CRUISE[cruise_idx][2])
			else:
				mp.play()
		elif music_level[m] <= 0.0 and mp.playing:
			if m == "cruise":
				cruise_pos = mp.get_playback_position()
			mp.stop()

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
		var c_cyl := int(car.stats.cyl)
		var li: int = 0
		if c_cyl > 0:
			var lb := eng_layer(maxf(float(car.rpm), 700.0))
			li = int(lb[0]) + (1 if float(lb[1]) > 0.5 else 0)
		if not ai_players.has(car):
			var p := AudioStreamPlayer3D.new()
			p.bus = "SFX"
			p.unit_size = 8.0
			p.max_distance = 140.0
			p.set_meta("layer", -1)
			car.add_child(p)
			ai_players[car] = p
		var ap: AudioStreamPlayer3D = ai_players[car]
		if int(ap.get_meta("layer")) != li:
			# Nearest rpm layer for AI (switching is inaudible at a distance).
			ap.set_meta("layer", li)
			ap.stream = streams["engine_0_on"] if c_cyl == 0 else eng_stream(c_cyl, true, li)
			ap.play(randf() * 0.4)
		ap.pitch_scale = clampf(0.4 + car.speed / 40.0, 0.4, 3.0) if c_cyl == 0 else clampf(maxf(float(car.rpm), 700.0) / float(ENG_RPMS[li]), 0.5, 2.0)
		ap.volume_db = -4.0 + float(car.input.throttle) * 4.0
