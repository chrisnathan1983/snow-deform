extends Node3D
## Connects the scene-authored world, snow system, and demo controls.

const PERSON_SCENE := preload("res://demos/characters/npc.tscn")
const MOUSE_SCENE := preload("res://demos/characters/mouse.tscn")
const WEATHER_PROFILES: Array[SnowWeatherSettings] = [
	preload("res://addons/snowfall/resources/weather/calm.tres"),
	preload("res://addons/snowfall/resources/weather/snowfall.tres"),
	preload("res://addons/snowfall/resources/weather/blizzard.tres"),
]
const DemoCharacter := preload("res://demos/scripts/demo_character.gd")
const FOLLOW_TARGETS := ["Camera", "Player", "Sled"]

@onready var snow: DeformableSurface = $DeformableSurface
@onready var weather: SnowWorldManager = $SnowWorldManager
@onready var player: DemoCharacter = $Actors/Player
@onready var npcs: Node3D = $Actors/NPCs
@onready var sled: Node3D = $Actors/Sled
@onready var sun: DirectionalLight3D = $Sun
@onready var camera: DemoCamera = $Camera3D

var hud: DemoHud
var settings: DemoSettings
var _people: Array[Node3D] = []
var _mice: Array[Node3D] = []
var _person_serial := 0
var _mouse_serial := 1
var _real_shadows := false
var _hud_t := 0.0
var _stick: TouchSticks
var _run_button := false
@export_enum("Camera:0", "Player:1", "Sled:2") var follow_target_mode := 0


func _ready() -> void:
	DemoNav.attach(self)
	# The scene stores this script property, but assigning it here keeps the
	# player controllable even if an export drops the non-exported scene value.
	player.role = DemoCharacter.Role.PLAYER
	snow.quality = DeformableSurfaceQuality.high()

	var weather_profile := WEATHER_PROFILES[2].duplicate() as SnowWeatherSettings
	weather_profile.follow_target_path = NodePath("../Actors/Player")
	weather.weather_settings = weather_profile
	_apply_follow_target(follow_target_mode)

	for person in npcs.get_children():
		_people.append(person as Node3D)
	_mice.append($Actors/Mouse as Node3D)

	sun.shadow_enabled = _real_shadows
	get_viewport().msaa_3d = Viewport.MSAA_2X
	_build_hud()
	settings.edit_profile("recovery_intensity", weather.snowfall_intensity)
	hud.set_value("surface.recovery", weather.snowfall_intensity)

	for body in [player, sled] + npcs.get_children():
		body.add_child(BlobShadow.make(2.0 if body == sled else 1.2, settings.quality_index != 2))
	_apply_blob_shadows()


func _build_hud() -> void:
	hud = DemoHud.new()
	add_child(hud)
	hud.set_title("Classic")
	settings = DemoSettings.create(hud, [snow] as Array[DeformableSurface])
	settings.quality_index = 2
	settings.allow_area = true
	settings.add_surface_tab()
	settings.add_weather_tab(weather)
	settings.add_graphics_tab(sun)

	var scene_tab := hud.add_tab("Scene")
	hud.add_counter(scene_tab, "people", "People", _people.size())
	hud.add_counter(scene_tab, "mice", "Mice", _mice.size())
	hud.add_option(scene_tab, "follow", "Weather follows", FOLLOW_TARGETS, follow_target_mode)
	hud.changed.connect(_on_hud_changed)

	var overlay := CanvasLayer.new()
	overlay.layer = 9
	add_child(overlay)
	var stick := TouchSticks.new()
	stick.is_blocked = hud.over_ui
	stick.stick_scale = hud.ui_scale
	get_viewport().size_changed.connect(func(): stick.stick_scale = hud.ui_scale)
	overlay.add_child(stick)
	camera.sticks = stick
	_stick = stick
	if hud.touch_ui:
		hud.add_touch_buttons()
	hud.set_hint("WASD / arrows move | Shift run | Space jump | M menu | Esc launcher", 12.0)


func _process(delta: float) -> void:
	var keys := Vector2(
		_axis(KEY_D, KEY_RIGHT) - _axis(KEY_A, KEY_LEFT),
		_axis(KEY_S, KEY_DOWN) - _axis(KEY_W, KEY_UP))
	if _stick:
		keys += _stick.move
	keys = keys.limit_length(1.0)
	player.move_input = Basis(Vector3.UP, camera.yaw) * Vector3(keys.x, 0.0, keys.y)
	player.running = Input.is_key_pressed(KEY_SHIFT) or _run_button
	_push_balls(delta)
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.4
		hud.set_info("%d FPS  |  %s  |  %d people  |  %d mice" % [
			Engine.get_frames_per_second(), DemoSettings.QUALITY_NAMES[settings.quality_index],
			_people.size(), _mice.size()])


func _on_hud_changed(key: String, value: Variant) -> void:
	match key:
		"gfx.shadows":
			_real_shadows = bool(value)
			_apply_blob_shadows()
		"follow": _apply_follow_target(int(value))
		"people":
			while _people.size() > int(value):
				_remove_person()
			while _people.size() < int(value):
				_add_person()
		"mice":
			while _mice.size() > int(value):
				_remove_mouse()
			while _mice.size() < int(value):
				_add_mouse()
		"jump": player.jump()
		"run": _run_button = bool(value)


func _axis(a: Key, b: Key) -> float:
	return 1.0 if Input.is_key_pressed(a) or Input.is_key_pressed(b) else 0.0


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_SPACE:
		player.jump()


## The explorer is not a physics body, so nudge any soccer ball it walks into.
func _push_balls(delta: float) -> void:
	var speed := player.move_input.length() * player.move_speed * (player.run_mult if player.running else 1.0)
	for node in get_tree().get_nodes_in_group(&"player_pushable"):
		var ball := node as RigidBody3D
		var away := ball.global_position - player.global_position
		away.y = 0.0
		if away.length() < 0.9 and away.length() > 0.001:
			ball.apply_central_impulse(away.normalized() * (2.0 + speed) * ball.mass * delta * 8.0)


func _apply_blob_shadows() -> void:
	for shadow in get_tree().get_nodes_in_group(&"blob_shadow"):
		shadow.visible = not _real_shadows


func _apply_follow_target(mode: int) -> void:
	match mode:
		1:
			weather.set_follow_target(player)
		2:
			weather.set_follow_target(sled)
		_:
			weather.set_follow_target(null)


func _add_person() -> void:
	var person := PERSON_SCENE.instantiate() as SnowNPC
	if person == null:
		push_error("Demo: could not instantiate a person.")
		return
	_person_serial += 1
	person.name = "Person%d" % _person_serial
	person.position = Vector3(randf_range(-9.0, 9.0), 0.0, randf_range(-9.0, 9.0))
	person.speed = randf_range(2.0, 3.2)
	npcs.add_child(person)
	person.add_child(BlobShadow.make(1.2, settings.quality_index != 2))
	_apply_blob_shadows()
	_people.append(person)


func _remove_person() -> void:
	if not _people.is_empty():
		_people.pop_back().queue_free()


func _add_mouse() -> void:
	var mouse := MOUSE_SCENE.instantiate() as Node3D
	if mouse == null:
		push_error("Demo: could not instantiate a mouse.")
		return
	_mouse_serial += 1
	mouse.name = "Mouse%d" % _mouse_serial
	mouse.position = Vector3(randf_range(-9.0, 9.0), 0.0, randf_range(-9.0, 9.0))
	$Actors.add_child(mouse)
	_mice.append(mouse)


func _remove_mouse() -> void:
	if not _mice.is_empty():
		_mice.pop_back().queue_free()
