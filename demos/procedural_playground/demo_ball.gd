extends Node3D
## BOUNCER: bounces around the arena, cratering the snow on every landing.
## THROWN: a snowball that flies in an arc, splats into a crater, then pops.

const Props := preload("demo_props.gd")

enum Kind { BOUNCER, THROWN }
const GRAVITY := 16.0

var kind := Kind.BOUNCER
var radius := 0.35
var velocity := Vector3.ZERO
var bounce_speed := 7.5
var half := 13.5
var color := Color(0.9, 0.2, 0.2)

var _deformer: SnowDeformer
var _landed := false
var _t := 0.0


func _ready() -> void:
    Props.add_mesh(self, Props.sphere(radius, 12), color if kind == Kind.BOUNCER else Color(0.97, 0.98, 1.0))
    _deformer = SnowDeformer.new()
    _deformer.position = Vector3(0, -radius, 0)
    if kind == Kind.THROWN:
        _deformer.radius = 0.62
        _deformer.strength = 1.0
        _deformer.active = false          # only stamp on impact
    else:
        _deformer.radius = radius * 1.2
        _deformer.strength = 0.85
    add_child(_deformer)


func _process(delta: float) -> void:
    if kind == Kind.BOUNCER:
        velocity.y -= GRAVITY * delta
        position += velocity * delta
        if position.y - radius <= 0.0:
            position.y = radius
            velocity.y = bounce_speed
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
            _deformer.active = true
    else:
        _t += delta
        if _t > 0.25:
            scale = Vector3.ONE * maxf(0.0, 1.0 - (_t - 0.25) / 0.2)
        if _t > 0.6:
            queue_free()
