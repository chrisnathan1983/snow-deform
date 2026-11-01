class_name Player
extends CharacterBody3D
## Movement and jump actions are registered if missing. Remap or override them
## in Project Settings > Input Map if you like.

const BallPush = preload("ball_push.gd")

@export var speed := 5.0
@export var jump_velocity := 5.0
var touch_stick: TouchStick

var _jump_requested := false


static func ensure_input_actions() -> void:
	_bind(&"move_left", KEY_A, KEY_LEFT, JOY_AXIS_LEFT_X, -1.0)
	_bind(&"move_right", KEY_D, KEY_RIGHT, JOY_AXIS_LEFT_X, 1.0)
	_bind(&"move_forward", KEY_W, KEY_UP, JOY_AXIS_LEFT_Y, -1.0)
	_bind(&"move_back", KEY_S, KEY_DOWN, JOY_AXIS_LEFT_Y, 1.0)
	if not InputMap.has_action(&"jump"):
		InputMap.add_action(&"jump")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_SPACE
		InputMap.action_add_event(&"jump", key)
		var button := InputEventJoypadButton.new()
		button.button_index = JOY_BUTTON_A
		InputMap.action_add_event(&"jump", button)


static func _bind(action: StringName, key_a: Key, key_b: Key, axis: JoyAxis, dir: float) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for k in [key_a, key_b]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	var j := InputEventJoypadMotion.new()
	j.axis = axis
	j.axis_value = dir
	InputMap.action_add_event(action, j)


func _ready() -> void:
	ensure_input_actions()


func request_jump() -> void:
	_jump_requested = true


func _physics_process(delta: float) -> void:
	# x = right, y = down on screen = +Z in the world (camera looks toward -Z)
	var v := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if touch_stick:
		v = (v + touch_stick.vector).limit_length(1.0)

	velocity.x = v.x * speed
	velocity.z = v.y * speed
	if is_on_floor():
		if _jump_requested or Input.is_action_just_pressed(&"jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity")) * delta
	_jump_requested = false
	var motion_velocity := velocity
	move_and_slide()   # the arena walls (see main.gd) keep us inside
	BallPush.apply_contact_impulses(self, motion_velocity)

	if v.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-v.x, -v.y), 12.0 * delta)
