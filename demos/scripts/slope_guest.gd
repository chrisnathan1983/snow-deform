extends Node3D
## Pooled slope traffic. Motion is driven by the demo so pause freezes everyone.

const Props := preload("res://demos/scripts/demo_props.gd")
enum Kind { SKIER, BOARDER, SLED, PENGUIN }

var kind := Kind.SKIER
var index := 0
var lane := 0.0
var cruise_speed := 12.0
var phase := 0.0
var heading := 0.0
var lift := 0.0
var recovery := 0.0
var visual: Node3D
var tracks: DeformerTracks
var tint := Color("9b64da")


func _ready() -> void:
	visual = Node3D.new()
	add_child(visual)
	_build_visual()
	tracks = DeformerTracks.new()
	tracks.preset = DeformerTracks.Preset.CUSTOM
	tracks.wheel_offsets = PackedVector2Array([Vector2(-0.32, -0.35), Vector2(0.32, -0.35)])
	tracks.wheel_width = 0.22
	tracks.strength = 0.8
	if kind == Kind.BOARDER or kind == Kind.PENGUIN:
		tracks.wheel_offsets = PackedVector2Array([Vector2(0, -0.2)])
		tracks.wheel_width = 0.62 if kind == Kind.BOARDER else 0.85
		tracks.strength = 0.65
	elif kind == Kind.SLED:
		tracks.wheel_offsets = PackedVector2Array([Vector2(-0.48, -0.5), Vector2(0.48, -0.5)])
		tracks.wheel_width = 0.18
	var mask := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	mask.fill(Color.WHITE)
	tracks.tread_texture = ImageTexture.create_from_image(mask)
	add_child(tracks)


func _build_visual() -> void:
	var dark := Color("24364d")
	var gold := Color("ffc957")
	if kind == Kind.PENGUIN:
		Props.add_mesh(visual, Props.sphere(0.65), dark, Vector3(0, 0.38, 0), Vector3(0.85, 0.6, 1.35))
		Props.add_mesh(visual, Props.sphere(0.37), dark, Vector3(0, 0.65, 0.65))
		Props.add_mesh(visual, Props.sphere(0.3), Color("edf5fa"), Vector3(0, 0.65, 0.85), Vector3(1, 0.8, 0.5))
		Props.add_mesh(visual, Props.cone(0.16, 0.4), gold, Vector3(0, 0.59, 1.1), Vector3.ONE, Vector3(90, 0, 0))
		Props.add_mesh(visual, Props.box(Vector3(0.75, 0.13, 0.26)), tint, Vector3(0, 0.6, 0.4))
		for side in [-1.0, 1.0]:
			Props.add_mesh(visual, Props.sphere(0.4), dark, Vector3(side * 0.65, 0.3, 0), Vector3(1.4, 0.16, 0.7))
			Props.add_mesh(visual, Props.sphere(0.06), dark, Vector3(side * 0.14, 0.74, 1.0))
		return
	if kind == Kind.BOARDER:
		Props.add_mesh(visual, Props.capsule(0.27, 2.0), tint, Vector3(0, 0.08, 0), Vector3(1, 1, 0.25), Vector3(90, 0, 0))
	elif kind == Kind.SLED:
		Props.add_mesh(visual, Props.box(Vector3(1.1, 0.18, 1.5)), Color("ba7951"), Vector3(0, 0.4, 0))
	for side in [-1.0, 1.0]:
		if kind != Kind.BOARDER:
			var spread := 0.48 if kind == Kind.SLED else 0.32
			Props.add_mesh(visual, Props.box(Vector3(0.16, 0.1, 2.0)), gold, Vector3(side * spread, 0.09, 0))
		Props.add_mesh(visual, Props.capsule(0.13, 0.55), dark, Vector3(side * 0.23, 0.55, 0.06))
		Props.add_mesh(visual, Props.capsule(0.12, 0.65), tint, Vector3(side * 0.48, 1.0, 0.04), Vector3.ONE, Vector3(20, 0, side * 40))
		if kind == Kind.SKIER:
			Props.add_mesh(visual, Props.cylinder(0.025, 1.1), dark, Vector3(side * 0.65, 0.5, -0.22), Vector3.ONE, Vector3(28, 0, 0))
	Props.add_mesh(visual, Props.capsule(0.3, 0.75), tint, Vector3(0, 1.0, 0))
	Props.add_mesh(visual, Props.sphere(0.26), Color("f2c69f"), Vector3(0, 1.5, 0.12))
	Props.add_mesh(visual, Props.sphere(0.29), gold, Vector3(0, 1.63, 0.1), Vector3(1, 0.7, 1))
	Props.add_mesh(visual, Props.box(Vector3(0.43, 0.12, 0.12)), dark, Vector3(0, 1.52, 0.36))
	if kind == Kind.SLED:
		visual.scale.y = 0.75


