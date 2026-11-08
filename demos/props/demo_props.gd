extends RefCounted
## Shared material helper for procedural demo geometry.

static var _mats: Dictionary = {}


static func mat(color: Color, roughness := 0.85, emissive := 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [color.to_html(), roughness, emissive]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emissive > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emissive
	_mats[key] = material
	return material
