shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Night-reactive emissive parts (neon signs, lamp heads, traffic signals).
// INSTANCE_CUSTOM.rgb = colour, .a = mode (0 normal, 0.6 signal lit in first half of cycle, 0.9 second half)
global uniform float night;
uniform float strength = 4.0;
uniform float day_strength = 0.25;
varying vec4 cust;
varying vec3 wpos;

void vertex() {
	cust = INSTANCE_CUSTOM;
	wpos = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec3 c = cust.rgb;
	float on = 1.0;
	if (cust.a > 0.5) {
		// Simple signal cycle offset per intersection.
		float t = mod(TIME + (wpos.x + wpos.z) * 0.05, 30.0);
		on = cust.a < 0.75 ? step(t, 15.0) : step(15.0, t);
	}
	ALBEDO = c * 0.2;
	ROUGHNESS = 0.3;
	EMISSION = c * on * mix(day_strength, strength, night);
}
