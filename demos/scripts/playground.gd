extends Node3D
## Fenced arena and streaming snow playground.
##
## Desktop: WASD/arrows move, Shift run, Space jump, drag = look, click = throw snowball,
##          wheel = zoom, M = menu, R = reset tracks, 1/2/3 = quality.
## Touch:   left half drag = move joystick, right half drag = camera joystick, tap = throw.

const Props := preload("res://demos/scripts/demo_props.gd")
const DemoCharacter := preload("res://demos/scripts/demo_character.gd")
const DemoSled := preload("res://demos/scripts/demo_sled.gd")
const DemoBall := preload("res://demos/scripts/demo_ball.gd")
const Snowangel := preload("res://demos/scripts/snow_angel.gd")

const FIELD_SIZE := 32.0
const GROUND_Y := -0.3
const SNOWFALL := 0.4
const SLED_PATH := Vector2(10.0, 6.5)
const TILE_QUALITY_PRESETS: Array[DeformableSurfaceQuality] = [
    preload("res://demos/resources/playground/low.tres"),
    preload("res://demos/resources/playground/medium.tres"),
    preload("res://demos/resources/playground/high.tres"),
]

@export var start_infinite := false

@onready var _people: Node3D = $Actors/People
@onready var _mouse: Node3D = $Actors/Mouse
@onready var _soccer_ball: RigidBody3D = $Actors/SoccerBall
@onready var _walls: Array[CollisionShape3D] = [
    $ArenaCollision/EastWall, $ArenaCollision/WestWall,
    $ArenaCollision/SouthWall, $ArenaCollision/NorthWall,
]

var infinite := false
var grid: DeformableSurfaceGrid
var snow: DeformableSurface
var snow_fields: Array[DeformableSurface] = []
var weather: SnowWorldManager
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var camera: DemoCamera
var _ground: MeshInstance3D
var _snow_root: Node3D
var _fence: Node3D
var _arena_size := FIELD_SIZE
var player: DemoCharacter
var sled: DemoSled
var ui: DemoHud
var settings: DemoSettings
var stick: TouchSticks
var _shell: DemoShell

var _rng := RandomNumberGenerator.new()
var _obstacles: Array[Vector3] = []
var _balls: Array[DemoBall] = []
var _penguins: Array[DemoCharacter] = []
var _yeti: DemoCharacter

var _quality := DeformableSurfaceQuality.platform_tier()
var _sun_height := 30.0
var _run_button := false
var _touch_ui := false
var _mouse_emulates_touch := bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false))

# pointer state
var _mouse_down := false
var _mouse_look_ok := false   # the drag began on the right half, the only place that moves the camera
var _mouse_start := Vector2.ZERO
var _mouse_moved := false
var _mouse_t := 0
var _hud_t := 0.0

## Lets tests/automation drive the player without input events.
var debug_move := Vector2.ZERO


func _ready() -> void:
    _shell = DemoShell.attach(self, true)
    _rng.seed = 1234
    _touch_ui = DisplayServer.is_touchscreen_available()
    _build_environment()
    _build_scenery()
    _build_actors()
    infinite = start_infinite
    camera.follow_target = player
    _build_snow(_snow_profile(), _presets()[_quality])
    _update_arena()
    camera.update_view()
    _build_ui()
    _set_sun(_sun_height)
    if _touch_ui:
        ui.set_hint("Left side: move   |   Right side: drag to turn the camera, tap to throw", 12.0)
    else:
        ui.set_hint("WASD move | Shift run | Space jump | drag to look | click to throw | wheel zoom | M menu", 12.0)


# ================================================================ world setup

