class_name Car
extends RigidBody3D
## Raycast-suspension vehicle with a slip-angle tyre model, load transfer,
## anti-roll bars, aero, a power-limited engine with gearbox, nitrous and
## optional driving assists. Used by the player, AI racers and police.

const CAR_SCENE := preload("res://assets/cars/CarConcept.glb")
const G := 9.81
const LAYER_CARS := 2

signal impact(strength: float)
signal shifted(gear: int)

var stats: Dictionary = {}
var input := {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "handbrake": 0.0, "nitro": false, "shift_up": false, "shift_down": false}
var assists := true
var manual := false
var is_player := false

# Geometry (car space, forward = -Z, right = +X)
var WHEEL_R := 0.38
const REST := 0.26
const SAG := 0.085
var wheels: Array = []
var layout := {"r": 0.38, "front": -1.485, "rear": 1.314, "x": 0.98}
var wheelbase := 2.8
var a_front := 1.3
var b_rear := 1.5

# State
var gear := 0
var rpm := 900.0
var shift_cut := 0.0
var reverse := false
var nitro := 1.0
var nitro_on := false
var burnout := false
var speed := 0.0
var forward_speed := 0.0
var lateral_speed := 0.0
var steer_angle := 0.0
var on_ground := false
var wheels_on_ground := 0
var air_time := 0.0
var landing_impact := 0.0
var wheelspin := 0.0
var slip_angle := 0.0 # body side-slip
var drift_mode := false # true only once the driver deliberately kicks the car sideways
var surface := "road"
var power_mul := 1.0
var gear_top: Array[float] = []
var drive_f := 10000.0
var power := 500000.0
var cd := 0.001
var last_vel := Vector3.ZERO
var accel_local := Vector3.ZERO

# Visuals
var model: Node3D
var body_root: Node3D
var paint_mats: Array[StandardMaterial3D] = []
var brake_mat: StandardMaterial3D
var head_mat: StandardMaterial3D
var headlights: Array[SpotLight3D] = []
var lights_on := false
var flames: Array[MeshInstance3D] = []
var police_lights: Array[OmniLight3D] = []
var police_mats: Array[StandardMaterial3D] = []
var is_police := false
var cast_light_shadows := false

func setup(car_stats: Dictionary, paint: Color, police := false, detail := true, light_shadows := false) -> void:
	cast_light_shadows = light_shadows
	stats = car_stats
	is_police = police
	mass = stats.mass
	collision_layer = LAYER_CARS
	collision_mask = 1
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.46, 0.08)
	inertia = Vector3(mass * (0.9 * 0.9 + 4.3 * 4.3) / 12.0 * 0.9, mass * (2.0 * 2.0 + 4.3 * 4.3) / 12.0 * 1.05, mass * (2.0 * 2.0 + 0.9 * 0.9) / 12.0 * 1.1)
	# Replace the project-default damping: drag and tyre forces model resistance explicitly.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.3
	linear_damp = 0.0
	continuous_cd = true
	can_sleep = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var pm := PhysicsMaterial.new()
	pm.friction = 0.25
	pm.bounce = 0.1
	physics_material_override = pm
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.95, 0.62, 4.25)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.68, 0.05)
	add_child(cs)
	var cabin := BoxShape3D.new()
	cabin.size = Vector3(1.5, 0.45, 2.0)
	var cs2 := CollisionShape3D.new()
	cs2.shape = cabin
	cs2.position = Vector3(0, 1.1, 0.3)
	add_child(cs2)
	_setup_model(paint, detail)
	_setup_wheels()
	_setup_engine()
	body_entered.connect(_on_body_entered)
	contact_monitor = true
	max_contacts_reported = 4

func _setup_engine() -> void:
	gear_top.clear()
	for g in int(stats.gears):
		gear_top.append(stats.top * 1.06 * pow(float(g + 1) / stats.gears, 0.72))
	gear = clampi(gear, 0, gear_top.size() - 1)
	cd = 4.5 / (stats.top * stats.top)
	power = (4.5 * stats.top + 0.12 * stats.top) * mass
	drive_f = mass * stats.accel

