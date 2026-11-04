extends Node3D
## A simple primitive-mesh character that leaves footprints via DeformerFootsteps.
## kind: "explorer" (player), "yeti", "penguin". Origin is at the feet, facing -Z.

const Props := preload("res://demos/common/demo_props.gd")

enum Role { PLAYER, WANDERER, FOLLOWER }

const GRAVITY := 16.0
const JUMP_SPEED := 6.0

var kind := "explorer"
var role := Role.WANDERER

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

var move_speed := 3.2
var run_mult := 1.9
var body_radius := 0.3
var half_extent := 15.2
var obstacles: Array[Vector3] = []   # (x, radius, z)

var on_ground := true
var _vy := 0.0
var _visual: Node3D
var _foot: DeformerFootsteps
var _speed := 0.0
var _bob := 0.0
var _last_pos := Vector3.ZERO
var _bob_amp := 0.07
var _roll_amp := 0.05


func _ready() -> void:
    # Character scenes (demos/common/characters/) ship their meshes under "Visual";
    # without one the body is built in code.
    _visual = get_node_or_null("Visual") as Node3D
    var has_authored_visual := _visual != null
    if not has_authored_visual:
        _visual = Node3D.new()
        _visual.name = "Visual"
        add_child(_visual)
    var foot_radius := 0.2
    var foot_aspect := 2.2
    var spread := 0.12
    var stride_min := 0.14
    var stride_max := 0.38
    var strength := 1.0
    match kind:
        "yeti":
            if not has_authored_visual:
                _build_yeti()
            foot_radius = 0.4
            foot_aspect = 1.7
            spread = 0.34
            stride_min = 0.3
            stride_max = 0.65
            body_radius = 0.7
            move_speed = 2.0
            _bob_amp = 0.12
            _roll_amp = 0.04
        "penguin":
            if not has_authored_visual:
                _build_penguin()
            foot_radius = 0.13
            foot_aspect = 1.6
            spread = 0.08
            stride_min = 0.07
            stride_max = 0.14
            strength = 0.8
            body_radius = 0.2
            move_speed = 3.0
            _bob_amp = 0.03
            _roll_amp = 0.24
        _:
            if not has_authored_visual:
                _build_explorer()
    _foot = DeformerFootsteps.new()
    _foot.foot_radius = foot_radius
    _foot.foot_aspect = foot_aspect
    _foot.spread = spread
    _foot.stride_min = stride_min
    _foot.stride_max = stride_max
    add_child(_foot)
    for c in _foot.get_children():
        if c is Deformer:
            (c as Deformer).strength = strength
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
    _visual.position.y = absf(sin(_bob)) * _bob_amp * k
    _visual.rotation.z = sin(_bob) * _roll_amp * k


# ---------------------------------------------------------------- visuals

func _build_explorer() -> void:
    var v := _visual
    var dark := Color(0.14, 0.14, 0.2)
    Props.add_mesh(v, Props.capsule(0.27, 1.05), Color(0.82, 0.16, 0.18), Vector3(0, 0.8, 0))
    Props.add_mesh(v, Props.cylinder(0.09, 0.5, 8), dark, Vector3(-0.1, 0.25, 0))
    Props.add_mesh(v, Props.cylinder(0.09, 0.5, 8), dark, Vector3(0.1, 0.25, 0))
    Props.add_mesh(v, Props.box(Vector3(0.14, 0.1, 0.3)), Color(0.3, 0.2, 0.12), Vector3(-0.1, 0.05, -0.04))
    Props.add_mesh(v, Props.box(Vector3(0.14, 0.1, 0.3)), Color(0.3, 0.2, 0.12), Vector3(0.1, 0.05, -0.04))
    Props.add_mesh(v, Props.sphere(0.21), Color(0.96, 0.78, 0.65), Vector3(0, 1.57, 0))
    Props.add_mesh(v, Props.cone(0.24, 0.34, 10), Color(0.2, 0.4, 0.85), Vector3(0, 1.9, 0))
    Props.add_mesh(v, Props.sphere(0.07, 8), Color(1, 1, 1), Vector3(0, 2.08, 0))
    Props.add_mesh(v, Props.cylinder(0.3, 0.1, 10), Color(0.95, 0.8, 0.2), Vector3(0, 1.34, 0))
    Props.add_mesh(v, Props.sphere(0.03, 6), Color(0.05, 0.05, 0.08), Vector3(-0.08, 1.6, -0.19))
    Props.add_mesh(v, Props.sphere(0.03, 6), Color(0.05, 0.05, 0.08), Vector3(0.08, 1.6, -0.19))
    Props.add_mesh(v, Props.sphere(0.035, 6), Color(1.0, 0.55, 0.2), Vector3(0, 1.55, -0.21))
    Props.add_mesh(v, Props.box(Vector3(0.3, 0.4, 0.15)), Color(0.45, 0.3, 0.15), Vector3(0, 0.95, 0.27))


