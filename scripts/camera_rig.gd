class_name CameraRig
extends Camera3D
## Chase / far chase / bumper / cockpit cameras with drift-follow, speed FOV and shake.

enum Mode { CHASE, FAR, BUMPER, COCKPIT }
const MODE_NAMES := ["Chase", "Far Chase", "Bumper", "Cockpit"]

var target: Car
var world: World
var mode := Mode.CHASE
var base_fov := 72.0
var snap := true
var shake := 0.0
var look_back := false
var orbit := 0.0
var _yaw := 0.0
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _fov := 72.0
var _pitch := 0.0
var _boom := 1.0 # 0..1 fraction of chase distance allowed by buildings
var _rng := RandomNumberGenerator.new()

func cycle() -> void:
	mode = ((mode + 1) % 4) as Mode
	snap = true

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var xf := target.get_global_transform_interpolated()
	var b := xf.basis.orthonormalized()
	var fwd := -b.z
	var vel := target.linear_velocity
	var spd := vel.length()
	var car_yaw := atan2(-fwd.x, -fwd.z)
	var vel_yaw := atan2(-vel.x, -vel.z) if spd > 4.0 else car_yaw
	var reversing := target.forward_speed < -1.0
	# In slides the chase camera swings toward the direction of travel.
	var blend := clampf(spd / 25.0, 0.0, 1.0) * (0.0 if reversing else 0.3)
	var target_yaw := car_yaw + wrapf(vel_yaw - car_yaw, -PI, PI) * blend
	if snap:
		_yaw = target_yaw
	_yaw += wrapf(target_yaw - _yaw, -PI, PI) * (1.0 - exp(-(30.0 if mode >= Mode.BUMPER else 5.0) * delta))
	var look_in := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	orbit = lerpf(orbit, look_in * 2.6, 1.0 - exp(-6.0 * delta))
	var yaw := _yaw + orbit + (PI if look_back else 0.0)
	# Follow the car's pitch on hills (smoothed, partial) so the camera doesn't dig into slopes.
	var tp := asin(clampf(fwd.y, -0.6, 0.6)) * 0.75 if not look_back else -asin(clampf(fwd.y, -0.6, 0.6)) * 0.75
	if snap:
		_pitch = tp
	_pitch = lerpf(_pitch, tp, 1.0 - exp(-4.0 * delta))
	var dir := Vector3(-sin(yaw) * cos(_pitch), sin(_pitch), -cos(yaw) * cos(_pitch))
	var sp := clampf(spd / 80.0, 0.0, 1.0)
	var desired: Vector3
	var look_at_pt: Vector3
	var origin := xf.origin
	match mode:
		Mode.CHASE, Mode.FAR:
			var far := mode == Mode.FAR
			var dist := (8.6 if far else 6.2) + sp * (2.2 if far else 1.4)
			var height := (3.2 if far else 2.05) - sp * 0.25
			var from := origin + Vector3.UP * 1.3
			var full := origin - dir * dist + Vector3.UP * height
			look_at_pt = origin + dir * 4.0 + Vector3.UP * 1.1
			# Only buildings pull the camera in (not road edges, kerbs or terrain bumps).
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(from, full, 4)
			q.exclude = [target.get_rid()]
			var hit := space.intersect_ray(q)
			var want := 1.0
			if not hit.is_empty():
				want = clampf((from.distance_to(hit.position) - 0.5) / maxf(from.distance_to(full), 0.1), 0.15, 1.0)
			if snap:
				_boom = want
			# Pull in fast, ease back out slowly: no popping.
			_boom = lerpf(_boom, want, 1.0 - exp(-(25.0 if want < _boom else 2.5) * delta))
			desired = from.lerp(full, _boom)
			if world:
				desired.y = maxf(desired.y, world.ground(desired.x, desired.z) + 1.0)
		Mode.BUMPER:
			var o := Vector3(0, 0.62, -2.35)
			desired = xf * o
			look_at_pt = xf * (o + Vector3(0, -0.1, -30.0))
			if look_back:
				desired = xf * Vector3(0, 0.9, 2.6)
				look_at_pt = xf * Vector3(0, 0.6, 30.0)
		Mode.COCKPIT:
			var o2 := Vector3(-0.37, 1.0, 0.02)
			desired = xf * o2
			look_at_pt = xf * (o2 + Vector3(sin(orbit) * -10.0, -0.15, -10.0 * cos(orbit)))
			if look_back:
				look_at_pt = xf * (o2 + Vector3(0, 0, 10.0))
	if snap or mode >= Mode.BUMPER:
		_pos = desired
		_look = look_at_pt
		snap = false
	else:
		_pos = _pos.lerp(desired, 1.0 - exp(-12.0 * delta))
		_look = _look.lerp(look_at_pt, 1.0 - exp(-20.0 * delta))
	global_position = _pos
	shake = maxf(0.0, shake - delta * 2.5)
	var s := (shake * 0.3 + pow(sp, 3.0) * 0.03 + (0.025 if target.nitro_on else 0.0)) * float(Settings.data.cam_shake)
	if target.surface == "terrain" and spd > 8.0:
		s += 0.02
	if s > 0.001:
		global_position += Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s), _rng.randf_range(-s, s))
	var up_vec := Vector3.UP
	if mode >= Mode.BUMPER:
		up_vec = b.y
	if not global_position.is_equal_approx(_look):
		look_at(_look, up_vec)
	var tf := base_fov + sp * 16.0 + (9.0 if target.nitro_on else 0.0) + (4.0 if mode == Mode.COCKPIT else 0.0)
	_fov = lerpf(_fov, tf, 1.0 - exp(-3.0 * delta))
	fov = _fov
	RenderingServer.global_shader_parameter_set("cam_pos", global_position)
