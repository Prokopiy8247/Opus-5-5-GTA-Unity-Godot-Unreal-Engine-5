extends Node3D
## Pooled visual effects (autoload "VFX"). All textures are generated procedurally.

var tex_soft: ImageTexture
var tex_spark: ImageTexture
var tex_hole: ImageTexture
var tex_scorch: ImageTexture
var _pools := {}
var _decals: Array[Decal] = []
var _decal_i := 0
var _flash_lights: Array[OmniLight3D] = []
var _flash_i := 0
var _tracers: Array[MeshInstance3D] = []
var _tracer_i := 0
var _muzzles: Array[MeshInstance3D] = []
var _muzzle_i := 0
var _fireballs: Array[MeshInstance3D] = []
var _fb_i := 0


func _ready() -> void:
	tex_soft = _make_soft(64, 1.6)
	tex_spark = _make_spark()
	tex_hole = _make_hole(false)
	tex_scorch = _make_hole(true)
	_make_pool("sparks", 10, _sparks_mat(), 24, 0.35, tex_spark, Vector2(0.04, 0.25), Color(1.0, 0.8, 0.4), true)
	_make_pool("dust", 10, _dust_mat(), 14, 0.9, tex_soft, Vector2(0.5, 0.5), Color(0.7, 0.66, 0.6, 0.6), false)
	_make_pool("blood", 8, _blood_mat(), 16, 0.6, tex_soft, Vector2(0.12, 0.12), Color(0.55, 0.05, 0.05, 0.9), false)
	_make_pool("splash", 8, _splash_mat(), 40, 1.0, tex_soft, Vector2(0.3, 0.3), Color(0.85, 0.95, 1.0, 0.7), false)
	_make_pool("glass", 6, _glass_mat(), 30, 1.0, tex_spark, Vector2(0.06, 0.06), Color(0.8, 0.95, 1.0, 0.8), false)
	_make_pool("smoke_big", 6, _smoke_mat(3.5, 6.0), 40, 3.5, tex_soft, Vector2(2.5, 2.5), Color(0.18, 0.18, 0.19, 0.55), false)
	_make_pool("fire_burst", 6, _fire_mat(), 36, 0.8, tex_soft, Vector2(1.4, 1.4), Color(1.0, 0.55, 0.15, 0.9), true)
	_make_pool("tire_smoke", 8, _smoke_mat(1.2, 1.5), 12, 1.6, tex_soft, Vector2(1.2, 1.2), Color(0.85, 0.85, 0.85, 0.35), false)
	_make_pool("water_jet", 3, _jet_mat(), 80, 1.4, tex_soft, Vector2(0.25, 0.25), Color(0.85, 0.95, 1.0, 0.7), false)
	for i in 6:
		var l := OmniLight3D.new()
		l.visible = false
		l.shadow_enabled = false
		add_child(l)
		_flash_lights.append(l)
	for i in 24:
		var t := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 1.0)
		t.mesh = bm
		t.material_override = Mats.unshaded(Color(1.0, 0.85, 0.5, 0.85), true)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		t.top_level = true
		add_child(t)
		_tracers.append(t)
	var star := _star_mesh()
	for i in 8:
		var m := MeshInstance3D.new()
		m.mesh = star
		m.material_override = Mats.unshaded(Color(1.0, 0.78, 0.35, 0.95), true)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		m.top_level = true
		add_child(m)
		_muzzles.append(m)
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 12
	sph.rings = 6
	for i in 4:
		var fb := MeshInstance3D.new()
		fb.mesh = sph
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = Color(1.0, 0.6, 0.2, 0.9)
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fb.material_override = fm
		fb.visible = false
		fb.top_level = true
		fb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fb)
		_fireballs.append(fb)
	for i in 48:
		var d := Decal.new()
		d.size = Vector3(0.22, 0.4, 0.22)
		d.texture_albedo = tex_hole
		d.visible = false
		d.cull_mask = 1
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		add_child(d)
		_decals.append(d)


# ------------------------------------------------------------------ textures

