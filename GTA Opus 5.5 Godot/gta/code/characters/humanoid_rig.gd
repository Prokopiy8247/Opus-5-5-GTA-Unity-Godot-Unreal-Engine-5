class_name HumanoidRig
extends Node3D
## Articulated "designer toy" humanoid: joint hierarchy (gameplay rig) + segmented meshes + procedural
## animation layers + physical ragdoll builder. Faces -Z. A Blender GLB with matching joint names
## (res://gta/generated/models/characters/<variant>.glb) can replace the procedural segments.

const SKIN_TONES := [Color(0.98, 0.84, 0.72), Color(0.93, 0.74, 0.6), Color(0.8, 0.6, 0.45), Color(0.62, 0.43, 0.3), Color(0.45, 0.3, 0.2), Color(0.33, 0.22, 0.15)]
const HAIR_COLS := [Color(0.1, 0.08, 0.06), Color(0.3, 0.2, 0.12), Color(0.55, 0.38, 0.2), Color(0.85, 0.7, 0.45), Color(0.6, 0.6, 0.62), Color(0.7, 0.25, 0.15)]
const CLOTH := [Color(0.85, 0.25, 0.25), Color(0.2, 0.45, 0.75), Color(0.95, 0.95, 0.92), Color(0.15, 0.15, 0.17), Color(0.95, 0.75, 0.2),
	Color(0.3, 0.6, 0.4), Color(0.6, 0.35, 0.65), Color(0.95, 0.55, 0.35), Color(0.4, 0.42, 0.45), Color(0.3, 0.75, 0.75)]
const PANTS := [Color(0.18, 0.22, 0.35), Color(0.12, 0.12, 0.14), Color(0.45, 0.4, 0.32), Color(0.55, 0.55, 0.58), Color(0.3, 0.35, 0.25), Color(0.6, 0.45, 0.3)]

var look := {}
var j := {}                     # joint name -> Node3D
var part_meshes: Array[MeshInstance3D] = []
var hand_socket: Node3D
var hand_l_socket: Node3D
var back_socket: Node3D
var head_mesh: MeshInstance3D
var phase := 0.0
var _t := 0.0
var _cur := {}                  # joint -> current Vector3 euler
var ragdoll_root: Node3D = null
var ragdoll_bodies := {}

# animation inputs (set by owner each frame)
var speed := 0.0
var grounded := true
var crouch := 0.0
var aim := 0.0
var aim_pitch := 0.0
var hold := 0                   # 0 none, 1 one-hand, 2 two-hand long, 3 melee, 4 heavy (shoulder)
var mode := "normal"
var action := ""
var action_t := 0.0
var lean := 0.0
var steer := 0.0
var look_yaw := 0.0
var swim_depth := 0.0
## Aim IK inputs for the held weapon (weapon space: grip at the origin, barrel toward -Z), set by the
## actor when the weapon model changes. ik_aim=false keeps the old FK aim pose (melee, throwables).
var ik_aim := false
var wpn_butt := Vector3(0, 0.05, 0.33)
var wpn_fore := Vector3(0, 0.0, -0.22)
var wpn_long := false
var aim_yaw := 0.0              # extra aim yaw on top of the rig's facing (drive-by)
var _ikq := {}                  # joint -> Quaternion target from the arm IK this frame


static func random_look(rng: RandomNumberGenerator, kind := "civilian") -> Dictionary:
	var female := rng.randf() < 0.5
	var d := {
		"female": female,
		"skin": SKIN_TONES[rng.randi() % SKIN_TONES.size()],
		"hair": HAIR_COLS[rng.randi() % HAIR_COLS.size()],
		"hair_style": (rng.randi_range(2, 4) if female else rng.randi_range(0, 3)),
		"top": CLOTH[rng.randi() % CLOTH.size()],
		"top_style": rng.randi_range(0, 2),
		"pants": PANTS[rng.randi() % PANTS.size()],
		"shoes": [Color(0.1, 0.1, 0.1), Color(0.95, 0.95, 0.95), Color(0.45, 0.3, 0.2), Color(0.8, 0.2, 0.2)][rng.randi() % 4],
		"hat": 0 if rng.randf() < 0.7 else rng.randi_range(1, 2),
		"hat_color": CLOTH[rng.randi() % CLOTH.size()],
		"glasses": 0 if rng.randf() < 0.75 else rng.randi_range(1, 2),
		"beard": 0 if (female or rng.randf() < 0.6) else rng.randi_range(1, 2),
		"build": rng.randf_range(0.92, 1.1),
		"height": rng.randf_range(0.94, 1.06) * (0.96 if female else 1.0),
		"vest": false, "uniform": "", "skirt": female and rng.randf() < 0.3,
	}
	match kind:
		"police":
			d.top = Color(0.16, 0.24, 0.42)
			d.pants = Color(0.12, 0.16, 0.28)
			d.top_style = 4
			d.hat = 3
			d.hat_color = Color(0.12, 0.16, 0.3)
			d.uniform = "police"
			d.skirt = false
		"swat":
			d.top = Color(0.14, 0.15, 0.17)
			d.pants = Color(0.16, 0.17, 0.19)
			d.top_style = 4
			d.hat = 4
			d.hat_color = Color(0.12, 0.13, 0.15)
			d.vest = true
			d.glasses = 1
			d.uniform = "swat"
			d.skirt = false
		"gang":
			d.top = [Color(0.55, 0.1, 0.55), Color(0.1, 0.1, 0.12)][rng.randi() % 2]
			d.top_style = 2
			d.hat = 1
			d.hat_color = Color(0.55, 0.1, 0.55)
			d.skirt = false
		"medic":
			d.top = Color(0.92, 0.95, 0.97)
			d.pants = Color(0.2, 0.5, 0.45)
			d.top_style = 4
			d.uniform = "medic"
			d.skirt = false
		"shop":
			d.top_style = 0
			d.top = Color(0.2, 0.45, 0.4)
	return d


static func player_look() -> Dictionary:
	return {
		"female": false, "skin": SKIN_TONES[2], "hair": HAIR_COLS[0], "hair_style": 1, "top": Color(0.18, 0.48, 0.52),
		"top_style": 1, "pants": Color(0.16, 0.18, 0.24), "shoes": Color(0.92, 0.92, 0.9), "hat": 0, "hat_color": Color(0.2, 0.2, 0.2),
		"glasses": 0, "beard": 1, "build": 1.04, "height": 1.0, "vest": false, "uniform": "", "skirt": false,
	}


