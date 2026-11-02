extends Node3D
## Deformable Snow - demo scene.
##
## Everything is built from code and primitive meshes, so the only requirement is the
## addon at res://addons/deformable_snow/ and the Compatibility renderer.
##
## Desktop: WASD/arrows move, Shift run, Space jump, drag = look, click = throw snowball,
##          wheel = zoom, M = menu, R = reset tracks, 1/2/3 = quality.
## Touch:   left half = floating joystick, right half = drag to look / tap to throw.

const Props := preload("demo_props.gd")
const DemoCharacter := preload("demo_character.gd")
const DemoSled := preload("demo_sled.gd")
const DemoBall := preload("demo_ball.gd")
const DemoUI := preload("demo_ui.gd")
const DemoStick := preload("demo_stick.gd")
const Snowangel := preload("snow_angel.gd")

const FIELD_SIZE := 32.0
const HALF := FIELD_SIZE * 0.5
const GROUND_Y := -0.3
const QUALITY_NAMES := ["Low", "Medium", "High"]

## The refill shader's `seed` uniform is never updated by the addon (v0.1.0), which makes tracks
## stop healing before they fully disappear. Setting it here keeps the demo looking right.
## Set to false to see the addon's unpatched behaviour.
const APPLY_SEED_WORKAROUND := true

var snow: SnowField
var snow_fields: Array[SnowField] = []
var weather: SnowWorldManager
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var camera: Camera3D
var _ground: MeshInstance3D
var player: DemoCharacter
var sled: DemoSled
var ui: DemoUI
var stick: DemoStick

var _rng := RandomNumberGenerator.new()
var _obstacles: Array[Vector3] = []
var _balls: Array[Node3D] = []
var _penguins: Array[Node3D] = []
var _yeti: Node3D
var _snowangel: Snowangel

var _quality := 1
var _snowfall := 0.4
var _wind := 0.3
var _sun_height := 30.0
var _run_button := false
var _touch_ui := false

# camera
var _yaw := 0.0
var _pitch := 0.42
var _dist := 7.5
var _cam_ready := false

# pointer state
var _touches := {}
var _stick_index := -1
var _mouse_down := false
var _mouse_start := Vector2.ZERO
var _mouse_moved := false
var _mouse_t := 0
var _hud_t := 0.0

## Lets tests/automation drive the player without input events.
var debug_move := Vector2.ZERO


func _ready() -> void:
    _rng.seed = 1234
    _touch_ui = DisplayServer.is_touchscreen_available()
    _build_environment()
    _build_snow()
    _build_scenery()
    _build_actors()
    _build_ui()
    get_viewport().size_changed.connect(_update_ui_scale)
    _update_ui_scale()
    _apply_quality(_quality)
    _set_sun(_sun_height)
    if _touch_ui:
        ui.set_hint("Left side: move   |   Right side: drag to look, tap to throw a snowball", 12.0)
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

    camera = Camera3D.new()
    camera.fov = 65.0
    camera.far = 400.0
    camera.current = true
    add_child(camera)


func _build_snow() -> void:
    snow = SnowField.new()
    snow.name = "SnowField"
    # Profiles are created in code so the demo is independent of the addon's preset .tres files.
    snow.low_surface_quality = _make_profile(384, 64, 4, 0.3, 64)
    snow.medium_surface_quality = _make_profile(768, 128, 8, 1.0, 96)
    snow.high_surface_quality = _make_profile(1024, 192, 12, 1.5, 128)
    snow.sun = sun
    _quality = SnowField.recommended_quality()
    snow.quality = _quality
    snow_fields.append(snow)
    add_child(snow)


func _make_profile(res: int, subdiv: int, puff: int,
        sparkle: float, stamps: int) -> SnowFieldQualitySettings:
    var p := SnowFieldQualitySettings.new()
    p.area_size = FIELD_SIZE
    p.res = res
    p.subdiv = subdiv
    p.puff = puff
    p.sparkle = sparkle
    p.max_stamps_per_frame = stamps
    p.recovery_intensity = _snowfall
    p.max_depth = 0.25
    p.berm_strength = 0.2
    p.berm_height = 0.08
    p.refill_levels_per_sec = 16.0
    return p


func _build_scenery() -> void:
    # Wide ground + distant hills + forests so the horizon looks natural.
    _ground = Props.add_mesh(self, PlaneMesh.new(), Color(0.88, 0.91, 0.97), Vector3(0, GROUND_Y, 0))
    (_ground.mesh as PlaneMesh).size = Vector2(800, 800)
    _ground.material_override = Props.mat(Color(0.88, 0.91, 0.97), 1.0)
    _ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    Props.add_hills(self, _rng, GROUND_Y)
    if _has_fence():
        Props.add_fence(self, HALF, GROUND_Y)
    Props.add_forest(self, _rng, 46, HALF, 1.5, 12.0, 0.8, 1.5, GROUND_Y, true)
    Props.add_forest(self, _rng, 170, HALF, 22.0, 75.0, 1.2, 2.6, GROUND_Y, false)

    # Obstacles inside the field, kept away from the sled path, yeti loop and spawn point.
    var keep := DemoSled.sample_path(Vector2(10.0, 6.5), 120)
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