func _build_environment() -> void:
    sky_mat = ProceduralSkyMaterial.new()
    var sky := Sky.new()
    sky.sky_material = sky_mat
    env = Environment.new()
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_density = 0.008
    var we := WorldEnvironment.new()
    we.environment = env
    add_child(we)

    sun = DirectionalLight3D.new()
    sun.shadow_enabled = not _touch_ui
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    sun.directional_shadow_max_distance = 40.0
    sun.shadow_bias = 0.05
    add_child(sun)

    camera = DemoCamera.new()
    camera.auto_update = false
    camera.focus_offset = Vector3(0, 1.2, 0)
    camera.follow_speed = 12.0
    camera.minimum_height = 0.5
    camera.pitch_limits = Vector2(0.08, 1.3)
    camera.distance_limits = Vector2(3.0, 16.0)
    camera.fov = 65.0
    camera.far = 400.0
    camera.current = true
    add_child(camera)


func _build_snow(profile: DeformableSurfaceType, quality: DeformableSurfaceQuality) -> void:
    if infinite:
        grid = DeformableSurfaceGrid.new()
        grid.name = "SurfaceGrid"
        grid.tile_size = FIELD_SIZE
        grid.surface_type = profile
        grid.quality = quality
        grid.sun = sun
        grid.follow_target = player
        grid.priority_camera = camera
        add_child(grid)
        _snow_root = grid
        snow_fields = grid.fields
        snow = grid.field_at(Vector2i.ZERO)
    else:
        grid = null
        snow = DeformableSurface.new()
        snow.name = "DeformableSurface"
        snow.quality = quality
        snow.size = _arena_size
        snow.surface_type = profile
        snow.sun = sun
        add_child(snow)
        _snow_root = snow
        snow_fields = [snow]


func _presets() -> Array[DeformableSurfaceQuality]:
    return TILE_QUALITY_PRESETS if infinite else DemoSettings.QUALITY_PRESETS


func set_infinite(enabled: bool) -> void:
    if infinite == enabled:
        return
    var profile := settings.current_profile()
    var quality := settings.current_quality()
    infinite = enabled
    settings.quality_presets = _presets()
    if settings.quality_index < settings.quality_presets.size():
        quality = settings.quality_presets[settings.quality_index]

    _snow_root.free()
    _build_snow(profile, quality)
    settings.replace_fields(snow_fields)
    if grid:
        grid.relocation_blocked = settings.has_pending_surface_updates
    _update_arena()
    ui.set_value("infinite", infinite)
    ui.set_slider_editable("surface.area_size", not infinite)
    ui.set_hint("Infinite snowfields enabled. Tracks cleared." if infinite
            else "Fenced arena enabled. Tracks cleared.", 3.0)


func _resize_arena(size: float) -> void:
    if infinite or is_equal_approx(size, _arena_size):
        return
    _arena_size = size
    snow.size = size
    _update_arena()


func _update_arena() -> void:
    var half := _arena_size * 0.5
    var actor_extent := 1000000.0 if infinite else half - 0.8
    player.half_extent = actor_extent
    for penguin in _penguins:
        penguin.half_extent = actor_extent

    var arena_scale := 1.0 if infinite else minf(1.0, _arena_size / FIELD_SIZE)
    sled.amp = SLED_PATH * arena_scale
    _yeti.circle_center = Vector3(-2.0, 0, -10.5) * arena_scale
    _yeti.circle_radius = 3.2 * arena_scale
    for ball in _balls:
        ball.half = (FIELD_SIZE * 0.5 if infinite else half) - 1.5

    var village_half := FIELD_SIZE * 0.5 if infinite else half
    for person: SnowNPC in _people.get_children():
        person.bounds = Vector2.ONE * (village_half - 1.0)
    _mouse.set("bounds", Vector2.ONE * (village_half - 1.0))
    _update_fence(half)

    if infinite:
        return
    var bounded := _constrain_target(player.position, 0.8)
    if not bounded.is_equal_approx(player.position):
        player.position = bounded
        camera.update_view()
    for penguin in _penguins:
        penguin.position = _constrain_target(penguin.position, 0.8)
    for person: Node3D in _people.get_children():
        person.position = _constrain_target(person.position, 1.0)
    _mouse.position = _constrain_target(_mouse.position, 1.0)
    if not _constrain_target(_soccer_ball.position, 0.5).is_equal_approx(_soccer_ball.position):
        _soccer_ball.position = Vector3(2.5, 0.35, -2.5)
        _soccer_ball.linear_velocity = Vector3.ZERO
        _soccer_ball.angular_velocity = Vector3.ZERO
    _ground.position.x = 0.0
    _ground.position.z = 0.0


