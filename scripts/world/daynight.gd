class_name DayNight
extends Node
## Sun/moon, sky, fog and exposure driven by the time of day.

const SKY_SHADER := preload("res://shaders/sky.gdshader")

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var hour := 19.0
var night := 0.0
var rain := 0.0
var _cloud := 0.0
var _sky_timer := 0.0
var flash := 0.0 # lightning, decays quickly

func setup(parent: Node) -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("cloud_noise", Proc.noise_tex(31, 0.008, 512, false, 6))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL if RenderingServer.get_current_rendering_method() != "gl_compatibility" else Sky.PROCESS_MODE_QUALITY
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.3)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.4)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 300.0
	env.fog_depth_end = 3000.0
	env.fog_density = 0.6
	env.fog_aerial_perspective = 0.45
	env.fog_sky_affect = 0.25
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 180.0
	env.volumetric_fog_sky_affect = 0.0
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.15
	world_env = WorldEnvironment.new()
	world_env.environment = env
	parent.add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.5
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	parent.add_child(sun)

func set_draw_distance(far: float) -> void:
	env.fog_depth_end = far * 0.95
	env.fog_depth_begin = far * 0.12

func _sun_dir(h: float) -> Vector3:
	# Sun rises in the east (+X) and sets in the west, slightly south-tilted.
	var ang := (h - 6.0) / 12.0 * PI
	return Vector3(cos(ang) * 0.85, sin(ang), 0.42).normalized()

func update(delta: float) -> void:
	var sd := _sun_dir(hour)
	var elev := sd.y
	night = 1.0 - smoothstep(-0.14, 0.08, elev)
	var golden := (1.0 - smoothstep(0.05, 0.35, elev)) * (1.0 - night)
	var moon := Vector3(-0.35, 0.62, -0.7).normalized()
	var light_dir := sd if night < 0.5 else moon
	if night < 0.5:
		# Lift the low dusk sun toward the moon so roads don't fall into grazing light.
		light_dir = sd.slerp(moon, smoothstep(0.05, 0.5, night) * 0.8).normalized()
	sun.look_at_from_position(Vector3.ZERO, -light_dir, Vector3.UP if absf(light_dir.y) < 0.99 else Vector3.FORWARD)
	if night < 0.5:
		var warm := Color(1.0, 0.55, 0.28).lerp(Color(1.0, 0.96, 0.9), smoothstep(0.02, 0.4, elev))
		# Twilight fill: blend toward the moonlight so dusk never goes pitch black.
		var dusk := smoothstep(0.05, 0.5, night)
		sun.light_color = warm.lerp(Color(0.6, 0.7, 1.0), dusk)
		sun.light_energy = maxf(lerpf(0.0, 2.6, smoothstep(-0.05, 0.25, elev)), 0.55 * dusk) * (1.0 - rain * 0.6)
	else:
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.light_energy = 0.7 * (1.0 - rain * 0.6)
	sun.light_volumetric_fog_energy = 1.0 + golden * 2.0
	# Night ambient: moonlit blue city glow instead of the near-black sky.
	env.ambient_light_color = Color(0.5, 0.55, 0.65).lerp(Color(0.16, 0.19, 0.3), night)
	env.ambient_light_sky_contribution = lerpf(0.85, 0.3, night)
	flash = maxf(0.0, flash - delta * 7.0)
	env.ambient_light_energy = lerpf(1.25, 1.05, night) + flash * 3.0
	env.background_energy_multiplier = lerpf(1.0, 0.9, night) + flash * 2.0
	env.tonemap_exposure = lerpf(0.92, 1.45, night) * (1.0 + golden * 0.1)
	var fog_day := Color(0.66, 0.74, 0.84)
	var fog_gold := Color(0.9, 0.62, 0.42)
	var fog_night := Color(0.05, 0.06, 0.1)
	var fogc := fog_day.lerp(fog_gold, golden).lerp(fog_night, night)
	env.fog_light_color = fogc.lerp(Color(0.4, 0.42, 0.45), rain * (1.0 - night))
	env.fog_light_energy = lerpf(1.0, 0.6, night)
	env.fog_density = 0.35 + rain * 1.5
	env.volumetric_fog_albedo = fogc
	env.volumetric_fog_density = 0.0035 + golden * 0.004 + rain * 0.01 + night * 0.002
	env.glow_intensity = lerpf(0.45, 0.9, night)
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("sun_dir", sd)
	sky_mat.set_shader_parameter("moon_dir", moon)
	sky_mat.set_shader_parameter("cloud_cover", 0.42 + rain * 0.5)
	_sky_timer -= delta
	if _sky_timer <= 0.0:
		_sky_timer = 2.0
		_cloud += 0.0025
		sky_mat.set_shader_parameter("cloud_offset", _cloud)
	RenderingServer.global_shader_parameter_set("night", night)
