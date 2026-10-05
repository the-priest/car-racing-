shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Heightmap-displaced terrain with procedural, slope/height driven materials.
uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D maskmap : filter_linear, repeat_disable; // R: road shoulder, G: urban
uniform float half_size = 3072.0;
uniform float tex_size = 769.0;
uniform sampler2D noise_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float water_level = 0.0;

global uniform float wetness;

varying vec3 wpos;

vec2 hm_uv(vec2 xz) {
	return (xz + half_size) / (2.0 * half_size) * ((tex_size - 1.0) / tex_size) + 0.5 / tex_size;
}
float height_at(vec2 xz) {
	vec2 g = clamp((xz + half_size) / (2.0 * half_size) * (tex_size - 1.0), vec2(0.0), vec2(tex_size - 1.001));
	ivec2 i = ivec2(floor(g));
	vec2 f = g - vec2(i);
	float a = texelFetch(heightmap, i, 0).r;
	float b = texelFetch(heightmap, i + ivec2(1, 0), 0).r;
	float c = texelFetch(heightmap, i + ivec2(0, 1), 0).r;
	float d = texelFetch(heightmap, i + ivec2(1, 1), 0).r;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = height_at(w.xz);
	// COLOR.a marks skirt vertices that hide cracks between LOD levels.
	VERTEX.y = h - COLOR.a * 8.0;
	wpos = vec3(w.x, VERTEX.y, w.z);
	float e = 8.0;
	vec3 n = normalize(vec3(height_at(w.xz - vec2(e, 0.0)) - height_at(w.xz + vec2(e, 0.0)), 2.0 * e,
		height_at(w.xz - vec2(0.0, e)) - height_at(w.xz + vec2(0.0, e))));
	NORMAL = n;
}

vec3 tri_sample(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy * s).rgb * w.x + texture(t, p.xz * s).rgb * w.y + texture(t, p.xy * s).rgb * w.z;
}

void fragment() {
	// Per-pixel normal from the heightmap for smooth large-scale lighting.
	float e = 4.0;
	vec3 n = normalize(vec3(height_at(wpos.xz - vec2(e, 0.0)) - height_at(wpos.xz + vec2(e, 0.0)), 2.0 * e,
		height_at(wpos.xz - vec2(0.0, e)) - height_at(wpos.xz + vec2(0.0, e))));
	float slope = 1.0 - n.y;
	vec4 mk = texture(maskmap, hm_uv(wpos.xz));
	float dist = length(wpos - CAMERA_POSITION_WORLD);

	// Multi-scale noise breaks up tiling.
	float macro = texture(noise_a, wpos.xz * 0.0011).r;
	float mid = texture(noise_b, wpos.xz * 0.013).r;
	float fine = texture(noise_a, wpos.xz * 0.21).r;
	float micro = texture(noise_b, wpos.xz * 1.3).r;

	vec3 grass_dry = vec3(0.17, 0.17, 0.06);
	vec3 grass_lush = vec3(0.045, 0.11, 0.02);
	vec3 grass = mix(grass_lush, grass_dry, smoothstep(0.55, 0.95, macro * 0.7 + mid * 0.5));
	grass *= 0.7 + fine * 0.4 + micro * 0.2;
	vec3 dirt = vec3(0.13, 0.10, 0.07) * (0.7 + fine * 0.5);
	float rn = tri_sample(noise_b, wpos, n, 0.06).r;
	vec3 rock = mix(vec3(0.13, 0.12, 0.11), vec3(0.3, 0.28, 0.26), rn) * (0.8 + tri_sample(noise_a, wpos, n, 0.35).r * 0.35);
	vec3 sand = vec3(0.45, 0.39, 0.27) * (0.85 + fine * 0.25);
	vec3 snow = vec3(0.86, 0.89, 0.93) * (0.92 + micro * 0.08);
	vec3 gravel = vec3(0.17, 0.16, 0.14) * (0.7 + micro * 0.5 + fine * 0.2);
	vec3 concrete = vec3(0.30, 0.30, 0.31) * (0.85 + fine * 0.2);

	vec3 col = grass;
	col = mix(col, dirt, smoothstep(0.7, 0.95, mid * 0.6 + macro * 0.5) * 0.5);
	float rockw = smoothstep(0.22, 0.42, slope + (rn - 0.5) * 0.15);
	col = mix(col, rock, rockw);
	float snoww = smoothstep(300.0, 360.0, wpos.y + macro * 60.0) * (1.0 - smoothstep(0.35, 0.6, slope));
	col = mix(col, snow, snoww);
	float sandw = (1.0 - smoothstep(water_level + 1.0, water_level + 6.0 + mid * 3.0, wpos.y)) * smoothstep(1650.0, 1850.0, wpos.z);
	col = mix(col, sand, sandw);
	col = mix(col, gravel, smoothstep(0.65, 0.95, mk.r + (micro - 0.5) * 0.2));
	col = mix(col, concrete, mk.g);

	// Wet sand near the waterline darkens.
	col *= 1.0 - 0.35 * (1.0 - smoothstep(water_level, water_level + 1.2, wpos.y)) * smoothstep(1650.0, 1850.0, wpos.z);

	ALBEDO = col;
	float rough = mix(0.92, 0.75, rockw) ;
	rough = mix(rough, 0.55, snoww);
	rough = mix(rough, 0.35, wetness * (1.0 - rockw) * 0.6);
	ROUGHNESS = rough;
	SPECULAR = 0.35;

	vec3 vn = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	NORMAL = normalize(vn);
	vec3 nm = texture(noise_n, wpos.xz * mix(0.25, 0.06, rockw)).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nm, (1.0 - smoothstep(60.0, 250.0, dist)) * 0.9);
	NORMAL_MAP_DEPTH = 1.2;
}
