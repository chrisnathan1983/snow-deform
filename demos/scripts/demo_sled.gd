extends Node3D
## A sled that glides along a figure-8, carving two parallel grooves with berms.
## Demonstrates elongated Deformers (aspect) and distance-based puffs.

const Props := preload("res://demos/scripts/demo_props.gd")

var amp := Vector2(10.0, 6.5)
var rate := 0.45
var running := true

var _t := 0.0
var _runners: Array[Deformer] = []


## Meshes of the sled. Authored in demos/props/sled.tscn; this builds the same
## body in code when the script is used without that scene.
static func build_visual(parent: Node3D) -> void:
    var wood := Color(0.5, 0.33, 0.2)
    Props.add_mesh(parent, Props.box(Vector3(0.9, 0.1, 1.7)), wood, Vector3(0, 0.22, 0))
    Props.add_mesh(parent, Props.box(Vector3(0.9, 0.3, 0.08)), wood, Vector3(0, 0.38, 0.8))
    for sx in [-1.0, 1.0]:
        var x: float = sx * 0.32
        Props.add_mesh(parent, Props.box(Vector3(0.07, 0.12, 2.0)), Color(0.35, 0.37, 0.42), Vector3(x, 0.1, -0.05))
        Props.add_mesh(parent, Props.box(Vector3(0.07, 0.16, 0.2)), Color(0.35, 0.37, 0.42), Vector3(x, 0.2, -1.05), Vector3.ONE, Vector3(-30, 0, 0))
        Props.add_mesh(parent, Props.box(Vector3(0.06, 0.14, 0.06)), wood, Vector3(x, 0.17, -0.5))
        Props.add_mesh(parent, Props.box(Vector3(0.06, 0.14, 0.06)), wood, Vector3(x, 0.17, 0.5))
    # a gift riding along
    Props.add_mesh(parent, Props.box(Vector3(0.45, 0.35, 0.45)), Color(0.85, 0.15, 0.2), Vector3(0, 0.45, 0.15))
    Props.add_mesh(parent, Props.box(Vector3(0.47, 0.37, 0.08)), Color(0.95, 0.8, 0.2), Vector3(0, 0.45, 0.15))
    Props.add_mesh(parent, Props.box(Vector3(0.08, 0.37, 0.47)), Color(0.95, 0.8, 0.2), Vector3(0, 0.45, 0.15))


func _ready() -> void:
    if get_node_or_null("Visual") == null:
        var visual := Node3D.new()
        visual.name = "Visual"
        add_child(visual)
        build_visual(visual)
    for sx in [-1.0, 1.0]:
        var x: float = sx * 0.32
        var d := Deformer.new()
        d.radius = 0.2
        d.aspect = 5.0
        d.strength = 0.9
        d.puff_distance = 1.2
        d.position = Vector3(x, 0.0, -0.1)
        add_child(d)
        _runners.append(d)
    _place()


func set_running(on: bool) -> void:
    running = on
    for d in _runners:
        d.active = on


func _process(delta: float) -> void:
    if not running:
        return
    _t += delta * rate
    _place()


func _place() -> void:
    position = Vector3(amp.x * sin(_t), 0.0, amp.y * sin(2.0 * _t))
    var d := Vector2(amp.x * cos(_t), 2.0 * amp.y * cos(2.0 * _t))
    if d.length() > 0.0001:
        rotation.y = atan2(-d.x, -d.y)


## Sample points along the path (used to keep scenery out of the way).
static func sample_path(a: Vector2, count := 120) -> PackedVector2Array:
    var pts := PackedVector2Array()
    for i in count:
        var t := TAU * float(i) / float(count)
        pts.append(Vector2(a.x * sin(t), a.y * sin(2.0 * t)))
    return pts
