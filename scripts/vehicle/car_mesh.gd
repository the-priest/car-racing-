class_name CarMesh
extends RefCounted
## Builds merged, low-draw-call versions of the car model for traffic and rivals.

const CAR_SCENE := preload("res://assets/cars/CarConcept.glb")

static var _body: ArrayMesh
static var _wheel: ArrayMesh
static var paint_surfaces: Array[int] = []
static var light_surfaces := {}

## Exterior body as one mesh, grouped by material (wheels excluded).
static func body() -> ArrayMesh:
	if _body:
		return _body
	_build()
	return _body

static func wheel() -> ArrayMesh:
	if _wheel:
		return _wheel
	_build()
	return _wheel

static func _build() -> void:
	var root: Node3D = CAR_SCENE.instantiate()
	# Same orientation as Car: model faces -Z.
	var flip := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var groups := {}
	var wheel_groups := {}
	var wheel_node: Node3D = root.find_child("WheelFrontL", true, false)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(m.name)
		if nm.begins_with("Interior") or nm == "Engine" or nm.contains("Pedal") or nm.contains("Steering") or nm == "Axles":
			continue
		var in_wheel := false
		var p: Node = m.get_parent()
		while p:
			if String(p.name).begins_with("Wheel"):
				in_wheel = true
				break
			p = p.get_parent()
		var xf := _local_xform(m, root)
		if in_wheel:
			if not _is_child_of(m, wheel_node):
				continue
			# Wheel mesh relative to its own wheel node (axle along X, centred).
			xf = _local_xform(m, wheel_node)
		else:
			xf = flip * xf
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			var key: String = mat.resource_name if mat else "none"
			var target := wheel_groups if in_wheel else groups
			if not target.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				target[key] = {"st": st, "mat": mat}
			(target[key].st as SurfaceTool).append_from(m.mesh, i, xf)
	_body = _commit(groups, true)
	_wheel = _commit(wheel_groups, false)
	root.free()

static func _commit(groups: Dictionary, track: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var idx := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var st: SurfaceTool = g.st
		st.commit(mesh)
		mesh.surface_set_material(idx, g.mat)
		if track:
			if String(key).begins_with("Paint"):
				paint_surfaces.append(idx)
			if key == "Headlight" or key == "Brakelight":
				light_surfaces[key] = idx
		idx += 1
	return mesh

static func _is_child_of(n: Node, parent: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p == parent:
			return true
		p = p.get_parent()
	return false

static func _local_xform(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur and cur != root:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

## Instance a merged car visual (body + 4 wheels). Returns the root Node3D.
static func instance(paint: StandardMaterial3D, lights: StandardMaterial3D = null) -> Node3D:
	var root := Node3D.new()
	var b := MeshInstance3D.new()
	b.mesh = body()
	for s in paint_surfaces:
		b.set_surface_override_material(s, paint)
	if lights and light_surfaces.has("Headlight"):
		b.set_surface_override_material(light_surfaces.Headlight, lights)
	root.add_child(b)
	var wm := wheel()
	for pos in [Vector3(-0.98, 0.38, -1.485), Vector3(0.98, 0.38, -1.485), Vector3(-0.98, 0.38, 1.314), Vector3(0.98, 0.38, 1.314)]:
		var w := MeshInstance3D.new()
		w.mesh = wm
		w.position = pos
		# The source wheel is the left one; mirror it for the right side.
		if pos.x > 0.0:
			w.scale = Vector3(-1, 1, 1)
		root.add_child(w)
	return root
