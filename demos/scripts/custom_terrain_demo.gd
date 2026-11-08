extends Node3D
## Showcases DeformableSurface with `render_mesh` off: the surface only maintains the deformation
## map, and a custom hilly terrain plus grass blades read it through deformable_surface.gdshaderinc.
## WASD / arrows walk (Shift runs); hold the left mouse button to carve; right-drag orbits;
## the wheel zooms. The walker wanders on its own until you press a movement key.

const TERRAIN_SHADER := preload("res://demos/shaders/terrain.gdshader")
const GRASS_SHADER := preload("res://demos/shaders/grass.gdshader")

const AREA := 40.0
const TERRAIN_CELLS := 160
const GRASS_SPACING := 0.34
const MAX_DEPTH := 0.12

var _surface: DeformableSurface
var _terrain_material: ShaderMaterial
var _grass_material: ShaderMaterial
var _grass: MultiMeshInstance3D
var _sun: DirectionalLight3D
var _camera: Camera3D
var _walker: Node3D
var _brush: Deformer
var _hud: DemoHud

var _orbit := Vector2(0.75, 0.6)   # pitch, yaw
var _distance := 11.0
var _autopilot := true
var _autopilot_time := 0.0
var _carving := false
var _camera_focus := Vector3.ZERO


func _ready() -> void:
	DemoNav.attach(self)
	_build_world()
	_build_terrain()
	_build_grass()
	_build_walker()
	_bind_deformation()
	_build_ui()


# Same function the terrain mesh is built from, so deformers can stand on the real ground.
static func terrain_height(x: float, z: float) -> float:
	return 1.5 * sin(x * 0.13) * cos(z * 0.11) \
			+ 0.7 * sin(x * 0.31 + z * 0.17) \
			+ 0.25 * sin(z * 0.52 - x * 0.2)


func _build_world() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.5, 0.8)
	sky_material.sky_horizon_color = Color(0.75, 0.82, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	_sun.shadow_enabled = true
	add_child(_sun)

	# render_mesh = false: no snow plane, the node only keeps the deformation map up to date.
	_surface = DeformableSurface.new()
	_surface.render_mesh = false
	_surface.size = AREA
	_surface.sun = _sun
	var quality := DeformableSurfaceQuality.new()
	quality.res = 1024
	_surface.quality = quality
	var surface_type := DeformableSurfaceType.new()
	surface_type.type_name = &"grass"
	surface_type.max_depth = MAX_DEPTH
	surface_type.berm_height = 0.03
	surface_type.initial_noise_enabled = false
	surface_type.recovery_intensity = 0.12
	var dust := Gradient.new()
	dust.set_color(0, Color(0.55, 0.46, 0.34, 0.7))
	dust.set_color(1, Color(0.55, 0.46, 0.34, 0.0))
	surface_type.puff_color_ramp = dust
	_surface.surface_type = surface_type
	add_child(_surface)

	_brush = Deformer.new()
	_brush.field = _surface
	_brush.radius = 0.7
	_brush.puff_distance = 0.8
	_brush.active = false
	add_child(_brush)

	_camera = Camera3D.new()
	_camera.far = 300.0
	add_child(_camera)


func _build_terrain() -> void:
	var step := AREA / TERRAIN_CELLS
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var row := TERRAIN_CELLS + 1
	for iz in row:
		for ix in row:
			var x := -AREA * 0.5 + ix * step
			var z := -AREA * 0.5 + iz * step
			verts.append(Vector3(x, terrain_height(x, z), z))
			normals.append(_terrain_normal(x, z))
	for iz in TERRAIN_CELLS:
		for ix in TERRAIN_CELLS:
			var a := iz * row + ix
			var b := a + 1
			var c := a + row
			var d := c + 1
			# Godot front faces are clockwise seen from above (+X right, +Z down).
			indices.append_array([a, b, d, a, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = TERRAIN_SHADER
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _terrain_material
	instance.extra_cull_margin = 1.0   # vertices are displaced beyond the undeformed bounds
	add_child(instance)


func _terrain_normal(x: float, z: float) -> Vector3:
	var e := 0.1
	var dx := terrain_height(x + e, z) - terrain_height(x - e, z)
	var dz := terrain_height(x, z + e) - terrain_height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func _build_grass() -> void:
	var width := 0.045
	var height := 0.6
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	# Two crossed blades, each a tapered strip: base, middle, tip.
	for blade in 2:
		var dir := Vector3(1.0, 0.0, 0.0) if blade == 0 else Vector3(0.0, 0.0, 1.0)
		var first := verts.size()
		verts.append_array([
			-dir * width, dir * width,
			-dir * width * 0.6 + Vector3.UP * height * 0.5, dir * width * 0.6 + Vector3.UP * height * 0.5,
			Vector3.UP * height,
		])
		uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.5), Vector2(1, 0.5), Vector2(0.5, 1)])
		for i in 5:
			normals.append(Vector3.UP)
		indices.append_array([first, first + 1, first + 3, first, first + 3, first + 2,
				first + 2, first + 3, first + 4])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var blade_mesh := ArrayMesh.new()
	blade_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var transforms: Array[Transform3D] = []
	var half := AREA * 0.5 - 0.5
	var steps := int(floor(half * 2.0 / GRASS_SPACING))
	for iz in steps:
		for ix in steps:
			var x := -half + (ix + rng.randf()) * GRASS_SPACING
			var z := -half + (iz + rng.randf()) * GRASS_SPACING
			if _terrain_normal(x, z).y < 0.82:
				continue   # too steep: bare rock
			var blade_scale := rng.randf_range(0.6, 1.2)
			var blade_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * blade_scale)
			transforms.append(Transform3D(blade_basis, Vector3(x, terrain_height(x, z), z)))

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = blade_mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])

	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_grass = MultiMeshInstance3D.new()
	_grass.multimesh = multimesh
	_grass.material_override = _grass_material
	_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grass.extra_cull_margin = 1.0
	add_child(_grass)