func _make_soft(size: int, power: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), power)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_spark() -> ImageTexture:
	var img := Image.create(16, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 16:
			var dx := absf(x - 7.5) / 8.0
			var dy := absf(y - 31.5) / 32.0
			var a := clampf(1.0 - dx, 0.0, 1.0) * clampf(1.0 - dy * dy, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_hole(scorch: bool) -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 if scorch else 3
	for y in s:
		for x in s:
			var v := Vector2(x - s * 0.5, y - s * 0.5)
			var d := v.length() / (s * 0.5)
			var ang := atan2(v.y, v.x)
			var rough := 0.85 + 0.15 * sin(ang * 7.0) + rng.randf_range(-0.05, 0.05)
			var a: float
			var c: Color
			if scorch:
				a = clampf((rough - d) * 2.0, 0.0, 0.85)
				c = Color(0.05, 0.04, 0.035, a)
			else:
				var core := clampf((0.3 - d) * 8.0, 0.0, 1.0)
				var ring := clampf((0.75 * rough - d) * 4.0, 0.0, 1.0) * 0.45
				a = maxf(core, ring)
				c = Color(0.06, 0.06, 0.06, a)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _star_mesh() -> ArrayMesh:
	var mb := MB.new()
	mb.use("f").col(Color.WHITE)
	for k in 3:
		var a := PI * k / 3.0
		var d := Vector3(cos(a), sin(a), 0) * 0.35
		var n := Vector3(-sin(a), cos(a), 0) * 0.06
		mb.quad(-d - n, d - n, d + n, -d + n, Vector3(0, 0, 1))
		mb.quad(-d - n, -d + n, d + n, d - n, Vector3(0, 0, -1))
	mb.quad(Vector3(-0.08, -0.08, 0), Vector3(0.08, -0.08, 0), Vector3(0.12, 0, -0.6), Vector3(-0.12, 0, -0.6), Vector3.UP)
	mb.quad(Vector3(-0.08, -0.08, 0), Vector3(-0.12, 0, -0.6), Vector3(0.12, 0, -0.6), Vector3(0.08, -0.08, 0), Vector3.DOWN)
	return mb.commit()


# ------------------------------------------------------------------ particle materials

func _base_pm() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	return pm


func _sparks_mat() -> ParticleProcessMaterial:
	var pm := _base_pm()
	pm.spread = 55.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -12, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.particle_flag_align_y = true
	return pm


func _dust_mat() -> ParticleProcessMaterial:
	var pm := _base_pm()
	pm.spread = 40.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -2.0, 0)
	pm.damping_min = 2.0
	pm.damping_max = 3.0
	pm.scale_min = 0.4
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	return pm


func _blood_mat() -> ParticleProcessMaterial:
	var pm := _base_pm()
	pm.spread = 35.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	return pm


func _splash_mat() -> ParticleProcessMaterial:
	var pm := _base_pm()
	pm.spread = 25.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.8
	return pm


func _glass_mat() -> ParticleProcessMaterial:
	var pm := _base_pm()
	pm.spread = 70.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.angular_velocity_min = -400.0
	pm.angular_velocity_max = 400.0
	return pm


func _smoke_mat(speed: float, grow: float) -> ParticleProcessMaterial:
	var pm := _base_pm()
	pm.spread = 25.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.0 * grow / 3.0 + 0.6))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	return pm


