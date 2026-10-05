class_name Mats
## Shared material cache. All runtime materials are project-generated.

static var _cache := {}


static func _key(parts: Array) -> String:
	return str(parts)


## Plain coloured material (stylised matte by default).
static func color(c: Color, rough := 0.78, metal := 0.0, key_extra := "") -> StandardMaterial3D:
	var k := _key(["c", c.to_html(), snappedf(rough, 0.01), snappedf(metal, 0.01), key_extra])
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[k] = m
	return m


## Vertex-colour material (used by merged procedural meshes).
static func vc(rough := 0.8, metal := 0.0, spec := 0.5) -> StandardMaterial3D:
	var k := _key(["vc", snappedf(rough, 0.01), snappedf(metal, 0.01), snappedf(spec, 0.01)])
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = spec
	_cache[k] = m
	return m


static func emissive(c: Color, energy := 2.5) -> StandardMaterial3D:
	var k := _key(["e", c.to_html(), snappedf(energy, 0.01)])
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	_cache[k] = m
	return m


static func glass(tint := Color(0.12, 0.16, 0.2, 0.55), rough := 0.05) -> StandardMaterial3D:
	var k := _key(["g", tint.to_html(), rough])
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = rough
	m.metallic = 0.3
	m.metallic_specular = 1.0
	_cache[k] = m
	return m


## Unique (non-cached) material – for things whose parameters change at runtime (vehicle paint, lights).
static func unique(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func unshaded(c: Color, additive := false) -> StandardMaterial3D:
	var k := _key(["u", c.to_html(), additive])
	if _cache.has(k):
		return _cache[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_cache[k] = m
	return m


static var _shader_cache := {}

static func shader(path: String) -> Shader:
	if not _shader_cache.has(path):
		_shader_cache[path] = load(path)
	return _shader_cache[path]


static func shader_mat(path: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(path)
	for p in params:
		m.set_shader_parameter(p, params[p])
	return m
