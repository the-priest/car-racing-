shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Night-reactive emissive surfaces coloured by vertex colour (station canopy
// lights, pump screens, price panels, lit shop windows). Brighter after dark.
global uniform float night;
uniform float strength = 3.0;
uniform float day_strength = 0.4;
uniform float base = 0.25;
uniform float rough = 0.3;
uniform float metal = 0.0;

void fragment() {
	ALBEDO = COLOR.rgb * base;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = COLOR.rgb * mix(day_strength, strength, night);
}
