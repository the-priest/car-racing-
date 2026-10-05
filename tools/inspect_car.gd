extends SceneTree
func _initialize():
	var scn: PackedScene = load("res://assets/cars/CarConcept.glb")
	var root: Node3D = scn.instantiate()
	get_root().add_child(root)
	print("root xform ", root.transform)
	_walk(root, 0)
	var mats := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = mi.mesh
		for i in m.get_surface_count():
			var mat = mi.get_active_material(i)
			if mat: mats[mat.resource_name] = mat.get_class()
	print("materials ", mats)
	quit()
func _walk(n: Node, d: int):
	if n is Node3D and (n.name.begins_with("Wheel") or n.name.contains("light") or n.name == "BodyUnderside" or d < 2):
		var aabb := ""
		if n is MeshInstance3D: aabb = str(n.get_aabb())
		print("  ".repeat(d), n.name, " ", n.get_class(), " gpos=", (n as Node3D).global_position.snapped(Vector3.ONE*0.01), " ", aabb)
	for c in n.get_children(): _walk(c, d + 1)
