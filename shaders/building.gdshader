shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Procedural facades for instanced buildings.
// INSTANCE_CUSTOM: r = style (0 glass, 1 office, 2 brick), g = palette, b = seed.
uniform sampler2D noise_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Surface texture arrays (raw sample, sRGB decoded in srgb()).
uniform sampler2DArray surf_albedo : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surf_nrh : filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float night;
global uniform float wetness;

varying vec3 wpos;
varying vec3 wnrm;
varying flat vec4 cust;

const float L_CONCRETE = 6.0;
const float L_BRICK = 8.0;
const float L_STUCCO = 9.0;
const float L_LIMESTONE = 10.0;
const float L_METAL_PANEL = 11.0;
const float L_ROOF = 13.0;

vec3 srgb(vec3 c) {
	return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

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
		// Membrane roofs with seams and gravel.
		float g = texture(noise_a, wpos.xz * 0.05).r;
		albedo = srgb(texture(surf_albedo, vec3(wpos.xz / 4.0, L_ROOF)).rgb) * (0.75 + g * 0.5);
		vec3 t = texture(surf_nrh, vec3(wpos.xz / 4.0, L_ROOF)).rgb;
		rough = mix(t.b, 0.2, wetness);
		nmap = vec3(t.rg, 1.0);
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
		vec3 wall_t = vec3(0.5, 0.5, 0.85);
		// Real wall materials from the surface array (image up = world up, so stains run down).
		vec2 wuv = vec2(u, -v);
		float layer;
		vec3 wtint;
		float scale;
		int pi = int(pal * 4.99);
		if (style == 2) {
			layer = L_BRICK; scale = 2.4;
			// red, brown, dark purple-brown, sandy, red again
			wtint = pi == 0 ? vec3(1.0) : (pi == 1 ? vec3(0.8, 0.72, 0.68) : (pi == 2 ? vec3(0.62, 0.5, 0.52) : (pi == 3 ? vec3(1.25, 1.1, 0.85) : vec3(1.05, 0.95, 0.9))));
		} else if (style == 1) {
			// cream render, limestone, concrete, terracotta render, blue-grey metal panels
			if (pi == 0) { layer = L_STUCCO; scale = 3.0; wtint = vec3(0.95, 0.9, 0.78); }
			else if (pi == 1) { layer = L_LIMESTONE; scale = 3.6; wtint = vec3(1.0); }
			else if (pi == 2) { layer = L_CONCRETE; scale = 4.0; wtint = vec3(1.45, 1.42, 1.36); }
			else if (pi == 3) { layer = L_STUCCO; scale = 3.0; wtint = vec3(0.85, 0.52, 0.38); }
			else { layer = L_METAL_PANEL; scale = 3.0; wtint = vec3(0.7, 0.78, 0.86); }
		} else {
			layer = L_METAL_PANEL; scale = 3.0; wtint = vec3(0.32, 0.34, 0.36); // spandrels between glass
		}
		vec2 tuv = wuv / scale + vec2(seed * 0.37, seed * 0.11);
		wall = srgb(texture(surf_albedo, vec3(tuv, layer)).rgb) * wtint;
		wall_t = texture(surf_nrh, vec3(tuv, layer)).rgb;
		wall *= 0.85 + grime * 0.25;
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
		vec3 tint = style == 0 ? mix(vec3(0.05, 0.09, 0.12), vec3(0.09, 0.12, 0.13), pal) : vec3(0.08, 0.09, 0.1);
		// Slight per-pane normal tilt gives imperfect, believable reflections.
		vec3 glass_n = normalize(vec3(0.5 + (pane - 0.5) * 0.025, 0.5 + (h21(id + seed + 3.1) - 0.5) * 0.025, 1.0));

		// Floor ledges: a lighter band with a bevelled top on every storey.
		if (style != 0 && !ground) {
			float ledge = (1.0 - step(0.07, f.y)) * aa;
			wall = mix(wall, wall * 1.18 + 0.02, ledge);
			if (ledge > 0.5) nmap = vec3(0.5, mix(0.5, 0.85, smoothstep(0.03, 0.07, f.y)), 1.0);
		}
		// Glass: unlit rooms show a hint of curtains/furniture behind a reflective pane.
		vec3 inside = mix(vec3(0.04, 0.045, 0.05), vec3(0.14, 0.11, 0.08), h21(id + seed + 7.0) * step(0.5, h21(id + seed + 8.0)));
		vec3 glass = mix(tint, inside, style == 0 ? 0.15 : 0.5);
		// Mullions and transoms split each window; frame colour per building.
		float mull = 0.0;
		if (!ground && style != 2) {
			float fx = style == 0 ? fract(f.x * 2.0) : f.x;
			mull = max(1.0 - smoothstep(0.0, 0.025 * (style == 0 ? 2.0 : 1.0), abs(fx - 0.5)), 1.0 - smoothstep(0.0, 0.03, abs(f.y - 0.72)));
		}
		vec3 frame = h21(vec2(seed, 2.0)) > 0.5 ? vec3(0.06, 0.06, 0.065) : vec3(0.55, 0.55, 0.53);
		glass = mix(glass, frame, mull * aa);
		albedo = mix(wall, glass, win);
		if (nmap.x == 0.5 && nmap.y == 0.5) nmap = vec3(wall_t.rg, 1.0);
		rough = mix(mix(wall_t.b, 0.35, wetness), mix(0.03 + pane * 0.05, 0.5, mull), win);
		metal = mix(style == 0 ? 0.3 : 0.0, mix(0.9, 0.3, mull), win);
		nmap = mix(nmap, glass_n, win * (1.0 - mull));
		// Shop fronts: a coloured fascia sign over the ground floor windows.
		if (ground && style != 0) {
			float fascia = step(0.86, f.y) * step(0.1, f.x) * step(f.x, 0.9);
			vec3 sc = vec3(h21(vec2(id.x, seed)), h21(vec2(id.x + 3.0, seed)), h21(vec2(id.x + 7.0, seed)));
			sc = normalize(sc + 0.05) * 0.6;
			albedo = mix(albedo, sc, fascia);
			nmap = mix(nmap, vec3(0.5, 0.5, 1.0), fascia);
			metal = mix(metal, 0.0, fascia);
			emis += sc * fascia * night * 1.1;
		}

		// Interior lights at night: random rooms, warm/cool, with ceiling falloff.
		float lit_chance = ground ? 0.8 : mix(0.18, 0.42, h21(vec2(id.y, seed)));
		float lit = step(1.0 - lit_chance, h21(id * 1.37 + seed + 11.0)) * win;
		vec3 room = mix(vec3(1.0, 0.62, 0.3), vec3(0.62, 0.78, 1.0), step(0.8, h21(id + seed + 5.0))) * (0.5 + 0.5 * h21(id + seed + 2.0));
		if (ground) room = mix(vec3(1.0, 0.8, 0.55), vec3(0.6, 0.9, 1.0), step(0.5, h21(vec2(id.x, seed))));
		float falloff = 0.55 + 0.45 * smoothstep(0.2, 0.95, f.y);
		// Half-drawn blinds in some rooms (soft, not stripes) and furniture silhouettes low down.
		float blinds = (style == 1 && h21(id + seed + 9.0) > 0.7) ? mix(0.35, 1.0, smoothstep(0.55, 0.6, 1.0 - f.y)) : 1.0;
		blinds *= mix(0.55, 1.0, clamp(smoothstep(0.3, 0.45, f.y) + step(0.5, h21(id + seed + 4.0)) * 0.5, 0.0, 1.0));
		emis += room * lit * falloff * blinds * night * (ground ? 0.45 : 0.3) * (0.55 + pane * 0.6) * (1.0 - mull);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5;
	NORMAL_MAP = nmap;
	EMISSION = emis;
}
