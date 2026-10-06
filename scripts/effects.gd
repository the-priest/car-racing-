class_name Effects
extends Node3D
## Tyre smoke, dirt spray, skid marks and rain.

const MAX_SKIDS := 2400

var skid_mm: MultiMesh
var skid_next := 0
var last_mark := {}
var cars: Array = []
var smoke_tex: Texture2D
var rain: GPUParticles3D
var quality := 1.0
var wet := 0.0

func setup(q: Dictionary) -> void:
	quality = 1.0 if q.renderer == "forward_plus" else 0.5
	smoke_tex = _smoke_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.02, 0.02, 0.02, 0.62)
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 1
	quad.material = mat
	skid_mm = MultiMesh.new()
	skid_mm.transform_format = MultiMesh.TRANSFORM_3D
	skid_mm.mesh = quad
	skid_mm.instance_count = MAX_SKIDS
	skid_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = skid_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-4000, -100, -4000), Vector3(8000, 900, 8000))
	add_child(mmi)
	_build_rain()

func _smoke_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.12
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length() / (s / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (0.65 + 0.35 * (n.get_noise_2d(x, y) * 0.5 + 0.5))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _emitter(color: Color, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(8, int(amount * quality))
	p.lifetime = 2.6
	p.emitting = false
	p.local_coords = false
	p.fixed_fps = 30
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 25, 60))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, 0.35, 0)
	pm.damping_min = 1.2
	pm.damping_max = 2.0
	pm.scale_min = 0.9
	pm.scale_max = 1.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 4.5))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.55))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.4)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = smoke_tex
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	q.material = m
	p.draw_pass_1 = q
	return p

func attach(car: Car) -> void:
	var entry := {"car": car, "smoke": [], "dust": []}
	for i in [2, 3]:
		var s := _emitter(Color(0.92, 0.92, 0.94), 70)
		add_child(s)
		var d := _emitter(Color(0.45, 0.36, 0.25), 50)
		add_child(d)
		entry.smoke.append(s)
		entry.dust.append(d)
	cars.append(entry)

func detach(car: Car) -> void:
	for e in cars.duplicate():
		if e.car == car:
			for p in e.smoke + e.dust:
				p.queue_free()
			cars.erase(e)

func clear_skids() -> void:
	skid_mm.visible_instance_count = 0
	skid_next = 0
	last_mark.clear()

static var prof_us := 0

func _process(_delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_tick()
	prof_us += Time.get_ticks_usec() - _t0

func _tick() -> void:
	for e in cars:
		var car: Car = e.car
		if not is_instance_valid(car):
			continue
		for k in 2:
			var w: Dictionary = car.wheels[2 + k]
			var skid: float = w.skid if w.contact else 0.0
			var road: bool = w.surface != "terrain"
			var sm: GPUParticles3D = e.smoke[k]
			var du: GPUParticles3D = e.dust[k]
			sm.global_position = (w.hit_pos as Vector3) + Vector3(0, 0.25, 0)
			du.global_position = sm.global_position
			# Tyre smoke when sliding; a fine spray off wet roads at speed.
			var spray: bool = wet > 0.35 and car.speed > 14.0 and w.contact
			sm.emitting = road and (skid > 0.3 or spray)
			sm.amount_ratio = clampf(maxf(skid, wet * clampf(car.speed / 60.0, 0.0, 0.6)), 0.15, 1.0)
			du.emitting = w.contact and not road and car.speed > 6.0
			du.amount_ratio = clampf(car.speed / 30.0, 0.2, 1.0)
		# Skid marks on all four wheels when sliding on hard surfaces.
		for i in 4:
			var w2: Dictionary = car.wheels[i]
			var key := str(car.get_instance_id()) + str(i)
			var on: bool = w2.contact and float(w2.skid) > 0.35 and w2.surface != "terrain"
			if not on:
				last_mark.erase(key)
				continue
			var p: Vector3 = (w2.hit_pos as Vector3) + Vector3(0, 0.03, 0)
			if last_mark.has(key):
				var prev: Vector3 = last_mark[key]
				var dv := p - prev
				var l := dv.length()
				if l < 0.5:
					continue
				if l < 6.0:
					var mid := (p + prev) * 0.5
					var fwd := dv.normalized()
					var side := fwd.cross(Vector3.UP).normalized()
					var b := Basis(side * 0.28, Vector3.UP, fwd * (l + 0.05))
					skid_mm.set_instance_transform(skid_next, Transform3D(b, mid))
					skid_next = (skid_next + 1) % MAX_SKIDS
					skid_mm.visible_instance_count = maxi(skid_mm.visible_instance_count, skid_next if skid_next > 0 else MAX_SKIDS)
			last_mark[key] = p

func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = int(6000 * quality)
	rain.lifetime = 1.2
	rain.emitting = false
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(35, 1, 35)
	pm.direction = Vector3(0.1, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.7)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = m
	rain.draw_pass_1 = q
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)

func update_rain(amount: float, cam_pos: Vector3, cam_vel: Vector3) -> void:
	wet = amount
	rain.emitting = amount > 0.05
	rain.amount_ratio = clampf(amount, 0.05, 1.0)
	rain.global_position = cam_pos + Vector3(0, 18, 0) + cam_vel * 0.6
