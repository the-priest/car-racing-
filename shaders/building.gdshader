shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural facades for instanced buildings.
// INSTANCE_CUSTOM: r = style (0 glass, 1 office, 2 brick), g = palette, b = seed.
uniform sampler2D noise_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float night;
global uniform float wetness;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 cust;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cust = INSTANCE_CUSTOM;
}

void fragment() {
	int style = int(cust.r * 3.0 + 0.5);
	float pal = cust.g;
	float seed = cust.b * 97.0;
	bool roof = wnrm.y > 0.5;
	float u = abs(wnrm.x) > 0.5 ? wpos.z * sign(wnrm.x) : -wpos.x * sign(wnrm.z);
	float v = wpos.y;

	vec3 albedo; float rough = 0.85; float metal = 0.0; vec3 emis = vec3(0.0);
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	if (roof) {
		float g = texture(noise_a, wpos.xz * 0.4).r;
		albedo = vec3(0.16, 0.16, 0.17) * (0.7 + g * 0.5);
		rough = mix(0.9, 0.2, wetness);
		nmap = texture(noise_n, wpos.xz * 0.5).rgb;
	} else {
		float floor_h = style == 2 ? 3.4 : 3.8;
		float col_w = style == 0 ? 1.55 : (style == 1 ? 2.7 : 3.1);
		vec2 cell = vec2(u / col_w, v / floor_h);
		vec2 f = fract(cell);
		vec2 id = floor(cell);
		float grime = texture(noise_b, vec2(u * 0.04, v * 0.006) + seed).r;
		float streak = texture(noise_a, vec2(u * 0.5, v * 0.02) + seed).r;

		// Wall material
		vec3 wall;
		if (style == 2) {
			// Brick courses with mortar
			vec2 b = vec2(u / 0.25 + step(1.0, mod(floor(v / 0.075), 2.0)) * 0.5, v / 0.075);
			vec2 bf = fract(b);
			float mortar = step(0.9, bf.x) + step(0.82, bf.y);
			vec3 brick = mix(vec3(0.33, 0.13, 0.08), vec3(0.47, 0.23, 0.15), h21(floor(b) + seed)) * mix(0.8, 1.0, pal);
			wall = mix(brick, vec3(0.42, 0.40, 0.36), clamp(mortar, 0.0, 1.0));
		} else if (style == 1) {
			wall = mix(vec3(0.46, 0.45, 0.42), vec3(0.62, 0.6, 0.55), pal) * (0.82 + grime * 0.3);
		} else {
			wall = vec3(0.16, 0.17, 0.18) * (0.9 + grime * 0.2);
		}
		wall *= 1.0 - smoothstep(0.55, 0.9, streak) * 0.15;
		// Darken near the ground (dirt, AO)
		wall *= 0.75 + 0.25 * smoothstep(0.0, 2.5, v);

		// Window layout
		float win;
		bool ground = id.y < 0.5;
		if (ground) {
			win = step(0.06, f.x) * step(f.x, 0.94) * step(0.08, f.y) * step(f.y, 0.86);
		} else if (style == 0) {
			win = step(0.035, f.x) * step(f.x, 0.965) * step(0.2, f.y) * step(f.y, 0.97);
		} else if (style == 1) {
			win = step(0.14, f.x) * step(f.x, 0.86) * step(0.28, f.y) * step(f.y, 0.86);
		} else {
			win = step(0.3, f.x) * step(f.x, 0.7) * step(0.22, f.y) * step(f.y, 0.78);
		}
		// Window recess bevel via fake normal
		float ex = min(f.x - (style == 1 ? 0.14 : 0.3), (style == 1 ? 0.86 : 0.7) - f.x);
		float ey = min(f.y - 0.25, 0.85 - f.y);
		if (style != 0 && !ground) {
			float bev = (1.0 - smoothstep(0.0, 0.04, abs(ex))) * step(0.25, f.y) * step(f.y, 0.85);
			nmap = vec3(0.5 + sign(ex) * bev * 0.3, 0.5, 1.0);
		}

		// Fade the window pattern to its average coverage where cells get smaller than a pixel.
		float aa = clamp(1.6 - max(fwidth(cell.x), fwidth(cell.y)) * 3.0, 0.0, 1.0);
		win = mix(style == 0 ? 0.75 : 0.3, win, aa);
		float pane = h21(id + seed);
		vec3 tint = style == 0 ? mix(vec3(0.05, 0.09, 0.12), vec3(0.09, 0.12, 0.13), pal) : vec3(0.05, 0.06, 0.07);
		// Slight per-pane normal tilt gives imperfect, believable reflections.
		vec3 glass_n = normalize(vec3(0.5 + (pane - 0.5) * 0.025, 0.5 + (h21(id + seed + 3.1) - 0.5) * 0.025, 1.0));

		albedo = mix(wall, tint, win);
		rough = mix(mix(0.85, 0.35, wetness), 0.04 + pane * 0.05, win);
		metal = mix(style == 0 ? 0.3 : 0.0, style == 0 ? 0.85 : 0.5, win);
		nmap = mix(nmap, glass_n, win);

		// Interior lights at night: random rooms, warm/cool, with ceiling falloff.
		float lit_chance = ground ? 0.8 : mix(0.18, 0.42, h21(vec2(id.y, seed)));
		float lit = step(1.0 - lit_chance, h21(id * 1.37 + seed + 11.0)) * win;
		vec3 room = mix(vec3(1.0, 0.62, 0.3), vec3(0.62, 0.78, 1.0), step(0.8, h21(id + seed + 5.0))) * (0.5 + 0.5 * h21(id + seed + 2.0));
		if (ground) room = mix(vec3(1.0, 0.8, 0.55), vec3(0.6, 0.9, 1.0), step(0.5, h21(vec2(id.x, seed))));
		float falloff = 0.55 + 0.45 * smoothstep(0.2, 0.95, f.y);
		float blinds = (style == 1 && h21(id + seed + 9.0) > 0.7) ? (0.6 + 0.4 * step(0.5, fract(f.y * 14.0))) : 1.0;
		emis = room * lit * falloff * blinds * night * (ground ? 1.4 : 0.75) * (0.6 + pane * 0.6);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	NORMAL_MAP = nmap;
	EMISSION = emis;
}
