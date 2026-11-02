extends Node3D
## A snow angel: presses a body + head into the snow, then sweeps arms and legs through the
## snow like a real one, leaving fan-shaped "wings" and a skirt.
##
## It only uses SnowDeformer from the Deformable Snow addon, so you can copy this single file
## into your own game.
##
## Usage:
##     const SnowAngel := preload("res://path/to/snow_angel.gd")
##     var angel := SnowAngel.make(self, ground_position, yaw)   # head points along -Z of yaw
##     await angel.finished                                       # limbs are done sweeping
##
## `ground_position` is the centre of the torso. Y should be the snow surface height.
## `yaw` is a rotation around Y (radians); the head points along the node's forward (-Z) axis.
## The angel is removed automatically when finished; the marks stay (and heal with snowfall).
##
## How the wings are made: each limb is ONE elongated deformer. A deformer that only rotates in
## place does not stamp, so the limb's centre also travels along an arc around the shoulder/hip
## while its heading follows the limb direction. Consecutive stamps overlap into a solid fan.

signal finished

# Layout in "size 1.0" units. +Z points toward the feet, -Z toward the head.
const SHOULDER := Vector3(0.20, 0.0, -0.50)
const HIP := Vector3(0.10, 0.0, 0.30)
const HEAD_Z := -0.90
const TORSO_Z := -0.10
const ARM_LEN := 0.90
const LEG_LEN := 0.85
const ARM_ASPECT := 5.0
const LEG_ASPECT := 4.0
const ARM_ANGLES := Vector2(12.0, 165.0)   # degrees: 0 = along the body toward the feet, 180 = over the head
const LEG_ANGLES := Vector2(3.0, 34.0)

## Overall scale (1.0 fits a ~1.8 m tall person).
var size := 1.0
## Seconds spent sweeping arms and legs.
var sweep_time := 2.4
## Seconds between pressing the body in and starting the sweep.
var settle_time := 0.3
## Number of out-and-back sweeps.
var cycles := 2.0
## Depth of the body and head prints (0..1).
var body_strength := 1.0
## Depth of the wings and skirt (0..1). Slightly shallower than the body looks best.
var wing_strength := 0.7

class Limb:
    var node: SnowDeformer
    var side := 1.0
    var arm := true

var _limbs: Array[Limb] = []
var _t := 0.0
var _sweeping := false
var _end_frames := 0


## Creates an angel under `parent`, centred at `world_position`, head toward `yaw`'s forward.
static func make(parent: Node3D, world_position: Vector3, yaw := 0.0, angel_size := 1.0,
        sweep_seconds := 2.4) -> Node3D:
    var a: Node3D = new()
    a.size = angel_size
    a.sweep_time = sweep_seconds
    a.position = world_position
    a.rotation.y = yaw
    parent.add_child(a)
    return a


func _ready() -> void:
    # Body and head: pressed in once.
    var torso := _deformer(0.28, 2.6, body_strength, true)
    torso.position = Vector3(0, 0, TORSO_Z) * size
    var head := _deformer(0.17, 1.0, body_strength, true)
    head.position = Vector3(0, 0, HEAD_Z) * size

    # Limbs: one elongated deformer each, posed (and swung) by _pose().
    for side in [-1.0, 1.0]:
        var sx: float = side
        _add_limb(sx, true)
        _add_limb(sx, false)
    _pose(0.0)


func _process(delta: float) -> void:
    _t += delta
    if _t < settle_time:
        return
    var p := clampf((_t - settle_time) / sweep_time, 0.0, 1.0)
    if not _sweeping:
        _sweeping = true
        for l in _limbs:
            l.node.active = true
    # 0 -> 1 -> 0 per cycle (arms/legs out and back)
    _pose(0.5 - 0.5 * cos(TAU * cycles * p))
    if p >= 1.0:
        # Give the snow field a couple of frames to stamp the final pose before cleaning up.
        _end_frames += 1
        if _end_frames >= 3:
            set_process(false)
            for l in _limbs:
                l.node.active = false
            finished.emit()
            queue_free()


func _pose(s: float) -> void:
    var arm_a := deg_to_rad(lerpf(ARM_ANGLES.x, ARM_ANGLES.y, s))
    var leg_a := deg_to_rad(lerpf(LEG_ANGLES.x, LEG_ANGLES.y, s))
    for l in _limbs:
        var a := arm_a if l.arm else leg_a
        var length := ARM_LEN if l.arm else LEG_LEN
        var origin := SHOULDER if l.arm else HIP
        var dir := Vector3(l.side * sin(a), 0.0, cos(a))
        var base := Vector3(l.side * origin.x, 0.0, origin.z)
        # centre of the limb, rotated so the elongated print lies along the limb
        l.node.position = (base + dir * (length * 0.5)) * size
        l.node.rotation.y = atan2(-dir.x, -dir.z)


func _add_limb(side: float, arm: bool) -> void:
    var l := Limb.new()
    l.side = side
    l.arm = arm
    var length := ARM_LEN if arm else LEG_LEN
    var aspect := ARM_ASPECT if arm else LEG_ASPECT
    # print half-length = radius * sqrt(aspect)  ->  pick radius so it matches the limb
    var radius := length * 0.5 / sqrt(aspect)
    l.node = _deformer(radius, aspect, wing_strength, false)
    l.node.puff_on_touchdown = false
    l.node.puff_distance = 0.4 * size      # sprays powder as the limb sweeps
    _limbs.append(l)


func _deformer(radius: float, aspect: float, strength: float, active: bool) -> SnowDeformer:
    var d := SnowDeformer.new()
    d.radius = radius * size
    d.aspect = aspect
    d.strength = strength
    d.active = active
    add_child(d)
    return d
