extends RigidBody3D

const GROUND_CLEARANCE := 0.42
const GROUND_NORMAL_MIN := 0.7

@onready var _deformer: SnowDeformer = $SnowDeformer


func _physics_process(_delta: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * GROUND_CLEARANCE
	)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var grounded := not hit.is_empty()

	if grounded:
		var normal: Vector3 = hit["normal"]
		grounded = normal.dot(Vector3.UP) >= GROUND_NORMAL_MIN
		if grounded:
			var ground_position: Vector3 = hit["position"]
			var deformer_position := Vector3(global_position.x, ground_position.y, global_position.z)
			if not _deformer.global_position.is_equal_approx(deformer_position):
				_deformer.global_position = deformer_position

	_deformer.active = grounded
