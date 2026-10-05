class_name EnvController
extends Node3D
## Time of day (sun/moon/sky palettes), weather state machine (clear/cloudy/rain/storm/fog),
## wetness, rain particles, lightning, street-light pool and underwater post effect.

const WEATHERS := ["clear", "cloudy", "rain", "storm", "fog"]
const W_PARAMS := {
	"clear": {"cloud": 0.18, "fog": 0.0009, "rain": 0.0, "wet": 0.0, "sun": 1.0},
	"cloudy": {"cloud": 0.62, "fog": 0.0016, "rain": 0.0, "wet": 0.0, "sun": 0.55},
	"rain": {"cloud": 0.85, "fog": 0.0035, "rain": 0.7, "wet": 1.0, "sun": 0.3},
	"storm": {"cloud": 0.97, "fog": 0.005, "rain": 1.0, "wet": 1.0, "sun": 0.15},
	"fog": {"cloud": 0.7, "fog": 0.016, "rain": 0.0, "wet": 0.25, "sun": 0.35},
}

var hour := 9.0
var minutes_per_hour := 1.0      # real minutes per game hour
var time_running := true
var weather := "clear"
var auto_weather := true
var _wp := {"cloud": 0.18, "fog": 0.0009, "rain": 0.0, "wet": 0.0, "sun": 1.0}
var _weather_timer := 240.0

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var rain: GPUParticles3D
var rain_audio: AudioStreamPlayer
var underwater_rect: ColorRect
var wetness := 0.0
var night := 0.0
var sun_dir := Vector3.UP
var _lightning_t := 0.0
var _flash := 0.0
var _sky_timer := 0.0
var _cloud_off := Vector2.ZERO
var lamp_lights: Array[OmniLight3D] = []
var _lamp_timer := 0.0
var lamp_points: Array = []
var underwater := false


func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://gta/shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.35
	env.fog_sun_scatter = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.5
	add_child(sun)
	_build_rain()
	underwater_rect = ColorRect.new()
	underwater_rect.color = Color(0.05, 0.35, 0.45, 0.0)
	underwater_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var cl := CanvasLayer.new()
	cl.layer = -1
	cl.add_child(underwater_rect)
	add_child(cl)
	for i in 12:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.omni_range = 16.0
		l.light_energy = 0.0
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		lamp_lights.append(l)
	set_weather("clear", true)
	_apply_time(true)


func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 6000
	rain.lifetime = 1.2
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	rain.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 1, 28)
	pm.direction = Vector3(0.1, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 28.0
	pm.initial_velocity_max = 34.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.03, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 0.82, 0.95, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	qm.material = m
	rain.draw_pass_1 = qm
	rain.emitting = false
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)
	rain_audio = AudioStreamPlayer.new()
	rain_audio.bus = "Master"
	add_child(rain_audio)


func set_weather(w: String, instant := false) -> void:
	if not W_PARAMS.has(w):
		return
	weather = w
	_weather_timer = randf_range(180.0, 360.0)
	if instant:
		_wp = W_PARAMS[w].duplicate()
	if Game.hud:
		Game.notify("Weather: " + w.capitalize())


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_apply_time(true)


func _process(delta: float) -> void:
	if time_running and not Game.paused:
		hour = fposmod(hour + delta / (minutes_per_hour * 60.0), 24.0)
	if auto_weather:
		_weather_timer -= delta
		if _weather_timer <= 0.0:
			var r := randf()
			set_weather("clear" if r < 0.4 else ("cloudy" if r < 0.65 else ("rain" if r < 0.82 else ("storm" if r < 0.92 else "fog"))))
	var target: Dictionary = W_PARAMS[weather]
	for k in _wp:
		_wp[k] = U.damp(_wp[k], target[k], 0.25, delta)
	var wet_target: float = target.wet
	wetness = move_toward(wetness, wet_target, delta * (0.08 if wet_target > wetness else 0.015))
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	_apply_time(false)
	_update_rain(delta)
	_update_lightning(delta)
	_update_lamps(delta)
	_update_underwater()


