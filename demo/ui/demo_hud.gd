class_name DemoHud
extends CanvasLayer
## Scene-authored controls for the demo. Emits signals without depending on the
## snow system or player implementation.

signal preset_selected(q: int)
signal options_previewed(
	q: int,
	custom: bool,
	settings: Dictionary,
	snowfall: float,
	shadows: bool,
	msaa: int,
	wrapped_diffuse_lighting: bool
)
signal options_cancelled(
	q: int,
	custom: bool,
	settings: Dictionary,
	snowfall: float,
	shadows: bool,
	msaa: int,
	wrapped_diffuse_lighting: bool
)
signal options_confirmed(
	q: int,
	custom: bool,
	settings: Dictionary,
	snowfall: float,
	shadows: bool,
	msaa: int,
	wrapped_diffuse_lighting: bool
)
signal reset_pressed
signal jump_pressed
signal add_person_pressed
signal remove_person_pressed
signal add_mouse_pressed
signal remove_mouse_pressed

@onready var stick: TouchStick = $TouchStick
@onready var fps_label: Label = $FPS
@onready var options_panel: PanelContainer = $OptionsPanel
@onready var people_count_label: Label = $PopulationControls/PeopleRow/Count
@onready var mice_count_label: Label = $PopulationControls/MiceRow/Count
@onready var quality_option: OptionButton = $OptionsPanel/ScrollContainer/OptionsContent/QualityOption
@onready var snowfall_label: Label = $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/SnowfallPanel/SnowfallLabel
@onready var snowfall_slider: HSlider = $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/SnowfallPanel/SnowfallSlider
@onready var shadows_toggle: CheckButton = $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Graphics/ShadowsRow/Shadows
@onready var msaa_option: OptionButton = $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Graphics/MSAARow/MSAA
@onready var wrapped_diffuse_toggle: CheckButton = $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Graphics/WrappedDiffuseRow/WrappedDiffuse
@onready var _follow_target_option: OptionButton = $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Particles/FollowTargetRow/FollowTarget
@onready var puffs_enabled_toggle: CheckButton = $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Particles/PuffsEnabledRow/PuffsEnabled

var _fps_timer := 0.0
var _updating_options := false
var _setting_inputs: Dictionary = {}
var _boolean_setting_inputs: Dictionary = {}
var _committed_quality := 1
var _committed_custom := false
var _committed_settings: Dictionary = {}
var _committed_snowfall := 0.3
var _committed_shadows := false
var _committed_msaa := 1
var _committed_wrapped_diffuse_lighting := true
var _draft_quality := 1
var _draft_custom := false
var _draft_settings: Dictionary = {}
var _draft_snowfall := 0.3
var _draft_shadows := false
var _draft_msaa := 1
var _draft_wrapped_diffuse_lighting := true


