extends RefCounted


static func apply_contact_impulses(character: CharacterBody3D, motion_velocity: Vector3) -> void:
	for index in character.get_slide_collision_count():
		var collision := character.get_slide_collision(index)
		var collider := collision.get_collider()
		if not collider is RigidBody3D or not collider.is_in_group(&"player_pushable"):
			continue

		var ball := collider as RigidBody3D
		var normal := collision.get_normal()
		var direction := Vector3(-normal.x, 0.0, -normal.z).normalized()
		if direction.is_zero_approx():
			continue

		var relative_velocity := motion_velocity - ball.linear_velocity
		var impact_speed := Vector3(relative_velocity.x, 0.0, relative_velocity.z).dot(direction)
		if impact_speed > 0.0:
			ball.apply_central_impulse(direction * impact_speed * ball.mass * 1.2)
