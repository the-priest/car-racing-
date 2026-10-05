shader_type sky;

// Analytic atmosphere with sun/moon, procedural clouds and stars.
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_offset = 0.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 moon_dir = vec3(0.3, 0.6, -0.7);
uniform vec3 sun_dir = vec3(0.3, 0.8, -0.5);
uniform float exposure = 1.0;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

vec3 atmosphere(vec3 d, vec3 s) {
	float sun_up = s.y;
	float mu = dot(d, s);
	float day = smoothstep(-0.2, 0.25, sun_up);
	vec3 zenith = mix(vec3(0.004, 0.008, 0.022), vec3(0.10, 0.26, 0.68), day);
	vec3 horizon = mix(vec3(0.02, 0.03, 0.06), vec3(0.62, 0.74, 0.88), day);
	// Rayleigh-ish gradient
	float h = clamp(d.y, -0.2, 1.0);
	vec3 col = mix(horizon, zenith, pow(max(h, 0.0), 0.45));
	// Sunset band and Mie glow
	float low_sun = (1.0 - smoothstep(0.0, 0.35, sun_up)) * smoothstep(-0.25, 0.02, sun_up);
	vec3 sunset = vec3(1.0, 0.38, 0.10) * low_sun;
	col += sunset * pow(max(mu, 0.0), 3.0) * (1.0 - max(h, 0.0)) * 1.6;
	col += vec3(1.0, 0.55, 0.3) * low_sun * pow(1.0 - abs(h), 8.0) * 0.5;
	col += vec3(1.0, 0.9, 0.75) * pow(max(mu, 0.0), 60.0) * day * 0.6;
	// Below horizon fades to ground haze
	if (d.y < 0.0) col = mix(horizon * 0.55, horizon * 0.25, clamp(-d.y * 4.0, 0.0, 1.0));
	return col;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = atmosphere(d, sun_dir);

	// Sun disc
	float mu = dot(d, sun_dir);
	col += vec3(1.0, 0.92, 0.8) * smoothstep(0.99975, 0.99992, mu) * 60.0 * smoothstep(-0.05, 0.02, sun_dir.y);

	// Stars and moon
	if (night > 0.0 && d.y > 0.0) {
		vec3 cell = floor(d * 380.0);
		float st = step(0.9975, hash3(cell));
		float tw = 0.6 + 0.4 * hash3(cell + 7.0);
		col += vec3(st * tw) * night * smoothstep(0.0, 0.2, d.y) * 2.0;
		// Milky haze
		col += vec3(0.02, 0.025, 0.04) * night * pow(max(0.0, 1.0 - abs(dot(d, normalize(vec3(0.5, 0.3, 0.8))))), 6.0);
		float md = dot(d, normalize(moon_dir));
		col += vec3(0.9, 0.92, 1.0) * smoothstep(0.9993, 0.9996, md) * 6.0 * night;
		col += vec3(0.25, 0.3, 0.45) * pow(max(md, 0.0), 200.0) * night * 0.6;
	}

	// Clouds on a curved plane
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.08) * 0.35 + vec2(cloud_offset, cloud_offset * 0.4);
		float n = texture(cloud_noise, uv * 0.6).r * 0.65 + texture(cloud_noise, uv * 1.9 + 3.1).r * 0.35;
		float dens = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, n);
		dens *= smoothstep(0.0, 0.12, d.y);
		float lit = clamp(dot(normalize(vec3(d.x, 0.2, d.z)), sun_dir) * 0.5 + 0.5, 0.0, 1.0);
		float day = smoothstep(-0.15, 0.25, sun_dir.y);
		vec3 base = mix(vec3(0.03, 0.035, 0.05), vec3(0.72, 0.74, 0.78), day);
		vec3 lit_col = mix(base, mix(vec3(1.0, 0.6, 0.35), vec3(1.0, 0.98, 0.95), smoothstep(0.05, 0.35, sun_dir.y)), lit * day);
		vec3 cc = mix(base * 0.7, lit_col, 0.6 + 0.4 * (1.0 - n));
		// Night clouds pick up city glow from below
		cc += vec3(0.09, 0.05, 0.03) * night * (1.0 - smoothstep(0.0, 0.4, d.y));
		col = mix(col, cc, dens * 0.92);
	}

	// City light pollution near the horizon at night
	col += vec3(0.08, 0.045, 0.025) * night * pow(1.0 - clamp(abs(d.y), 0.0, 1.0), 10.0);
	COLOR = col * exposure;
}