func _setup_wheels() -> void:
	wheels.clear()
	# Wheel centres measured from the model (front at -Z after orientation).
	WHEEL_R = layout.r
	var fz: float = layout.front
	var rz: float = layout.rear
	var wx: float = layout.x
	var defs := [["WheelFrontL", Vector3(-wx, WHEEL_R, fz), true], ["WheelFrontR", Vector3(wx, WHEEL_R, fz), true],
		["WheelRearL", Vector3(-wx, WHEEL_R, rz), false], ["WheelRearR", Vector3(wx, WHEEL_R, rz), false]]
	a_front = -fz - center_of_mass.z
	b_rear = rz + center_of_mass.z
	wheelbase = a_front + b_rear
	for d in defs:
		var w := {
			"name": d[0], "center": d[1], "front": d[2], "left": d[1].x < 0.0,
			"anchor": d[1] + Vector3(0, REST - SAG, 0), "comp": SAG, "prev_comp": SAG, "contact": false,
			"spin": 0.0, "spin_vel": 0.0, "load": 0.0, "slip": 0.0, "skid": 0.0, "hit_pos": Vector3.ZERO,
			"node": null, "spinners": [], "base": Transform3D(), "surface": "road",
		}
		if model:
			var n: Node3D = model.find_child(d[0], true, false)
			if n:
				w.node = n
				# Remove the modelled steering/rotation pose; keep the position.
				n.transform = Transform3D(Basis(), n.transform.origin)
				w.base = n.transform
				for c in n.get_children():
					if c is MeshInstance3D and not String(c.name).contains("Brake"):
						w.spinners.append(c)
		wheels.append(w)

func _setup_model(paint: Color, detail: bool) -> void:
	var body_id: String = stats.get("body", "concept")
	if body_id != "concept":
		_setup_generated(body_id, paint)
		return
	model = CAR_SCENE.instantiate()
	# The asset faces +Z; our vehicles face -Z.
	model.rotation.y = PI
	add_child(model)
	body_root = model
	var seen := {}
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(m.name)
		if not detail and (nm.begins_with("Interior") or nm == "Engine" or nm.contains("Pedal") or nm.contains("Steering")):
			m.visible = false
			continue
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var rn := mat.resource_name
			if rn.begins_with("Paint") or rn == "Brakelight" or rn == "Headlight":
				var key := rn
				if not seen.has(key):
					var dup := mat.duplicate() as StandardMaterial3D
					seen[key] = dup
					if rn.begins_with("Paint 1"):
						paint_mats.append(dup)
					elif rn.begins_with("Paint 2"):
						paint_mats.append(dup)
					elif rn == "Brakelight":
						brake_mat = dup
						dup.emission_enabled = true
						dup.emission = Color(1, 0.05, 0.02)
					elif rn == "Headlight":
						head_mat = dup
						dup.emission_enabled = true
						dup.emission = Color(1, 0.95, 0.85)
				m.set_surface_override_material(i, seen[key])
	set_paint(paint)
	_setup_lamps()

func _setup_generated(body_id: String, paint: Color) -> void:
	var pm := StandardMaterial3D.new()
	paint_mats.append(pm)
	model = BodyGen.build(body_id, pm)
	add_child(model)
	body_root = model
	layout = BodyGen.wheel_layout(body_id)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if String(mi.name) == "Headlamp":
			head_mat = mi.material_override as StandardMaterial3D
		elif String(mi.name) == "Taillamp":
			brake_mat = mi.material_override as StandardMaterial3D
	set_paint(paint)
	_setup_lamps()

func _setup_lamps() -> void:
	# Headlights
	for x in [-0.62, 0.62]:
		var l := SpotLight3D.new()
		l.position = Vector3(x, 0.66, -2.2)
		l.rotation_degrees = Vector3(-6, 0, 0)
		l.spot_range = 60.0
		l.spot_angle = 32.0
		l.spot_attenuation = 0.8
		l.light_energy = 0.0
		l.light_color = Color(1.0, 0.95, 0.88)
		l.shadow_enabled = cast_light_shadows
		l.visible = false
		add_child(l)
		headlights.append(l)
	# Nitrous flames at the exhaust
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.albedo_color = Color(0.35, 0.55, 1.0, 0.9)
	for x in [-0.42, 0.42]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.09
		cone.height = 0.9
		cone.material = flame_mat
		var f := MeshInstance3D.new()
		f.mesh = cone
		f.rotation_degrees = Vector3(-90, 0, 0)
		f.position = Vector3(x, 0.32, 2.55)
		f.visible = false
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)
		flames.append(f)
	if is_police:
		_setup_police_bar()