func _apply_time(force: bool) -> void:
	var day_t := (hour - 6.0) / 13.5
	var theta := day_t * PI
	sun_dir = Vector3(cos(theta), sin(theta) * 0.92, 0.38 * sin(theta)).normalized()
	var elev := sun_dir.y
	night = smoothstep(0.08, -0.16, elev)
	Game.night_factor = night
	RenderingServer.global_shader_parameter_set("city_night", night)
	var moon_dir := Vector3(-sun_dir.x, absf(sun_dir.y) * 0.8 + 0.25, -sun_dir.z + 0.2).normalized()
	# palettes
	var day_top := Color(0.2, 0.42, 0.82)
	var day_hor := Color(0.72, 0.82, 0.92)
	var gold_top := Color(0.28, 0.36, 0.66)
	var gold_hor := Color(1.0, 0.62, 0.42)
	var dusk_top := Color(0.08, 0.1, 0.25)
	var dusk_hor := Color(0.62, 0.32, 0.4)
	var night_top := Color(0.015, 0.025, 0.06)
	var night_hor := Color(0.07, 0.08, 0.14)
	var top: Color
	var hor: Color
	if elev > 0.3:
		top = day_top; hor = day_hor
	elif elev > 0.0:
		var t := elev / 0.3
		top = gold_top.lerp(day_top, t); hor = gold_hor.lerp(day_hor, t)
	elif elev > -0.18:
		var t2 := -elev / 0.18
		top = gold_top.lerp(dusk_top, t2).lerp(night_top, t2 * t2); hor = gold_hor.lerp(dusk_hor, t2).lerp(night_hor, t2 * t2)
	else:
		top = night_top; hor = night_hor
	# weather greys the sky
	var grey := Color(0.5, 0.53, 0.58) * (1.0 - night * 0.85)
	var cover: float = _wp.cloud
	top = top.lerp(grey, cover * 0.75)
	hor = hor.lerp(grey.lightened(0.1), cover * 0.6)
	var fog_extra: float = _wp.fog
	# sun / moon light
	var sun_col := Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.62, 0.38), clampf(1.0 - elev / 0.35, 0.0, 1.0))
	var day_energy := clampf(elev * 4.0, 0.0, 1.0) * 1.3 * float(_wp.sun)
	var moon_energy := night * 0.22 * (1.0 - cover * 0.6)
	if day_energy > moon_energy:
		sun.light_color = sun_col
		sun.light_energy = day_energy + _flash * 2.0
		_point_light(sun_dir)
	else:
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.light_energy = moon_energy + _flash * 2.5
		_point_light(moon_dir)
	sun.shadow_enabled = sun.light_energy > 0.05
	env.ambient_light_energy = lerpf(0.9, 0.6, night) + _flash
	env.ambient_light_color = Color(0.66, 0.66, 0.68).lerp(Color(0.12, 0.14, 0.24), night)
	env.fog_light_color = hor.lerp(Color(0.12, 0.13, 0.17), night * 0.5)
	env.fog_density = fog_extra + (0.0008 * night)
	env.fog_sun_scatter = 0.25 * (1.0 - night)
	env.tonemap_exposure = lerpf(1.05, 1.35, night)
	_sky_timer -= get_process_delta_time()
	_cloud_off += Vector2(0.0025, 0.0012) * get_process_delta_time() * (1.0 + cover * 2.0)
	if force or _sky_timer <= 0.0 or _flash > 0.01:
		_sky_timer = 0.25
		sky_mat.set_shader_parameter("top_color", top + Color(_flash, _flash, _flash * 1.1))
		sky_mat.set_shader_parameter("horizon_color", hor + Color(_flash, _flash, _flash * 1.1) * 0.6)
		sky_mat.set_shader_parameter("ground_color", hor.darkened(0.6))
		sky_mat.set_shader_parameter("sun_dir_u", sun_dir)
		sky_mat.set_shader_parameter("moon_dir", moon_dir)
		sky_mat.set_shader_parameter("sun_glow", sun_col)
		sky_mat.set_shader_parameter("cloud_cover", cover)
		sky_mat.set_shader_parameter("cloud_lit", Color(1, 0.97, 0.94).lerp(Color(0.35, 0.37, 0.45), night).lerp(Color(0.7, 0.72, 0.76), cover * 0.5))
		sky_mat.set_shader_parameter("cloud_dark", Color(0.55, 0.58, 0.66).lerp(Color(0.06, 0.07, 0.1), night).darkened(cover * 0.35))
		sky_mat.set_shader_parameter("star_strength", night)
		sky_mat.set_shader_parameter("cloud_offset", _cloud_off)


