extends RefCounted
## Internal helpers. Intentionally has no class_name, to keep the global
## namespace clean. Use: const SnowUtil = preload("snow_util.gd")


## Soft round white dot, used for flakes and puffs.
static func soft_dot(size := 32) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.5, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t
