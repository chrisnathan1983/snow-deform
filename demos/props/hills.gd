extends Node3D
## Procedural distant hill silhouettes for demo scenes.

@export var random_seed := 461
@export var ground_y := -0.3
@export_range(1, 64) var hill_count := 14


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var hill_mesh := SphereMesh.new()
	hill_mesh.radius = 1.0
	hill_mesh.height = 2.0
	hill_mesh.radial_segments = 16
	hill_mesh.rings = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.86, 0.90, 0.97)
	material.roughness = 1.0
	for i in hill_count:
		var angle := TAU * float(i) / float(hill_count) + rng.randf() * 0.3
		var distance := rng.randf_range(95.0, 140.0)
		var radius := rng.randf_range(22.0, 45.0)
		var hill := MeshInstance3D.new()
		hill.mesh = hill_mesh
		hill.material_override = material
		hill.position = Vector3(cos(angle) * distance, ground_y + radius * 0.15,
				sin(angle) * distance)
		hill.scale = Vector3(radius * 1.6, radius * 0.55, radius * 1.2)
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hill)
