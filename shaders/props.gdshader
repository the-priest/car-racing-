shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Textured props (rooftop gear, parapets, awnings, poles, lamps, bark, lawns):
// world-space triplanar sampling from the surface texture array, tinted by the
// vertex colour. Vertex alpha < 0.75 switches to the alternate material (stone).
uniform sampler2DArray surf_albedo : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray surf_nrh : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layer = 12.0;
uniform float scale = 1.0;
uniform float alt_layer = 10.0;
uniform float alt_scale = 3.6;
uniform float color_ref = 0.5; // average brightness of the texture, so vertex colours keep their meaning
uniform bool use_vertex_color = true;
uniform float metallic_amt = 0.0;
uniform float bump = 0.6;
global uniform float wetness;

varying vec3 wpos;
varying vec3 wn;
varying vec4 vcol;

vec3 srgb(vec3 c) {
	return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

void fragment() {
	bool alt = vcol.a < 0.75;
	float L = alt ? alt_layer : layer;
	float sc = alt ? alt_scale : scale;
	vec3 n = normalize(wn);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 ux = vec2(wpos.z, -wpos.y) / sc, uy = wpos.xz / sc, uz = vec2(wpos.x, -wpos.y) / sc;
	vec3 a = srgb(texture(surf_albedo, vec3(ux, L)).rgb) * w.x + srgb(texture(surf_albedo, vec3(uy, L)).rgb) * w.y + srgb(texture(surf_albedo, vec3(uz, L)).rgb) * w.z;
	vec3 tx = texture(surf_nrh, vec3(ux, L)).rgb, ty = texture(surf_nrh, vec3(uy, L)).rgb, tz = texture(surf_nrh, vec3(uz, L)).rgb;
	vec2 dx = tx.rg * 2.0 - 1.0, dy = ty.rg * 2.0 - 1.0, dz = tz.rg * 2.0 - 1.0;
	vec3 off = vec3(0.0, dx.y, dx.x * sign(n.x)) * w.x + vec3(dy.x, 0.0, -dy.y) * w.y + vec3(dz.x * sign(n.z), dz.y, 0.0) * w.z;
	float rough = tx.b * w.x + ty.b * w.y + tz.b * w.z;
	vec3 tint = use_vertex_color ? vcol.rgb / color_ref : vec3(1.0);
	if (alt) tint = vcol.rgb / 0.65;
	ALBEDO = a * tint * mix(1.0, 0.7, wetness);
	ROUGHNESS = mix(rough, 0.25, wetness * 0.6);
	METALLIC = alt ? 0.0 : metallic_amt * (1.0 - smoothstep(0.7, 0.85, rough));
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n + off * bump), 0.0)).xyz);
}
