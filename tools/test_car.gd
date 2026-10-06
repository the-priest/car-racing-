extends SceneTree
## Headless vehicle dynamics test: run with --fixed-fps 120.

var car: Car
var t := 0.0
var phase := 0
var log := []
var t100 := -1.0
var t200 := -1.0
var max_lat := 0.0
var max_beta := 0.0
var car_id := "vanta"
var maxed := false

func _initialize() -> void:
	print("init start")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			car_id = a.substr(6)
		if a == "--max":
			maxed = true
	var ground := StaticBody3D.new()
	ground.set_meta("surface", "road")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4000, 2, 4000)
	cs.shape = bs
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	get_root().add_child(ground)
	car = Car.new()
	get_root().add_child(car)
	var up := {}
	if maxed:
		for k in Data.UPGRADES:
			up[k] = Data.UPGRADES[k].cost.size()
	car.setup(Data.stats_for(car_id, up), Color.RED, false, false)
	car.global_position = Vector3(0, 0.05, 0)
	print("init done")
	physics_frame.connect(_tick)

func _tick() -> void:
	var dt := 1.0 / 120.0
	t += dt
	var kmh: float = car.speed * 3.6
	if Engine.get_physics_frames() % 120 == 0 and phase == 1: print("tick t=", snappedf(t, 0.01), " kmh=", int(kmh), " gear=", car.gear, " rpm=", int(car.rpm), " ground=", car.wheels_on_ground, " comp=", car.wheels.map(func(w): return snappedf(w.comp, 0.01)), " spin=", snappedf(car.wheelspin, 0.01), " pitch=", snappedf(car.global_transform.basis.z.y, 0.01))
	match phase:
		0: # settle
			car.input.throttle = 0.0
			if t > 1.0:
				phase = 1; t = 0.0
				print("settled y=%.3f comp=%s" % [car.global_position.y, str(car.wheels.map(func(w): return snappedf(w.comp, 0.001)))])
		1: # straight-line acceleration
			car.input.throttle = 1.0
			if t100 < 0 and kmh >= 100: t100 = t
			if t200 < 0 and kmh >= 200: t200 = t
			if car.global_position.length() > 1700.0:
				car.global_position = Vector3(0, car.global_position.y, 0)
				car.reset_physics_interpolation()
			if t > (40.0 if maxed else 12.0):
				print("0-100 %.2fs  0-200 %.2fs  v@30s %d km/h gear %d" % [t100, t200, kmh, car.gear + 1])
				phase = 2; t = 0.0
		2: # brake to stop
			car.input.throttle = 0.0; car.input.brake = 1.0
			if car.speed < 0.5:
				print("brake from top: %.2fs" % t)
				car.input.brake = 0.0
				phase = 3; t = 0.0
		3: # accelerate to 90 then steady turn ramp
			if t < dt * 1.5:
				car.global_position = Vector3(0, 0.05, 0)
			car.input.throttle = 1.0 if kmh < 90 else 0.45
			if kmh >= 90 or t > 15:
				phase = 4; t = 0.0
		4:
			car.input.steer = minf(1.0, t / 4.0)
			car.input.throttle = 0.5
			max_lat = maxf(max_lat, absf(car.accel_local.x))
			if t > 6.0:
				print("max lateral %.2f g at %d km/h, slip %.2f, upright %.2f yaw %.2f drift %s" % [max_lat / 9.81, kmh, car.slip_angle, car.global_transform.basis.y.y, car.angular_velocity.y, car.drift_mode])
				car.input.steer = 0.0
				phase = 5; t = 0.0
		5: # straighten & get speed for drift
			car.input.throttle = 1.0 if kmh < 95 else 0.3
			if t > 6.0:
				phase = 6; t = 0.0
		6: # handbrake flick + held steer + throttle
			car.input.steer = 0.8
			car.input.handbrake = 1.0 if t < 0.5 else 0.0
			car.input.throttle = 1.0
			max_beta = maxf(max_beta, absf(car.slip_angle))
			if t > 5.0:
				print("drift held: max beta %.2f, beta now %.2f, %d km/h, upright %.2f" % [max_beta, car.slip_angle, kmh, car.global_transform.basis.y.y])
				phase = 7; t = 0.0
		7: # release steer: should recover
			car.input.steer = 0.0
			car.input.throttle = 1.0
			if t > 3.0:
				print("recovery: beta %.2f, yaw rate %.2f, %d km/h" % [car.slip_angle, car.angular_velocity.y, kmh])
				quit()
