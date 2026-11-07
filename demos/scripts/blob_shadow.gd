class_name BlobShadow
extends RefCounted
## Cheap fake contact shadow: a soft dark quad just above the snow.
## Everything made here is in group "blob_shadow" so it can be toggled together
## (real sun shadows replace them on High quality).

static var _mesh: PlaneMesh
static var _dot_cache: GradientTexture2D


static func mesh() -> PlaneMesh:
	if _mesh == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = _soft_dot(64)
		m.albedo_color = Color(0.16, 0.24, 0.42, 0.45)
		_mesh = PlaneMesh.new()
		_mesh.size = Vector2.ONE
		_mesh.material = m
	return _mesh


static func make(size: float, shown: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh()
	mi.scale = Vector3(size, 1.0, size)
	mi.position = Vector3(0.0, 0.04, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = shown
	mi.add_to_group(&"blob_shadow")
	return mi


static func _soft_dot(size := 32) -> GradientTexture2D:
	if size == 32 and _dot_cache != null:
		return _dot_cache

	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.5, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	if size == 32:
		_dot_cache = t
	return t
