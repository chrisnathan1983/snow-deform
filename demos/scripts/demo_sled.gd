extends AnimatableBody3D
## Carves parallel grooves along a figure eight or a wobbling orbit.

enum PathMode { FIGURE_EIGHT, ORBIT }

@export var path_mode := PathMode.FIGURE_EIGHT
@export var orbit_radius := 7.0
@export var orbit_speed := 0.6
@export var height := 0.1
@export_range(0.0, 2.0, 0.05, "or_greater") var wobble_amplitude := 0.3
@export_range(0.0, 8.0, 0.1, "or_greater") var wobble_cycles := 3.0

var amp := Vector2(10.0, 6.5)
var rate := 0.45
var running := true

var _t := 0.0
var _runners: Array[Deformer] = []


func _ready() -> void:
    var orbiting := path_mode == PathMode.ORBIT
    sync_to_physics = orbiting
    set_physics_process(orbiting)
    set_process(not orbiting)
    $CollisionShape3D.disabled = not orbiting
    for side in [-1.0, 1.0]:
        var x: float = side * (0.35 if orbiting else 0.32)
        var d := Deformer.new()
        d.radius = 0.2
        d.aspect = 3.0 if orbiting else 5.0
        d.strength = 1.0 if orbiting else 0.9
        d.puff_distance = 1.0 if orbiting else 1.2
        d.position = Vector3(x, -0.1, 0.0) if orbiting else Vector3(x, 0.0, -0.1)
        d.active = running
        add_child(d)
        _runners.append(d)
    if not orbiting:
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


func _physics_process(delta: float) -> void:
    if not running:
        return
    _t += delta * orbit_speed
    var wobble_angle := _t * wobble_cycles
    var radius := orbit_radius + sin(wobble_angle) * wobble_amplitude
    var radial_speed := cos(wobble_angle) * wobble_amplitude * wobble_cycles
    var tangent := Vector2(
        -sin(_t) * radius + cos(_t) * radial_speed,
        cos(_t) * radius + sin(_t) * radial_speed)
    var heading := atan2(-tangent.x, -tangent.y)
    var next_position := Vector3(cos(_t) * radius, height, sin(_t) * radius)
    global_transform = Transform3D(Basis(Vector3.UP, heading), next_position)


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