func _update_fence(half: float) -> void:
    if _fence:
        _fence.free()
        _fence = null
    for wall in _walls:
        wall.disabled = infinite
    if infinite:
        return
    var edge := half + 0.25
    _walls[0].position.x = edge
    _walls[1].position.x = -edge
    _walls[2].position.z = edge
    _walls[3].position.z = -edge
    (_walls[0].shape as BoxShape3D).size.z = _arena_size + 1.0
    (_walls[2].shape as BoxShape3D).size.x = _arena_size + 1.0

    _fence = Node3D.new()
    _fence.name = "Fence"
    add_child(_fence)
    Props.add_fence(_fence, half, GROUND_Y)


func _snow_profile() -> DeformableSurfaceType:
    var profile := DemoSettings.SNOW_PROFILE.duplicate() as DeformableSurfaceType
    profile.recovery_intensity = SNOWFALL
    return profile


func _build_scenery() -> void:
    # Wide ground + distant hills + forests so the horizon looks natural.
    _ground = Props.add_mesh(self, PlaneMesh.new(), Color(0.88, 0.91, 0.97), Vector3(0, GROUND_Y, 0))
    (_ground.mesh as PlaneMesh).size = Vector2(800, 800)
    _ground.material_override = Props.mat(Color(0.88, 0.91, 0.97), 1.0)
    _ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    Props.add_hills(self, _rng, GROUND_Y)
    _add_forest(46, Vector2(1.5, 12.0), Vector2(0.8, 1.5), true)
    _add_forest(170, Vector2(22.0, 75.0), Vector2(1.2, 2.6), false)

    # Obstacles inside the field, kept away from the sled path, yeti loop and spawn point.
    var keep := DemoSled.sample_path(SLED_PATH)
    for i in 24:
        var a := TAU * float(i) / 24.0
        keep.append(Vector2(-2.0 + cos(a) * 3.2, -10.5 + sin(a) * 3.2))
    for i in 7:
        var p := _free_spot(keep, 2.4, 11.5)
        var r := _rng.randf_range(0.5, 1.1)
        Props.add_rock(self, Vector3(p.x, 0, p.y), r, _rng.randf() * 360.0)
        _obstacles.append(Vector3(p.x, r * 0.9, p.y))
        keep.append(p)
    for i in 4:
        var p := _free_spot(keep, 2.4, 11.5)
        Props.add_snowman(self, Vector3(p.x, 0, p.y), _rng.randf() * 360.0)
        _obstacles.append(Vector3(p.x, 0.65, p.y))
        keep.append(p)


func _add_forest(count: int, band: Vector2, tree_scale: Vector2, cast_shadows: bool) -> void:
    var forest := PineForest.new()
    forest.position.y = GROUND_Y
    forest.visual_only = true
    forest.cast_shadows = cast_shadows
    forest.scatter_ring(_rng, count, FIELD_SIZE * 0.5, band, tree_scale)
    add_child(forest)


func _free_spot(keep: PackedVector2Array, margin: float, extent: float) -> Vector2:
    var best := Vector2(extent, extent)
    for attempt in 80:
        var p := Vector2(_rng.randf_range(-extent, extent), _rng.randf_range(-extent, extent))
        if p.length() < 4.5:
            continue
        var ok := true
        for k in keep:
            if p.distance_to(k) < margin:
                ok = false
                break
        if ok:
            return p
        best = p
    return best


