shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 deep_color : source_color = vec3(0.01, 0.06, 0.09);
uniform vec3 shallow_color : source_color = vec3(0.05, 0.28, 0.30);
uniform bool use_depth = true;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Gentle swell
	float t = TIME * 0.6;
	VERTEX.y += sin(wpos.x * 0.03 + t) * 0.18 + cos(wpos.z * 0.025 + t * 1.3) * 0.22;
}

void fragment() {
	float t = TIME;
	vec2 uv1 = wpos.xz * 0.018 + vec2(t * 0.012, t * 0.008);
	vec2 uv2 = wpos.xz * 0.061 + vec2(-t * 0.02, t * 0.017);
	vec3 n1 = texture(normal_a, uv1).rgb;
	vec3 n2 = texture(normal_b, uv2).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.8;

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = deep_color;
	float alpha = 0.92;
	if (use_depth) {
		float d = texture(depth_tex, SCREEN_UV).r;
		vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
		vec4 vpos = INV_PROJECTION_MATRIX * ndc;
		vpos.xyz /= vpos.w;
		float depth_diff = clamp((-vpos.z) - (-VERTEX.z), 0.0, 60.0);
		float shallow = exp(-depth_diff * 0.18);
		vec2 refr_uv = SCREEN_UV + NORMAL_MAP.xy * 0.02 * (1.0 - shallow);
		vec3 refr = texture(screen_tex, refr_uv).rgb;
		col = mix(deep_color, mix(shallow_color, refr * shallow_color * 2.2, 0.55), shallow);
		// Foam at the shoreline
		float foam = smoothstep(0.75, 1.0, exp(-depth_diff * 1.6)) * (0.6 + 0.4 * sin(t * 1.7 + wpos.x * 0.2));
		col = mix(col, vec3(0.85), foam * 0.7);
		alpha = mix(1.0, 0.97, shallow);
	}
	ALBEDO = col * (1.0 - fres * 0.6);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.65;
	ALPHA = alpha;
}
