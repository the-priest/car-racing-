shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, skip_vertex_transform;

// Infinite grass field that wraps around the camera. Instances are laid out on
// a grid in [-radius, radius]; the vertex shader places them on the terrain.
global uniform vec3 cam_pos;
uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform sampler2D maskmap : filter_linear, repeat_disable;
uniform sampler2D blade_tex : source_color, filter_linear_mipmap;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform float half_size = 3072.0;
uniform float tex_size = 769.0;
uniform float radius = 60.0;

varying vec3 tint;

vec2 hm_uv(vec2 xz) {
	return (xz + half_size) / (2.0 * half_size) * ((tex_size - 1.0) / tex_size) + 0.5 / tex_size;
}
float h_at(vec2 xz) {
	vec2 g = clamp((xz + half_size) / (2.0 * half_size) * (tex_size - 1.0), vec2(0.0), vec2(tex_size - 1.001));
	ivec2 i = ivec2(floor(g));
	vec2 f = g - vec2(i);
	float a = texelFetch(heightmap, i, 0).r;
	float b = texelFetch(heightmap, i + ivec2(1, 0), 0).r;
	float c = texelFetch(heightmap, i + ivec2(0, 1), 0).r;
	float d = texelFetch(heightmap, i + ivec2(1, 1), 0).r;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	vec2 o = MODEL_MATRIX[3].xz;
	vec2 wxz = cam_pos.xz + mod(o - cam_pos.xz + radius, 2.0 * radius) - radius;
	float r = hash(o);
	wxz += (vec2(hash(o + 1.7), hash(o + 4.3)) - 0.5) * 1.2;
	float h = h_at(wxz);
	vec4 mk = textureLod(maskmap, hm_uv(wxz), 0.0);
	float slope = abs(h_at(wxz + vec2(2.0, 0.0)) - h) + abs(h_at(wxz + vec2(0.0, 2.0)) - h);
	float dens = (1.0 - smoothstep(0.05, 0.3, mk.r)) * (1.0 - mk.g) * (1.0 - smoothstep(0.9, 1.6, slope));
	dens *= smoothstep(1.5, 3.0, h) * (1.0 - smoothstep(260.0, 300.0, h));
	float nz = textureLod(noise_a, wxz * 0.02, 0.0).r;
	dens *= smoothstep(0.25, 0.5, nz + r * 0.25);
	float d = length(wxz - cam_pos.xz);
	float fade = 1.0 - smoothstep(radius * 0.55, radius * 0.95, d);
	float s = dens * fade * (0.6 + r * 0.7);
	float a = r * 6.2831;
	vec3 lv = VERTEX * s;
	lv.xz = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * lv.xz;
	float top = clamp(VERTEX.y, 0.0, 1.0);
	lv.x += sin(TIME * 2.1 + wxz.x * 0.3 + wxz.y * 0.2) * 0.12 * top * s;
	lv.z += cos(TIME * 1.7 + wxz.y * 0.35) * 0.08 * top * s;
	vec3 world = vec3(wxz.x, h - 0.05, wxz.y) + lv;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	tint = mix(vec3(0.55, 0.75, 0.35), vec3(0.85, 0.8, 0.45), nz) * (0.7 + top * 0.5);
}

void fragment() {
	vec4 t = texture(blade_tex, UV);
	ALBEDO = t.rgb * tint;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.2, 0.25, 0.08);
}
