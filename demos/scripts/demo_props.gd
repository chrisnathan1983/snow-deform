extends RefCounted
## Static helpers that build all demo scenery from primitive meshes (no assets).

static var _mats: Dictionary = {}


static func mat(color: Color, roughness := 0.85, emissive := 0.0) -> StandardMaterial3D:
    var key := "%s_%s_%s" % [color.to_html(), roughness, emissive]
    if _mats.has(key):
        return _mats[key] as StandardMaterial3D
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = roughness
    if emissive > 0.0:
        m.emission_enabled = true
        m.emission = color
        m.emission_energy_multiplier = emissive
    _mats[key] = m
    return m


static func sphere(r: float, segs := 12) -> SphereMesh:
    var m := SphereMesh.new()
    m.radius = r
    m.height = r * 2.0
    m.radial_segments = segs
    m.rings = maxi(segs >> 1, 4)
    return m


static func cone(r: float, h: float, segs := 8) -> CylinderMesh:
    var m := CylinderMesh.new()
    m.top_radius = 0.0
    m.bottom_radius = r
    m.height = h
    m.radial_segments = segs
    m.rings = 1
    return m


static func cylinder(r: float, h: float, segs := 8) -> CylinderMesh:
    var m := CylinderMesh.new()
    m.top_radius = r
    m.bottom_radius = r
    m.height = h
    m.radial_segments = segs
    m.rings = 1
    return m


static func box(size: Vector3) -> BoxMesh:
    var m := BoxMesh.new()
    m.size = size
    return m


static func capsule(r: float, h: float) -> CapsuleMesh:
    var m := CapsuleMesh.new()
    m.radius = r
    m.height = maxf(h, r * 2.0)
    m.radial_segments = 10
    m.rings = 4
    return m


static func add_mesh(parent: Node, mesh: Mesh, color: Color, pos := Vector3.ZERO,
        scl := Vector3.ONE, rot_deg := Vector3.ZERO) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat(color)
    mi.position = pos
    mi.scale = scl
    mi.rotation_degrees = rot_deg
    parent.add_child(mi)
    return mi


static func _multimesh(parent: Node3D, mesh: Mesh, color: Color, xforms: Array[Transform3D],
        cast_shadows: bool) -> void:
    if xforms.is_empty():
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = mesh
    mm.instance_count = xforms.size()
    for i in xforms.size():
        mm.set_instance_transform(i, xforms[i])
    var mi := MultiMeshInstance3D.new()
    mi.multimesh = mm
    mi.material_override = mat(color)
    mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows
            else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
    parent.add_child(mi)


static func add_hills(parent: Node3D, rng: RandomNumberGenerator, ground_y: float) -> void:
    for i in 14:
        var a := TAU * float(i) / 14.0 + rng.randf() * 0.3
        var d := rng.randf_range(95.0, 140.0)
        var r := rng.randf_range(22.0, 45.0)
        var mi := add_mesh(parent, sphere(1.0, 16), Color(0.86, 0.90, 0.97),
                Vector3(cos(a) * d, ground_y + r * 0.15, sin(a) * d),
                Vector3(r * 1.6, r * 0.55, r * 1.2))
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Wooden fence around the field, plus a snow-coloured skirt hiding the seam
## between the snow mesh and the lower ground plane.
static func add_fence(parent: Node3D, half: float, ground_y: float) -> void:
    var wood := Color(0.33, 0.21, 0.13)
    var fh := half + 0.25
    var posts: Array[Transform3D] = []
    var step := 2.0
    var n := int(half * 2.0 / step)
    for i in n + 1:
        var u := -half + float(i) * step
        posts.append(Transform3D(Basis(), Vector3(u, 0.55, -fh)))
        posts.append(Transform3D(Basis(), Vector3(u, 0.55, fh)))
        if i > 0 and i < n:
            posts.append(Transform3D(Basis(), Vector3(-fh, 0.55, u)))
            posts.append(Transform3D(Basis(), Vector3(fh, 0.55, u)))
    _multimesh(parent, box(Vector3(0.2, 1.1, 0.2)), wood, posts, true)
    var fence_length := half * 2.0 + 0.5
    for y in [0.4, 0.85]:
        add_mesh(parent, box(Vector3(fence_length, 0.08, 0.06)), wood, Vector3(0, y, -fh))
        add_mesh(parent, box(Vector3(fence_length, 0.08, 0.06)), wood, Vector3(0, y, fh))
        add_mesh(parent, box(Vector3(0.06, 0.08, fence_length)), wood, Vector3(-fh, y, 0))
        add_mesh(parent, box(Vector3(0.06, 0.08, fence_length)), wood, Vector3(fh, y, 0))
    var skirt_h := -ground_y + 0.02
    var snow := Color(0.88, 0.91, 0.97)
    var sy := ground_y + skirt_h * 0.5
    add_mesh(parent, box(Vector3(half * 2.0 + 0.2, skirt_h, 0.1)), snow, Vector3(0, sy, -half - 0.04))
    add_mesh(parent, box(Vector3(half * 2.0 + 0.2, skirt_h, 0.1)), snow, Vector3(0, sy, half + 0.04))
    add_mesh(parent, box(Vector3(0.1, skirt_h, half * 2.0 + 0.2)), snow, Vector3(-half - 0.04, sy, 0))
    add_mesh(parent, box(Vector3(0.1, skirt_h, half * 2.0 + 0.2)), snow, Vector3(half + 0.04, sy, 0))


## Scene-based props live in demos/props/ and can be dropped into any scene.
static func add_rock(parent: Node3D, pos: Vector3, r: float, yaw_deg: float) -> Node3D:
    var rock := (load("res://demos/props/rock.tscn") as PackedScene).instantiate() as Node3D
    rock.position = pos
    rock.scale = Vector3.ONE * r
    rock.rotation_degrees.y = yaw_deg
    parent.add_child(rock)
    return rock


static func add_snowman(parent: Node3D, pos: Vector3, yaw_deg: float) -> Node3D:
    var snowman := (load("res://demos/props/snowman.tscn") as PackedScene).instantiate() as Node3D
    snowman.position = pos
    snowman.rotation_degrees.y = yaw_deg
    parent.add_child(snowman)
    return snowman
