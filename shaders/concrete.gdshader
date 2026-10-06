shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Sidewalk slabs / plazas with joints, stains and wet sheen.
uniform sampler2D noise_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base : source_color = vec3(0.42, 0.41, 0.39);
// Stored sRGB but sampled raw and decoded with srgb() below: texture arrays are not
// sRGB-decoded on every renderer, this way all of them agree.
uniform sampler2DArray surf_albedo : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surf_nrh : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 1.5;
global uniform float wetness;
varying vec3 wpos;

vec3 srgb(vec3 c) {
	return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}
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
	float m = texture(noise_b, wpos.xz * 0.05).r;
	// Each slab samples the concrete texture with its own offset so slabs differ.
	vec2 slab = floor(p / tile);
	vec2 uv = p / 3.0 + fract(sin(vec2(dot(slab, vec2(12.9898, 78.233)), dot(slab, vec2(39.35, 11.13)))) * 437.585);
	vec3 tex = srgb(texture(surf_albedo, vec3(uv, 6.0)).rgb);
	vec3 nrh = texture(surf_nrh, vec3(uv, 6.0)).rgb;
	vec3 col = tex * (base / 0.36) * (0.85 + m * 0.25);
	col *= 1.0 - joint * 0.5;
	col *= 1.0 - smoothstep(0.6, 0.75, m) * 0.25;
	ALBEDO = col * mix(1.0, 0.65, wetness);
	ROUGHNESS = mix(nrh.b, 0.2, wetness * (1.0 - joint));
	NORMAL_MAP = vec3(nrh.rg, 1.0);
	NORMAL_MAP_DEPTH = 0.8;
}
