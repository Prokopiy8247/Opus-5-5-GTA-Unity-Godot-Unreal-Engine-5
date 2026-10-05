class_name ModelLib
extends RefCounted
## Blender-authored static models (res://gta/generated/models/<dir>/<id>.glb) baked into the world's
## batched meshes instead of being instanced one node each. Every GLB surface is routed to the shared
## world surface named by its Blender material "<surface>__<role>" (vc, gloss, metal, glass, emit_warm,
## neon_*...) with the Blender colour as vertex colour, or with the per-instance tint given for <role>
## (house walls, roofs and doors). Collision stays with the callers' simple boxes.

const DIR := "res://gta/generated/models/"
static var _cache := {}


## Parts of a GLB: [{name, xf (relative to the scene root), surfaces: [{key, role, color, v, n, uv}]}].
static func parts(path: String) -> Array:
	if _cache.has(path):
		return _cache[path]
	var out := []
	if ResourceLoader.exists(path):
		var inst := (load(path) as PackedScene).instantiate()
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				out.append({"name": String(mi.name), "xf": _xf_in(inst, mi), "surfaces": _surfaces(mi.mesh)})
		inst.free()
	_cache[path] = out
	return out


static func has(id: String) -> bool:
	return not parts(DIR + id + ".glb").is_empty()


## Bakes model `id` (path under models/ without extension) into the builder at xf. `only` limits the bake
## to parts whose name starts with it (multi-object sets such as the safehouse furniture).
static func bake(mb: MB, id: String, xf: Transform3D, tints := {}, only := "") -> bool:
	var ps := parts(DIR + id + ".glb")
	if ps.is_empty():
		return false
	for p in ps:
		if only != "" and not String(p.name).begins_with(only):
			continue
		var t: Transform3D = xf * p.xf
		for s in p.surfaces:
			mb.append_tris(s.key, s.v, s.n, s.uv, tints.get(s.role, s.color), t)
	return true


static func _xf_in(root: Node, n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## De-indexes each surface once so later bakes are plain array appends.
static func _surfaces(mesh: Mesh) -> Array:
	var res := []
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		var mname := String(m.resource_name) if m else "vc"
		var a := mesh.surface_get_arrays(i)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var uv := PackedVector2Array()
		var count := idx.size() if idx.size() > 0 else vs.size()
		v.resize(count)
		n.resize(count)
		uv.resize(count)
		for k in count:
			var j: int = idx[k] if idx.size() > 0 else k
			v[k] = vs[j]
			n[k] = ns[j]
			if uvs.size() > j:
				uv[k] = uvs[j]
		res.append({"key": mname.get_slice("__", 0), "role": mname.get_slice("__", 1) if mname.contains("__") else "",
			"color": (m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else Color.WHITE, "v": v, "n": n, "uv": uv})
	return res
