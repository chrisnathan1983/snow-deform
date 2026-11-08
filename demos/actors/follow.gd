extends Node
## Follow-target movement policy for DemoCharacter.

@export var follow_target: Node3D
@export var follow_distance := 1.2
@onready var character: DemoCharacter = get_parent() as DemoCharacter


func _process(delta: float) -> void:
	if not is_instance_valid(follow_target):
		return
	var direction := follow_target.global_position - character.global_position
	direction.y = 0.0
	var distance := direction.length()
	if distance > follow_distance:
		direction /= distance
		var speed := clampf(character.move_speed + (distance - follow_distance) * 1.4,
				0.0, character.move_speed * 2.4)
		var step := minf(speed * delta, distance - follow_distance)
		character.position += direction * step
		character.turn_towards(direction, delta)
	character.collide()
