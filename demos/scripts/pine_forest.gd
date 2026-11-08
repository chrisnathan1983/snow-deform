class_name PineForest
extends Node3D
## Draws every pine with one MultiMesh (2 surfaces: foliage + trunk) plus one
## MultiMesh for blob shadows, instead of ~5 MeshInstance3D per tree.
## Collision is a single StaticBody3D with one cylinder per tree.
##
## The demo forest is generated from exported settings when this node enters
## the scene tree unless a custom layout was populated before entering it.

const SEGMENTS := 8

@export var area_size := Vector2(24, 24)
@export var random_seed := 7
@export_range(0, 100) var inner_tree_count := 8
@export var inner_bounds := Vector2(10, 10)
@export var inner_clear_radius := 5.0
@export_range(1.0, 12.0, 1.0) var edge_spacing := 2.0

var visual_only := false
var cast_shadows := true
var blobs_visible := true
var _spots: Array[Transform3D] = []


func _ready() -> void:
	if _spots.is_empty():
		_generate_spots()
	build()


func _generate_spots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var half := area_size * 0.5
	for t in range(-int(half.x), int(half.x) + 1, roundi(edge_spacing)):
		var jitter := rng.randf_range(-0.3, 0.3)
		add_tree(Vector3(t + jitter, 0.0, -half.y - 0.3), rng.randf_range(1.0, 1.5))
		add_tree(Vector3(t + jitter, 0.0, half.y + 0.3), rng.randf_range(1.0, 1.5))
		add_tree(Vector3(-half.x - 0.3, 0.0, t + jitter), rng.randf_range(1.0, 1.5))
		add_tree(Vector3(half.x + 0.3, 0.0, t + jitter), rng.randf_range(1.0, 1.5))

	var placed := 0
	while placed < inner_tree_count:
		var p := Vector2(rng.randf_range(-inner_bounds.x, inner_bounds.x),
				rng.randf_range(-inner_bounds.y, inner_bounds.y))
		if p.length() < inner_clear_radius:
			continue
		add_tree(Vector3(p.x, 0.0, p.y), rng.randf_range(0.8, 1.3))
		placed += 1


func scatter_ring(rng: RandomNumberGenerator, count: int, half: float, band: Vector2,
		tree_scale: Vector2) -> void:
	for i in count:
		var angle := rng.randf() * TAU
		var direction := Vector2(cos(angle), sin(angle))
		var edge := maxf(absf(direction.x), absf(direction.y))
		var point := direction / edge * (half + rng.randf_range(band.x, band.y))
		var s := rng.randf_range(tree_scale.x, tree_scale.y)
		add_tree(Vector3(point.x, 0.0, point.y), s, rng.randf() * TAU)


func add_tree(pos: Vector3, s: float, yaw := 0.0) -> void:
	_spots.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos))


func build() -> void:
	if _spots.is_empty():
		return

	var foliage_mat := ShaderMaterial.new()
	foliage_mat.shader = preload("res://demos/shaders/tree_snow.gdshader")
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.22, 0.12)

	var mesh := _make_mesh()
	mesh.surface_set_material(0, foliage_mat)
	mesh.surface_set_material(1, trunk_mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _spots.size()
	for i in _spots.size():
		mm.set_instance_transform(i, _spots[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not cast_shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	if visual_only:
		return

	# Blob shadows
	var bmm := MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.mesh = BlobShadow.mesh()
	bmm.instance_count = _spots.size()
	for i in _spots.size():
		var s := _spots[i].basis.get_scale().x * 2.8
		bmm.set_instance_transform(i, Transform3D(
				Basis.IDENTITY.scaled(Vector3(s, 1.0, s)),
				_spots[i].origin + Vector3(0.0, 0.04, 0.0)))
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = bmm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bmi.visible = blobs_visible
	bmi.add_to_group(&"blob_shadow")
	add_child(bmi)

	# Collision
	var body := StaticBody3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 2.0
	for t in _spots:
		var cs := CollisionShape3D.new()
		cs.shape = cyl
		cs.position = t.origin + Vector3(0.0, 1.0, 0.0)
		body.add_child(cs)
	add_child(body)


## Surface 0: three stacked cones (flat shaded, COLOR.r = 0 apex .. 1 rim).
## Surface 1: trunk. Winding is clockwise-from-outside (Godot front faces);
## normals are set explicitly so lighting doesn't depend on it.
func _make_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var r := 1.3 - i * 0.3
		var h := 1.4
		var cy := 1.2 + i * 0.9
		var apex := Vector3(0.0, cy + h * 0.5, 0.0)
		var base_y := cy - h * 0.5
		for k in SEGMENTS:
			var a0 := TAU * k / SEGMENTS
			var a1 := TAU * (k + 1) / SEGMENTS
			var am := (a0 + a1) * 0.5
			var p0 := Vector3(cos(a0) * r, base_y, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, base_y, sin(a1) * r)
			var n := Vector3(cos(am) * h, r, sin(am) * h).normalized()
			st.set_normal(n)
			st.set_color(Color(0, 0, 0, 1))
			st.add_vertex(apex)
			st.set_normal(n)
			st.set_color(Color(1, 0, 0, 1))
			st.add_vertex(p0)
			st.set_normal(n)
			st.set_color(Color(1, 0, 0, 1))
			st.add_vertex(p1)
	st.commit(mesh)

	var trunk_surface := SurfaceTool.new()
	trunk_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_top := 0.12
	var r_bot := 0.18
	var th := 0.8
	for k in SEGMENTS:
		var a0 := TAU * k / SEGMENTS
		var a1 := TAU * (k + 1) / SEGMENTS
		var am := (a0 + a1) * 0.5
		var n := Vector3(cos(am), 0.0, sin(am))
		var t0 := Vector3(cos(a0) * r_top, th, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, th, sin(a1) * r_top)
		var b0 := Vector3(cos(a0) * r_bot, 0.0, sin(a0) * r_bot)
		var b1 := Vector3(cos(a1) * r_bot, 0.0, sin(a1) * r_bot)
		for v in [t0, b0, b1, t0, b1, t1]:
			trunk_surface.set_normal(n)
			trunk_surface.add_vertex(v)
	trunk_surface.commit(mesh)
	return mesh
