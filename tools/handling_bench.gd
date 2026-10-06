extends SceneTree
## Headless handling bench on a flat plane. Prints response/drift metrics per car.
## godot --headless --path . --script tools/handling_bench.gd  (CAR=vanta to pick one)

var car: Car
var frame := 0
var scenario := 0
var log_data := {}
var cars: Array = []
var car_idx := 0
var HZ := 120.0

const SCENARIOS := ["step_steer", "step_fast", "slow_turn", "lane_change", "gas_tap_drift", "drift_counter", "handbrake_turn", "lift_exit"]

func _initialize() -> void:
	if OS.has_environment("PHYS_HZ"):
		Engine.physics_ticks_per_second = int(OS.get_environment("PHYS_HZ"))
	HZ = float(Engine.physics_ticks_per_second)
	var ground := StaticBody3D.new()
	ground.set_meta("surface", "road")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20000, 2, 20000)
	cs.shape = bs
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	get_root().add_child(ground)
	cars = [OS.get_environment("CAR")] if OS.has_environment("CAR") else ["vanta", "stallion", "vanta_x"]
	_start()
	physics_frame.connect(_tick)

func _start() -> void:
	if car:
		car.queue_free()
	car = Car.new()
	get_root().add_child(car)
	car.setup(Data.stats_for(cars[car_idx], {}), Color.RED, false, false)
	car.tap_drift = true
	car.global_transform = Transform3D(Basis(), Vector3(0, 0.6, 0))
	frame = 0
	log_data = {"max_beta": 0.0, "yaw0": 0.0, "t90": -1.0, "spun": false, "drift_frames": 0}

func _heading() -> float:
	var f := -car.global_transform.basis.z
	return atan2(f.x, f.z)

func _tick() -> void:
	frame += 1
	var t := frame / HZ
	var name: String = SCENARIOS[scenario]
	var inp := car.input
	inp.throttle = 0.0
	inp.brake = 0.0
	inp.steer = 0.0
	inp.handbrake = 0.0
	var target_kmh: float = {"step_steer": 100.0, "step_fast": 190.0, "slow_turn": 35.0, "lane_change": 120.0, "gas_tap_drift": 95.0, "drift_counter": 95.0, "handbrake_turn": 70.0, "lift_exit": 95.0}[name]
	# Phase 1 (0-1 s): hold speed exactly, straight.
	if t < 1.0:
		car.linear_velocity = -car.global_transform.basis.z * target_kmh / 3.6
		car.angular_velocity = Vector3.ZERO
		inp.throttle = 0.3
		log_data.yaw0 = _heading()
		log_data.v0 = car.speed
		return
	var tt := t - 1.0
	match name:
		"step_steer", "step_fast", "slow_turn":
			inp.throttle = 0.5
			inp.steer = 1.0
			var yr := absf(car.angular_velocity.y)
			log_data.yaw_hist = log_data.get("yaw_hist", []) + [yr]
		"gas_tap_drift", "drift_counter", "lift_exit":
			inp.steer = 0.75
			# lift then stab the throttle
			inp.throttle = 1.0 if tt < 0.3 or tt > 0.5 else 0.0
			if name == "drift_counter" and tt > 1.2:
				inp.steer = -0.25
			if name == "lift_exit" and tt > 1.6:
				inp.throttle = 0.0
				inp.steer = 0.0
		"lane_change":
			inp.throttle = 0.6
			inp.steer = 1.0 if tt < 0.5 else (-1.0 if tt < 1.0 else 0.0)
			var side := car.global_position.dot(Vector3(1, 0, 0))
			log_data.max_side = maxf(log_data.get("max_side", 0.0), absf(side))
			if tt > 2.5:
				log_data.settle_yaw = maxf(log_data.get("settle_yaw", 0.0), absf(car.angular_velocity.y))
		"handbrake_turn":
			inp.throttle = 0.3
			inp.steer = 1.0 if tt < 0.9 else 0.0
			inp.handbrake = 1.0 if tt < 0.6 else 0.0
	var beta := absf(car.slip_angle)
	log_data.max_beta = maxf(log_data.max_beta, beta)
	if car.drift_mode:
		log_data.drift_frames += 1
	if beta > 1.4:
		log_data.spun = true
	if tt >= 3.5:
		var turned := rad_to_deg(absf(wrapf(_heading() - log_data.yaw0, -PI, PI)))
		var out := "%-10s %-15s turned=%5.1f deg  speed %3d->%3d km/h  max_beta=%4.2f end_beta=%4.2f drift_t=%4.2fs spun=%s" % [cars[car_idx], name, turned, int(log_data.v0 * 3.6), int(car.speed * 3.6), log_data.max_beta, beta, log_data.drift_frames / HZ, log_data.spun]
		if name == "lane_change":
			out += "  lateral=%.1fm  residual_yaw=%.2f" % [log_data.get("max_side", 0.0), log_data.get("settle_yaw", 0.0)]
		if name in ["step_steer", "step_fast", "slow_turn"]:
			var hist: Array = log_data.yaw_hist
			var steady: float = hist[hist.size() - 1]
			var t90 := 0.0
			for i in hist.size():
				if hist[i] >= steady * 0.9:
					t90 = i / HZ
					break
			out += "  yaw_rate=%.2f rad/s  t90=%.2fs  lat_g=%.2f" % [steady, t90, steady * car.speed / 9.81]
		print(out)
		scenario += 1
		if scenario >= SCENARIOS.size():
			scenario = 0
			car_idx += 1
			if car_idx >= cars.size():
				quit()
				return
		_start()