func respawn(player_z: float, ahead: bool) -> void:
	position = Vector3(lane, 0, player_z + (52.0 if ahead else -38.0))
	heading = 0
	lift = 0
	recovery = 0
	rotation = Vector3.ZERO
	visual.rotation = Vector3.ZERO
	tracks.reset_path()
	tracks.active = true


func set_paused(value: bool) -> void:
	tracks.active = not value and position.y < 0.05 and recovery <= 0
	if value:
		tracks.reset_path()


func advance(delta: float, player: Node3D, scenery: Array[Node3D], peers: Array) -> void:
	# Only recycle beyond the camera, and discard the previous ribbon endpoint.
	if position.z < player.position.z - 40.0:
		respawn(player.position.z, true)
	elif position.z > player.position.z + 56.0:
		respawn(player.position.z, false)
	phase += delta * (1.15 if kind == Kind.SKIER else 0.7)
	recovery = maxf(0, recovery - delta)
	var amplitude := 3.5 if kind == Kind.BOARDER else 2.2
	var target_x := lane + sin(phase) * amplitude
	var desired := clampf((target_x - position.x) * 0.45, -0.8, 0.8)
	# Predict obstacles a few metres ahead, then steer toward the clear side.
	for obstacle in scenery:
		var offset := obstacle.position - position
		if offset.z > -1.5 and offset.z < 9.0 and absf(offset.x) < 3.1:
			var obstacle_kind: String = obstacle.get_meta("kind")
			if obstacle_kind != "jump":
				var away := -1.0 if offset.x > 0 else 1.0
				desired += away * (1.0 - maxf(offset.z, 0) / 10.0) * 1.5
			if Vector2(offset.x, offset.z).length() < 1.55 and position.y == 0 and recovery <= 0:
				if obstacle_kind == "jump" or obstacle_kind == "rock":
					lift = 7.5
				else:
					recovery = 0.85
	# Friendly traffic yields to the player and nearby riders instead of causing pileups.
	var neighbors: Array = [player]
	neighbors.append_array(peers)
	for other in neighbors:
		if other == self:
			continue
		var offset: Vector3 = other.position - position
		if absf(offset.z) < 3.5 and absf(offset.x) < 1.8:
			desired += -0.7 if offset.x > 0 else 0.7
	heading = move_toward(heading, clampf(desired, -1.0, 1.0), delta * 2.0)
	var pace := cruise_speed * (0.18 if recovery > 0 else 1.0)
	position += Vector3(sin(heading), 0, cos(heading)) * pace * delta
	position.x = clampf(position.x, -23.0, 23.0)
	if position.y > 0 or lift > 0:
		lift -= delta * 18.0
		position.y = maxf(0, position.y + lift * delta)
		if position.y == 0:
			lift = 0
	rotation.y = heading
	visual.rotation.z = lerpf(visual.rotation.z, 1.1 if recovery > 0 else -heading * 0.32, 1.0 - exp(-8.0 * delta))
	tracks.active = position.y < 0.05 and recovery <= 0