func _point_light(from_dir: Vector3) -> void:
	var up := Vector3.UP if absf(from_dir.y) < 0.98 else Vector3.FORWARD
	sun.global_transform = Transform3D(Basis.looking_at(-from_dir, up), Vector3.ZERO)


func _update_rain(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var intensity: float = _wp.rain
	rain.emitting = intensity > 0.05 and not underwater
	rain.amount_ratio = clampf(intensity, 0.05, 1.0)
	if cam:
		rain.global_position = cam.global_position + Vector3(0, 14, 0) + U.flat(-cam.global_basis.z) * 8.0
	if intensity > 0.05:
		if not rain_audio.playing:
			rain_audio.stream = Audio.get_stream("rain_loop")
			rain_audio.play()
		rain_audio.volume_db = linear_to_db(clampf(intensity, 0.01, 1.0)) - 6.0
	elif rain_audio.playing:
		rain_audio.stop()


func _update_lightning(delta: float) -> void:
	_flash = maxf(_flash - delta * 4.0, 0.0)
	if weather != "storm":
		return
	_lightning_t -= delta
	if _lightning_t <= 0.0:
		_lightning_t = randf_range(5.0, 14.0)
		_flash = randf_range(0.6, 1.2)
		var cam := get_viewport().get_camera_3d()
		if cam:
			var d := randf_range(1.0, 3.0)
			get_tree().create_timer(d).timeout.connect(func(): Audio.play_2d("thunder", -2.0, randf_range(0.8, 1.1)))


func _update_lamps(delta: float) -> void:
	_lamp_timer -= delta
	if _lamp_timer > 0.0:
		return
	_lamp_timer = 0.4
	var on := night > 0.35
	var cam := get_viewport().get_camera_3d()
	if not on or cam == null or lamp_points.is_empty():
		for l in lamp_lights:
			l.visible = false
		return
	var cp := cam.global_position
	var best: Array = []
	for p in lamp_points:
		var d: float = (p as Vector3).distance_squared_to(cp)
		if d < 120.0 * 120.0:
			best.append([d, p])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for i in lamp_lights.size():
		var l := lamp_lights[i]
		if i < best.size():
			l.visible = true
			l.global_position = best[i][1] - Vector3(0, 0.3, 0)
			l.light_energy = 1.6 * night
		else:
			l.visible = false


func _update_underwater() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var uw := cam.global_position.y < C.SEA_LEVEL - 0.05
	if uw != underwater:
		underwater = uw
		if uw:
			env.fog_light_color = Color(0.05, 0.3, 0.38)
	if underwater:
		env.fog_density = 0.07
		env.fog_light_color = Color(0.04, 0.28 * (1.0 - night * 0.7), 0.36 * (1.0 - night * 0.6))
		env.fog_sky_affect = 1.0
		underwater_rect.color = Color(0.05, 0.35, 0.45, 0.28)
	else:
		env.fog_sky_affect = 0.35
		underwater_rect.color = Color(0.05, 0.35, 0.45, 0.0)


func rain_intensity() -> float:
	return _wp.rain


func grip_factor() -> float:
	return 1.0 - wetness * 0.22
