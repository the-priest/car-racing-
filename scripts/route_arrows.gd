class_name RouteArrows
extends MultiMeshInstance3D
## Glowing chevrons on the road along the GPS route for the next ~180 m, so you can
## follow the route without staring at the minimap. Rebuilt on every GPS tick.

const SPACING := 11.0
const AHEAD := 180.0
const COUNT := 18
const LANE := 2.6

var game: Node

func setup(g: Node) -> void:
	game = g
	var quad := QuadMesh.new()
	quad.size = Vector2(3.2, 4.2) # long along the road so it reads at a glance from the chase camera
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
global uniform float night;
varying float fade;
void vertex() {
	fade = INSTANCE_CUSTOM.a;
}
void fragment() {
	// The quad's local -Z is the route direction, which is UV.y = 0 on a FACE_Y quad;
	// flip so the chevron's tip (largest p.y) points that way.
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float v = abs(p.x) * 0.9 + p.y;
	float shape = smoothstep(0.1, 0.0, abs(v - 0.1) - 0.32) * step(abs(p.x), 0.95) * step(p.y, 0.95);
	float a = shape * fade * mix(0.8, 1.0, night);
	ALBEDO = vec3(1.0, 0.68, 0.15) * a * 4.0;
	ALPHA = a;
}
"""
	mat.shader = sh
	quad.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = COUNT
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Lays chevrons along `path` (route leg start, road nodes, destination). They sit at
## fixed spots on each road segment, so they stay put on the road as you drive; ones
## behind or right under the car are skipped.
func update_route(path: PackedVector2Array, enabled: bool, car_pos := Vector2.ZERO, car_fwd := Vector2.ZERO) -> void:
	if not enabled or path.size() < 2:
		multimesh.visible_instance_count = 0
		return
	var world: World = game.world
	var n := 0
	var walked := 0.0
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.5:
			continue
		var dir := (b - a) / seg
		var off := SPACING * 0.5
		while off < seg - SPACING * 0.3 and n < COUNT:
			# In your lane (right of the centre line), not on it.
			var p := a + dir * off + Vector2(-dir.y, dir.x) * LANE
			off += SPACING
			var to := p - car_pos
			var d := to.length()
			if d < 7.0 or to.dot(car_fwd) < 0.0 or d > AHEAD:
				continue
			var y: float = world.drive_y(p.x, p.y) + 0.12
			var basis := Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP)
			multimesh.set_instance_transform(n, Transform3D(basis, Vector3(p.x, y, p.y)))
			# Fade in near the car and out toward the end of the run.
			var f := clampf((d - 7.0) / 6.0, 0.0, 1.0) * clampf((AHEAD - d) / 50.0, 0.0, 1.0)
			multimesh.set_instance_custom_data(n, Color(0, 0, 0, f))
			n += 1
		walked += seg
		if n >= COUNT or walked > AHEAD * 1.5:
			break
	multimesh.visible_instance_count = n
