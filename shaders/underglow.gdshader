shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Underglow: a soft coloured pool of light on the road beneath the car.
uniform vec4 glow : source_color = vec4(0.2, 0.5, 1.0, 1.0);
global uniform float night;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// Rounded rectangle falloff, brightest under the sills.
	float d = length(max(abs(p) - vec2(0.35, 0.55), 0.0)) / 0.5;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
	ALBEDO = glow.rgb * a * mix(0.6, 1.6, night);
}
