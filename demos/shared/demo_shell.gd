class_name DemoShell
extends Node

const SCENE := "res://demos/shared/demo_shell.tscn"

@onready var hud: DemoHud = $DemoHud
@onready var _overlay: CanvasLayer = $TouchOverlay

var sticks: TouchSticks
var _with_sticks := false


static func attach(demo: Node, with_sticks := false) -> DemoShell:
	var shell := (load(SCENE) as PackedScene).instantiate() as DemoShell
	shell._with_sticks = with_sticks
	demo.add_child(shell)
	demo.move_child(shell, 0)
	return shell


func _ready() -> void:
	if not _with_sticks:
		return
	sticks = TouchSticks.new()
	sticks.is_blocked = hud.over_ui
	_update_stick_scale()
	get_viewport().size_changed.connect(_update_stick_scale)
	_overlay.add_child(sticks)
	if hud.touch_ui:
		hud.add_touch_buttons()


func bind_surfaces(fields: Array[DeformableSurface]) -> DemoSettings:
	return DemoSettings.create(hud, fields)


func _update_stick_scale() -> void:
	sticks.stick_scale = hud.ui_scale
