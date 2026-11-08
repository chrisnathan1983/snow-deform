extends RefCounted
## Shared seamless FastNoiseLite textures used to initialize and heal surface maps.

const TEXTURE_SIZE := 1024
const WORLD_PERIOD := 128.0
const BASE_TEXTURE_FREQUENCY := WORLD_PERIOD / float(TEXTURE_SIZE)

static var _cache: Dictionary = {}


static func for_profile(profile: DeformableSurfaceType) -> Dictionary:
	var source := _source_noise(profile)
	var key := _noise_key(source)
	var key_string := var_to_str(key)
	if _cache.has(key_string):
		return _cache[key_string]

	var base_noise := source.duplicate() as FastNoiseLite
	base_noise.frequency = BASE_TEXTURE_FREQUENCY
	var detail_noise := base_noise.duplicate() as FastNoiseLite
	detail_noise.seed = source.seed + 1013
	var mound_noise := FastNoiseLite.new()
	mound_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mound_noise.seed = source.seed + 7919
	mound_noise.frequency = BASE_TEXTURE_FREQUENCY

	var textures := {
		"base": _texture(base_noise),
		"detail": _texture(detail_noise),
		"mound": _texture(mound_noise),
	}
	_cache[key_string] = textures
	return textures


static func ready_for_profile(profile: DeformableSurfaceType) -> bool:
	if not profile.initial_noise_enabled:
		return true
	for texture in for_profile(profile).values():
		if (texture as NoiseTexture2D).get_image() == null:
			return false
	return true


static func _source_noise(profile: DeformableSurfaceType) -> FastNoiseLite:
	if profile.initial_noise != null:
		return profile.initial_noise
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN_SQUARED
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	noise.cellular_jitter = 0.9
	return noise


static func _noise_key(noise: FastNoiseLite) -> Array:
	var names := PackedStringArray()
	for info in noise.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var name: String = info["name"]
		if name not in ["resource_name", "resource_local_to_scene", "script", "frequency"]:
			names.append(name)
	names.sort()
	var values: Array = []
	for name in names:
		values.append([name, noise.get(name)])
	return values


static func _texture(noise: FastNoiseLite) -> NoiseTexture2D:
	var texture := NoiseTexture2D.new()
	texture.width = TEXTURE_SIZE
	texture.height = TEXTURE_SIZE
	texture.seamless = true
	texture.seamless_blend_skirt = 0.1
	texture.normalize = false
	texture.generate_mipmaps = true
	texture.noise = noise
	return texture
