class_name DemoHud
extends CanvasLayer
## The one HUD every demo uses: info line (top-left), hint (bottom-centre), Menu button (top-right,
## M key) that opens a tabbed settings panel, and optional Run/Jump touch buttons.
## Everything is built in code and scaled by one factor so it is usable on phones.
##
## Controls report through `changed(key, value)`. `DemoSettings` adds the standard surface,
## weather and graphics tabs; demos add their own tab with the `add_*` helpers.

signal changed(key: String, value: Variant)

var root: Control
var blockers: Array[Control] = []
var ui_scale := 1.0
var touch_ui := false

var _info: Label
var _hint: Label
var _title: Label
var _panel: PanelContainer
var _tabs: TabContainer
var _menu_btn: Button
var _touch_row: HBoxContainer
var _hint_tween: Tween
var _controls := {}


func _init() -> void:
	layer = 10


func _ready() -> void:
	touch_ui = DisplayServer.is_touchscreen_available()
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = DemoTheme.get_theme()
	add_child(root)

	_info = Label.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	DemoTheme.style_floating_label(_info)
	_info.position = Vector2(12, 8)
	root.add_child(_info)

	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	DemoTheme.style_floating_label(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_hint)

	_menu_btn = Button.new()
	_menu_btn.text = "Menu (M)"
	_menu_btn.toggle_mode = true
	_menu_btn.custom_minimum_size = Vector2(110, 40)
	_menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_menu_btn.offset_right = -12
	_menu_btn.offset_top = 10
	_menu_btn.focus_mode = Control.FOCUS_NONE
	root.add_child(_menu_btn)
	blockers.append(_menu_btn)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -392
	_panel.offset_right = -12
	_panel.offset_top = 56
	_panel.offset_bottom = -16
	root.add_child(_panel)
	blockers.append(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	box.add_child(_title)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.clip_tabs = true
	box.add_child(_tabs)

	_menu_btn.toggled.connect(func(on: bool) -> void: _panel.visible = on)
	var open := not touch_ui
	_menu_btn.set_pressed_no_signal(open)
	_panel.visible = open

	get_viewport().size_changed.connect(_update_scale)
	_update_scale()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_M:
		toggle_menu()


func set_title(text: String) -> void:
	_title.text = text


func toggle_menu() -> void:
	_menu_btn.button_pressed = not _menu_btn.button_pressed


func set_info(text: String) -> void:
	_info.text = text


func set_hint(text: String, seconds := 10.0) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(seconds)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 1.5)


## True if a screen-space point (viewport pixels) is over an interactive control.
func over_ui(p: Vector2) -> bool:
	for c in blockers:
		if not c.is_visible_in_tree():
			continue
		var local := c.get_global_transform().affine_inverse() * p
		if Rect2(Vector2.ZERO, c.size).has_point(local):
			return true
	return false


## Adds Run (toggle, optional) and Jump buttons at the bottom-right; they report "run" and "jump".
func add_touch_buttons(with_run := true) -> void:
	if _touch_row:
		return
	_touch_row = HBoxContainer.new()
	_touch_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_touch_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_touch_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_touch_row.offset_right = -16
	_touch_row.offset_bottom = -16
	_touch_row.add_theme_constant_override("separation", 10)
	root.add_child(_touch_row)
	blockers.append(_touch_row)
	if with_run:
		var run_btn := Button.new()
		run_btn.text = "RUN"
		run_btn.toggle_mode = true
		run_btn.custom_minimum_size = Vector2(84, 84)
		run_btn.focus_mode = Control.FOCUS_NONE
		run_btn.toggled.connect(func(on: bool) -> void: changed.emit("run", on))
		_touch_row.add_child(run_btn)
	var jump_btn := Button.new()
	jump_btn.text = "JUMP"
	jump_btn.custom_minimum_size = Vector2(104, 84)
	jump_btn.focus_mode = Control.FOCUS_NONE
	jump_btn.pressed.connect(func() -> void: changed.emit("jump", true))
	_touch_row.add_child(jump_btn)
	_panel.offset_bottom = -118


