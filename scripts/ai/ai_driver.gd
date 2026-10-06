class_name AIDriver
extends RefCounted
## Drives a Car along a RacePath with a curvature-based speed plan.

var car: Car
var path: RacePath
var skill := 0.9
var lane := 0.0
var idx := 0
var lap := 0
var progress := 0.0
var stuck := 0.0
var profile: PackedFloat32Array
var finished := false
var finish_time := INF
var nitro_bias := randf()

func _init(c: Car, p: RacePath, s: float, lane_offset: float) -> void:
	car = c
	path = p
	skill = s
	lane = lane_offset
	refresh_profile()

func refresh_profile() -> void:
	var st := car.stats
	profile = path.speed_profile(float(st.grip) * 0.88 * skill, minf(float(st.brake), float(st.grip)) * 0.72, float(st.top) * 1.1)

func update(dt: float, others: Array, frozen: bool) -> void:
	var pos := car.global_position
	var p2 := Vector2(pos.x, pos.z)
	var prev := idx
	idx = path.nearest(p2, idx, 10, 50)
	if path.closed and prev > path.n * 0.8 and idx < path.n * 0.2:
		lap += 1
	progress = lap * path.length + path.cum[idx]
	var spd := car.speed
	var look := 7.0 + spd * 0.42
	var ti := idx + int(look / RacePath.SPACING)
	var tgt := path.at(ti, true)
	var d := path.dir(ti)
	var off := lane
	var b := car.global_transform.basis
	var fwd := -b.z
	var right := b.x
	for o in others:
		if o == car:
			continue
		var dv: Vector3 = o.global_position - pos
		var ahead := dv.dot(fwd)
		var side := dv.dot(right)
		if ahead > 0.0 and ahead < 14.0 + spd * 0.3 and absf(side) < 2.4 and spd > o.speed - 1.0:
			off += -3.0 if side > 0.0 else 3.0
			break
	var lat := Vector2(-d.y, d.x) # right of path direction
	var target := Vector3(tgt.x + lat.x * off, pos.y, tgt.y + lat.y * off)
	var local := b.inverse() * (target - pos)
	var ang := atan2(local.x, -local.z)
	var steer := clampf(ang * 2.4 - car.angular_velocity.y * 0.08, -1.0, 1.0)
	var vt := INF
	var ahead_n := int(spd * 0.5 / RacePath.SPACING) + 2
	for k in range(0, ahead_n, 2):
		vt = minf(vt, profile[path.idx(idx + k)])
	vt *= 1.0 - minf(absf(ang), 0.6) * 0.5
	var throttle := 0.0
	var brake := 0.0
	var err := vt - car.forward_speed
	if err > 1.5:
		throttle = 1.0
	elif err > -1.0:
		throttle = 0.4 + err * 0.2
	else:
		brake = clampf(-err / 6.0, 0.2, 1.0)
	var nitro := err > 12.0 and absf(ang) < 0.08 and car.nitro > 0.15 and nitro_bias < 0.85
	if car.forward_speed < -0.5 and not frozen:
		# Rolling backwards: drive forward (also cancels reverse gear).
		throttle = 1.0
		brake = 0.0
	if frozen:
		throttle = 0.0
		brake = 0.0
		steer = 0.0
	car.input.handbrake = 1.0 if frozen else 0.0
	if not path.closed and idx >= path.n - 2:
		throttle = 0.0
		brake = 0.6
	car.input.throttle = throttle
	car.input.brake = brake
	car.input.steer = steer
	car.input.nitro = nitro
	# Recover when stuck or lost
	var dist_off := path.at(idx).distance_to(p2)
	var at_finish := not path.closed and idx >= path.n - 5
	if not frozen and not at_finish and (spd < 2.0 or dist_off > 30.0):
		stuck += dt
	else:
		stuck = maxf(0.0, stuck - dt)
	if stuck > 3.0:
		stuck = 0.0
		var q := path.at(idx + 3)
		var dd := path.dir(idx + 3)
		var y := (path.heights[path.idx(idx + 3)] if path.heights.size() > 0 else pos.y) + 0.8
		var t := Transform3D(Basis.looking_at(Vector3(dd.x, 0, dd.y), Vector3.UP), Vector3(q.x, y, q.y))
		car.reset_to(t)
		car.linear_velocity = Vector3(dd.x, 0, dd.y) * 12.0