func _setup_police_bar() -> void:
	var bar := Node3D.new()
	bar.position = Vector3(0, 1.2, 0.15)
	add_child(bar)
	var housing := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.1, 0.28)
	housing.mesh = bm
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.05, 0.05, 0.05)
	housing.material_override = hm
	bar.add_child(housing)
	for i in 2:
		var lm := StandardMaterial3D.new()
		lm.emission_enabled = true
		lm.albedo_color = Color(0.1, 0.1, 0.1)
		lm.emission = Color(1, 0.02, 0.05) if i == 0 else Color(0.05, 0.2, 1)
		var lens := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.45, 0.11, 0.26)
		lens.mesh = lb
		lens.material_override = lm
		lens.position = Vector3(-0.28 if i == 0 else 0.28, 0.02, 0)
		bar.add_child(lens)
		police_mats.append(lm)
		var ol := OmniLight3D.new()
		ol.light_color = lm.emission
		ol.omni_range = 14.0
		ol.light_energy = 0.0
		ol.position = lens.position + Vector3(0, 0.2, 0)
		bar.add_child(ol)
		police_lights.append(ol)

func set_paint(c: Color) -> void:
	for i in paint_mats.size():
		var m := paint_mats[i]
		if is_police:
			m.albedo_color = Color(0.02, 0.02, 0.025) if i % 2 == 0 else Color(0.85, 0.86, 0.88)
		else:
			m.albedo_color = c if i % 2 == 0 else c.darkened(0.55)
		m.metallic = 0.35
		m.roughness = 0.3
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.05

func set_lights(on: bool, night: float) -> void:
	lights_on = on
	for l in headlights:
		l.visible = on
		l.light_energy = 6.0 if on else 0.0
	if head_mat:
		head_mat.emission_energy_multiplier = 6.0 if on else 0.3

func reset_to(t: Transform3D) -> void:
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reverse = false
	gear = 0
	air_time = 0.0
	landing_impact = 0.0
	last_vel = Vector3.ZERO
	nitro_on = false
	drift_mode = false
	for w in wheels:
		w.comp = SAG
		w.prev_comp = SAG
	reset_physics_interpolation()

# ---------------------------------------------------------------- physics
func _tire(alpha: float) -> float:
	# Peak ~0.19 rad, stays near 92% grip past the peak so slides don't snap away.
	return sin(1.25 * atan(16.0 * alpha))

static var prof_us := 0
static var wet_grip := 1.0 # set from the weather: wet tarmac grips a little less

