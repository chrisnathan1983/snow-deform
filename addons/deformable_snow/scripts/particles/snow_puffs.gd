extends Node3D
## Pool of tiny one-shot CPUParticles3D bursts (kicked-up snow).
## Internal (no class_name); SnowField preloads it.
## CPUParticles are used on purpose: with only a handful of particles per
## burst they are cheap, and they behave identically on every Web/mobile GPU.

const SnowUtil = preload("../utilities/snow_util.gd")

@export var pool_size := 24

var _pool: Array[CPUParticles3D] = []
var _next := 0
var _amount := 8


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = SnowUtil.soft_dot()

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.3, 0.3)
	mesh.material = mat

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.85))
	ramp.set_color(1, Color(1, 1, 1, 0.0))

	for i in pool_size:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = _amount
		p.lifetime = 0.6
		p.local_coords = false   # world space: puffs stay put after the node moves
		p.mesh = mesh
		p.color_ramp = ramp
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.1
		p.direction = Vector3.UP
		p.spread = 55.0
		p.gravity = Vector3(0, -2.5, 0)
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.4
		p.damping_min = 1.0
		p.damping_max = 2.0
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_pool.append(p)


func set_amount(n: int) -> void:
	if _amount == n:
		return
	_amount = n
	for p in _pool:
		if p.amount != n:
			p.amount = n


## `push` biases the spray direction (e.g. opposite to travel for a sled).
func burst(world_pos: Vector3, radius: float, push := Vector3.ZERO) -> void:
	if _pool.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	var k := clampf(radius / 0.2, 0.5, 3.0)
	p.global_position = world_pos + Vector3(0, 0.05, 0)
	p.scale_amount_min = 0.5 * k
	p.scale_amount_max = 1.0 * k
	p.emission_sphere_radius = radius * 0.5
	p.direction = (Vector3.UP + push.normalized() * 0.7).normalized()
	p.restart()
	p.emitting = true