func _build_actors() -> void:
    player = _make_character("explorer", DemoCharacter.Role.PLAYER)
    player.position = Vector3(0, 0, 4.0)
    player.obstacles = _obstacles
    add_child(player)

    # weather follows the player
    weather = SnowWorldManager.new()
    weather.name = "SnowWorldManager"
    var profile := DemoSettings.WEATHER_PRESETS[1].duplicate() as SnowWeatherSettings
    var tier := DemoSettings.WEATHER_PRESETS[_quality]
    profile.flake_count = tier.flake_count
    profile.near_flake_count = tier.near_flake_count
    profile.quality = tier.quality
    profile.wind.y = 0.09
    profile.snowfall_intensity = SNOWFALL
    weather.weather_settings = profile
    add_child(weather)
    weather.follow_target = player

    sled = (load("res://demos/props/sled.tscn") as PackedScene).instantiate() as DemoSled
    add_child(sled)

    var snowangel := Snowangel.make(self, Vector3(5.0, 0.0, 5.0))
    snowangel.cycles = 10

    _yeti = _make_character("yeti", DemoCharacter.Role.WANDERER)
    add_child(_yeti)

    var prev: Node3D = player
    for i in 3:
        var pg := _make_character("penguin", DemoCharacter.Role.FOLLOWER)
        pg.follow_target = prev
        pg.follow_distance = 1.1 + 0.1 * float(i)
        pg.obstacles = _obstacles
        pg.position = Vector3(0.4 * float(i + 1) - 1.0, 0, 5.8 + 0.9 * float(i))
        add_child(pg)
        _penguins.append(pg)
        prev = pg

    var cols := [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.95), Color(0.95, 0.6, 0.1),
            Color(0.2, 0.75, 0.4), Color(0.8, 0.3, 0.85), Color(0.95, 0.85, 0.2)]
    for i in 6:
        var b := (load("res://demos/props/ball.tscn") as PackedScene).instantiate() as DemoBall
        b.kind = DemoBall.Kind.BOUNCER
        b.radius = _rng.randf_range(0.3, 0.45)
        b.color = cols[i]
        b.bounce_speed = _rng.randf_range(6.5, 9.0)
        var ang := _rng.randf() * TAU
        b.velocity = Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(1.5, 4.0)
        b.position = Vector3(_rng.randf_range(-10, 10), b.radius + _rng.randf() * 2.0, _rng.randf_range(-10, 10))
        add_child(b)
        _balls.append(b)


func _make_character(kind: String, role: int) -> DemoCharacter:
    var c := (load("res://demos/characters/%s.tscn" % kind) as PackedScene).instantiate() as DemoCharacter
    c.kind = kind
    c.role = role as DemoCharacter.Role
    return c


func _build_ui() -> void:
    ui = _shell.hud
    ui.set_title("Playground")
    settings = _shell.bind_surfaces(snow_fields)
    settings.quality_presets = _presets()
    settings.quality_index = _quality
    settings.area_handler = _resize_arena
    settings.sun_handler = _set_sun
    settings.add_surface_tab()
    ui.set_slider_editable("surface.area_size", not infinite)
    if grid:
        grid.relocation_blocked = settings.has_pending_surface_updates
    settings.add_weather_tab(weather)
    settings.add_graphics_tab(sun, _sun_height)
    var scene_tab := ui.add_tab("Scene")
    ui.add_toggle(scene_tab, "infinite", "Infinite", infinite)
    ui.add_toggle(scene_tab, "people", "Wandering NPCs", true)
    ui.add_toggle(scene_tab, "mouse", "Mouse", true)
    ui.add_toggle(scene_tab, "soccer_ball", "Soccer ball", true)
    ui.add_toggle(scene_tab, "sled", "Sled (figure-8)", true)
    ui.add_toggle(scene_tab, "balls", "Bouncing balls", true)
    ui.add_toggle(scene_tab, "yeti", "Yeti", true)
    ui.add_toggle(scene_tab, "penguins", "Penguin parade", true)
    ui.add_button(scene_tab, "storm", "Snowball storm")
    ui.changed.connect(_on_ui)
    stick = _shell.sticks
    stick.tapped.connect(_throw_at)


