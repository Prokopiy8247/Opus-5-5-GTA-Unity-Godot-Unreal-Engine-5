class_name Projectile
extends Node3D
## Rockets (straight, raycast-stepped), thrown grenades and launcher grenades (physical, bouncing).

var kind := "rocket"
var shooter: Node3D
var damage := 200.0
var radius := 7.0
var vel := Vector3.ZERO
var life := 0.0
var fuse := 3.0
var body: RigidBody3D
var trail: GPUParticles3D


static func launch(k: String, origin: Vector3, dir: Vector3, src: Node3D, dmg: float, rad: float) -> void:
	var p := Projectile.new()
	p.kind = k
	p.shooter = src
	p.damage = dmg
	p.radius = rad
	var root := (Engine.get_main_loop() as SceneTree).current_scene
	root.add_child(p)
	p.global_position = origin
	p._setup(dir)


func _setup(dir: Vector3) -> void:
	var mb := MB.new()
	if kind == "rocket":
		mb.use("a").col(Color.WHITE)
		mb.cylinder_axis(Vector3.ZERO, Vector3(0, 0, -1), 0.05, 0.6, 8)
		mb.cylinder_axis(Vector3(0, 0, -0.38), Vector3(0, 0, -1), 0.05, 0.16, 8, true, 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit({"a": Mats.color(Color(0.4, 0.45, 0.35), 0.6)})
		add_child(mi)
		look_at(global_position + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
		vel = dir * 48.0
		trail = VFX.attach_emitter(self, "smoke", Vector3(0, 0, 0.35))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.3)
		l.light_energy = 2.0
		l.omni_range = 6.0
		l.position = Vector3(0, 0, 0.4)
		add_child(l)
	else:
		body = RigidBody3D.new()
		body.mass = 0.4
		body.collision_layer = C.L_PROJECTILE
		body.collision_mask = C.L_WORLD | C.L_VEHICLE | C.L_PROP | C.L_NPC | C.L_RAGDOLL
		body.contact_monitor = true
		body.max_contacts_reported = 2
		body.continuous_cd = true
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.07
		cs.shape = sh
		body.add_child(cs)
		mb.use("p").col(Color.WHITE)
		mb.sphere(Vector3.ZERO, 0.07, 8, 5, Vector3(1, 1.2, 1))
		var mi2 := MeshInstance3D.new()
		mi2.mesh = mb.commit({"p": Mats.color(Color(0.3, 0.38, 0.25), 0.6)})
		body.add_child(mi2)
		add_child(body)
		body.global_position = global_position
		var speed := 17.0 if kind == "grenade" else 30.0
		body.linear_velocity = dir * speed + Vector3(0, 3.5 if kind == "grenade" else 1.5, 0)
		body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		if shooter is CollisionObject3D:
			body.add_collision_exception_with(shooter)
		fuse = 2.8 if kind == "grenade" else 6.0
		if kind == "gl_grenade":
			body.body_entered.connect(func(_b): if life > 0.08: _explode(body.global_position))


func _physics_process(delta: float) -> void:
	life += delta
	if kind == "rocket":
		var from := global_position
		var to := from + vel * delta
		var ex: Array = [shooter] if shooter is CollisionObject3D else []
		var hit := U.ray(from, to, C.MASK_BULLET, ex)
		if not hit.is_empty():
			_explode(hit.position)
			return
		if to.y < C.SEA_LEVEL and from.y >= C.SEA_LEVEL:
			_explode(Vector3(to.x, C.SEA_LEVEL, to.z))
			return
		global_position = to
		vel.y -= 0.6 * delta
		if life > 7.0:
			_explode(global_position)
	else:
		if body == null or not is_instance_valid(body):
			queue_free()
			return
		if life > fuse:
			_explode(body.global_position)
		elif body.global_position.y < C.SEA_LEVEL - 0.2:
			body.linear_velocity *= 0.9


func _explode(at: Vector3) -> void:
	if is_queued_for_deletion():
		return
	if at.y <= C.SEA_LEVEL + 0.3 and WorldMap.is_water(at.x, at.z):
		VFX.splash(at, 3.0)
	Game.explosion(at, radius, damage, shooter)
	queue_free()
