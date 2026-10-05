class_name LighthouseBeacon
extends Node3D
## Rotating lighthouse beam, active at night.

var spot: SpotLight3D
var beam: MeshInstance3D


func _ready() -> void:
	spot = SpotLight3D.new()
	spot.light_color = Color(1.0, 0.95, 0.8)
	spot.spot_range = 160.0
	spot.spot_angle = 9.0
	spot.light_energy = 0.0
	spot.shadow_enabled = false
	add_child(spot)
	var cm := CylinderMesh.new()
	cm.top_radius = 5.0
	cm.bottom_radius = 0.2
	cm.height = 60.0
	cm.radial_segments = 10
	beam = MeshInstance3D.new()
	beam.mesh = cm
	beam.material_override = Mats.unshaded(Color(1.0, 0.95, 0.75, 0.06), true)
	beam.rotation = Vector3(-PI * 0.5, 0, 0)
	beam.position = Vector3(0, 0, -30)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spot.add_child(beam)


func _process(delta: float) -> void:
	rotate_y(delta * 0.9)
	var night: float = Game.night_factor if Game else 0.0
	spot.light_energy = night * 6.0
	beam.visible = night > 0.3
