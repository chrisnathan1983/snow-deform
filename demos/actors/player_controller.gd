extends Node
## Player movement policy for DemoCharacter.

@onready var character: DemoCharacter = get_parent() as DemoCharacter


func _process(delta: float) -> void:
	var speed := character.move_speed * (character.run_mult if character.running else 1.0)
	var direction := character.move_input
	character.move_by(direction, speed, delta)
	if direction.length() > 0.08:
		character.turn_towards(direction, delta)
	if not character.on_ground:
		character._vy -= DemoCharacter.GRAVITY * delta
		character.position.y += character._vy * delta
		if character.position.y <= 0.0:
			character.position.y = 0.0
			character._vy = 0.0
			character.on_ground = true
	var footsteps := character.get_node("DeformerFootsteps") as DeformerFootsteps
	footsteps.active = character.on_ground
	character.collide()