func _build_yeti() -> void:
    var v := _visual
    var fur := Color(0.82, 0.88, 0.97)
    var dark := Color(0.2, 0.25, 0.38)
    Props.add_mesh(v, Props.cylinder(0.17, 0.7, 8), fur, Vector3(-0.3, 0.4, 0))
    Props.add_mesh(v, Props.cylinder(0.17, 0.7, 8), fur, Vector3(0.3, 0.4, 0))
    Props.add_mesh(v, Props.box(Vector3(0.3, 0.12, 0.5)), dark, Vector3(-0.3, 0.06, -0.05))
    Props.add_mesh(v, Props.box(Vector3(0.3, 0.12, 0.5)), dark, Vector3(0.3, 0.06, -0.05))
    Props.add_mesh(v, Props.sphere(0.62), fur, Vector3(0, 1.3, 0), Vector3(1.0, 1.15, 0.95))
    Props.add_mesh(v, Props.capsule(0.15, 0.95), fur, Vector3(-0.78, 1.2, -0.05), Vector3.ONE, Vector3(0, 0, 14))
    Props.add_mesh(v, Props.capsule(0.15, 0.95), fur, Vector3(0.78, 1.2, -0.05), Vector3.ONE, Vector3(0, 0, -14))
    Props.add_mesh(v, Props.sphere(0.38), fur, Vector3(0, 2.15, -0.05))
    Props.add_mesh(v, Props.sphere(0.26, 10), Color(0.7, 0.8, 0.95), Vector3(0, 2.1, -0.22), Vector3(1.0, 0.85, 0.6))
    Props.add_mesh(v, Props.sphere(0.05, 6), Color(0.04, 0.04, 0.08), Vector3(-0.13, 2.2, -0.34))
    Props.add_mesh(v, Props.sphere(0.05, 6), Color(0.04, 0.04, 0.08), Vector3(0.13, 2.2, -0.34))
    Props.add_mesh(v, Props.box(Vector3(0.22, 0.05, 0.05)), Color(0.15, 0.08, 0.1), Vector3(0, 2.02, -0.36))
    Props.add_mesh(v, Props.cone(0.07, 0.25, 6), Color(0.95, 0.95, 0.9), Vector3(-0.22, 2.5, 0), Vector3.ONE, Vector3(0, 0, 20))
    Props.add_mesh(v, Props.cone(0.07, 0.25, 6), Color(0.95, 0.95, 0.9), Vector3(0.22, 2.5, 0), Vector3.ONE, Vector3(0, 0, -20))


func _build_penguin() -> void:
    var v := _visual
    var dark := Color(0.1, 0.12, 0.18)
    var orange := Color(1.0, 0.6, 0.15)
    Props.add_mesh(v, Props.capsule(0.2, 0.7), dark, Vector3(0, 0.45, 0))
    Props.add_mesh(v, Props.sphere(0.17, 10), Color(0.97, 0.97, 1.0), Vector3(0, 0.45, -0.09), Vector3(1.0, 1.3, 0.6))
    Props.add_mesh(v, Props.sphere(0.14, 10), dark, Vector3(0, 0.88, 0))
    Props.add_mesh(v, Props.cone(0.04, 0.12, 6), orange, Vector3(0, 0.85, -0.18), Vector3.ONE, Vector3(-90, 0, 0))
    Props.add_mesh(v, Props.sphere(0.025, 6), Color(1, 1, 1), Vector3(-0.06, 0.92, -0.11))
    Props.add_mesh(v, Props.sphere(0.025, 6), Color(1, 1, 1), Vector3(0.06, 0.92, -0.11))
    Props.add_mesh(v, Props.box(Vector3(0.04, 0.28, 0.12)), dark, Vector3(-0.22, 0.5, 0), Vector3.ONE, Vector3(0, 0, 15))
    Props.add_mesh(v, Props.box(Vector3(0.04, 0.28, 0.12)), dark, Vector3(0.22, 0.5, 0), Vector3.ONE, Vector3(0, 0, -15))
    Props.add_mesh(v, Props.box(Vector3(0.1, 0.03, 0.16)), orange, Vector3(-0.08, 0.02, -0.04))
    Props.add_mesh(v, Props.box(Vector3(0.1, 0.03, 0.16)), orange, Vector3(0.08, 0.02, -0.04))
