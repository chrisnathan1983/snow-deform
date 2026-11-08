class_name DemoNPC
extends DemoCharacter

@export var bounds := Vector2(11.0, 11.0):
	set(value):
		bounds = value
		if is_node_ready():
			$Behavior.call("set_bounds", bounds)
@export var body_color := Color(0.2, 0.5, 0.9)


func _ready() -> void:
	super._ready()
	var body := $Visual/Body as MeshInstance3D
	var material := body.material_override.duplicate() as StandardMaterial3D
	material.albedo_color = body_color
	body.material_override = material
	$Behavior.set("random_waypoints", true)
	$Behavior.call("set_bounds", bounds)