func build(appearance: Dictionary) -> void:
	look = appearance
	for c in get_children():
		c.queue_free()
	j.clear()
	part_meshes.clear()
	var s: float = look.get("height", 1.0)
	var b: float = look.get("build", 1.0)
	var fem: bool = look.get("female", false)
	var sw := (0.17 if fem else 0.2) * b      # shoulder half-width
	var hipw := (0.1 if fem else 0.095) * b
	var root := _joint("root", self, Vector3.ZERO)
	var hips := _joint("hips", root, Vector3(0, 0.94 * s, 0))
	var spine := _joint("spine", hips, Vector3(0, 0.1 * s, 0))
	var chest := _joint("chest", spine, Vector3(0, 0.24 * s, 0))
	var neck := _joint("neck", chest, Vector3(0, 0.25 * s, 0))
	var head := _joint("head", neck, Vector3(0, 0.07 * s, 0))
	var sh_l := _joint("shoulder_l", chest, Vector3(-sw, 0.2 * s, 0))
	var el_l := _joint("elbow_l", sh_l, Vector3(0, -0.29 * s, 0))
	var ha_l := _joint("hand_l", el_l, Vector3(0, -0.26 * s, 0))
	var sh_r := _joint("shoulder_r", chest, Vector3(sw, 0.2 * s, 0))
	var el_r := _joint("elbow_r", sh_r, Vector3(0, -0.29 * s, 0))
	var ha_r := _joint("hand_r", el_r, Vector3(0, -0.26 * s, 0))
	var th_l := _joint("thigh_l", hips, Vector3(-hipw, -0.04 * s, 0))
	var kn_l := _joint("knee_l", th_l, Vector3(0, -0.43 * s, 0))
	var an_l := _joint("ankle_l", kn_l, Vector3(0, -0.43 * s, 0))
	var th_r := _joint("thigh_r", hips, Vector3(hipw, -0.04 * s, 0))
	var kn_r := _joint("knee_r", th_r, Vector3(0, -0.43 * s, 0))
	var an_r := _joint("ankle_r", kn_r, Vector3(0, -0.43 * s, 0))
	hand_socket = Node3D.new()
	hand_socket.name = "HandSocket"
	hand_socket.position = Vector3(0, -0.07, 0)
	hand_socket.rotation = Vector3(-PI * 0.5, 0, 0)
	ha_r.add_child(hand_socket)
	hand_l_socket = Node3D.new()
	hand_l_socket.position = Vector3(0, -0.07, 0)
	ha_l.add_child(hand_l_socket)
	back_socket = Node3D.new()
	back_socket.position = Vector3(0, 0.1, 0.16)
	chest.add_child(back_socket)
	if not _try_glb_parts():
		_build_meshes(s, b, fem, sw, hipw)
	for k in j:
		_cur[k] = Vector3.ZERO


