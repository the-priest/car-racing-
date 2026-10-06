shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Asphalt with analytic lane markings. UV.x = metres across from left edge,
// UV.y = metres along the road.
uniform float road_width = 20.0;
uniform int lanes_per_side = 2;
uniform int style = 0; // 0 city/highway (double yellow), 1 two-lane (dashed yellow), 2 runway, 3 intersection
uniform sampler2D noise_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 asphalt_tint : source_color = vec3(0.075, 0.075, 0.08);
// Stored sRGB but sampled raw and decoded with srgb() below: texture arrays are not
// sRGB-decoded on every renderer, this way all of them agree.
uniform sampler2DArray surf_albedo : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surf_nrh : filter_linear_mipmap_anisotropic, repeat_enable;

global uniform float wetness;

varying vec3 wpos;

vec3 srgb(vec3 c) {
	return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float band(float x, float c, float w, float fw) {
	return 1.0 - smoothstep(w * 0.5 - fw, w * 0.5 + fw, abs(x - c));
}

void fragment() {
	float x = UV.x, y = UV.y, W = road_width;
	float fw = max(fwidth(x), 0.004) * 0.75;
	float n1 = texture(noise_a, wpos.xz * 0.35).r;
	float n2 = texture(noise_b, wpos.xz * 0.045).r;
	float n3 = texture(noise_a, wpos.xz * 2.7).r;
	// Real asphalt texture in road space (runs along the road), two scales mixed.
	vec2 ruv = vec2(x, y) / 2.6;
	vec2 ruv2 = vec2(y, -x) / 6.1 + 0.41;
	float mixer = smoothstep(0.3, 0.7, texture(noise_b, wpos.xz * 0.02).r);
	vec3 tex = mix(srgb(texture(surf_albedo, vec3(ruv, 0.0)).rgb), srgb(texture(surf_albedo, vec3(ruv2, 0.0)).rgb), mixer);
	vec3 trh1 = texture(surf_nrh, vec3(ruv, 0.0)).rgb;
	vec3 trh = mix(trh1, texture(surf_nrh, vec3(ruv2, 0.0)).rgb, mixer);
	// The texture is authored around a 0.07 grey; per-road tints shift it.
	vec3 col = tex * (asphalt_tint / 0.075) * (0.85 + n2 * 0.3);
	// Broken, gravelly outer edge instead of a razor-sharp asphalt border.
	if (style < 2 && max(abs(wpos.x), abs(wpos.z)) > 640.0) { // countryside only; city roads have kerbs
		float e = min(x, W - x);
		float crumble = 1.0 - smoothstep(0.08, 0.32 + n1 * 0.18, e + (n3 - 0.5) * 0.12);
		vec3 grav = srgb(texture(surf_albedo, vec3(vec2(x, y) / 2.5, 5.0)).rgb) * 0.8;
		col = mix(col, grav, crumble);
	}
	// Patches and tar seams
	float patch = smoothstep(0.62, 0.66, texture(noise_b, wpos.xz * 0.012 + 7.0).r);
	col = mix(col, col * 0.7, patch * 0.6);
	float seam = band(fract(y / 37.0) * 37.0, 18.0, 0.08, fw) * 0.5;
	col *= 1.0 - seam * 0.5;

	float lane_w = W / float(lanes_per_side * 2);
	// Tyre wear: darker, polished tracks in each lane.
	float wear = 0.0;
	for (int i = 0; i < lanes_per_side * 2; i++) {
		float c = lane_w * (float(i) + 0.5);
		wear += band(x, c - 0.85, 0.6, 0.3) + band(x, c + 0.85, 0.6, 0.3);
	}
	col *= 1.0 - wear * 0.12;

	vec3 white = vec3(0.82, 0.82, 0.78);
	vec3 yellow = vec3(0.85, 0.6, 0.08);
	float worn = 0.75 + 0.25 * smoothstep(0.3, 0.7, n1);
	float paint_w = 0.0, paint_y = 0.0;
	if (style == 3) {
		// Intersection: zebra crossings near each edge.
		float zx = step(fract(x / 1.2), 0.55), zy = step(fract(y / 1.2), 0.55);
		float edge_x = step(y, 3.5) + step(W - 3.5, y);
		float edge_y = step(x, 3.5) + step(W - 3.5, x);
		paint_w = clamp(zx * edge_x * step(1.5, x) * step(x, W - 1.5) + zy * edge_y * step(1.5, y) * step(y, W - 1.5), 0.0, 1.0);
		// Stop lines
		paint_w = max(paint_w, band(y, 4.0, 0.4, fw) * step(W * 0.5, x) + band(y, W - 4.0, 0.4, fw) * step(x, W * 0.5));
	} else if (style == 2) {
		paint_w = band(x, W * 0.5, 0.9, fw) * step(fract(y / 60.0), 0.5);
		paint_w += band(x, 1.2, 0.9, fw) + band(x, W - 1.2, 0.9, fw);
		// Threshold piano keys at the ends handled by v range
		float keys = step(fract(x / 3.0), 0.6) * (step(y, 40.0) + step(2340.0, y)) * step(5.0, x) * step(x, W - 5.0);
		paint_w = max(paint_w, keys);
	} else {
		paint_w += band(x, 0.45, 0.15, fw) + band(x, W - 0.45, 0.15, fw);
		if (style == 0) {
			paint_y += band(x, W * 0.5 - 0.17, 0.12, fw) + band(x, W * 0.5 + 0.17, 0.12, fw);
		} else {
			paint_y += band(x, W * 0.5, 0.13, fw) * step(fract(y / 9.0), 0.45);
		}
		for (int i = 1; i < lanes_per_side; i++) {
			float dash = step(fract(y / 12.0), 0.4);
			paint_w += (band(x, W * 0.5 - lane_w * float(i), 0.13, fw) + band(x, W * 0.5 + lane_w * float(i), 0.13, fw)) * dash;
		}
	}
	paint_w = clamp(paint_w, 0.0, 1.0) * worn;
	paint_y = clamp(paint_y, 0.0, 1.0) * worn;
	col = mix(col, white, paint_w);
	col = mix(col, yellow, paint_y);
	float paint = max(paint_w, paint_y);

	// Wet roads: darker, glossy, with puddles in low spots.
	float puddle = smoothstep(0.55, 0.62, texture(noise_b, wpos.xz * 0.03).r + n3 * 0.08) * wetness;
	float wet = clamp(wetness * 0.8 + puddle, 0.0, 1.0);
	col *= mix(1.0, 0.55, wet * (1.0 - paint * 0.5));
	ALBEDO = col;
	ROUGHNESS = mix(mix(trh.b, 0.55, paint), 0.05, wet * mix(0.75, 1.0, puddle));
	SPECULAR = 0.5;
	NORMAL_MAP = mix(vec3(trh1.rg, 1.0), vec3(0.5, 0.5, 1.0), max(paint * 0.7, puddle));
	NORMAL_MAP_DEPTH = 0.7;
}
