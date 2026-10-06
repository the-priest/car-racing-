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
// Surface texture arrays (see tools/textures/gen_textures.py for the slice order).
// Stored sRGB but sampled raw and decoded with srgb() below: texture arrays are not
// sRGB-decoded on every renderer, this way all of them agree.
uniform sampler2DArray surf_albedo : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surf_nrh : filter_linear_mipmap_anisotropic, repeat_enable;
const float L_GRASS = 1.0;
const float L_DIRT = 2.0;
const float L_ROCK = 3.0;
const float L_SAND = 4.0;
const float L_GRAVEL = 5.0;
const float L_CONCRETE = 6.0;
const float L_SNOW = 7.0;

global uniform float wetness;

varying vec3 wpos;

vec3 srgb(vec3 c) {
	return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

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

// A ground layer seen from above: two samples at unrelated scales/rotations,
// mixed by a noise mask, so the tile never repeats visibly. Returns albedo and
// the world-space normal offset (xyz) + roughness (w).
void ground_layer(float layer, vec2 xz, float scale, float mixer, out vec3 alb, out vec4 nr) {
	vec2 uv1 = xz / scale;
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * xz / (scale * 2.37) + 0.37;
	vec3 a1 = srgb(texture(surf_albedo, vec3(uv1, layer)).rgb);
	vec3 a2 = srgb(texture(surf_albedo, vec3(uv2, layer)).rgb);
	vec3 n1 = texture(surf_nrh, vec3(uv1, layer)).rgb;
	vec3 n2 = texture(surf_nrh, vec3(uv2, layer)).rgb;
	alb = mix(a1, a2, mixer);
	vec3 t = mix(n1, n2, mixer);
	vec2 d = t.rg * 2.0 - 1.0;
	// UV2 is rotated: rotate its slope back so the light still comes from the right side.
	vec2 d2 = n2.rg * 2.0 - 1.0;
	d2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * d2;
	d = mix(n1.rg * 2.0 - 1.0, d2, mixer);
	nr = vec4(d.x, 0.0, -d.y, t.b);
}

// Cliff rock: triplanar, strata run horizontally on the side projections.
void rock_layer(vec3 p, vec3 n, float scale, out vec3 alb, out vec4 nr) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 ux = vec2(p.z, -p.y) / scale, uy = p.xz / scale, uz = vec2(p.x, -p.y) / scale;
	vec3 ax = srgb(texture(surf_albedo, vec3(ux, L_ROCK)).rgb), ay = srgb(texture(surf_albedo, vec3(uy, L_ROCK)).rgb), az = srgb(texture(surf_albedo, vec3(uz, L_ROCK)).rgb);
	vec3 tx = texture(surf_nrh, vec3(ux, L_ROCK)).rgb, ty = texture(surf_nrh, vec3(uy, L_ROCK)).rgb, tz = texture(surf_nrh, vec3(uz, L_ROCK)).rgb;
	alb = ax * w.x + ay * w.y + az * w.z;
	vec2 dx = tx.rg * 2.0 - 1.0, dy = ty.rg * 2.0 - 1.0, dz = tz.rg * 2.0 - 1.0;
	vec3 off = vec3(0.0, dx.y, dx.x * sign(n.x)) * w.x + vec3(dy.x, 0.0, -dy.y) * w.y + vec3(dz.x * sign(n.z), dz.y, 0.0) * w.z;
	nr = vec4(off, tx.b * w.x + ty.b * w.y + tz.b * w.z);
}

