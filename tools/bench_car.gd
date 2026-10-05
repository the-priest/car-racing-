extends SceneTree
var car: Car
var n := 0
var t0 := 0
func _initialize() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2000, 2, 2000)
	cs.shape = bs
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	get_root().add_child(ground)
	car = Car.new()
	get_root().add_child(car)
	car.setup(Data.stats_for("vanta_z", {}), Color.RED, false, OS.has_environment("DETAIL"))
	t0 = Time.get_ticks_msec()
	physics_frame.connect(func():
		n += 1
		car.input.throttle = 1.0 if n > 120 else 0.0
		if n % 120 == 0:
			print("tick s=", n / 120, " kmh=", int(car.speed * 3.6), " gear=", car.gear, " rpm=", int(car.rpm), " ground=", car.wheels_on_ground, " comp=", car.wheels.map(func(w): return snappedf(w.comp, 0.01)), " spin=", snappedf(car.wheelspin, 0.01), " pitchz=", snappedf(car.global_transform.basis.z.y, 0.02), " wall_ms=", Time.get_ticks_msec() - t0)
		if n >= 120 * 12:
			quit())
