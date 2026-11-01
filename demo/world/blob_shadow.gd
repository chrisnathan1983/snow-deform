class_name BlobShadow
extends RefCounted
## Cheap fake contact shadow: a soft dark quad just above the snow.
## Everything made here is in group "blob_shadow" so it can be toggled together
## (real sun shadows replace them on High quality).

const SnowUtil = preload("res://addons/deformable_snow/scripts/snow_util.gd")

static var _mesh: PlaneMesh


static func mesh() -> PlaneMesh:
	if _mesh == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = SnowUtil.soft_dot(64)
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
