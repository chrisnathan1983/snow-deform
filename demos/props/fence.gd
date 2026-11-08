extends Node3D
## Adjustable perimeter fence for the Playground arena.

@export var half_extent := 16.0
@export var ground_y := -0.3


func configure(half: float, ground: float) -> void:
	half_extent = half
	ground_y = ground


func _ready() -> void:
	_build_fence()


func _build_fence() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.33, 0.21, 0.13)
	wood.roughness = 0.9
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.88, 0.91, 0.97)
	snow.roughness = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.2, 1.1, 0.2)
	var transforms: Array[Transform3D] = []
	var post_extent := half_extent + 0.25
	var count := int(half_extent)
	for i in count * 2 + 1:
		var u := -half_extent + float(i)
		transforms.append(Transform3D(Basis(), Vector3(u, 0.55, -post_extent)))
		transforms.append(Transform3D(Basis(), Vector3(u, 0.55, post_extent)))
		if i > 0 and i < count * 2:
			transforms.append(Transform3D(Basis(), Vector3(-post_extent, 0.55, u)))
			transforms.append(Transform3D(Basis(), Vector3(post_extent, 0.55, u)))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var posts_node := MultiMeshInstance3D.new()
	posts_node.multimesh = multimesh
	posts_node.material_override = wood
	add_child(posts_node)
	var fence_length := half_extent * 2.0 + 0.5
	for y in [0.4, 0.85]:
		_add_mesh(BoxMesh.new(), wood, Vector3(0, y, -post_extent), Vector3(fence_length, 0.08, 0.06))
		_add_mesh(BoxMesh.new(), wood, Vector3(0, y, post_extent), Vector3(fence_length, 0.08, 0.06))
		_add_mesh(BoxMesh.new(), wood, Vector3(-post_extent, y, 0), Vector3(0.06, 0.08, fence_length))
		_add_mesh(BoxMesh.new(), wood, Vector3(post_extent, y, 0), Vector3(0.06, 0.08, fence_length))
	var skirt_height := -ground_y + 0.02
	var skirt_y := ground_y + skirt_height * 0.5
	_add_mesh(BoxMesh.new(), snow, Vector3(0, skirt_y, -half_extent - 0.04), Vector3(half_extent * 2.0 + 0.2, skirt_height, 0.1))
	_add_mesh(BoxMesh.new(), snow, Vector3(0, skirt_y, half_extent + 0.04), Vector3(half_extent * 2.0 + 0.2, skirt_height, 0.1))
	_add_mesh(BoxMesh.new(), snow, Vector3(-half_extent - 0.04, skirt_y, 0), Vector3(0.1, skirt_height, half_extent * 2.0 + 0.2))
	_add_mesh(BoxMesh.new(), snow, Vector3(half_extent + 0.04, skirt_y, 0), Vector3(0.1, skirt_height, half_extent * 2.0 + 0.2))


func _add_mesh(mesh: BoxMesh, material: StandardMaterial3D, at: Vector3, dimensions: Vector3) -> void:
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
