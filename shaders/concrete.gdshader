shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Sidewalk slabs / plazas with joints, stains and wet sheen.
uniform sampler2D noise_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base : source_color = vec3(0.42, 0.41, 0.39);
uniform float tile = 1.5;
global uniform float wetness;
varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec2 p = abs(wn.y) > 0.5 ? wpos.xz : vec2(wpos.x + wpos.z, wpos.y);
	vec2 f = fract(p / tile);
	float fw = fwidth(p.x / tile) + 0.01;
	float joint = 1.0 - smoothstep(0.0, fw * 2.0, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	float n = texture(noise_a, wpos.xz * 0.3).r, m = texture(noise_b, wpos.xz * 0.05).r;
	vec3 col = base * (0.8 + n * 0.3) * (0.85 + m * 0.25);
	col *= 1.0 - joint * 0.45;
	col *= 1.0 - smoothstep(0.6, 0.75, m) * 0.25;
	ALBEDO = col * mix(1.0, 0.65, wetness);
	ROUGHNESS = mix(0.8, 0.2, wetness * (1.0 - joint));
	NORMAL_MAP = texture(noise_n, wpos.xz * 0.8).rgb;
	NORMAL_MAP_DEPTH = 0.4;
}