# ================================================================ settings

func _set_sun(height_deg: float) -> void:
    _sun_height = height_deg
    sun.rotation_degrees = Vector3(-height_deg, 35.0, 0.0)
    var k := inverse_lerp(6.0, 70.0, height_deg)
    sun.light_color = Color(1.0, 0.76, 0.58).lerp(Color(1.0, 0.97, 0.93), clampf(k * 1.6, 0.0, 1.0))
    sun.light_energy = lerpf(0.65, 0.85, k)
    var horizon := Color(0.93, 0.70, 0.58).lerp(Color(0.74, 0.85, 0.96), clampf(k * 1.5, 0.0, 1.0))
    var top := Color(0.24, 0.32, 0.58).lerp(Color(0.33, 0.57, 0.9), k)
    sky_mat.sky_top_color = top
    sky_mat.sky_horizon_color = horizon
    sky_mat.ground_horizon_color = horizon
    sky_mat.ground_bottom_color = horizon.darkened(0.1)
    env.fog_light_color = horizon
    env.ambient_light_color = Color(0.55, 0.64, 0.85).lerp(Color(0.62, 0.72, 0.92), k)
    env.ambient_light_energy = lerpf(0.5, 0.6, k)


func _on_ui(key: String, value: Variant) -> void:
    match key:
        "infinite": set_infinite(bool(value))
        "people": _set_actor(_people, bool(value))
        "mouse": _set_actor(_mouse, bool(value))
        "soccer_ball": _set_actor(_soccer_ball, bool(value))
        "sled":
            sled.visible = bool(value)
            sled.set_running(bool(value))
        "balls":
            for ball in _balls:
                _set_actor(ball, bool(value))
        "yeti": _set_actor(_yeti, bool(value))
        "penguins":
            for penguin in _penguins:
                _set_actor(penguin, bool(value))
            if bool(value):
                for i in _penguins.size():
                    var spawn := player.position + Vector3(0.5 * float(i + 1), 0, 1.5 + float(i))
                    _penguins[i].position = _constrain_target(spawn, 0.8)
        "storm": _storm()
        "jump": player.jump()
        "run": _run_button = bool(value)


func _set_actor(actor: Node3D, enabled: bool) -> void:
    actor.visible = enabled
    actor.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
    if not enabled:
        for child in actor.find_children("*", "Node3D", true, false):
            if child is Deformer:
                child.active = false


func _reset_fields() -> void:
    for field in snow_fields:
        field.reset_trails()


func _constrain_target(target: Vector3, margin: float) -> Vector3:
    if not infinite:
        var limit := _arena_size * 0.5 - margin
        target.x = clampf(target.x, -limit, limit)
        target.z = clampf(target.z, -limit, limit)
    return target


func _storm() -> void:
    for i in 14:
        var a := _rng.randf() * TAU
        var d := _rng.randf_range(1.5, 9.0)
        var t := player.position + Vector3(cos(a) * d, 0, sin(a) * d)
        t = _constrain_target(t, 0.8)
        var ball := (load("res://demos/props/ball.tscn") as PackedScene).instantiate() as DemoBall
        ball.kind = DemoBall.Kind.THROWN
        ball.radius = 0.28
        ball.position = t + Vector3(0, _rng.randf_range(9.0, 15.0), 0)
        add_child(ball)
        await get_tree().create_timer(0.07).timeout