# ---------------------------------------------------------------- tabs and controls

## Returns the content box of a (possibly existing) tab.
func add_tab(tab_name: String) -> VBoxContainer:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == tab_name:
			return (_tabs.get_child(i) as ScrollContainer).get_child(0) as VBoxContainer
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box


func add_heading(tab: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", DemoTheme.ACCENT_COLOR)
	tab.add_child(l)


func add_slider(tab: Control, key: String, text: String, lo: float, hi: float,
		step: float, value: float) -> void:
	var l := Label.new()
	tab.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 26)
	l.text = "%s: %s" % [text, str(snappedf(s.value, step))]
	s.value_changed.connect(func(v: float) -> void:
		l.text = "%s: %s" % [text, str(snappedf(v, step))]
		changed.emit(key, v))
	tab.add_child(s)
	_controls[key] = {"control": s, "label": l, "text": text, "step": step}


func add_toggle(tab: Control, key: String, text: String, on: bool) -> void:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(func(v: bool) -> void: changed.emit(key, v))
	tab.add_child(b)
	_controls[key] = {"control": b}


## `items` are display strings; `changed` reports the selected index.
func add_option(tab: Control, key: String, text: String, items: Array, selected: int) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		o.add_item(str(item))
	o.select(selected)
	o.item_selected.connect(func(i: int) -> void: changed.emit(key, i))
	row.add_child(o)
	tab.add_child(row)
	_controls[key] = {"control": o}


func add_button(tab: Control, key: String, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: changed.emit(key, true))
	tab.add_child(b)


## +/- stepper for integer counts. `changed` reports the new count.
func add_counter(tab: Control, key: String, text: String, value: int, lo := 0, hi := 99) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(44, 40)
	minus.focus_mode = Control.FOCUS_NONE
	row.add_child(minus)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(44, 40)
	plus.focus_mode = Control.FOCUS_NONE
	row.add_child(plus)
	tab.add_child(row)
	var state := {"value": value, "label": l, "text": text}
	l.text = "%s: %d" % [text, value]
	var bump := func(d: int) -> void:
		var v := clampi(int(state["value"]) + d, lo, hi)
		if v == int(state["value"]):
			return
		state["value"] = v
		l.text = "%s: %d" % [text, v]
		changed.emit(key, v)
	minus.pressed.connect(bump.bind(-1))
	plus.pressed.connect(bump.bind(1))
	_controls[key] = {"counter": state}


func add_label(tab: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(l)
	return l


func has_control(key: String) -> bool:
	return _controls.has(key)


## Updates a control without emitting `changed`.
func set_value(key: String, value: Variant) -> void:
	if not _controls.has(key):
		return
	var entry: Dictionary = _controls[key]
	if entry.has("counter"):
		var st: Dictionary = entry["counter"]
		st["value"] = int(value)
		(st["label"] as Label).text = "%s: %d" % [st["text"], int(value)]
		return
	var c: Control = entry["control"]
	if c is HSlider:
		(c as HSlider).set_value_no_signal(float(value))
		(entry["label"] as Label).text = "%s: %s" % [
			entry["text"], str(snappedf(float(value), float(entry["step"])))]
	elif c is OptionButton:
		(c as OptionButton).select(int(value))
	elif c is BaseButton:
		(c as BaseButton).set_pressed_no_signal(bool(value))


func _update_scale() -> void:
	var vs := get_viewport().get_visible_rect().size
	var short := minf(vs.x, vs.y)
	ui_scale = clampf(short / 480.0, 1.0, 3.5) if touch_ui else clampf(short / 720.0, 1.0, 2.0)
	root.scale = Vector2(ui_scale, ui_scale)
	root.position = Vector2.ZERO
	root.size = vs / ui_scale
