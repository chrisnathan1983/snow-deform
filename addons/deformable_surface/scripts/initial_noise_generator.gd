extends RefCounted
## Incrementally builds an initial deformation map. `step()` can be called once per
## frame on single-threaded platforms or repeatedly from a worker thread.

const MAP_NEUTRAL := 128.0 / 255.0

var resolution: int
var area: Vector2
var origin: Vector2
var depth: float
var height_amplitude: float
var invert: bool
var detail: float
var pixel_world_size_x: float
var pixel_world_size_z: float
var stride: int
var heights := PackedFloat32Array()
var image_data := PackedByteArray()
var image: Image
var noise: FastNoiseLite
var fine_noise: FastNoiseLite
var mound_noise: FastNoiseLite
var mound_height: float
var _noise_row := -1
var _image_row := 0
var done := false


func _init(p: DeformableSurfaceType, p_resolution: int, p_area: Vector2, p_origin: Vector2) -> void:
	resolution = p_resolution
	area = p_area
	origin = p_origin
	depth = p.max_depth
	stride = resolution + 2
	heights.resize(stride * stride)
	image_data.resize(resolution * resolution * 3)
	height_amplitude = clampf(p.initial_noise_height, 0.0, depth)
	invert = p.initial_noise_invert
	detail = clampf(p.initial_noise_detail, 0.0, 1.0)
	pixel_world_size_x = area.x / float(resolution - 1)
	pixel_world_size_z = area.y / float(resolution - 1)
	noise = p.initial_noise
	if noise == null:
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = maxf(p.initial_noise_frequency, 0.01)
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN_SQUARED
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		noise.cellular_jitter = 0.9
	if detail > 0.0:
		fine_noise = noise.duplicate() as FastNoiseLite
		fine_noise.seed = noise.seed + 1013
		fine_noise.frequency = noise.frequency * maxf(p.initial_noise_detail_scale, 0.05)
	mound_height = clampf(p.initial_noise_mound_height, 0.0, depth)
	if mound_height > 0.0:
		mound_noise = FastNoiseLite.new()
		mound_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		mound_noise.seed = noise.seed + 7919
		mound_noise.frequency = maxf(p.initial_noise_mound_frequency, 0.005)


## Processes rows until the time budget is spent. Returns true when the image is ready.
func step(budget_usec: int) -> bool:
	if done:
		return true
	var started := Time.get_ticks_usec()
	while _noise_row <= resolution:
		_generate_noise_row(_noise_row)
		_noise_row += 1
		if Time.get_ticks_usec() - started >= budget_usec:
			return false
	while _image_row < resolution:
		_generate_image_row(_image_row)
		_image_row += 1
		if Time.get_ticks_usec() - started >= budget_usec:
			return false
	image = Image.create_from_data(resolution, resolution, false, Image.FORMAT_RGB8, image_data)
	done = true
	return true


func run_to_completion() -> Image:
	while not step(100000):
		pass
	return image


func _generate_noise_row(y: int) -> void:
	var world_z := origin.y + float(y) * pixel_world_size_z
	for x in range(-1, resolution + 1):
		var world_x := origin.x + float(x) * pixel_world_size_x
		var noise_value := noise.get_noise_2d(world_x, world_z)
		if fine_noise != null:
			noise_value = (noise_value + detail * fine_noise.get_noise_2d(world_x, world_z)) / (1.0 + detail)
		if invert:
			noise_value = -noise_value
		var surface_level := height_amplitude
		if mound_noise != null:
			var mound := smoothstep(-0.1, 0.6, mound_noise.get_noise_2d(world_x, world_z))
			surface_level += mound * mound_height
		var height := minf(surface_level * (1.0 + noise_value) - height_amplitude, depth)
		heights[(y + 1) * stride + x + 1] = height


func _generate_image_row(y: int) -> void:
	for x in resolution:
		var index := (y + 1) * stride + x + 1
		var height := heights[index]
		var slope_x := (heights[index + 1] - heights[index - 1]) / (2.0 * pixel_world_size_x)
		var slope_z := (heights[index + stride] - heights[index - stride]) / (2.0 * pixel_world_size_z)
		var pixel := (y * resolution + x) * 3
		image_data[pixel] = _encode_channel(MAP_NEUTRAL + height / (2.0 * depth))
		image_data[pixel + 1] = _encode_channel(MAP_NEUTRAL + slope_x / 16.0)
		image_data[pixel + 2] = _encode_channel(MAP_NEUTRAL + slope_z / 16.0)


func _encode_channel(value: float) -> int:
	return clampi(roundi(clampf(value, 0.0, 1.0) * 255.0), 0, 255)