func _fire_mat() -> ParticleProcessMaterial:
	var pm := _base_pm()
	pm.spread = 180.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3(0, 3.0, 0)
	pm.damping_min = 5.0
	pm.damping_max = 8.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6, 1))
	g.add_point(0.4, Color(1.0, 0.45, 0.1, 0.8))
	g.set_color(g.get_point_count() - 1, Color(0.2, 0.15, 0.12, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	return pm


func _jet_mat() -> ParticleProcessMaterial:
	var pm := _base_pm()
	pm.spread = 6.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -9.8, 0)
	return pm


func _draw_mat(tex: Texture2D, col: Color, additive: bool, align_velocity := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if not align_velocity else BaseMaterial3D.BILLBOARD_FIXED_Y
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_pool(name: String, count: int, pm: ParticleProcessMaterial, amount: int, life: float, tex: Texture2D, size: Vector2, col: Color, additive: bool) -> void:
	var list: Array[GPUParticles3D] = []
	var qm := QuadMesh.new()
	qm.size = size
	qm.material = _draw_mat(tex, col, additive, name == "sparks")
	for i in count:
		var p := GPUParticles3D.new()
		p.process_material = pm
		p.draw_pass_1 = qm
		p.amount = amount
		p.lifetime = life
		p.one_shot = true
		p.explosiveness = 0.92
		p.emitting = false
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
		add_child(p)
		list.append(p)
	_pools[name] = {"list": list, "i": 0}


func burst(name: String, pos: Vector3, dir := Vector3.UP, scale := 1.0) -> GPUParticles3D:
	if not _pools.has(name):
		return null
	var pool: Dictionary = _pools[name]
	var p: GPUParticles3D = pool.list[pool.i]
	pool.i = (pool.i + 1) % pool.list.size()
	var up := dir.normalized()
	var basis := Basis.IDENTITY
	if absf(up.dot(Vector3.UP)) < 0.999:
		var x := Vector3.UP.cross(up).normalized()
		basis = Basis(x, up, x.cross(up)).orthonormalized()
	elif up.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	p.global_transform = Transform3D(basis.scaled(Vector3.ONE * scale), pos)
	p.restart()
	p.emitting = true
	return p


# ------------------------------------------------------------------ public effects

func muzzle_flash(xf: Transform3D, scale := 1.0) -> void:
	var m := _muzzles[_muzzle_i]
	_muzzle_i = (_muzzle_i + 1) % _muzzles.size()
	m.global_transform = Transform3D(xf.basis.orthonormalized().scaled(Vector3.ONE * scale * randf_range(0.8, 1.2)) * Basis(Vector3(0, 0, 1), randf() * TAU), xf.origin)
	m.visible = true
	_flash(xf.origin, Color(1.0, 0.75, 0.4), 2.5 * scale, 7.0, 0.06)
	get_tree().create_timer(0.045).timeout.connect(func(): m.visible = false)


func tracer(from: Vector3, to: Vector3) -> void:
	var t := _tracers[_tracer_i]
	_tracer_i = (_tracer_i + 1) % _tracers.size()
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var mid := from.lerp(to, 0.5)
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	t.global_transform = Transform3D(Basis.looking_at(to - from, up).scaled(Vector3(1, 1, length)), mid)
	t.visible = true
	get_tree().create_timer(0.05).timeout.connect(func(): t.visible = false)


func _flash(pos: Vector3, col: Color, energy: float, rng: float, dur: float) -> void:
	var l := _flash_lights[_flash_i]
	_flash_i = (_flash_i + 1) % _flash_lights.size()
	l.global_position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.visible = true
	get_tree().create_timer(dur).timeout.connect(func(): l.visible = false)


func impact(pos: Vector3, normal: Vector3, surface: String) -> void:
	match surface:
		C.SURF_METAL:
			burst("sparks", pos, normal, 1.0)
			Audio.play_3d("impact_metal", pos, -6.0, randf_range(0.9, 1.3), 60.0)
		C.SURF_GLASS:
			burst("glass", pos, normal)
			Audio.play_3d("glass", pos, -4.0, randf_range(0.9, 1.2), 60.0)
		C.SURF_FLESH:
			burst("blood", pos, normal)
			Audio.play_3d("impact_flesh", pos, -4.0, randf_range(0.9, 1.1), 50.0)
			return
		C.SURF_WATER:
			burst("splash", pos, Vector3.UP, 0.5)
			return
		C.SURF_WOOD:
			burst("dust", pos, normal, 0.6)
			Audio.play_3d("impact_wood", pos, -6.0, randf_range(0.9, 1.2), 50.0)
		_:
			burst("dust", pos, normal, 0.7)
			burst("sparks", pos, normal, 0.4)
			Audio.play_3d("impact_concrete", pos, -6.0, randf_range(0.8, 1.2), 50.0)
	bullet_hole(pos, normal)


func bullet_hole(pos: Vector3, normal: Vector3, scorch := false, size := 0.22) -> void:
	var d := _decals[_decal_i]
	_decal_i = (_decal_i + 1) % _decals.size()
	var up := normal.normalized()
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	d.global_transform = Transform3D(Basis(x, up, x.cross(up)).orthonormalized().rotated(up, randf() * TAU), pos)
	d.size = Vector3(size, 0.4, size)
	d.texture_albedo = tex_scorch if scorch else tex_hole
	d.visible = true


func explosion(pos: Vector3, scale := 1.0) -> void:
	burst("fire_burst", pos + Vector3(0, 0.5, 0), Vector3.UP, scale)
	burst("smoke_big", pos + Vector3(0, 1.0, 0), Vector3.UP, scale)
	burst("sparks", pos, Vector3.UP, scale * 1.6)
	_flash(pos + Vector3(0, 2, 0), Color(1.0, 0.6, 0.25), 12.0 * scale, 26.0 * scale, 0.25)
	bullet_hole(pos + Vector3(0, 0.05, 0), Vector3.UP, true, 4.0 * scale)
	var fb := _fireballs[_fb_i]
	_fb_i = (_fb_i + 1) % _fireballs.size()
	fb.global_position = pos + Vector3(0, 1.0, 0)
	fb.scale = Vector3.ONE * 0.5
	fb.visible = true
	var mat := fb.material_override as StandardMaterial3D
	mat.albedo_color = Color(1.0, 0.65, 0.25, 0.95)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(fb, "scale", Vector3.ONE * 4.5 * scale, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mat, "albedo_color", Color(0.5, 0.2, 0.08, 0.0), 0.5)
	tw.chain().tween_callback(func(): fb.visible = false)


func splash(pos: Vector3, scale := 1.0) -> void:
	burst("splash", Vector3(pos.x, C.SEA_LEVEL + 0.1, pos.z), Vector3.UP, scale)
	Audio.play_3d("splash", pos, -2.0 + scale * 2.0, randf_range(0.8, 1.1), 80.0)


func tire_smoke(pos: Vector3) -> void:
	burst("tire_smoke", pos, Vector3.UP, 1.0)


func dust_cloud(pos: Vector3, scale := 1.0) -> void:
	burst("dust", pos, Vector3.UP, scale * 2.0)


func water_jet(pos: Vector3) -> void:
	var p := burst("water_jet", pos, Vector3.UP, 1.0)
	if p:
		p.one_shot = false
		p.explosiveness = 0.0
		p.emitting = true
		get_tree().create_timer(18.0).timeout.connect(func():
			p.emitting = false
			p.one_shot = true
			p.explosiveness = 0.92)


## Persistent attached emitter for burning/smoking vehicles. kind: "smoke" | "fire"
func attach_emitter(parent: Node3D, kind: String, offset := Vector3.ZERO) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var qm := QuadMesh.new()
	if kind == "fire":
		p.process_material = _fire_mat()
		(p.process_material as ParticleProcessMaterial).initial_velocity_min = 0.5
		(p.process_material as ParticleProcessMaterial).initial_velocity_max = 2.0
		(p.process_material as ParticleProcessMaterial).emission_sphere_radius = 0.5
		qm.size = Vector2(0.9, 0.9)
		qm.material = _draw_mat(tex_soft, Color(1.0, 0.55, 0.2, 0.9), true)
		p.amount = 40
		p.lifetime = 0.8
	else:
		p.process_material = _smoke_mat(1.6, 4.0)
		qm.size = Vector2(1.2, 1.2)
		qm.material = _draw_mat(tex_soft, Color(0.25, 0.25, 0.26, 0.5), false)
		p.amount = 24
		p.lifetime = 2.2
	p.draw_pass_1 = qm
	p.local_coords = false
	p.position = offset
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 14, 12))
	parent.add_child(p)
	p.emitting = true
	return p
