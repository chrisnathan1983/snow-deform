extends Node3D
## A simple primitive-mesh character that leaves footprints via DeformerFootsteps.
## Origin is at the feet, facing -Z.

enum Role { PLAYER, WANDERER, FOLLOWER }

const GRAVITY := 16.0
const JUMP_SPEED := 6.0

var role := Role.WANDERER

@export var body_radius := 0.3
@export var move_speed := 3.2
@export var bob_amplitude := 0.07
@export var roll_amplitude := 0.05

# PLAYER: world-space input direction (length 0..1), set by the demo every frame.
var move_input := Vector3.ZERO
var running := false

# WANDERER: walks a circle.
var circle_center := Vector3.ZERO
var circle_radius := 3.0
var phase := 0.0

# FOLLOWER: trails another node.
var follow_target: Node3D
var follow_distance := 1.2

var run_mult := 1.9
var half_extent := 15.2
var obstacles: Array[Vector3] = []   # (x, radius, z)

var on_ground := true
var _vy := 0.0
@onready var _foot: DeformerFootsteps = $DeformerFootsteps
var _speed := 0.0
var _bob := 0.0
var _last_pos := Vector3.ZERO

@onready var _visual: Node3D = $Visual


func _ready() -> void:
    _last_pos = position


func jump() -> void:
    if on_ground:
        _vy = JUMP_SPEED
        on_ground = false


func face_towards(target: Vector3) -> void:
    var d := target - global_position
    d.y = 0.0
    if d.length() > 0.01:
        rotation.y = atan2(-d.x, -d.z)


func _process(delta: float) -> void:
    match role:
        Role.PLAYER:
            _process_player(delta)
        Role.WANDERER:
            _process_wander(delta)
        Role.FOLLOWER:
            _process_follow(delta)
    _animate(delta)


func _process_player(delta: float) -> void:
    var spd := move_speed * (run_mult if running else 1.0)
    var vel := move_input * spd
    position.x += vel.x * delta
    position.z += vel.z * delta
    if move_input.length() > 0.08:
        _turn_towards(move_input, delta)
    # Jumping / gravity. DeformerFootsteps can't detect airborne state, so we pause it.
    if not on_ground:
        _vy -= GRAVITY * delta
        position.y += _vy * delta
        if position.y <= 0.0:
            position.y = 0.0
            _vy = 0.0
            on_ground = true
    _foot.active = on_ground
    _collide()


func _process_wander(delta: float) -> void:
    phase += move_speed / circle_radius * delta
    var target := circle_center + Vector3(cos(phase) * circle_radius, 0.0, sin(phase) * circle_radius)
    var d := target - position
    if delta > 0.0 and d.length() > 0.0001:
        _turn_towards(d, delta)
    position = target


func _process_follow(delta: float) -> void:
    if not is_instance_valid(follow_target):
        return
    var to := follow_target.global_position - position
    to.y = 0.0
    var dist := to.length()
    if dist > follow_distance:
        var dir := to / dist
        var spd := clampf(move_speed + (dist - follow_distance) * 1.4, 0.0, move_speed * 2.4)
        var step := minf(spd * delta, dist - follow_distance)
        position += dir * step
        _turn_towards(dir, delta)
    _collide()


func _turn_towards(dir: Vector3, delta: float) -> void:
    var target_yaw := atan2(-dir.x, -dir.z)
    rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))


func _collide() -> void:
    position.x = clampf(position.x, -half_extent, half_extent)
    position.z = clampf(position.z, -half_extent, half_extent)
    for o in obstacles:
        var dx := position.x - o.x
        var dz := position.z - o.z
        var min_d := o.y + body_radius
        var d2 := dx * dx + dz * dz
        if d2 < min_d * min_d and d2 > 0.000001:
            var d := sqrt(d2)
            position.x = o.x + dx / d * min_d
            position.z = o.z + dz / d * min_d


func _animate(delta: float) -> void:
    var moved := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length()
    _last_pos = position
    var inst := moved / maxf(delta, 0.0001)
    _speed = lerpf(_speed, inst, 1.0 - exp(-10.0 * delta))
    var k := clampf(_speed / 3.0, 0.0, 1.0)
    _bob += _speed * delta * 3.2
    _visual.position.y = absf(sin(_bob)) * bob_amplitude * k
    _visual.rotation.z = sin(_bob) * roll_amplitude * k