func _ready() -> void:
	$TopControls/OptionsButton.pressed.connect(_open_options)
	$TopControls/Reset.pressed.connect(reset_pressed.emit)
	$Jump.pressed.connect(jump_pressed.emit)
	$PopulationControls/PeopleRow/Remove.pressed.connect(remove_person_pressed.emit)
	$PopulationControls/PeopleRow/Add.pressed.connect(add_person_pressed.emit)
	$PopulationControls/MiceRow/Remove.pressed.connect(remove_mouse_pressed.emit)
	$PopulationControls/MiceRow/Add.pressed.connect(add_mouse_pressed.emit)
	$OptionsPanel/ScrollContainer/OptionsContent/Actions/CancelButton.pressed.connect(_cancel_options)
	$OptionsPanel/ScrollContainer/OptionsContent/Actions/ConfirmButton.pressed.connect(_confirm_options)

	quality_option.add_item("Low", 0)
	quality_option.add_item("Medium", 1)
	quality_option.add_item("High", 2)
	quality_option.add_item("Custom", 3)
	quality_option.set_item_disabled(3, true)
	quality_option.item_selected.connect(_on_quality_selected)

	msaa_option.add_item("Disabled", Viewport.MSAA_DISABLED)
	msaa_option.add_item("2x", Viewport.MSAA_2X)
	msaa_option.add_item("4x", Viewport.MSAA_4X)
	msaa_option.item_selected.connect(_on_msaa_selected)

	_follow_target_option.add_item("Camera", 0)
	_follow_target_option.add_item("Player", 1)
	_follow_target_option.add_item("Sled", 2)

	_setting_inputs = {
		&"res": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Graphics/ResolutionRow/Resolution,
		&"subdiv": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Graphics/SubdivisionsRow/Subdivisions,
		&"sparkle": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/SparkleRow/Sparkle,
		&"flakes": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Particles/FlakesRow/Flakes,
		&"near": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Particles/NearFlakesRow/NearFlakes,
		&"puff": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Particles/PuffRow/Puff,
		&"area_size": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/AreaSizeRow/AreaSize,
		&"max_depth": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/MaxDepthRow/MaxDepth,
		&"berm_strength": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/BermStrengthRow/BermStrength,
		&"berm_height": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/BermHeightRow/BermHeight,
		&"max_stamps_per_frame": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/MaxStampsRow/MaxStamps,
		&"refill_levels_per_sec": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/RefillRateRow/RefillRate,
		&"berm_decay_mult": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/BermDecayRow/BermDecay,
		&"refill_interval": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Surface/RefillIntervalRow/RefillInterval,
		&"wind_x": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Particles/WindXRow/WindX,
		&"wind_z": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Particles/WindZRow/WindZ,
		&"fall_height": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Particles/FallHeightRow/FallHeight,
		&"puff_min_interval": $OptionsPanel/ScrollContainer/OptionsContent/Tabs/Particles/PuffIntervalRow/PuffInterval,
	}
	_boolean_setting_inputs = {
		&"puffs_enabled": puffs_enabled_toggle,
		&"shadows": shadows_toggle,
		&"wrapped_diffuse_lighting": wrapped_diffuse_toggle,
	}
	for setting in _setting_inputs:
		var input: SpinBox = _setting_inputs[setting]
		input.value_changed.connect(_on_quality_setting_changed.bind(setting))
	for setting in _boolean_setting_inputs:
		var input: CheckButton = _boolean_setting_inputs[setting]
		input.toggled.connect(_on_boolean_setting_changed.bind(setting))

	snowfall_slider.value_changed.connect(_on_snowfall_changed)
	_follow_target_option.item_selected.connect(_on_follow_target_selected)
	_set_game_hud_visible(true)


func set_population_counts(people_count: int, mouse_count: int) -> void:
	people_count_label.text = str(people_count)
	mice_count_label.text = str(mouse_count)
	$PopulationControls/PeopleRow/Remove.disabled = people_count == 0
	$PopulationControls/MiceRow/Remove.disabled = mouse_count == 0


func _process(delta: float) -> void:
	_fps_timer += delta
	if _fps_timer >= 0.25:
		_fps_timer = 0.0
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and options_panel.visible:
		_cancel_options()
		get_viewport().set_input_as_handled()


func set_current_options(
	q: int,
	settings: Dictionary,
	snowfall: float,
	custom: bool,
	shadows: bool,
	msaa: int,
	wrapped_diffuse_lighting: bool
) -> void:
	_committed_quality = q
	_committed_settings = settings.duplicate(true)
	_committed_snowfall = snowfall
	_committed_custom = custom
	_committed_shadows = shadows
	_committed_msaa = msaa
	_committed_wrapped_diffuse_lighting = wrapped_diffuse_lighting
	_restore_draft()


func set_draft_preset(q: int, settings: Dictionary) -> void:
	_draft_quality = q
	_draft_custom = false
	_draft_settings = settings.duplicate(true)
	_draft_snowfall = _draft_settings["snowfall"]
	_draft_shadows = _draft_settings["shadows"]
	_draft_msaa = _draft_settings["msaa"]
	_draft_wrapped_diffuse_lighting = _draft_settings["wrapped_diffuse_lighting"]
	_update_controls()
	_emit_options_preview()


func _open_options() -> void:
	_restore_draft()
	options_panel.show()
	_set_game_hud_visible(false)


func _cancel_options() -> void:
	options_cancelled.emit(
		_committed_quality,
		_committed_custom,
		_committed_settings.duplicate(true),
		_committed_snowfall,
		_committed_shadows,
		_committed_msaa,
		_committed_wrapped_diffuse_lighting
	)
	_restore_draft()
	options_panel.hide()
	_set_game_hud_visible(true)


