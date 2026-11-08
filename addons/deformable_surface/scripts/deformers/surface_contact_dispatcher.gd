extends RefCounted
## Normalizes surface contacts and routes their optional particle effects.

var _surface: Node


func setup(surface: Node) -> void:
	_surface = surface
	if not surface.contact.is_connected(_on_contact):
		surface.contact.connect(_on_contact)


func emit(world_pos: Vector3, strength: float, mode: int, source: Node,
		radius: float, puff: bool) -> void:
	var depth: float = strength * _surface.max_depth
	if mode == 1:
		depth = -depth
	elif mode == 2:
		depth = 0.0
		puff = false
	_surface.contact.emit(world_pos, depth, _surface._effective_surface_type().type_name,
			source, radius, puff)


func _on_contact(world_pos: Vector3, _depth: float, _surface_type: StringName,
		source: Node, radius: float, puff: bool) -> void:
	if puff:
		_surface._spawn_puff(world_pos, radius, Vector3.ZERO, source)