func _build_walker() -> void:
	_walker = Node3D.new()
	add_child(_walker)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.5
	body.mesh = capsule
	body.position.y = 0.75
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.3, 0.2)
	body.material_override = material
	_walker.add_child(body)
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.14, 0.14, 0.3)
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, 1.1, -0.3)
	_walker.add_child(nose)
	var feet := DeformerFootsteps.new()
	feet.field = _surface
	feet.foot_radius = 0.22
	_walker.add_child(feet)
	_update_walker(Vector3.ZERO, 0.0)


# The map and its world rectangle are all a custom shader needs from the surface.
func _bind_deformation() -> void:
	for material in [_terrain_material, _grass_material]:
		material.set_shader_parameter("deform_map", _surface.get_deform_texture())
		material.set_shader_parameter("deform_area", _surface.get_deform_area_transform())
		material.set_shader_parameter("deform_max_depth", _surface.max_depth)


func _build_ui() -> void:
	_hud = DemoHud.new()
	add_child(_hud)
	_hud.set_title("Custom terrain")
	var tab := _hud.add_tab("Scene")
	_hud.add_heading(tab, "Controls")
	_hud.add_toggle(tab, "autopilot", "Autopilot walker", _autopilot)
	_hud.add_option(tab, "brush", "Mouse brush", ["Carve", "Raise", "Smooth"], 0)
	_hud.add_heading(tab, "Grass")
	_hud.add_toggle(tab, "grass", "Show grass", true)
	_hud.add_slider(tab, "bend", "Bend strength", 0.0, 1.0, 0.05, 0.35)
	_hud.add_slider(tab, "flatten", "Flatten in prints", 0.0, 1.0, 0.05, 0.75)
	_hud.add_heading(tab, "Terrain")
	_hud.add_slider(tab, "normals", "Print normal strength", 0.0, 3.0, 0.05, 1.0)
	_hud.add_slider(tab, "recovery", "Recovery", 0.0, 1.0, 0.05, 0.12)
	_hud.changed.connect(_on_hud_changed)
	_hud.set_info("DeformableSurface.render_mesh = false | %d grass blades" % _grass.multimesh.instance_count)
	_hud.set_hint("WASD walk | Shift run | LMB brush | RMB drag orbit | wheel zoom | M menu", 12.0)


