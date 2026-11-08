extends RefCounted
## Shared seamless FastNoiseLite textures used to initialize and heal surface maps.

const TEXTURE_SIZE := 1024
const WORLD_PERIOD := 128.0
const BASE_TEXTURE_FREQUENCY := WORLD_PERIOD / float(TEXTURE_SIZE)

static var _cache: Dictionary = {}
static var _mound_cache: Dictionary = {}
static var _profile_noise_keys: Dictionary = {}


static func for_profile(profile: DeformableSurfaceType) -> Dictionary:
	var source: FastNoiseLite
	var key_string := _cached_profile_noise_key(profile)
	if key_string.is_empty():
		source = _source_noise(profile)
		key_string = var_to_str(_noise_key(source))
		_cache_profile_noise_key(profile, key_string)
	if _cache.has(key_string):
		return _cache[key_string]
	if source == null:
		source = _source_noise(profile)

	var base_noise := source.duplicate() as FastNoiseLite
	base_noise.frequency = BASE_TEXTURE_FREQUENCY
	var detail_noise := base_noise.duplicate() as FastNoiseLite
	detail_noise.seed = source.seed + 1013
	var textures := {
		"base": _texture(base_noise),
		"detail": _texture(detail_noise),
		"mound": _mound_texture(source.seed + 7919),
	}
	_cache[key_string] = textures
	return textures


static func _cached_profile_noise_key(profile: DeformableSurfaceType) -> String:
	var profile_id := profile.get_instance_id()
	if not _profile_noise_keys.has(profile_id):
		return ""
	var entry: Dictionary = _profile_noise_keys[profile_id]
	if (entry["profile"] as WeakRef).get_ref() == profile:
		return entry["key"]
	_profile_noise_keys.erase(profile_id)
	return ""


static func _cache_profile_noise_key(profile: DeformableSurfaceType, key: String) -> void:
	var profile_id := profile.get_instance_id()
	_profile_noise_keys[profile_id] = {"profile": weakref(profile), "key": key}
	var profile_invalidator := _invalidate_profile_noise_key.bind(profile_id)
	if not profile.changed.is_connected(profile_invalidator):
		profile.changed.connect(profile_invalidator)
	if profile.initial_noise != null:
		var noise_invalidator := _invalidate_profile_noise_key.bind(profile_id)
		if not profile.initial_noise.changed.is_connected(noise_invalidator):
			profile.initial_noise.changed.connect(noise_invalidator)


static func _invalidate_profile_noise_key(profile_id: int) -> void:
	_profile_noise_keys.erase(profile_id)


static func _mound_texture(seed: int) -> NoiseTexture2D:
	if _mound_cache.has(seed):
		return _mound_cache[seed]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed
	noise.frequency = BASE_TEXTURE_FREQUENCY
	var texture := _texture(noise)
	_mound_cache[seed] = texture
	return texture


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