func _throw_at(screen_pos: Vector2) -> void:
    var o := camera.project_ray_origin(screen_pos)
    var d := camera.project_ray_normal(screen_pos)
    var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(o, d)
    if hit == null:
        return
    var target: Vector3 = hit
    target = _constrain_target(target, 0.6)
    var ball := (load("res://demos/props/ball.tscn") as PackedScene).instantiate() as DemoBall
    ball.kind = DemoBall.Kind.THROWN
    ball.radius = 0.28
    var start := player.global_position + Vector3(0, 1.4, 0)
    var dist := Vector2(target.x - start.x, target.z - start.z).length()
    var t := clampf(dist / 13.0, 0.45, 1.4)
    var g := DemoBall.GRAVITY
    ball.velocity = Vector3((target.x - start.x) / t,
            (ball.radius - start.y + 0.5 * g * t * t) / t,
            (target.z - start.z) / t)
    ball.position = start
    add_child(ball)
    player.face_towards(target)


# ================================================================ per-frame

func _process(delta: float) -> void:
    var kb := Vector2(
        _key(KEY_D, KEY_RIGHT) - _key(KEY_A, KEY_LEFT),
        _key(KEY_S, KEY_DOWN) - _key(KEY_W, KEY_UP))
    var mv := (kb + stick.move + debug_move).limit_length(1.0)
    player.move_input = Basis(Vector3.UP, camera.yaw) * Vector3(mv.x, 0.0, mv.y)
    player.running = Input.is_key_pressed(KEY_SHIFT) or _run_button

    camera.apply_stick(stick.look, delta)
    camera.update_view(delta)
    if infinite:
        _ground.position.x = player.position.x
        _ground.position.z = player.position.z

    _hud_t -= delta
    if _hud_t <= 0.0:
        _hud_t = 0.4
        ui.set_info("%d FPS  |  %s  |  map %d  |  %d deformers" % [
            Engine.get_frames_per_second(), DemoSettings.QUALITY_NAMES[settings.quality_index],
            snow.quality.res, Deformer.unassigned.size()])


## The explorer moves kinematically without a physics body.
func _physics_process(delta: float) -> void:
    if not _soccer_ball.can_process() or not player.on_ground:
        return
    var away := _soccer_ball.global_position - player.global_position
    away.y = 0.0
    if away.length_squared() > 0.000001 and away.length_squared() < 0.81:
        var speed := player.move_input.length() * player.move_speed
        if player.running:
            speed *= player.run_mult
        _soccer_ball.apply_central_impulse(away.normalized() * (2.0 + speed) * _soccer_ball.mass * delta * 8.0)


func _key(a: Key, b: Key) -> float:
    return 1.0 if (Input.is_key_pressed(a) or Input.is_key_pressed(b)) else 0.0


# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey:
        var k := event as InputEventKey
        if k.pressed and not k.echo:
            match k.keycode:
                KEY_SPACE: player.jump()
                KEY_R: _reset_fields()
                KEY_1: settings.set_quality(0)
                KEY_2: settings.set_quality(1)
                KEY_3: settings.set_quality(2)
    elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            camera.zoom(-0.6)
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            camera.zoom(0.6)
        elif _mouse_emulates_touch:
            pass   # the emulated touch drives the sticks; reacting here too would also turn the camera
        elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
            if mb.pressed:
                _mouse_down = true
                _mouse_look_ok = mb.position.x >= get_viewport().get_visible_rect().size.x * 0.5
                _mouse_moved = false
                _mouse_start = mb.position
                _mouse_t = Time.get_ticks_msec()
            else:
                if _mouse_down and not _mouse_moved and mb.button_index == MOUSE_BUTTON_LEFT \
                        and Time.get_ticks_msec() - _mouse_t < 400:
                    _throw_at(mb.position)
                _mouse_down = false
    elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
        var mm := event as InputEventMouseMotion
        if _mouse_down and not _mouse_emulates_touch:
            if not _mouse_look_ok:
                return
            if mm.position.distance_to(_mouse_start) > 6.0:
                _mouse_moved = true
            if _mouse_moved:
                camera.drag(mm.relative)
