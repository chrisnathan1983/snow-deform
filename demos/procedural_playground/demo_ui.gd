extends CanvasLayer
## HUD + settings menu. Everything is built in code and scaled by a single factor so it is
## usable on phones. Emits `changed(key, value)`; snow_demo.gd decides what to do with it.

signal changed(key: String, value: Variant)

var root: Control
var blockers: Array[Control] = []
var ui_scale := 1.0

var _info: Label
var _hint: Label
var _panel: PanelContainer
var _menu_btn: Button
var _quality_btns: Array[Button] = []


func build(defaults: Dictionary) -> void:
    layer = 10
    root = Control.new()
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.theme = _make_theme()
    add_child(root)

    # --- info label (top-left)
    _info = Label.new()
    _info.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
    _info.add_theme_constant_override("outline_size", 4)
    _info.position = Vector2(12, 8)
    root.add_child(_info)

    # --- hint (bottom-centre)
    _hint = Label.new()
    _hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
    _hint.add_theme_constant_override("outline_size", 5)
    _hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
    _hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
    root.add_child(_hint)

    # --- menu button (top-right)
    _menu_btn = Button.new()
    _menu_btn.text = "Menu"
    _menu_btn.toggle_mode = true
    _menu_btn.custom_minimum_size = Vector2(90, 40)
    _menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _menu_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    _menu_btn.offset_right = -12
    _menu_btn.offset_top = 10
    _menu_btn.focus_mode = Control.FOCUS_NONE
    root.add_child(_menu_btn)
    blockers.append(_menu_btn)

    # --- panel
    _panel = PanelContainer.new()
    _panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _panel.anchor_bottom = 1.0
    _panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    _panel.offset_left = -312
    _panel.offset_right = -12
    _panel.offset_top = 56
    _panel.offset_bottom = -118
    root.add_child(_panel)
    blockers.append(_panel)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _panel.add_child(scroll)
    var box := VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 6)
    scroll.add_child(box)

    _add_title(box, "Snow Lab")
    _add_label(box, "Quality")
    var qrow := HBoxContainer.new()
    box.add_child(qrow)
    var group := ButtonGroup.new()
    var names := ["Low", "Medium", "High"]
    for i in 3:
        var b := Button.new()
        b.text = names[i]
        b.toggle_mode = true
        b.button_group = group
        b.focus_mode = Control.FOCUS_NONE
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.custom_minimum_size = Vector2(0, 40)
        b.button_pressed = (i == int(defaults.get("quality", 1)))
        var idx := i
        b.pressed.connect(func(): changed.emit("quality", idx))
        qrow.add_child(b)
        _quality_btns.append(b)

    _add_slider(box, "snowfall", "Snowfall", 0.0, 1.0, 0.05, float(defaults.get("snowfall", 0.4)))
    _add_slider(box, "wind", "Wind", -4.0, 4.0, 0.1, float(defaults.get("wind", 0.3)))
    _add_slider(box, "sun", "Sun height", 6.0, 70.0, 1.0, float(defaults.get("sun", 30.0)))

    _add_label(box, "Scene")
    _add_toggle(box, "sled", "Sled (figure-8)", true)
    _add_toggle(box, "balls", "Bouncing balls", true)
    _add_toggle(box, "yeti", "Yeti", true)
    _add_toggle(box, "penguins", "Penguin parade", true)
    _add_toggle(box, "shadows", "Sun shadows", bool(defaults.get("shadows", true)))

    _add_label(box, "Actions")
    _add_button(box, "Snowball storm", "storm")
    _add_button(box, "Reset tracks", "reset")

    # --- jump / run (bottom-right)
    var row := HBoxContainer.new()
    row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    row.grow_vertical = Control.GROW_DIRECTION_BEGIN
    row.offset_right = -16
    row.offset_bottom = -16
    row.add_theme_constant_override("separation", 10)
    root.add_child(row)
    blockers.append(row)
    var run_btn := Button.new()
    run_btn.text = "RUN"
    run_btn.toggle_mode = true
    run_btn.custom_minimum_size = Vector2(84, 84)
    run_btn.focus_mode = Control.FOCUS_NONE
    run_btn.toggled.connect(func(on: bool): changed.emit("run", on))
    row.add_child(run_btn)
    var jump_btn := Button.new()
    jump_btn.text = "JUMP"
    jump_btn.custom_minimum_size = Vector2(104, 84)
    jump_btn.focus_mode = Control.FOCUS_NONE
    jump_btn.pressed.connect(func(): changed.emit("jump", true))
    row.add_child(jump_btn)

    _menu_btn.toggled.connect(func(on: bool): _panel.visible = on)
    var open := bool(defaults.get("menu_open", true))
    _menu_btn.set_pressed_no_signal(open)
    _panel.visible = open


func set_ui_scale(s: float) -> void:
    ui_scale = s
    root.scale = Vector2(s, s)
    root.position = Vector2.ZERO
    root.size = get_viewport().get_visible_rect().size / s


func toggle_menu() -> void:
    _menu_btn.button_pressed = not _menu_btn.button_pressed


func set_quality_selected(i: int) -> void:
    for k in _quality_btns.size():
        _quality_btns[k].set_pressed_no_signal(k == i)


func set_info(text: String) -> void:
    _info.text = text


func set_hint(text: String, seconds := 10.0) -> void:
    _hint.text = text
    _hint.modulate.a = 1.0
    var tw := create_tween()
    tw.tween_interval(seconds)
    tw.tween_property(_hint, "modulate:a", 0.0, 1.5)


## True if a screen-space point (viewport pixels) is over an interactive control.
func over_ui(p: Vector2) -> bool:
    for c in blockers:
        if not c.is_visible_in_tree():
            continue
        var local := c.get_global_transform().affine_inverse() * p
        if Rect2(Vector2.ZERO, c.size).has_point(local):
            return true
    return false


# ---------------------------------------------------------------- builders

func _make_theme() -> Theme:
    var t := Theme.new()
    t.default_font_size = 18
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.06, 0.10, 0.18, 0.84)
    sb.set_corner_radius_all(10)
    sb.set_content_margin_all(10)
    t.set_stylebox("panel", "PanelContainer", sb)
    return t


func _add_title(parent: Control, text: String) -> void:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", 24)
    parent.add_child(l)


func _add_label(parent: Control, text: String) -> void:
    var l := Label.new()
    l.text = text
    l.add_theme_color_override("font_color", Color(0.7, 0.82, 1.0))
    parent.add_child(l)


func _add_slider(parent: Control, key: String, text: String, lo: float, hi: float,
        step: float, value: float) -> void:
    var l := Label.new()
    l.text = "%s: %s" % [text, str(snappedf(value, step))]
    parent.add_child(l)
    var s := HSlider.new()
    s.min_value = lo
    s.max_value = hi
    s.step = step
    s.value = value
    s.focus_mode = Control.FOCUS_NONE
    s.custom_minimum_size = Vector2(0, 26)
    s.value_changed.connect(func(v: float):
        l.text = "%s: %s" % [text, str(snappedf(v, step))]
        changed.emit(key, v))
    parent.add_child(s)


func _add_toggle(parent: Control, key: String, text: String, on: bool) -> void:
    var b := CheckButton.new()
    b.text = text
    b.button_pressed = on
    b.focus_mode = Control.FOCUS_NONE
    b.toggled.connect(func(v: bool): changed.emit(key, v))
    parent.add_child(b)


func _add_button(parent: Control, text: String, key: String) -> void:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(0, 42)
    b.focus_mode = Control.FOCUS_NONE
    b.pressed.connect(func(): changed.emit(key, true))
    parent.add_child(b)