func _confirm_options() -> void:
	options_confirmed.emit(
		_draft_quality,
		_draft_custom,
		_draft_settings.duplicate(true),
		_draft_snowfall,
		_draft_shadows,
		_draft_msaa,
		_draft_wrapped_diffuse_lighting
	)
	_committed_quality = _draft_quality
	_committed_custom = _draft_custom
	_committed_settings = _draft_settings.duplicate(true)
	_committed_snowfall = _draft_snowfall
	_committed_shadows = _draft_shadows
	_committed_msaa = _draft_msaa
	_committed_wrapped_diffuse_lighting = _draft_wrapped_diffuse_lighting
	options_panel.hide()
	_set_game_hud_visible(true)


func _restore_draft() -> void:
	_draft_quality = _committed_quality
	_draft_custom = _committed_custom
	_draft_settings = _committed_settings.duplicate(true)
	_draft_snowfall = _committed_snowfall
	_draft_shadows = _committed_shadows
	_draft_msaa = _committed_msaa
	_draft_wrapped_diffuse_lighting = _committed_wrapped_diffuse_lighting
	_update_controls()


func _update_controls() -> void:
	_updating_options = true
	quality_option.set_item_disabled(3, not _draft_custom)
	quality_option.select(3 if _draft_custom else _draft_quality)
	for setting in _setting_inputs:
		var input: SpinBox = _setting_inputs[setting]
		input.value = _draft_settings[String(setting)]
	for setting in _boolean_setting_inputs:
		var input: CheckButton = _boolean_setting_inputs[setting]
		input.button_pressed = _draft_settings[String(setting)]
	_follow_target_option.select(_draft_settings["follow_target_mode"])
	snowfall_slider.value = _draft_snowfall
	_update_snowfall_label(_draft_snowfall)
	msaa_option.select(msaa_option.get_item_index(_draft_msaa))
	_updating_options = false


func _set_game_hud_visible(hud_visible: bool) -> void:
	$TopControls.visible = hud_visible
	$TouchStick.visible = hud_visible
	$FPS.visible = hud_visible
	$Help.visible = hud_visible
	$PopulationControls.visible = hud_visible
	$Jump.visible = hud_visible
	stick.set_process_input(hud_visible)
	if not hud_visible:
		stick.cancel()


func _on_quality_selected(index: int) -> void:
	if _updating_options or index == 3:
		return
	preset_selected.emit(index)


func _on_quality_setting_changed(value: float, setting: StringName) -> void:
	if _updating_options:
		return
	_draft_settings[String(setting)] = value
	_draft_custom = true
	quality_option.set_item_disabled(3, false)
	quality_option.select(3)
	_emit_options_preview()


func _on_snowfall_changed(value: float) -> void:
	if _updating_options:
		return
	_draft_snowfall = value
	_draft_settings["snowfall"] = value
	_update_snowfall_label(value)
	_mark_options_custom()


func _on_msaa_selected(index: int) -> void:
	if _updating_options:
		return
	_draft_msaa = msaa_option.get_item_id(index)
	_draft_settings["msaa"] = _draft_msaa
	_mark_options_custom()


func _on_follow_target_selected(index: int) -> void:
	if _updating_options:
		return
	_draft_settings["follow_target_mode"] = _follow_target_option.get_item_id(index)
	_mark_options_custom()


func _on_boolean_setting_changed(enabled: bool, setting: StringName) -> void:
	if _updating_options:
		return
	_draft_settings[String(setting)] = enabled
	if setting == &"shadows":
		_draft_shadows = enabled
	elif setting == &"wrapped_diffuse_lighting":
		_draft_wrapped_diffuse_lighting = enabled
	_mark_options_custom()


func _mark_options_custom() -> void:
	_draft_custom = true
	quality_option.set_item_disabled(3, false)
	quality_option.select(3)
	_emit_options_preview()


func _emit_options_preview() -> void:
	options_previewed.emit(
		_draft_quality,
		_draft_custom,
		_draft_settings.duplicate(true),
		_draft_snowfall,
		_draft_shadows,
		_draft_msaa,
		_draft_wrapped_diffuse_lighting
	)


func _update_snowfall_label(value: float) -> void:
	snowfall_label.text = "Snowfall %d%%" % roundi(value * 100.0)