func _physics_process(dt: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_physics_step(dt)
	prof_us += Time.get_ticks_usec() - _t0

func _physics_step(dt: float) -> void:
	var xf := global_transform
	var basis_n := xf.basis.orthonormalized()
	var up := basis_n.y
	var fwd := -basis_n.z
	var right := basis_n.x
	var v := linear_velocity
	speed = v.length()
	forward_speed = v.dot(fwd)
	lateral_speed = v.dot(right)
	var abs_u := absf(forward_speed)
	var mu_base: float = stats.grip / G

	# Local acceleration (for weight transfer telemetry and camera/visual cues)
	var acc := (v - last_vel) / dt
	last_vel = v
	accel_local = accel_local.lerp(Vector3(acc.dot(right), acc.dot(up), acc.dot(fwd)), 1.0 - exp(-10.0 * dt))

	var beta := atan2(lateral_speed, maxf(abs_u, 0.5)) if speed > 3.0 else 0.0
	slip_angle = beta
	# --- Drift mode: only entered on purpose (handbrake, or brake-flick while
	# steering on throttle). Without it the car grips and ESC keeps it straight.
	var steer_in := absf(float(input.steer))
	if speed > 11.0 and forward_speed > 0.0:
		if float(input.handbrake) > 0.3 and steer_in > 0.2:
			drift_mode = true
		elif float(input.brake) > 0.4 and float(input.throttle) > 0.4 and steer_in > 0.5:
			drift_mode = true
	if drift_mode and (speed < 8.0 or forward_speed < 0.0 or (absf(beta) < 0.1 and float(input.handbrake) < 0.1) or (steer_in < 0.15 and float(input.handbrake) < 0.1) or (float(input.throttle) < 0.1 and absf(beta) < 0.25 and float(input.handbrake) < 0.1)):
		drift_mode = false
	if not assists:
		drift_mode = absf(beta) > 0.15
	# --- Steering: lock limited to what the front tyres can actually use at speed
	var lock := 0.6 / (1.0 + maxf(0.0, abs_u - 5.0) / 15.0)
	if not drift_mode and abs_u > 8.0:
		lock = minf(lock, atan(wheelbase * mu_base * G / (abs_u * abs_u)) + 0.13)
	var target := -float(input.steer) * lock
	if assists and speed > 6.0 and forward_speed > 0.0:
		target -= clampf(beta, -0.5, 0.5) * 0.6 * smoothstep(0.04, 0.25, absf(beta))
	var steer_rate := lerpf(5.0, 2.6, smoothstep(10.0, 50.0, abs_u)) * (1.6 if drift_mode else 1.0)
	steer_angle = move_toward(steer_angle, clampf(target, -0.75, 0.75), dt * steer_rate)

	# --- Engine & gearbox
	var idle: float = stats.idle
	var red: float = stats.red
	var throttle: float = input.throttle
	var brake: float = input.brake
	if brake > 0.1 and forward_speed < 0.8 and throttle < 0.1:
		reverse = true
	if throttle > 0.1 and forward_speed > -0.8:
		reverse = false
	if reverse:
		var t := throttle
		throttle = brake
		brake = t
	# Burnout / donuts: throttle + brake at low speed spins the rear tyres in place.
	burnout = throttle > 0.5 and brake > 0.5 and abs_u < 7.0 and not reverse
	if shift_cut > 0.0:
		shift_cut -= dt
	var rpm_n := clampf(abs_u / gear_top[gear], 0.0, 1.05)
	if gear_top.size() > 1:
		if manual:
			if input.shift_up and gear < gear_top.size() - 1:
				gear += 1
				shift_cut = 0.1
			if input.shift_down and gear > 0:
				gear -= 1
		else:
			if rpm_n > 0.97 and gear < gear_top.size() - 1 and not reverse and wheels_on_ground > 2:
				gear += 1
				shift_cut = float(stats.get("shift_time", 0.15))
				shifted.emit(gear)
			elif gear > 0 and abs_u < gear_top[gear - 1] * 0.62:
				gear -= 1
	input.shift_up = false
	input.shift_down = false
	rpm_n = clampf(abs_u / gear_top[gear], 0.0, 1.05)
	var free_rev := 0.3 * throttle if abs_u < 3.0 else 0.0
	var target_rpm := idle + (red - idle) * maxf(rpm_n, free_rev)
	if wheelspin > 0.2:
		target_rpm = lerpf(target_rpm, red, 0.4)
	if burnout:
		target_rpm = red * (0.88 + 0.06 * sin(Time.get_ticks_msec() * 0.03))
	rpm = lerpf(rpm, minf(target_rpm, red * 1.01), 1.0 - exp(-20.0 * dt))

	var drive := 0.0
	if throttle > 0.0:
		var shape := 0.75 + 0.25 * sin(PI * clampf(0.1 + rpm_n * 0.75, 0.0, 1.0)) if gear_top.size() > 1 else 1.0
		var limiter := 0.0 if rpm_n >= 1.02 or (rpm_n >= 1.0 and gear == gear_top.size() - 1) else 1.0
		drive = throttle * minf(drive_f, power / maxf(abs_u, 1.0)) * shape * limiter * power_mul
		if shift_cut > 0.0:
			drive *= 0.2
		if reverse:
			drive = 0.0 if abs_u > 15.0 else -drive * 0.55

	nitro_on = false
	var boost := 0.0
	if input.nitro and nitro > 0.0 and not reverse and wheels_on_ground >= 2 and forward_speed > 2.0:
		nitro_on = true
		nitro = maxf(0.0, nitro - dt / float(stats.get("nitro_cap", 4.0)))
		boost = mass * float(stats.nitro) * (1.0 - smoothstep(stats.top * 1.05, stats.top * 1.22, abs_u))

	# --- Wheels
	var space := get_world_3d().direct_space_state
	var hb: float = input.handbrake
	var awd: bool = stats.awd
	wheels_on_ground = 0
	var total_load_static := mass * G / 4.0
	var k := total_load_static / SAG
	var damp := 2.0 * 0.32 * sqrt(k * mass / 4.0)
	var comp := [0.0, 0.0, 0.0, 0.0]
	var spin_total := 0.0
	var surf_counts := {}
	for i in wheels.size():
		var w: Dictionary = wheels[i]
		var from: Vector3 = xf * (w.anchor as Vector3)
		var to: Vector3 = from - up * (REST + WHEEL_R)
		var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
		var hit := space.intersect_ray(q)
		w.contact = not hit.is_empty()
		if not w.contact:
			w.prev_comp = w.comp
			w.comp = move_toward(w.comp, 0.0, dt * 2.0)
			w.load = 0.0
			w.skid = 0.0
			continue
		wheels_on_ground += 1
		var dist: float = (hit.position - from).length()
		var c := clampf(REST - (dist - WHEEL_R), 0.0, REST)
		var cvel := (c - float(w.comp)) / dt
		w.prev_comp = w.comp
		w.comp = c
		comp[i] = c
		var fz := k * c + damp * cvel
		if c > REST * 0.9:
			fz += (c - REST * 0.9) * k * 8.0 # bump stop
		fz = maxf(fz, 0.0)
		w.load = fz
		var n: Vector3 = hit.normal
		var col = hit.collider
		var surf := "terrain"
		if col and col.has_meta("surface"):
			surf = col.get_meta("surface")
		w.surface = surf
		surf_counts[surf] = surf_counts.get(surf, 0) + 1
		var grip_mul := wet_grip
		var roll_res := 0.015
		if surf == "terrain":
			grip_mul = 0.72
			roll_res = 0.06
		var wfwd := fwd
		if w.front:
			wfwd = fwd.rotated(up, steer_angle)
		var f := (wfwd - n * wfwd.dot(n)).normalized()
		var lat := f.cross(n).normalized()
		var p: Vector3 = hit.position
		var com_g := xf * center_of_mass
		var pv := v + angular_velocity.cross(p - com_g)
		var vx := pv.dot(f)
		var vy := pv.dot(lat)
		# Load-sensitive friction
		var mu := mu_base * grip_mul * (1.0 - 0.08 * (fz / total_load_static - 1.0))
		if not w.front and hb > 0.0:
			mu *= lerpf(1.0, 0.32, hb)
		if not w.front:
			if drift_mode and hb < 0.1:
				mu *= 1.0 - 0.08 * float(stats.drift)
			elif not drift_mode:
				mu *= 1.12 # rear bias rear bias: stable, planted feel

		# Longitudinal: drive split, brakes, rolling resistance
		var fx := 0.0
		var driven: bool = (not w.front) or awd
		if driven:
			var share := 0.5
			if awd:
				var rear_slide := smoothstep(0.08, 0.3, absf(slip_angle))
				var front_share := (0.08 if hb > 0.0 else lerpf(0.35, 0.12, rear_slide))
				share = (front_share if w.front else 1.0 - front_share) * 0.5
			fx += drive * share
		var bshare := 0.65 if w.front else 0.35
		var bf := brake * float(stats.brake) * mass * bshare * 0.5
		if not w.front and hb > 0.0:
			bf += hb * mass * 3.0
		if absf(vx) > 0.05:
			fx -= signf(vx) * bf
		elif throttle < 0.05:
			fx -= vx * mass * 0.25 # hold still
		fx -= signf(vx) * fz * roll_res

		# Lateral slip angle and the cornering force the tyre wants
		var alpha := atan2(vy, maxf(absf(vx), 3.0))
		var fy := -mu * fz * _tire(alpha)
		var low := smoothstep(1.0, 4.0, absf(vx) + absf(vy))
		fy = lerpf(-vy * mass * 0.25 * 4.0, fy, low)
		# Traction limit. With assists and not drifting, traction control keeps the
		# driven tyres from eating the grip needed for cornering (no power oversteer).
		var maxf_ := maxf(mu * fz, 1.0)
		if assists:
			if drift_mode:
				maxf_ *= 0.95
			elif driven and fx > 0.0:
				maxf_ = maxf(sqrt(maxf(0.0, pow(mu * fz, 2.0) - fy * fy)), mu * fz * 0.3) * 0.92
		var spin := 0.0
		if driven and absf(fx) > maxf_:
			spin = minf(absf(fx) / maxf_ - 1.0, 3.0)
			fx = signf(fx) * (maxf_ if assists else maxf_ * 0.85)
		if burnout and driven and not w.front:
			# Rear tyres light up; only a little forward bite so the car pivots.
			spin = 2.5
			fx = mu * fz * (0.12 + 0.25 * absf(float(input.steer)))
		elif burnout and w.front and not awd:
			fx = -signf(vx) * minf(mu * fz, absf(vx) * mass * 2.0)
		spin_total = maxf(spin_total, spin)

		var cap := sqrt(maxf(0.0, pow(mu * fz, 2.0) - fx * fx)) * (0.7 if spin > 0.0 else 1.0)
		fy = clampf(fy, -cap, cap)
		w.slip = alpha
		w.skid = clampf((absf(alpha) - 0.12) * 3.0 + spin * 0.7 + (0.5 if (not w.front and hb > 0.5 and speed > 5.0) else 0.0), 0.0, 1.0) * clampf(speed / 8.0, 0.0, 1.0)
		w.hit_pos = p
		# Vertical load at the contact patch; tyre forces applied nearer the CoM height,
		# emulating anti-squat/anti-dive/roll-centre geometry.
		apply_force(n * fz, p - xf.origin)
		var lever := p + up * (center_of_mass.y * 0.8)
		apply_force(f * fx + lat * fy, lever - xf.origin)
		# Wheel spin for visuals
		w.spin_vel = vx / WHEEL_R * (1.0 + spin * 0.8)
	wheelspin = spin_total
	on_ground = wheels_on_ground >= 2
	surface = "road"
	if surf_counts.get("terrain", 0) >= 2:
		surface = "terrain"

	# Anti-roll bars
	var arb := k * 0.6
	for pair in [[0, 1], [2, 3]]:
		var d: float = comp[pair[0]] - comp[pair[1]]
		# Resist roll: push up on the compressed side, down on the extended side.
		if wheels[pair[0]].contact:
			apply_force(up * d * arb, (xf * (wheels[pair[0]].anchor as Vector3)) - xf.origin)
		if wheels[pair[1]].contact:
			apply_force(-up * d * arb, (xf * (wheels[pair[1]].anchor as Vector3)) - xf.origin)

	# Aero drag, downforce and nitrous
	apply_central_force(-v * v.length() * cd * mass)
	if on_ground:
		apply_central_force(-up * mass * G * float(stats.get("downforce", 0.00011)) * forward_speed * forward_speed)
	if boost > 0.0:
		apply_central_force(fwd * boost)

	# Stability control. Grip mode: yaw rate follows the steering and side-slip is
	# killed early. Drift mode: lets the slide hold but stops spin-outs.
	if assists and on_ground and speed > 8.0 and forward_speed > 0.0:
		var yaw_rate := angular_velocity.dot(up)
		if drift_mode:
			var hold := lerpf(0.2, 0.45, smoothstep(0.1, 0.6, steer_in))
			var excess := maxf(0.0, absf(beta) - hold)
			apply_torque(up * (-signf(beta) * excess * 22.0 - yaw_rate * minf(excess * 6.0, 2.0)) * inertia.y)
		else:
			var r_des := forward_speed * tan(steer_angle) / wheelbase
			var r_max := mu_base * G / maxf(abs_u, 1.0)
			r_des = clampf(r_des, -r_max, r_max)
			var err := r_des - yaw_rate
			# Strong against over-rotation, gentle help on turn-in.
			var over := absf(yaw_rate) > absf(r_des) or signf(yaw_rate) != signf(r_des)
			var gain := (6.0 if over else 1.5) * smoothstep(8.0, 16.0, speed)
			apply_torque(up * err * gain * inertia.y)
			var excess2 := maxf(0.0, absf(beta) - 0.06)
			apply_torque(up * (-signf(beta) * excess2 * 10.0) * inertia.y)

	if burnout and on_ground:
		apply_torque(up * -float(input.steer) * inertia.y * 2.2)

	# Anti-rollover: big roll angles are pushed back toward level (cars land on wheels).
	if wheels_on_ground >= 1 and absf(right.y) > 0.28:
		apply_torque(fwd * right.y * inertia.z * 22.0 - fwd * angular_velocity.dot(fwd) * inertia.z * 2.0)

	# Airborne: light pitch/roll control and self-righting.
	if wheels_on_ground == 0:
		air_time += dt
		apply_torque(right * float(input.throttle - input.brake) * inertia.x * 0.6)
		apply_torque(-fwd * float(input.steer) * inertia.z * 0.5)
	else:
		if air_time > 0.35:
			landing_impact = absf(linear_velocity.y) + air_time * 4.0
		air_time = 0.0
	if up.y < 0.4 and speed < 4.0:
		# Gently flip upright when stuck on the side or roof.
		apply_torque(up.cross(Vector3.UP) * inertia.x * 8.0)
		apply_central_force(Vector3.UP * mass * 4.0)

static var prof_vis_us := 0

func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_visuals(delta)
	prof_vis_us += Time.get_ticks_usec() - _t0

func _visuals(delta: float) -> void:
	# Wheel visuals: suspension travel, steering and spin.
	for w in wheels:
		if w.node == null:
			continue
		var n: Node3D = w.node
		var drop: float = SAG - float(w.comp)
		var steer := steer_angle if w.front else 0.0
		w.spin = fmod(float(w.spin) + float(w.spin_vel) * delta, TAU)
		# Wheel node lives in the model's Z-up parent space; vertical is local Z there.
		var parent_up := (n.get_parent() as Node3D).global_transform.basis.inverse() * global_transform.basis.y
		var origin: Vector3 = w.base.origin - parent_up.normalized() * drop
		n.transform = Transform3D(Basis(parent_up.normalized(), steer), origin)
		for s in w.spinners:
			(s as Node3D).rotation = Vector3(-float(w.spin), 0, 0)
	if brake_mat:
		var braking := float(input.brake) > 0.1 and not reverse
		brake_mat.emission_energy_multiplier = 6.0 if braking else (2.0 if lights_on else 0.2)
	for f in flames:
		f.visible = nitro_on
		if nitro_on:
			f.scale = Vector3.ONE * randf_range(0.8, 1.3)
	if is_police:
		var t := Time.get_ticks_msec() / 1000.0
		var phase := int(t * 7.0) % 4
		var r_on := phase == 0 or phase == 2
		police_mats[0].emission_energy_multiplier = 9.0 if r_on else 0.2
		police_mats[1].emission_energy_multiplier = 0.2 if r_on else 9.0
		police_lights[0].light_energy = 5.0 if r_on else 0.0
		police_lights[1].light_energy = 0.0 if r_on else 5.0

func set_police_active(on: bool) -> void:
	for l in police_lights:
		l.visible = on
	for m in police_mats:
		m.emission_enabled = on

func _on_body_entered(b: Node) -> void:
	# Impact strength = velocity change from the hit, not the car's speed.
	impact.emit((last_vel - linear_velocity).length())

var kmh: float:
	get:
		return speed * 3.6
