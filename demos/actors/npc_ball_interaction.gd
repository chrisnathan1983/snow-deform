extends Area3D
## Small contact area that lets the wandering explorer nudge the soccer ball.

@export var impulse := 0.8


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body is RigidBody3D or not body.is_in_group(&"player_pushable"):
		return
	var direction := body.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = -global_basis.z
		direction.y = 0.0
	(body as RigidBody3D).apply_central_impulse(direction.normalized() * impulse)
