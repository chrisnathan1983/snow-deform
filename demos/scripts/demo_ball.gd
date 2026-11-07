extends Node3D
## BOUNCER: bounces around the arena, cratering the snow on every landing.
## THROWN: a snowball that flies in an arc, splats into a crater, then pops.

const Props := preload("res://demos/scripts/demo_props.gd")

enum Kind { BOUNCER, THROWN }
const GRAVITY := 16.0

var kind := Kind.BOUNCER
var radius := 0.35
var velocity := Vector3.ZERO
var bounce_speed := 7.5
var half := 13.5
var color := Color(0.9, 0.2, 0.2)

var _landed := false
var _t := 0.0


## Unit-radius sphere; authored in demos/props/ball.tscn.
static func build_visual(parent: Node3D) -> void:
    Props.add_mesh(parent, Props.sphere(1.0, 12), Color.WHITE).name = "Sphere"


func _ready() -> void:
    var visual := get_node_or_null("Visual") as Node3D
    if visual == null:
        visual = Node3D.new()
        visual.name = "Visual"
        add_child(visual)
        build_visual(visual)
    visual.scale = Vector3.ONE * radius
    var tint := color if kind == Kind.BOUNCER else Color(0.97, 0.98, 1.0)
    for child in visual.get_children():
        var mi := child as MeshInstance3D
        if mi:
            mi.material_override = Props.mat(tint)


func _impact() -> void:
    var r := 0.62 if kind == Kind.THROWN else radius * 1.2
    var s := 1.0 if kind == Kind.THROWN else 0.85
    var p := Vector3(global_position.x, 0.0, global_position.z)
    for surface in DeformableSurface.instances:
        surface.stamp_at(p, r, s, null, DeformableSurface.StampMode.CARVE, 0.0, 1.0, kind == Kind.THROWN)


func _process(delta: float) -> void:
    if kind == Kind.BOUNCER:
        velocity.y -= GRAVITY * delta
        position += velocity * delta
        if position.y - radius <= 0.0:
            position.y = radius
            velocity.y = bounce_speed
            _impact()
        if absf(position.x) > half:
            position.x = clampf(position.x, -half, half)
            velocity.x = -velocity.x
        if absf(position.z) > half:
            position.z = clampf(position.z, -half, half)
            velocity.z = -velocity.z
        return

    if not _landed:
        velocity.y -= GRAVITY * delta
        position += velocity * delta
        if velocity.y < 0.0 and position.y - radius <= 0.0:
            position.y = radius
            _landed = true
            _impact()
    else:
        _t += delta
        if _t > 0.25:
            scale = Vector3.ONE * maxf(0.0, 1.0 - (_t - 0.25) / 0.2)
        if _t > 0.6:
            queue_free()
