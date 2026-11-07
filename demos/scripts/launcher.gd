extends Control
## Start screen for the project's playable snow demos.

const DEMOS := [
	{
		"title": "Powder Run — SkiFree in 3D",
		"description": "Carve endless ski tracks, dodge pines, jump rocks, and chase slalom gates.",
		"scene": "res://demos/ski_free.tscn",
	},
	{
		"title": "Classic Snow Demo",
		"description": "Explore footprints, NPCs, sleds, snowballs, and weather controls.",
		"scene": "res://demos/classic.tscn",
	},
	{
		"title": "Infinite Snowfields",
		"description": "Travel across a recycled grid of independent surfaces and shared weather.",
		"scene": "res://demos/infinite_snow.tscn",
	},
	{
		"title": "Material Showcase",
		"description": "Snow, sand, mud, dirt and ash presets with albedo/normal textures and triplanar mode.",
		"scene": "res://demos/materials_demo.tscn",
	},
	{
		"title": "Custom Terrain & Grass",
		"description": "Hilly terrain and grass with their own shaders, driven by a surface with render_mesh off.",
		"scene": "res://demos/custom_terrain_demo.tscn",
	},
	{
		"title": "Procedural Snow Playground",
		"description": "A self-contained playground with actors, props, and quality controls.",
		"scene": "res://demos/snow_demo.tscn",
	},
	{
		"title": "Infinite Snow Playground",
		"description": "The procedural playground on a fence-free, recycled snowfield.",
		"scene": "res://demos/snow_demo_infinite.tscn",
	},
]

var _status: Label


func _ready() -> void:
	_build_interface()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color(0.78, 0.86, 0.96)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700.0, 0.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.96, 0.98, 1.0, 0.97)
	panel_style.set_corner_radius_all(18)
	panel_style.set_content_margin_all(32.0)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)

	var heading := Label.new()
	heading.text = "DEFORMABLE SNOW"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", Color(0.12, 0.2, 0.34))
	content.add_child(heading)

	var subtitle := Label.new()
	subtitle.text = "Choose a demo to explore"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.3, 0.39, 0.53))
	content.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6.0
	content.add_child(spacer)

	for demo in DEMOS:
		var button := Button.new()
		button.text = "%s\n%s" % [demo["title"], demo["description"]]
		button.custom_minimum_size = Vector2(620.0, 58.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_launch_demo.bind(demo["scene"]))
		content.add_child(button)

	_status = Label.new()
	_status.text = "Godot Compatibility renderer"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(0.36, 0.44, 0.56))
	content.add_child(_status)


func _launch_demo(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		var message := "Could not open demo '%s': %s" % [scene_path, error_string(error)]
		push_error(message)
		_status.text = message
