class_name DemoNav
extends CanvasLayer
## Shared "back to launcher" control for every demo: a button in the bottom-left corner
## plus the Escape key, and the small FPS readout (DemoFps). Add it to a demo with
## `DemoNav.attach(self)`.

const LAUNCHER_SCENE := "res://demos/launcher.tscn"


## Adds the control to `demo`. It becomes the first child so that other nodes (for example
## an options panel closing on Escape) see unhandled input before it does.
static func attach(demo: Node) -> DemoNav:
	var nav := DemoNav.new()
	demo.add_child(nav)
	demo.move_child(nav, 0)
	return nav


func _init() -> void:
	layer = 100
	name = "DemoNav"


func _ready() -> void:
	if DeformableSurfaceQuality.platform_tier() == 0:
		get_viewport().scaling_3d_scale = 0.7
	add_child(DemoFps.new())
	var button := Button.new()
	button.text = "Launcher (Esc)"
	button.theme = DemoTheme.get_theme()
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.pressed.connect(return_to_launcher)
	add_child(button)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		return_to_launcher()


func return_to_launcher() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var error := get_tree().change_scene_to_file(LAUNCHER_SCENE)
	if error != OK:
		push_error("Could not open the launcher: %s" % error_string(error))
