shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Alpha-tested leaf cards with wind sway and translucency.
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float sway = 0.12;
varying vec3 tint;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	vec3 wp = MODEL_MATRIX[3].xyz;
	float ph = INSTANCE_CUSTOM.a * 6.28;
	float h = max(VERTEX.y, 0.0);
	float w = sin(TIME * 1.4 + ph + wp.x * 0.03) * 0.6 + sin(TIME * 2.9 + ph * 1.7) * 0.25;
	VERTEX.x += w * sway * h * 0.15;
	VERTEX.z += cos(TIME * 1.1 + ph) * sway * h * 0.08;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALBEDO = t.rgb * tint;
	// Mipmapping averages leaf coverage away, so distant canopies would thin out to
	// bare branches. Scale alpha up with the mip level to keep their silhouette.
	vec2 px = UV * vec2(textureSize(leaf_tex, 0));
	vec2 ddx = dFdx(px), ddy = dFdy(px);
	float lod = max(0.5 * log2(max(dot(ddx, ddx), dot(ddy, ddy))), 0.0);
	ALPHA = t.a * (1.0 + lod * 0.3);
	ALPHA_SCISSOR_THRESHOLD = 0.42;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	BACKLIGHT = t.rgb * tint * 0.6;
}