void fragment() {
	// Per-pixel normal from the heightmap for smooth large-scale lighting.
	float e = 4.0;
	vec3 n = normalize(vec3(height_at(wpos.xz - vec2(e, 0.0)) - height_at(wpos.xz + vec2(e, 0.0)), 2.0 * e,
		height_at(wpos.xz - vec2(0.0, e)) - height_at(wpos.xz + vec2(0.0, e))));
	float slope = 1.0 - n.y;
	vec4 mk = texture(maskmap, hm_uv(wpos.xz));
	float dist = length(wpos - CAMERA_POSITION_WORLD);

	// Multi-scale noise drives where each material shows and breaks up tiling.
	float macro = texture(noise_a, wpos.xz * 0.0011).r;
	float mid = texture(noise_b, wpos.xz * 0.013).r;
	float fine = texture(noise_a, wpos.xz * 0.21).r;
	float mixer = smoothstep(0.35, 0.65, texture(noise_b, wpos.xz * 0.02).r);
	float rn = texture(noise_b, wpos.xz * 0.06).r;

	// Material weights (painter's order: later layers cover earlier ones).
	float dirtw = smoothstep(0.7, 0.95, mid * 0.6 + macro * 0.5) * 0.6;
	float rockw = smoothstep(0.22, 0.42, slope + (rn - 0.5) * 0.15);
	float snoww = smoothstep(300.0, 360.0, wpos.y + macro * 60.0) * (1.0 - smoothstep(0.35, 0.6, slope));
	float sandw = (1.0 - smoothstep(water_level + 1.0, water_level + 6.0 + mid * 3.0, wpos.y)) * smoothstep(1650.0, 1850.0, wpos.z);
	float gravw = smoothstep(0.65, 0.95, mk.r + (fine - 0.5) * 0.25);
	float concw = mk.g;

	vec3 alb; vec4 nr;
	ground_layer(L_GRASS, wpos.xz, 3.0, mixer, alb, nr);
	// Dry / lush variation across the hills.
	float dry = smoothstep(0.5, 0.95, macro * 0.7 + mid * 0.5);
	vec3 col = alb * mix(vec3(0.95, 1.0, 0.85), vec3(1.4, 1.15, 0.72), dry);
	vec4 det = nr;
	vec3 a2; vec4 n2;
	if (dirtw > 0.01) {
		ground_layer(L_DIRT, wpos.xz, 4.0, mixer, a2, n2);
		col = mix(col, a2, dirtw); det = mix(det, n2, dirtw);
	}
	if (rockw > 0.01) {
		rock_layer(wpos, n, 9.0, a2, n2);
		col = mix(col, a2 * mix(vec3(1.0), vec3(0.85, 0.9, 1.0), macro), rockw); det = mix(det, n2, rockw);
	}
	if (snoww > 0.01) {
		ground_layer(L_SNOW, wpos.xz, 6.0, mixer, a2, n2);
		col = mix(col, a2, snoww); det = mix(det, n2, snoww);
	}
	if (sandw > 0.01) {
		ground_layer(L_SAND, wpos.xz, 4.0, mixer, a2, n2);
		col = mix(col, a2, sandw); det = mix(det, n2, sandw);
	}
	if (gravw > 0.01) {
		ground_layer(L_GRAVEL, wpos.xz, 2.5, mixer, a2, n2);
		col = mix(col, a2, gravw); det = mix(det, n2, gravw);
	}
	if (concw > 0.01) {
		ground_layer(L_CONCRETE, wpos.xz, 3.0, mixer, a2, n2);
		col = mix(col, a2 * 0.9, concw); det = mix(det, n2, concw);
	}
	// Large-scale tone variation so distant hills aren't flat.
	col *= 0.82 + macro * 0.3 + mid * 0.12;

	// Wet sand near the waterline darkens.
	col *= 1.0 - 0.35 * (1.0 - smoothstep(water_level, water_level + 1.2, wpos.y)) * smoothstep(1650.0, 1850.0, wpos.z);

	ALBEDO = col;
	float rough = det.w;
	rough = mix(rough, 0.35, wetness * (1.0 - rockw) * 0.6);
	ROUGHNESS = rough;
	SPECULAR = 0.35;

	// Detail normals fade out with distance (mip-averaged anyway), keeping far hills smooth.
	float near = 1.0 - smoothstep(80.0, 400.0, dist);
	vec3 wn = normalize(n + det.xyz * mix(0.25, 0.9, near));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