func _has_fence() -> bool:
    return true


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
    weather.weather_settings = _make_weather_profile(_quality)
    add_child(weather)
    weather.follow_target = player
    for field in snow_fields:
        field.world_manager = weather

    sled = DemoSled.new()
    add_child(sled)

    # torso centre on the snow surface; yaw = rotation around Y, head points along -Z
    var x := 5.0
    var z := 5.0
    var yaw := 0.0
    _snowangel = Snowangel.make(self, Vector3(x, 0.0, z), yaw)
    _snowangel.cycles = 10
    #await _snowangel.finished    # limbs have finished sweeping; the node then frees itself

    _yeti = _make_character("yeti", DemoCharacter.Role.WANDERER)
    _yeti.circle_center = Vector3(-2.0, 0, -10.5)
    _yeti.circle_radius = 3.2
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
        var b := DemoBall.new()
        b.kind = DemoBall.Kind.BOUNCER
        b.radius = _rng.randf_range(0.3, 0.45)
        b.color = cols[i]
        b.half = HALF - 1.5
        b.bounce_speed = _rng.randf_range(6.5, 9.0)
        var ang := _rng.randf() * TAU
        b.velocity = Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(1.5, 4.0)
        b.position = Vector3(_rng.randf_range(-10, 10), b.radius + _rng.randf() * 2.0, _rng.randf_range(-10, 10))
        add_child(b)
        _balls.append(b)


func _make_character(kind: String, role: int) -> DemoCharacter:
    var c := DemoCharacter.new()
    c.kind = kind
    c.role = role
    return c


func _build_ui() -> void:
    ui = DemoUI.new()
    add_child(ui)
    ui.build({
        "quality": _quality, "snowfall": _snowfall, "wind": _wind,
        "sun": _sun_height, "shadows": sun.shadow_enabled, "menu_open": not _touch_ui,
    })
    ui.changed.connect(_on_ui)
    var overlay := CanvasLayer.new()
    overlay.layer = 9
    add_child(overlay)
    stick = DemoStick.new()
    overlay.add_child(stick)


func _update_ui_scale() -> void:
    var vs := get_viewport().get_visible_rect().size
    var short := minf(vs.x, vs.y)
    var s := clampf(short / 480.0, 1.0, 3.5) if _touch_ui else clampf(short / 720.0, 1.0, 2.0)
    ui.set_ui_scale(s)


# ================================================================ settings

func _apply_quality(q: int) -> void:
    _quality = q
    for field in snow_fields:
        field.quality = q
        field.recovery_intensity = _snowfall
    weather.weather_settings = _make_weather_profile(q)
    weather.follow_target = player
    ui.set_quality_selected(q)


func _make_weather_profile(q: int) -> SnowWeatherSettings:
    var profile := SnowWeatherSettings.new()
    match q:
        SnowField.Quality.LOW:
            profile.flake_count = 300
            profile.near_flake_count = 0
        SnowField.Quality.MEDIUM:
            profile.flake_count = 900
            profile.near_flake_count = 120
        SnowField.Quality.HIGH:
            profile.flake_count = 2000
            profile.near_flake_count = 280
    profile.wind = Vector2(_wind, _wind * 0.3)
    profile.snowfall_intensity = _snowfall
    profile.quality = q as SnowWeatherSettings.Quality
    return profile


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
        "quality": _apply_quality(int(value))
        "snowfall":
            _snowfall = float(value)
            for field in snow_fields:
                field.recovery_intensity = _snowfall
            weather.snowfall_intensity = _snowfall
        "wind":
            _wind = float(value)
            weather.wind = Vector2(_wind, _wind * 0.3)
        "sun": _set_sun(float(value))
        "sled":
            sled.visible = bool(value)
            sled.set_running(bool(value))
        "balls": _set_group(_balls, bool(value))
        "yeti": _set_group([_yeti], bool(value))
        "penguins":
            _set_group(_penguins, bool(value))
            if bool(value):
                for i in _penguins.size():
                    _penguins[i].position = player.position + Vector3(0.5 * float(i + 1), 0, 1.5 + float(i))
        "shadows": sun.shadow_enabled = bool(value)
        "reset": _reset_fields()
        "storm": _storm()
        "jump": player.jump()
        "run": _run_button = bool(value)


func _set_group(nodes: Array, on: bool) -> void:
    for n in nodes:
        var node := n as Node3D
        node.visible = on
        node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _reset_fields() -> void:
    for field in snow_fields:
        field.reset_trails()


