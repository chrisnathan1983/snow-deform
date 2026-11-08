class_name StampBatchRenderer
extends RefCounted
## Owns the MultiMesh batches used to draw stamps into a surface's deformation viewport.

var _viewport: SubViewport
var _sprite_shader: Shader
var _analytic_material: ShaderMaterial
var _sprite_material: ShaderMaterial
var _base_multimesh: MultiMesh
var _batches: Array[Dictionary] = []
var stamps_used := 0
var cost_pixels := 0.0


func setup(viewport: SubViewport, analytic_shader: Shader, sprite_shader: Shader,
		capacity: int) -> void:
	_viewport = viewport
	_analytic_material = ShaderMaterial.new()
	_analytic_material.shader = analytic_shader
	_sprite_shader = sprite_shader
	_sprite_material = ShaderMaterial.new()
	_sprite_material.shader = sprite_shader

	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color.WHITE)
	var stamp_texture := GradientTexture2D.new()
	stamp_texture.gradient = gradient
	stamp_texture.width = 1
	stamp_texture.height = 1

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_base_multimesh = _new_multimesh(quad, capacity)
	_add_batch(null, _base_multimesh, stamp_texture)


func get_batch_count() -> int:
	return _batches.size()


func get_active_batch_count() -> int:
	var active := 0
	for batch in _batches:
		if int(batch["used"]) > 0:
			active += 1
	return active


func configure_materials(profile: DeformableSurfaceType,
		textured_berm_dilation: bool) -> void:
	var materials: Array[ShaderMaterial] = [_analytic_material, _sprite_material]
	for batch in _batches:
		var batch_material := batch["material"] as ShaderMaterial
		if not materials.has(batch_material):
			materials.append(batch_material)
	for material in materials:
		material.set_shader_parameter("berm_strength", profile.berm_strength)
		material.set_shader_parameter("berm_height_ratio", profile.berm_height / maxf(profile.max_depth, 0.01))
		material.set_shader_parameter("map_resolution", float(_viewport.size.x))
		if material.shader == _sprite_shader:
			material.set_shader_parameter("textured_berm_dilation_enabled", textured_berm_dilation)


func set_capacity(capacity: int) -> void:
	for batch in _batches:
		var multimesh := batch["multimesh"] as MultiMesh
		if multimesh.instance_count != capacity:
			multimesh.instance_count = capacity


func reset_counts() -> void:
	stamps_used = 0
	cost_pixels = 0.0
	for batch in _batches:
		batch["used"] = 0


func submit() -> void:
	for batch in _batches:
		var multimesh := batch["multimesh"] as MultiMesh
		var visible_count: int = batch["used"]
		if multimesh.visible_instance_count != visible_count:
			multimesh.visible_instance_count = visible_count


func stamp(texture: Texture2D, transform: Transform2D, color: Color,
		custom_data: Color, covered_pixels: float) -> bool:
	var batch := _get_batch(texture)
	var multimesh := batch["multimesh"] as MultiMesh
	if int(batch["used"]) >= multimesh.instance_count:
		return false
	var index: int = batch["used"]
	multimesh.set_instance_transform_2d(index, transform)
	multimesh.set_instance_color(index, color)
	multimesh.set_instance_custom_data(index, custom_data)
	batch["used"] = index + 1
	stamps_used += 1
	cost_pixels += covered_pixels
	return true


func _get_batch(texture: Texture2D) -> Dictionary:
	for batch in _batches:
		if batch["texture"] == texture:
			return batch

	var multimesh := _new_multimesh(_base_multimesh.mesh, _base_multimesh.instance_count)
	return _add_batch(texture, multimesh, texture)


func _new_multimesh(mesh: Mesh, capacity: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	return multimesh


func _add_batch(texture: Texture2D, multimesh: MultiMesh,
		fallback_texture: Texture2D = null) -> Dictionary:
	var instance := MultiMeshInstance2D.new()
	instance.multimesh = multimesh
	instance.texture = texture if texture != null else fallback_texture
	var material := _analytic_material
	if texture != null:
		material = _sprite_material.duplicate() as ShaderMaterial
		material.set_shader_parameter("stamp_texture", texture)
	instance.material = material
	_viewport.add_child(instance)
	var batch := {
		"texture": texture,
		"multimesh": multimesh,
		"material": material,
		"used": 0,
	}
	_batches.append(batch)
	return batch
