extends Node3D
## Pooled slope traffic. Motion is driven by the demo so pause freezes everyone.

enum Kind { SKIER, BOARDER, SLED, PENGUIN }

@export var kind := Kind.SKIER
@export var tint := Color("9b64da")
@export var tint_parts: Array[MeshInstance3D] = []

@onready var visual: Node3D = $Visual
@onready var tracks: DeformerTracks = $Tracks

var lane := 0.0
var cruise_speed := 12.0
var phase := 0.0
var heading := 0.0
var lift := 0.0
var recovery := 0.0
var use_blob_shadow := false
var shadow: MeshInstance3D


func _ready() -> void:
	if not tint_parts.is_empty():
		var material := tint_parts[0].material_override.duplicate() as StandardMaterial3D
		material.albedo_color = tint
		for part in tint_parts:
			part.material_override = material
	if use_blob_shadow:
		shadow = BlobShadow.make(1.8, true)
		add_child(shadow)


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
	if shadow != null:
		shadow.position.y = 0.04 - position.y
	visual.rotation.z = lerpf(visual.rotation.z, 1.1 if recovery > 0 else -heading * 0.32, 1.0 - exp(-8.0 * delta))
	tracks.active = position.y < 0.05 and recovery <= 0