func _joint(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = n
	node.position = pos
	parent.add_child(node)
	j[n] = node
	return node


static var _kits := {}   # kit path -> {node name suffix -> Mesh}


static func _kit(path: String) -> Dictionary:
	if not _kits.has(path):
		var d := {}
		var inst := (load(path) as PackedScene).instantiate()
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			d[String(n.name).get_slice("__", 1)] = (n as MeshInstance3D).mesh
		inst.free()
		_kits[path] = d
	return _kits[path]


## Blender character kit (characters/kit_m.glb / kit_f.glb): one mesh per joint segment (M_<joint>) plus
## look overlays (X_<joint>_<variant>). Material slots named chr_* are remapped to this actor's colours.
func _try_glb_parts() -> bool:
	var path := "res://gta/generated/models/characters/%s.glb" % ("kit_f" if look.get("female", false) else "kit_m")
	if not ResourceLoader.exists(path):
		return false
	var kit := _kit(path)
	if not kit.has("M_hips"):
		return false
	var s: float = look.get("height", 1.0)
	var b: float = look.get("build", 1.0)
	var ts: int = look.get("top_style", 0)
	var uni: String = look.get("uniform", "")
	var skin: Color = look.skin
	var top: Color = look.top
	var hat_c: Color = look.get("hat_color", Color(0.2, 0.2, 0.2))
	var sleeve := top if (ts in [0, 1, 2, 3, 4]) else skin
	var vest_col := Color(0.12, 0.13, 0.14) if uni == "swat" else top.darkened(0.15)
	var cols := {"chr_skin": [skin, 0.7], "chr_top": [top, 0.85], "chr_top_dark": [top.darkened(0.25), 0.85], "chr_sleeve": [sleeve, 0.85],
		"chr_pants": [look.pants, 0.85], "chr_shoes": [look.shoes, 0.6], "chr_hand": [Color(0.1, 0.1, 0.1) if uni == "swat" else skin, 0.7],
		"chr_hair": [look.hair, 0.9], "chr_brow": [look.hair, 0.9], "chr_hat": [hat_c, 0.8], "chr_vest": [vest_col, 0.9],
		"chr_mouth": [skin.darkened(0.35), 0.7]}
	var overlays := {"chest": [], "hips": [], "head": []}
	if ts == 1 or ts == 3:
		overlays.chest.append("X_chest_jacket")
	if ts == 2:
		overlays.chest.append("X_chest_hood")
	if look.get("vest", false) or uni == "police":
		overlays.chest.append("X_chest_vest")
	if uni == "police":
		overlays.chest.append("X_chest_badge")
	if look.get("skirt", false):
		overlays.hips.append("X_hips_skirt")
	var hs: int = look.get("hair_style", 1)
	if hs > 0:
		overlays.head.append("X_head_hair%d" % hs)
	if int(look.get("beard", 0)) > 0:
		overlays.head.append("X_head_beard%d" % int(look.beard))
	if int(look.get("hat", 0)) > 0:
		overlays.head.append("X_head_hat%d" % int(look.hat))
	if int(look.get("glasses", 0)) > 0:
		overlays.head.append("X_head_glasses%d" % int(look.glasses))
	for jn in j:
		var mesh: Mesh = kit.get("M_" + jn)
		if mesh == null:
			continue
		var mi := _seg(jn, mesh)
		mi.scale = Vector3(1.0, s, 1.0) if jn == "head" else (Vector3(b, 1.0, b) if jn.begins_with("hand") or jn.begins_with("ankle") else Vector3(b, s, b))
		_paint(mi, cols)
		if jn == "head":
			head_mesh = mi
		for ov in overlays.get(jn, []):
			var om: Mesh = kit.get(ov)
			if om:
				var o := MeshInstance3D.new()
				o.mesh = om
				mi.add_child(o)
				_paint(o, cols)
	return true


static func _paint(mi: MeshInstance3D, cols: Dictionary) -> void:
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m and cols.has(m.resource_name):
			var c: Array = cols[m.resource_name]
			mi.set_surface_override_material(i, Mats.color(c[0], c[1]))


func _seg(joint: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	j[joint].add_child(mi)
	part_meshes.append(mi)
	return mi


func _m(c: Color, rough := 0.85) -> StandardMaterial3D:
	return Mats.color(c, rough)


func _build_meshes(s: float, b: float, fem: bool, sw: float, hipw: float) -> void:
	var skin: Color = look.skin
	var top: Color = look.top
	var pants: Color = look.pants
	var shoes: Color = look.shoes
	var ts: int = look.get("top_style", 0)
	var sleeve_long := ts in [1, 2, 3, 4]
	# pelvis
	var mb := MB.new()
	mb.use("p").col(Color.WHITE)
	mb.prism(Vector3(0, -0.1 * s, 0), 0.2 * s, Vector2(hipw + 0.08, 0.1) * b, Vector2(hipw + 0.07, 0.1) * b, 0.04)
	if look.get("skirt", false):
		mb.prism(Vector3(0, -0.3 * s, 0), 0.25 * s, Vector2(hipw + 0.14, 0.15) * b, Vector2(hipw + 0.08, 0.11) * b, 0.04)
	_seg("hips", mb.commit({"p": _m(pants)}))
	# abdomen + chest (top)
	mb = MB.new()
	mb.use("t").col(Color.WHITE)
	mb.prism(Vector3(0, -0.02, 0), 0.26 * s, Vector2(sw - 0.05, 0.1) * Vector2(1, b), Vector2(sw - 0.02, 0.11) * Vector2(1, b), 0.04)
	_seg("spine", mb.commit({"t": _m(top)}))
	mb = MB.new()
	mb.use("t").col(Color.WHITE)
	var chest_w := sw + (0.02 if not fem else 0.0)
	mb.prism(Vector3(0, -0.02, 0), 0.27 * s, Vector2(chest_w - 0.02, 0.115) * Vector2(1, b), Vector2(chest_w + 0.03, 0.105) * Vector2(1, b), 0.05)
	if fem:
		mb.box(Vector3(0, 0.1 * s, -0.1 * b), Vector3(chest_w * 1.3, 0.1, 0.06), 0.03)
	if ts == 1 or ts == 3:
		# jacket: open front lapels + collar
		mb.use("j").col(Color.WHITE)
		mb.box(Vector3(-chest_w * 0.55, 0.12 * s, -0.11 * b), Vector3(0.08, 0.26 * s, 0.02))
		mb.box(Vector3(chest_w * 0.55, 0.12 * s, -0.11 * b), Vector3(0.08, 0.26 * s, 0.02))
		mb.box(Vector3(0, 0.25 * s, 0.02), Vector3(chest_w * 1.4, 0.06, 0.2), 0.02)
	if ts == 2:
		mb.use("j").col(Color.WHITE)
		mb.box(Vector3(0, 0.22 * s, 0.1), Vector3(chest_w * 1.2, 0.12, 0.1), 0.04)   # hood
	if look.get("vest", false) or look.get("uniform", "") == "police":
		mb.use("v").col(Color.WHITE)
		mb.prism(Vector3(0, 0.0, 0), 0.24 * s, Vector2(chest_w + 0.01, 0.13) * Vector2(1, b), Vector2(chest_w + 0.03, 0.125) * Vector2(1, b), 0.04)
	if look.get("uniform", "") == "police":
		mb.use("badge").col(Color.WHITE)
		mb.box(Vector3(-chest_w * 0.45, 0.16 * s, -0.135 * b), Vector3(0.05, 0.06, 0.01))
	var vest_col := Color(0.12, 0.13, 0.14) if look.get("uniform", "") == "swat" else top.darkened(0.15)
	_seg("chest", mb.commit({"t": _m(top), "j": _m(top.darkened(0.25)), "v": _m(vest_col, 0.9), "badge": Mats.color(Color(0.95, 0.8, 0.3), 0.3, 0.8)}))
	# neck & head
	mb = MB.new()
	mb.use("s").col(Color.WHITE)
	mb.cylinder(Vector3(0, -0.02, 0), 0.055 * b, 0.1 * s, 8)
	_seg("neck", mb.commit({"s": _m(skin)}))
	head_mesh = _seg("head", _head_mesh(s, fem))
	# arms
	for side in ["l", "r"]:
		mb = MB.new()
		mb.use("u").col(Color.WHITE)
		mb.prism(Vector3(0, -0.29 * s, 0), 0.31 * s, Vector2(0.05, 0.05) * b, Vector2(0.065, 0.065) * b, 0.02)
		_seg("shoulder_" + side, mb.commit({"u": _m(top if (sleeve_long or ts == 0) else skin)}))
		mb = MB.new()
		mb.use("f").col(Color.WHITE)
		mb.prism(Vector3(0, -0.26 * s, 0), 0.27 * s, Vector2(0.04, 0.04) * b, Vector2(0.05, 0.05) * b, 0.015)
		_seg("elbow_" + side, mb.commit({"f": _m(top if (sleeve_long or ts == 0) else skin)}))
		mb = MB.new()
		mb.use("h").col(Color.WHITE)
		mb.box(Vector3(0, -0.06, -0.005), Vector3(0.075, 0.11, 0.045) * b, 0.015)
		mb.box(Vector3(0.0, -0.025, -0.04), Vector3(0.03, 0.06, 0.03) * b)
		var glove: bool = look.get("uniform", "") == "swat"
		_seg("hand_" + side, mb.commit({"h": _m(Color(0.1, 0.1, 0.1) if glove else skin)}))
		# legs
		mb = MB.new()
		mb.use("p").col(Color.WHITE)
		mb.prism(Vector3(0, -0.43 * s, 0), 0.45 * s, Vector2(0.06, 0.065) * b, Vector2(0.085, 0.09) * b, 0.025)
		_seg("thigh_" + side, mb.commit({"p": _m(pants)}))
		mb = MB.new()
		mb.use("p").col(Color.WHITE)
		mb.prism(Vector3(0, -0.42 * s, 0), 0.43 * s, Vector2(0.05, 0.05) * b, Vector2(0.065, 0.065) * b, 0.02)
		_seg("knee_" + side, mb.commit({"p": _m(pants)}))
		# note: ankle mesh (shoes) is built below in the same loop
		mb = MB.new()
		mb.use("sh").col(Color.WHITE)
		mb.box(Vector3(0, -0.04, -0.05), Vector3(0.11, 0.08, 0.26) * Vector3(b, 1, 1), 0.03)
		_seg("ankle_" + side, mb.commit({"sh": _m(shoes, 0.6)}))


func _head_mesh(s: float, fem: bool) -> ArrayMesh:
	var skin: Color = look.skin
	var hair: Color = look.hair
	var mb := MB.new()
	mb.use("s").col(Color.WHITE)
	mb.prism(Vector3(0, 0.0, 0), 0.25 * s, Vector2(0.095, 0.105), Vector2(0.1, 0.11), 0.045)
	mb.box(Vector3(0, 0.1 * s, -0.112), Vector3(0.03, 0.05, 0.03))           # nose
	mb.box(Vector3(-0.1, 0.12 * s, 0.0), Vector3(0.02, 0.05, 0.035))         # ears
	mb.box(Vector3(0.1, 0.12 * s, 0.0), Vector3(0.02, 0.05, 0.035))
	mb.use("e").col(Color.WHITE)
	mb.box(Vector3(-0.04, 0.135 * s, -0.108), Vector3(0.028, 0.022, 0.01))
	mb.box(Vector3(0.04, 0.135 * s, -0.108), Vector3(0.028, 0.022, 0.01))
	mb.use("m").col(Color.WHITE)
	mb.box(Vector3(0, 0.055 * s, -0.107), Vector3(0.05, 0.012, 0.01))
	# hair
	var hs: int = look.get("hair_style", 1)
	mb.use("hair").col(Color.WHITE)
	match hs:
		1:
			mb.prism(Vector3(0, 0.19 * s, 0.005), 0.08, Vector2(0.105, 0.118), Vector2(0.09, 0.1), 0.04)
		2:
			mb.prism(Vector3(0, 0.17 * s, 0.01), 0.1, Vector2(0.108, 0.12), Vector2(0.09, 0.1), 0.04)
			mb.box(Vector3(0, 0.06 * s, 0.07), Vector3(0.21, 0.24, 0.08), 0.03)
		3:
			mb.prism(Vector3(0, 0.18 * s, 0.01), 0.08, Vector2(0.106, 0.118), Vector2(0.09, 0.1), 0.04)
			mb.sphere(Vector3(0, 0.26 * s, 0.08), 0.06, 6, 4)
		4:
			mb.prism(Vector3(0, 0.17 * s, 0.01), 0.1, Vector2(0.108, 0.12), Vector2(0.09, 0.1), 0.04)
			mb.box(Vector3(0, 0.0, 0.1), Vector3(0.2, 0.36, 0.05), 0.02)
		5:
			mb.box(Vector3(0, 0.27 * s, 0.0), Vector3(0.03, 0.08, 0.2))
	var beard: int = look.get("beard", 0)
	if beard > 0:
		mb.box(Vector3(0, 0.03 * s, -0.08), Vector3(0.18, 0.06 if beard == 1 else 0.1, 0.06), 0.02)
	# hats
	var hat: int = look.get("hat", 0)
	mb.use("hat").col(Color.WHITE)
	match hat:
		1:
			mb.prism(Vector3(0, 0.2 * s, 0.0), 0.08, Vector2(0.11, 0.12), Vector2(0.1, 0.11), 0.04)
			mb.box(Vector3(0, 0.205 * s, -0.16), Vector3(0.19, 0.02, 0.12))
		2:
			mb.prism(Vector3(0, 0.19 * s, 0.0), 0.11, Vector2(0.11, 0.12), Vector2(0.085, 0.095), 0.04)
		3:
			mb.prism(Vector3(0, 0.2 * s, 0.0), 0.07, Vector2(0.11, 0.12), Vector2(0.125, 0.135), 0.03)
			mb.box(Vector3(0, 0.205 * s, -0.15), Vector3(0.2, 0.02, 0.1))
		4:
			mb.prism(Vector3(0, 0.12 * s, 0.0), 0.17, Vector2(0.125, 0.135), Vector2(0.1, 0.11), 0.05)
	var g: int = look.get("glasses", 0)
	if g > 0:
		mb.use("gl").col(Color.WHITE)
		mb.box(Vector3(0, 0.135 * s, -0.118), Vector3(0.17, 0.04, 0.012))
	var hat_c: Color = look.get("hat_color", Color(0.2, 0.2, 0.2))
	return mb.commit({"s": _m(skin, 0.7), "e": Mats.color(Color(0.08, 0.08, 0.1), 0.3), "m": _m(skin.darkened(0.35)),
		"hair": _m(hair, 0.9), "hat": _m(hat_c, 0.8), "gl": Mats.color(Color(0.05, 0.05, 0.06), 0.15, 0.6) if g == 1 else Mats.color(Color(0.6, 0.7, 0.8, 0.5), 0.1, 0.3)})


func set_head_visible(v: bool) -> void:
	if head_mesh:
		head_mesh.visible = v


# ------------------------------------------------------------------ animation

const LIMBS := {"shoulder_l": 1, "shoulder_r": 1, "elbow_l": 1, "elbow_r": 1, "hand_l": 1, "hand_r": 1,
	"thigh_l": 1, "thigh_r": 1, "knee_l": 1, "knee_r": 1, "ankle_l": 1, "ankle_r": 1}

## Limb targets are authored with "negative X = swing forward"; limbs hang along -Y so the
## engine convention is the opposite – flip X for limb joints here.
func _set_joint(jn: String, target: Vector3, rate: float, dt: float) -> void:
	if LIMBS.has(jn):
		target.x = -target.x
	var cur: Vector3 = _cur.get(jn, Vector3.ZERO)
	cur = cur.lerp(target, 1.0 - exp(-rate * dt))
	_cur[jn] = cur
	j[jn].rotation = cur


func play_action(a: String) -> void:
	action = a
	action_t = 0.0


func update_pose(dt: float) -> void:
	if ragdoll_root != null or j.is_empty():
		return
	_t += dt
	if action != "":
		action_t += dt
		if action_t > _action_len(action):
			action = ""
	var tg := {}
	for k in j:
		tg[k] = Vector3.ZERO
	var rate := 14.0
	var hip_y := 0.0
	var hip_x_tilt := 0.0
	match mode:
		"swim", "dive":
			var sp := clampf(speed / 2.0, 0.2, 1.0)
			phase += dt * (3.0 + sp * 3.0)
			var flat := 1.35 if mode == "dive" or speed > 0.4 else 0.35
			tg.root = Vector3(-flat, 0, 0)
			tg.shoulder_l = Vector3(-PI * 0.5 - sin(phase) * 1.4, 0, -0.3)
			tg.shoulder_r = Vector3(-PI * 0.5 - sin(phase + PI) * 1.4, 0, 0.3)
			tg.elbow_l = Vector3(-0.4, 0, 0)
			tg.elbow_r = Vector3(-0.4, 0, 0)
			tg.thigh_l = Vector3(sin(phase * 2.0) * 0.4, 0, 0)
			tg.thigh_r = Vector3(-sin(phase * 2.0) * 0.4, 0, 0)
			tg.knee_l = Vector3(0.3, 0, 0)
			tg.knee_r = Vector3(0.3, 0, 0)
			tg.neck = Vector3(flat * 0.6, 0, 0)
			rate = 8.0
		"drive":
			tg.thigh_l = Vector3(-1.45, 0, -0.08)
			tg.thigh_r = Vector3(-1.45, 0, 0.08)
			tg.knee_l = Vector3(1.4, 0, 0)
			tg.knee_r = Vector3(1.4, 0, 0)
			tg.shoulder_l = Vector3(-1.05, 0, -0.15 + steer * 0.3)
			tg.shoulder_r = Vector3(-1.05, 0, 0.15 + steer * 0.3)
			tg.elbow_l = Vector3(-0.7, 0, 0)
			tg.elbow_r = Vector3(-0.7, 0, 0)
			tg.chest = Vector3(0, steer * 0.1, 0)
			hip_y = -0.45
			if aim > 0.5:
				_aim_arms(tg, 1)
		"ride":
			tg.thigh_l = Vector3(-1.1, 0, -0.35)
			tg.thigh_r = Vector3(-1.1, 0, 0.35)
			tg.knee_l = Vector3(1.6, 0, 0)
			tg.knee_r = Vector3(1.6, 0, 0)
			tg.spine = Vector3(-0.35, 0, 0)
			tg.shoulder_l = Vector3(-1.2, 0, -0.25)
			tg.shoulder_r = Vector3(-1.2, 0, 0.25)
			tg.elbow_l = Vector3(-0.4, 0, 0)
			tg.elbow_r = Vector3(-0.4, 0, 0)
			tg.root = Vector3(0, 0, -steer * 0.35)
			hip_y = -0.32
			if aim > 0.5:
				_aim_arms(tg, 1)
		"sit":
			tg.thigh_l = Vector3(-1.5, 0, 0)
			tg.thigh_r = Vector3(-1.5, 0, 0)
			tg.knee_l = Vector3(1.5, 0, 0)
			tg.knee_r = Vector3(1.5, 0, 0)
			tg.shoulder_l = Vector3(-0.3, 0, -0.1)
			tg.shoulder_r = Vector3(-0.3, 0, 0.1)
			hip_y = -0.45
		"fall":
			phase += dt * 6.0
			tg.shoulder_l = Vector3(-2.4 + sin(phase) * 0.4, 0, -0.6)
			tg.shoulder_r = Vector3(-2.4 + sin(phase + 1.0) * 0.4, 0, 0.6)
			tg.thigh_l = Vector3(sin(phase) * 0.5 - 0.3, 0, 0)
			tg.thigh_r = Vector3(-sin(phase) * 0.5 - 0.3, 0, 0)
			tg.knee_l = Vector3(0.6, 0, 0)
			tg.knee_r = Vector3(0.6, 0, 0)
			rate = 8.0
		"skydive":
			tg.root = Vector3(-1.3, 0, 0)
			tg.shoulder_l = Vector3(-1.4, 0, -1.2)
			tg.shoulder_r = Vector3(-1.4, 0, 1.2)
			tg.thigh_l = Vector3(0.3, 0, -0.25)
			tg.thigh_r = Vector3(0.3, 0, 0.25)
			tg.knee_l = Vector3(0.6, 0, 0)
			tg.knee_r = Vector3(0.6, 0, 0)
			tg.neck = Vector3(0.9, 0, 0)
		"parachute":
			tg.shoulder_l = Vector3(-2.7, 0, -0.35)
			tg.shoulder_r = Vector3(-2.7, 0, 0.35)
			tg.elbow_l = Vector3(-0.5, 0, 0)
			tg.elbow_r = Vector3(-0.5, 0, 0)
			tg.thigh_l = Vector3(-0.15 + sin(_t * 2.0) * 0.1, 0, 0)
			tg.thigh_r = Vector3(-0.1 - sin(_t * 2.0) * 0.1, 0, 0)
			tg.root = Vector3(0, 0, -steer * 0.25)
		"ladder":
			phase += dt * speed * 4.0
			var s1 := sin(phase)
			tg.shoulder_l = Vector3(-2.3 + s1 * 0.35, 0, 0)
			tg.shoulder_r = Vector3(-2.3 - s1 * 0.35, 0, 0)
			tg.elbow_l = Vector3(-0.6, 0, 0)
			tg.elbow_r = Vector3(-0.6, 0, 0)
			tg.thigh_l = Vector3(-0.7 - s1 * 0.4, 0, 0)
			tg.thigh_r = Vector3(-0.7 + s1 * 0.4, 0, 0)
			tg.knee_l = Vector3(1.0 + s1 * 0.3, 0, 0)
			tg.knee_r = Vector3(1.0 - s1 * 0.3, 0, 0)
		"handsup":
			tg.shoulder_l = Vector3(-2.8, 0, -0.3)
			tg.shoulder_r = Vector3(-2.8, 0, 0.3)
			tg.elbow_l = Vector3(-0.4, 0, 0)
			tg.elbow_r = Vector3(-0.4, 0, 0)
		"cower":
			tg.thigh_l = Vector3(-1.9, 0, -0.2)
			tg.thigh_r = Vector3(-1.9, 0, 0.2)
			tg.knee_l = Vector3(2.2, 0, 0)
			tg.knee_r = Vector3(2.2, 0, 0)
			tg.spine = Vector3(-0.6, 0, 0)
			tg.shoulder_l = Vector3(-2.6, 0, -0.5)
			tg.shoulder_r = Vector3(-2.6, 0, 0.5)
			tg.elbow_l = Vector3(-2.0, 0, 0)
			tg.elbow_r = Vector3(-2.0, 0, 0)
			hip_y = -0.5
		"phone":
			_locomotion(tg, dt)
			tg.shoulder_r = Vector3(-0.4, 0, 0.6)
			tg.elbow_r = Vector3(-2.4, 0, 0)
		"lying":
			tg.root = Vector3(-PI * 0.5, 0, 0)
			hip_y = -0.8
		_:
			_locomotion(tg, dt)
			if crouch > 0.01:
				hip_y -= 0.38 * crouch
				tg.thigh_l = tg.thigh_l + Vector3(-1.0, 0, 0) * crouch
				tg.thigh_r = tg.thigh_r + Vector3(-1.0, 0, 0) * crouch
				tg.knee_l = tg.knee_l + Vector3(1.6, 0, 0) * crouch
				tg.knee_r = tg.knee_r + Vector3(1.6, 0, 0) * crouch
				tg.ankle_l = tg.ankle_l + Vector3(-0.6, 0, 0) * crouch
				tg.ankle_r = tg.ankle_r + Vector3(-0.6, 0, 0) * crouch
				tg.spine = tg.spine + Vector3(-0.35, 0, 0) * crouch
			tg.chest = tg.chest + Vector3(0, 0, -lean * 0.4)
			tg.root = tg.root + Vector3(0, 0, -lean * 0.12)
			if aim > 0.05:
				_aim_arms(tg, hold)
			elif hold == 2 or hold == 4:
				# carry long gun across the body
				tg.shoulder_r = Vector3(-0.5, 0, 0.15)
				tg.elbow_r = Vector3(-1.2, 0, 0)
				tg.shoulder_l = Vector3(-0.7, 0, -0.35)
				tg.elbow_l = Vector3(-1.4, 0.3, 0)
	_apply_action(tg)
	if hold == 0 and aim > 0.5 and mode == "normal":
		# fists up (melee stance)
		tg.shoulder_l = Vector3(-1.2, 0, -0.25)
		tg.elbow_l = Vector3(-2.0, 0, 0)
		tg.shoulder_r = Vector3(-1.1, 0, 0.25)
		tg.elbow_r = Vector3(-2.1, 0, 0)
	tg.head = tg.head + Vector3(0, clampf(look_yaw, -1.0, 1.0), 0)
	var w := 1.0 - exp(-rate * dt)
	for k in tg:
		if _ikq.has(k) and action == "":
			# IK joints blend as quaternions (the arm poses sit near the YXZ gimbal lock)
			var jn: Node3D = j[k]
			jn.quaternion = jn.quaternion.slerp(_ikq[k], w)
			_cur[k] = jn.rotation
		else:
			_set_joint(k, tg[k], rate, dt)
	_ikq.clear()
	var hips: Node3D = j.hips
	var base_y: float = 0.94 * float(look.get("height", 1.0))
	hips.position.y = lerpf(hips.position.y, base_y + hip_y, 1.0 - exp(-12.0 * dt))


func _locomotion(tg: Dictionary, dt: float) -> void:
	var sp := speed
	if not grounded and mode == "normal":
		tg.thigh_l = Vector3(-0.6, 0, 0)
		tg.thigh_r = Vector3(0.2, 0, 0)
		tg.knee_l = Vector3(0.9, 0, 0)
		tg.knee_r = Vector3(0.5, 0, 0)
		tg.shoulder_l = Vector3(-0.6, 0, -0.4)
		tg.shoulder_r = Vector3(-0.6, 0, 0.4)
		return
	var stride := clampf(sp / 6.5, 0.0, 1.0)
	phase += dt * (sp * 1.55 + (0.0 if sp > 0.1 else 0.0))
	var s := sin(phase * PI * 0.5 * 1.3)
	var c := cos(phase * PI * 0.5 * 1.3)
	var amp := lerpf(0.0, 0.85, stride)
	tg.thigh_l = Vector3(s * amp, 0, 0)
	tg.thigh_r = Vector3(-s * amp, 0, 0)
	tg.knee_l = Vector3(maxf(0.0, c) * amp * 1.4 + 0.05, 0, 0)
	tg.knee_r = Vector3(maxf(0.0, -c) * amp * 1.4 + 0.05, 0, 0)
	tg.ankle_l = Vector3(-s * amp * 0.3, 0, 0)
	tg.ankle_r = Vector3(s * amp * 0.3, 0, 0)
	tg.shoulder_l = Vector3(-s * amp * 0.9, 0, -0.08)
	tg.shoulder_r = Vector3(s * amp * 0.9, 0, 0.08)
	tg.elbow_l = Vector3(-0.25 - stride * 0.9, 0, 0)
	tg.elbow_r = Vector3(-0.25 - stride * 0.9, 0, 0)
	tg.spine = Vector3(-stride * 0.22, s * 0.08 * stride, 0)
	tg.chest = Vector3(0, -s * 0.12 * stride, 0)
	if sp < 0.1:
		var br := sin(_t * 1.8) * 0.02
		tg.chest = Vector3(br, 0, 0)
		tg.shoulder_l = Vector3(0.0, 0, -0.06)
		tg.shoulder_r = Vector3(0.0, 0, 0.06)
		tg.elbow_l = Vector3(-0.15, 0, 0)
		tg.elbow_r = Vector3(-0.15, 0, 0)
	var hips: Node3D = j.hips
	hips.position.x = 0.0
	tg.hips = Vector3(0, s * 0.1 * stride, 0)


func _aim_arms(tg: Dictionary, h: int) -> void:
	var p := aim_pitch
	if ik_aim and h in [1, 2, 4]:
		_aim_ik(tg, h)
		return
	match h:
		1:
			tg.shoulder_r = Vector3(-PI * 0.5 + p, 0.0, 0.1)
			tg.elbow_r = Vector3(0.0, 0, 0)
			tg.shoulder_l = Vector3(-PI * 0.5 + p + 0.1, 0.0, -0.55)
			tg.elbow_l = Vector3(-0.25, 0.0, 0.0)
			tg.chest = Vector3(0, -0.15, 0)
		2, 4:
			tg.shoulder_r = Vector3(-PI * 0.5 + p + 0.1, 0.0, 0.35)
			tg.elbow_r = Vector3(-0.9, 0, 0)
			tg.shoulder_l = Vector3(-PI * 0.5 + p + 0.15, 0.0, -0.75)
			tg.elbow_l = Vector3(-0.35, 0.0, 0)
			tg.chest = Vector3(0, -0.35, 0)
			if h == 4:
				tg.shoulder_r = Vector3(-PI * 0.5 + p - 0.3, 0.0, 0.5)
				tg.elbow_r = Vector3(-1.6, 0, 0)
		3:
			tg.shoulder_r = Vector3(-1.4, 0, 0.6)
			tg.elbow_r = Vector3(-1.5, 0, 0)
	tg.neck = Vector3(-p * 0.5, 0, 0)


## Two-handed aim pose by analytic IK: the torso takes most of the pitch, the gun is placed so it
## points exactly along the aim (stock in the shoulder pocket for long guns, on top of the shoulder
## for launchers, at arm's length for handguns) and both arms are solved to reach it.
func _aim_ik(tg: Dictionary, h: int) -> void:
	var s: float = look.get("height", 1.0)
	var p := clampf(aim_pitch, -1.2, 1.2)
	var twist := -0.15 if h == 1 else -0.5
	tg.spine = tg.spine + Vector3(-p * 0.35, 0, 0)
	tg.chest = Vector3(-p * 0.35, twist, tg.chest.z)
	tg.neck = Vector3(-p * 0.25, -twist * 0.8, 0)
	# aim direction in the chest frame, from the target chain (exact once the pose has settled)
	var chain := Basis.from_euler(tg.root) * Basis.from_euler(tg.hips) * Basis.from_euler(tg.spine) * Basis.from_euler(tg.chest)
	var aim_dir := Basis(Vector3.UP, aim_yaw) * (Basis(Vector3.RIGHT, -p) * Vector3.FORWARD)
	var d := (chain.inverse() * aim_dir).normalized()
	var wb := Basis.looking_at(d, Vector3.UP)
	var sw: float = absf((j.shoulder_r as Node3D).position.x)
	var grip: Vector3
	var pole_r := Vector3(1.0, -0.7, 0.15)
	var pole_l := Vector3(-0.35, -1.0, 0.1)
	match h:
		2:
			grip = Vector3(sw * 0.7, 0.2 * s - 0.02, -0.08) - wb * wpn_butt
		4:
			grip = Vector3(sw * 0.8, 0.2 * s + 0.09, 0.02) - wb * Vector3(0, 0.12, 0.1)
			pole_r = Vector3(1.0, -0.5, 0.3)
		_:
			grip = Vector3(sw * 0.2, 0.27 * s, (-0.36 if wpn_long else -0.47) * s)
			pole_r = Vector3(0.5, -1.0, 0.0)
			pole_l = Vector3(-0.5, -1.0, 0.0)
	# right hand holds the grip through the socket (-90 deg about X): wrist sits 0.07 m behind it
	_ik_arm("r", grip - d * 0.07, pole_r, wb * Basis(Vector3.RIGHT, PI * 0.5))
	# support hand under the fore-end, fingers wrapping up its right side, thumb along the barrel
	var fingers := (wb.y * 0.75 + wb.x * 0.66).normalized()
	var fore := grip + wb * wpn_fore
	var y_ax := -fingers
	var z_ax := -d
	_ik_arm("l", fore - fingers * 0.07 - wb.y * 0.02, pole_l, Basis(y_ax.cross(z_ax), y_ax, z_ax))


## Analytic two-bone IK for one arm in the chest frame. Limbs hang along -Y and the elbow hinges
## about local X (positive bends the forearm toward local -Z); `pole` picks the elbow side.
func _ik_arm(side: String, wrist: Vector3, pole: Vector3, hand: Basis) -> void:
	var sh: Vector3 = (j["shoulder_" + side] as Node3D).position
	var l1: float = (j["elbow_" + side] as Node3D).position.length()
	var l2: float = (j["hand_" + side] as Node3D).position.length()
	var v := wrist - sh
	var dist := clampf(v.length(), 0.08, l1 + l2 - 0.002)
	var dir := v.normalized()
	var a := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var bend := PI - acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
	var side_v := pole - dir * pole.dot(dir)
	if side_v.length_squared() < 1e-6:
		side_v = Vector3.DOWN - dir * dir.dot(Vector3.DOWN)
	side_v = side_v.normalized()
	var upper := (dir * cos(a) + side_v * sin(a)).normalized()
	var fore_dir := (sh + dir * dist - (sh + upper * l1)).normalized()
	var perp := fore_dir - upper * fore_dir.dot(upper)
	perp = (perp if perp.length_squared() > 1e-6 else -side_v).normalized()
	var y_ax := -upper
	var z_ax := -perp
	var bu := Basis(y_ax.cross(z_ax), y_ax, z_ax).orthonormalized()
	var bf := bu * Basis(Vector3.RIGHT, bend)
	_ikq["shoulder_" + side] = bu.get_rotation_quaternion()
	_ikq["elbow_" + side] = Quaternion(Vector3.RIGHT, bend)
	_ikq["hand_" + side] = (bf.inverse() * hand.orthonormalized()).get_rotation_quaternion()


func _action_len(a: String) -> float:
	match a:
		"punch": return 0.32
		"punch2": return 0.32
		"heavy": return 0.6
		"kick": return 0.55
		"swing": return 0.45
		"reload": return 1.4
		"throw": return 0.5
		"takedown": return 0.9
		"hit": return 0.3
		"enter": return 0.6
		"jack": return 0.9
		"vault": return 0.5
		"roll": return 0.6
		"block": return 0.4
	return 0.5


func _apply_action(tg: Dictionary) -> void:
	if action == "":
		return
	var t := action_t / _action_len(action)
	var k := sin(clampf(t, 0.0, 1.0) * PI)
	match action:
		"punch":
			tg.shoulder_r = Vector3(-1.55 * k - 0.2, 0, 0.1)
			tg.elbow_r = Vector3(-1.6 * (1.0 - k), 0, 0)
			tg.chest = Vector3(0, -0.4 * k, 0)
		"punch2":
			tg.shoulder_l = Vector3(-1.55 * k - 0.2, 0, -0.1)
			tg.elbow_l = Vector3(-1.6 * (1.0 - k), 0, 0)
			tg.chest = Vector3(0, 0.4 * k, 0)
		"heavy", "takedown":
			var wind := clampf(t * 2.5, 0.0, 1.0)
			var hit := clampf((t - 0.4) * 3.0, 0.0, 1.0)
			tg.shoulder_r = Vector3(-0.3 - 2.2 * wind + 1.5 * hit, 0, 0.6 - 0.5 * hit)
			tg.elbow_r = Vector3(-1.4 + hit, 0, 0)
			tg.chest = Vector3(0.1 * hit, 0.6 * wind - 1.0 * hit, 0)
		"kick":
			tg.thigh_r = Vector3(-1.4 * k, 0, 0)
			tg.knee_r = Vector3(0.4 * (1.0 - k), 0, 0)
			tg.spine = Vector3(0.25 * k, 0, 0)
		"swing":
			var w2 := clampf(t * 3.0, 0.0, 1.0)
			var h2 := clampf((t - 0.3) * 2.5, 0.0, 1.0)
			tg.shoulder_r = Vector3(-1.2 - 0.8 * w2 + 1.0 * h2, 0.0, 0.9 - 1.6 * h2)
			tg.elbow_r = Vector3(-0.8 + 0.6 * h2, 0, 0)
			tg.chest = Vector3(0, 0.8 * w2 - 1.6 * h2, 0)
		"reload":
			tg.shoulder_l = Vector3(-0.9, 0, -0.2)
			tg.elbow_l = Vector3(-1.6 + sin(t * TAU * 2.0) * 0.3, 0, 0)
			tg.shoulder_r = Vector3(-0.8, 0, 0.2)
			tg.elbow_r = Vector3(-1.2, 0, 0)
		"throw":
			tg.shoulder_r = Vector3(-2.6 + 2.4 * clampf(t * 1.6, 0.0, 1.0), 0, 0.3)
			tg.elbow_r = Vector3(-1.0 * (1.0 - t), 0, 0)
		"hit":
			tg.spine = Vector3(0.3 * k, 0, 0)
			tg.neck = Vector3(0.4 * k, 0, 0)
		"enter", "jack":
			tg.shoulder_r = Vector3(-1.4 * k, 0, 0.3)
			tg.shoulder_l = Vector3(-1.2 * k, 0, -0.3)
		"vault":
			tg.shoulder_l = Vector3(-1.2 * k, 0, -0.2)
			tg.shoulder_r = Vector3(-1.2 * k, 0, 0.2)
			tg.thigh_l = Vector3(-1.4 * k, 0, 0)
			tg.thigh_r = Vector3(-1.0 * k, 0, 0)
			tg.knee_l = Vector3(1.6 * k, 0, 0)
			tg.knee_r = Vector3(1.2 * k, 0, 0)
		"roll":
			tg.root = Vector3(-TAU * clampf(t, 0.0, 1.0), 0, 0)
			tg.spine = Vector3(-1.0 * k, 0, 0)
			tg.thigh_l = Vector3(-2.0 * k, 0, 0)
			tg.thigh_r = Vector3(-2.0 * k, 0, 0)
			tg.knee_l = Vector3(2.2 * k, 0, 0)
			tg.knee_r = Vector3(2.2 * k, 0, 0)
		"block":
			tg.shoulder_l = Vector3(-2.0, 0, -0.1)
			tg.shoulder_r = Vector3(-2.0, 0, 0.1)
			tg.elbow_l = Vector3(-2.2, 0, 0)
			tg.elbow_r = Vector3(-2.2, 0, 0)


# ------------------------------------------------------------------ ragdoll

const RAG_PARTS := {
	# joint: [parent_body_joint, half_size, centre offset (local, down the bone)]
	"hips": ["", Vector3(0.16, 0.1, 0.1), Vector3(0, -0.02, 0)],
	"chest": ["hips", Vector3(0.18, 0.22, 0.11), Vector3(0, -0.05, 0)],
	"head": ["chest", Vector3(0.1, 0.13, 0.11), Vector3(0, 0.12, 0)],
	"shoulder_l": ["chest", Vector3(0.06, 0.15, 0.06), Vector3(0, -0.15, 0)],
	"elbow_l": ["shoulder_l", Vector3(0.05, 0.16, 0.05), Vector3(0, -0.16, 0)],
	"shoulder_r": ["chest", Vector3(0.06, 0.15, 0.06), Vector3(0, -0.15, 0)],
	"elbow_r": ["shoulder_r", Vector3(0.05, 0.16, 0.05), Vector3(0, -0.16, 0)],
	"thigh_l": ["hips", Vector3(0.08, 0.21, 0.08), Vector3(0, -0.21, 0)],
	"knee_l": ["thigh_l", Vector3(0.06, 0.24, 0.07), Vector3(0, -0.24, 0)],
	"thigh_r": ["hips", Vector3(0.08, 0.21, 0.08), Vector3(0, -0.21, 0)],
	"knee_r": ["thigh_r", Vector3(0.06, 0.24, 0.07), Vector3(0, -0.24, 0)],
}
# which joints' meshes go with each ragdoll body
const RAG_GROUPS := {
	"hips": ["hips"], "chest": ["spine", "chest", "neck"], "head": ["head"],
	"shoulder_l": ["shoulder_l"], "elbow_l": ["elbow_l", "hand_l"], "shoulder_r": ["shoulder_r"], "elbow_r": ["elbow_r", "hand_r"],
	"thigh_l": ["thigh_l"], "knee_l": ["knee_l", "ankle_l"], "thigh_r": ["thigh_r"], "knee_r": ["knee_r", "ankle_r"],
}


## Converts the rig into a physical ragdoll in world space. Returns the ragdoll root node.
func make_ragdoll(container: Node, velocity: Vector3, impulse: Vector3, hit_joint := "chest") -> Node3D:
	if ragdoll_root != null:
		return ragdoll_root
	var root := Node3D.new()
	root.name = "Ragdoll"
	container.add_child(root)
	var bodies := {}
	for jn in RAG_PARTS:
		var info: Array = RAG_PARTS[jn]
		var joint_node: Node3D = j[jn]
		var gx := joint_node.global_transform.orthonormalized()
		var rb := RigidBody3D.new()
		rb.collision_layer = C.L_RAGDOLL
		rb.collision_mask = C.L_WORLD | C.L_VEHICLE | C.L_PROP | C.L_RAGDOLL
		rb.mass = 9.0 if jn in ["hips", "chest"] else 3.5
		rb.angular_damp = 3.0
		rb.linear_damp = 0.15
		rb.set_meta("surface", C.SURF_FLESH)
		rb.continuous_cd = jn in ["hips", "chest"]
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = (info[1] as Vector3) * 2.0
		cs.shape = bs
		cs.position = info[2]
		rb.add_child(cs)
		root.add_child(rb)
		rb.global_transform = gx
		for mj in RAG_GROUPS[jn]:
			var src: Node3D = j[mj]
			for c in src.get_children():
				if c is MeshInstance3D:
					var g := (c as MeshInstance3D).global_transform
					src.remove_child(c)
					rb.add_child(c)
					c.global_transform = g
				elif c == hand_socket:
					var g2 := (c as Node3D).global_transform
					src.remove_child(c)
					rb.add_child(c)
					c.global_transform = g2
		rb.linear_velocity = velocity
		bodies[jn] = rb
	for jn in RAG_PARTS:
		var parent: String = RAG_PARTS[jn][0]
		if parent == "":
			continue
		var jt := ConeTwistJoint3D.new()
		root.add_child(jt)
		jt.global_transform = Transform3D(bodies[jn].global_basis, bodies[jn].global_position)
		jt.node_a = jt.get_path_to(bodies[parent])
		jt.node_b = jt.get_path_to(bodies[jn])
		var span := 0.9
		if jn.begins_with("knee") or jn.begins_with("elbow"):
			span = 1.1
		elif jn == "head":
			span = 0.5
		jt.swing_span = span
		jt.twist_span = 0.4
		jt.exclude_nodes_from_collision = true
	var hb: RigidBody3D = bodies.get(hit_joint, bodies.chest)
	hb.apply_central_impulse(impulse)
	bodies.hips.apply_central_impulse(impulse * 0.5)
	visible = false
	ragdoll_root = root
	ragdoll_bodies = bodies
	return root


func ragdoll_center() -> Vector3:
	if ragdoll_bodies.has("hips") and is_instance_valid(ragdoll_bodies.hips):
		return (ragdoll_bodies.hips as Node3D).global_position
	return global_position


func freeze_ragdoll() -> void:
	for k in ragdoll_bodies:
		var rb: RigidBody3D = ragdoll_bodies[k]
		if is_instance_valid(rb):
			rb.freeze = true