func _on_hud_changed(key: String, value: Variant) -> void:
	match key:
		"autopilot":
			_autopilot = bool(value)
		"brush":
			_brush.mode = [DeformableSurface.StampMode.CARVE, DeformableSurface.StampMode.RAISE,
					DeformableSurface.StampMode.SMOOTH][int(value)]
		"grass":
			_grass.visible = bool(value)
		"bend":
			_grass_material.set_shader_parameter("bend_strength", float(value))
		"flatten":
			_grass_material.set_shader_parameter("flatten_amount", float(value))
		"normals":
			_terrain_material.set_shader_parameter("normal_strength", float(value))
		"recovery":
			_surface.set_recovery_intensity(float(value))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_carving = mb.pressed and not _hud.over_ui(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(4.0, _distance - 0.8)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(30.0, _distance + 0.8)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var motion := event as InputEventMouseMotion
		_orbit.y -= motion.relative.x * 0.005
		_orbit.x = clampf(_orbit.x + motion.relative.y * 0.005, 0.25, 1.45)


func _process(delta: float) -> void:
	_process_walker(delta)
	_process_brush()
	_update_camera(delta)


func _process_walker(delta: float) -> void:
	var move := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
				- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
				- float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	var pos := _walker.position
	var heading := _walker.rotation.y
	if move != Vector2.ZERO:
		if _autopilot:
			_autopilot = false
			_hud.set_value("autopilot", false)
		# Movement is relative to the camera's yaw.
		var direction := Vector3(move.x, 0.0, move.y).normalized().rotated(Vector3.UP, _orbit.y)
		var speed := 5.5 if Input.is_key_pressed(KEY_SHIFT) else 3.0
		pos += direction * speed * delta
		heading = atan2(-direction.x, -direction.z)
	elif _autopilot:
		_autopilot_time += delta * 0.32
		var t := _autopilot_time
		var next := _autopilot_position(t)
		var ahead := _autopilot_position(t + 0.05)
		pos = next
		heading = atan2(-(ahead.x - next.x), -(ahead.z - next.z))
	var limit := AREA * 0.5 - 1.0
	pos.x = clampf(pos.x, -limit, limit)
	pos.z = clampf(pos.z, -limit, limit)
	_update_walker(pos, heading)


func _autopilot_position(t: float) -> Vector3:
	return Vector3(sin(t) * 12.0, 0.0, sin(t * 2.0) * 8.0)


func _update_walker(pos: Vector3, heading: float) -> void:
	pos.y = terrain_height(pos.x, pos.z)
	_walker.position = pos
	_walker.rotation.y = heading


func _process_brush() -> void:
	if not _carving:
		_brush.active = false
		return
	var hit := _ground_point(get_viewport().get_mouse_position())
	_brush.active = hit != Vector3.INF
	if _brush.active:
		_brush.global_position = hit


# Marches the mouse ray against the height function (the terrain has no collider).
func _ground_point(mouse: Vector2) -> Vector3:
	var origin := _camera.project_ray_origin(mouse)
	var direction := _camera.project_ray_normal(mouse)
	var previous := 0.0
	var travelled := 0.0
	while travelled < 120.0:
		var p := origin + direction * travelled
		if p.y <= terrain_height(p.x, p.z):
			var lo := previous
			var hi := travelled
			for i in 8:
				var mid := (lo + hi) * 0.5
				var q := origin + direction * mid
				if q.y <= terrain_height(q.x, q.z):
					hi = mid
				else:
					lo = mid
			var hit := origin + direction * hi
			if absf(hit.x) > AREA * 0.5 or absf(hit.z) > AREA * 0.5:
				return Vector3.INF
			return Vector3(hit.x, terrain_height(hit.x, hit.z), hit.z)
		previous = travelled
		travelled += 0.3
	return Vector3.INF


func _update_camera(delta: float) -> void:
	_camera_focus = _camera_focus.lerp(_walker.global_position + Vector3(0.0, 0.8, 0.0), 1.0 - exp(-6.0 * delta))
	var offset := Vector3(0.0, sin(_orbit.x), cos(_orbit.x)).rotated(Vector3.UP, _orbit.y) * _distance
	_camera.global_position = _camera_focus + offset
	_camera.look_at(_camera_focus)