func _constrain_target(target: Vector3, margin: float) -> Vector3:
    target.x = clampf(target.x, -HALF + margin, HALF - margin)
    target.z = clampf(target.z, -HALF + margin, HALF - margin)
    return target


func _storm() -> void:
    for i in 14:
        var a := _rng.randf() * TAU
        var d := _rng.randf_range(1.5, 9.0)
        var t := player.position + Vector3(cos(a) * d, 0, sin(a) * d)
        t = _constrain_target(t, 0.8)
        var ball := DemoBall.new()
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
    var ball := DemoBall.new()
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
    if APPLY_SEED_WORKAROUND:
        for field in snow_fields:
            var rm: Variant = field.get("_refill_material")
            if rm is ShaderMaterial:
                (rm as ShaderMaterial).set_shader_parameter("seed", _rng.randf() * 1000.0)

    var kb := Vector2(
        _key(KEY_D, KEY_RIGHT) - _key(KEY_A, KEY_LEFT),
        _key(KEY_S, KEY_DOWN) - _key(KEY_W, KEY_UP))
    var mv := (kb + stick.value() + debug_move).limit_length(1.0)
    player.move_input = Basis(Vector3.UP, _yaw) * Vector3(mv.x, 0.0, mv.y)
    player.running = Input.is_key_pressed(KEY_SHIFT) or _run_button

    _update_camera(delta)

    _hud_t -= delta
    if _hud_t <= 0.0:
        _hud_t = 0.4
        ui.set_info("%d FPS  |  %s  |  map %d  |  %d deformers" % [
            Engine.get_frames_per_second(), QUALITY_NAMES[_quality],
            int(snow.get_active_quality_settings().get("res", 0)), SnowDeformer.unassigned.size()])


func _key(a: Key, b: Key) -> float:
    return 1.0 if (Input.is_key_pressed(a) or Input.is_key_pressed(b)) else 0.0


func _update_camera(delta: float) -> void:
    var focus := player.global_position + Vector3(0, 1.2, 0)
    var off := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -_pitch) * Vector3(0, 0, _dist)
    var want := focus + off
    want.y = maxf(want.y, 0.5)
    if not _cam_ready:
        camera.global_position = want
        _cam_ready = true
    else:
        camera.global_position = camera.global_position.lerp(want, 1.0 - exp(-12.0 * delta))
    camera.look_at(focus, Vector3.UP)


# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey:
        var k := event as InputEventKey
        if k.pressed and not k.echo:
            match k.keycode:
                KEY_SPACE: player.jump()
                KEY_M: ui.toggle_menu()
                KEY_R: _reset_fields()
                KEY_1: _apply_quality(0)
                KEY_2: _apply_quality(1)
                KEY_3: _apply_quality(2)
    elif event is InputEventScreenTouch:
        var st := event as InputEventScreenTouch
        if st.pressed:
            _touch_down(st.index, st.position)
        else:
            _touch_up(st.index, st.position)
    elif event is InputEventScreenDrag:
        var sd := event as InputEventScreenDrag
        _touch_drag(sd.index, sd.position, sd.relative)
    elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            _dist = clampf(_dist - 0.6, 3.0, 16.0)
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            _dist = clampf(_dist + 0.6, 3.0, 16.0)
        elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
            if mb.pressed:
                _mouse_down = true
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
        if _mouse_down:
            if mm.position.distance_to(_mouse_start) > 6.0:
                _mouse_moved = true
            if _mouse_moved:
                _look(mm.relative)


func _look(rel: Vector2) -> void:
    _yaw -= rel.x * 0.006
    _pitch = clampf(_pitch + rel.y * 0.005, 0.08, 1.3)


func _touch_down(index: int, pos: Vector2) -> void:
    if ui.over_ui(pos):
        return
    var role := "look"
    if pos.x < get_viewport().get_visible_rect().size.x * 0.45 and _stick_index == -1:
        role = "stick"
        _stick_index = index
        stick.begin(pos, 62.0 * ui.ui_scale)
    _touches[index] = {"role": role, "start": pos, "moved": false, "t": Time.get_ticks_msec()}


func _touch_up(index: int, pos: Vector2) -> void:
    if not _touches.has(index):
        return
    var info: Dictionary = _touches[index]
    if info["role"] == "stick":
        _stick_index = -1
        stick.end()
    elif not info["moved"] and Time.get_ticks_msec() - int(info["t"]) < 350:
        _throw_at(pos)
    _touches.erase(index)


func _touch_drag(index: int, pos: Vector2, rel: Vector2) -> void:
    if not _touches.has(index):
        return
    var info: Dictionary = _touches[index]
    if info["role"] == "stick":
        stick.drag_to(pos)
    else:
        if pos.distance_to(info["start"]) > 14.0 * ui.ui_scale:
            info["moved"] = true
        if info["moved"]:
            _look(rel * 0.8)
