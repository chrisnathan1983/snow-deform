class_name DemoFps
extends CanvasLayer
## Small gamescope-style performance overlay (top-centre), created by DemoNav so every demo has one.
##
## Graph: how much of the frame budget (1 / display refresh rate) the CPU and GPU use, so a fast
## machine shows its headroom instead of a flat line. The top edge is 100% of the budget and only
## rescales when a frame goes over. CPU = script + physics + render submission; GPU comes from the
## renderer's timestamp queries and reads "n/a" where unavailable.
##
## Breakdown (F4): what each operation costs, as its average over the window (bar fill) against
## its maximum (white tick). A bar that is full-length at its average is a constant cost; a short
## fill with a far tick is an occasional spike. CPU rows are milliseconds against the frame
## budget. GPU rows are estimates in millions of map pixels shaded per frame (Godot has no
## per-pass GPU timer), scaled against the largest in their group.
##
## Everything covers the last WINDOW_SECONDS. F3 toggles the whole overlay.

const WINDOW_SECONDS := 10.0
const SAMPLES := 180   # one per graph pixel; each covers WINDOW_SECONDS / SAMPLES
const GRAPH_SIZE := Vector2(180.0, 44.0)
const DETAIL_WIDTH := 290.0
const ROW_HEIGHT := 15.0
const FONT_SIZE := 12
const DETAIL_FONT_SIZE := 11
const UPDATE_INTERVAL := 0.25
const FALLBACK_REFRESH := 60.0
const BG_COLOR := Color(0.0, 0.0, 0.0, 0.45)
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const LIMIT_COLOR := Color(1.0, 0.5, 0.45, 0.6)
const CPU_COLOR := Color(0.45, 0.75, 1.0)
const GPU_COLOR := Color(1.0, 0.7, 0.35)
const GOOD_COLOR := Color(0.55, 1.0, 0.6)
const OK_COLOR := Color(1.0, 0.85, 0.4)
const BAD_COLOR := Color(1.0, 0.5, 0.45)
const TEXT_COLOR := Color(0.9, 0.94, 1.0)
const DIM_COLOR := Color(1.0, 1.0, 1.0, 0.5)
const BAR_BACK_COLOR := Color(1.0, 1.0, 1.0, 0.1)
const MAX_COLOR := Color(1.0, 1.0, 1.0, 0.95)

enum Scale { BUDGET, CAPACITY, GROUP }

## name, decimals shown, color, and what the bar is scaled against:
## BUDGET = the frame budget in ms, CAPACITY = the stamp budget, GROUP = the largest peak among
## rows sharing `group`. Order matches _read_frame().
const ROWS := [
	{"name": "Deformers", "dec": 2, "unit": "ms", "scale": Scale.BUDGET, "color": CPU_COLOR},
	{"name": "Queued stamps", "dec": 2, "unit": "ms", "scale": Scale.BUDGET, "color": CPU_COLOR},
	{"name": "Puffs", "dec": 2, "unit": "ms", "scale": Scale.BUDGET, "color": CPU_COLOR},
	{"name": "Rest of CPU", "dec": 2, "unit": "ms", "scale": Scale.BUDGET, "color": CPU_COLOR},
	{"name": "Stamps", "dec": 0, "unit": "", "scale": Scale.CAPACITY, "color": GPU_COLOR},
	{"name": "Stamp fill", "dec": 2, "unit": "Mpx", "scale": Scale.GROUP, "color": GPU_COLOR, "group": 1},
	{"name": "Refill pass", "dec": 2, "unit": "Mpx", "scale": Scale.GROUP, "color": GPU_COLOR, "group": 1},
]
const STAMPS_ROW := 4

var _graph: Control
var _detail: Control
var _label: Label
var _viewport_rid: RID
var _cpu := PackedFloat32Array()   # worst CPU ms per slice, ring buffer
var _gpu := PackedFloat32Array()   # worst GPU ms per slice, ring buffer
var _head := 0
var _slice_elapsed := 0.0
var _slice_cpu := 0.0
var _slice_gpu := 0.0
var _budget_ms := 1000.0 / FALLBACK_REFRESH
var _scale := 1.0   # graph height in budgets
var _elapsed := 0.0
var _frames := 0
var _sum_cpu := 0.0
var _sum_gpu := 0.0
var _gpu_seen := false

# Per row: this frame's value, the slice in progress, and ring buffers of finished slices.
var _now := PackedFloat32Array()
var _stamp_capacity := 0.0
var _slice_sum := PackedFloat32Array()
var _slice_max := PackedFloat32Array()
var _slice_frames := 0
var _ring_sum: Array[PackedFloat32Array] = []
var _ring_max: Array[PackedFloat32Array] = []
var _ring_frames := PackedInt32Array()


func _init() -> void:
	layer = 99
	name = "DemoFps"


func _ready() -> void:
	_cpu.resize(SAMPLES)
	_gpu.resize(SAMPLES)
	_ring_frames.resize(SAMPLES)
	var count := ROWS.size()
	_now.resize(count)
	_slice_sum.resize(count)
	_slice_max.resize(count)
	for i in count:
		var sums := PackedFloat32Array()
		sums.resize(SAMPLES)
		var maxes := PackedFloat32Array()
		maxes.resize(SAMPLES)
		_ring_sum.append(sums)
		_ring_max.append(maxes)

	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	_update_budget()

	_graph = Control.new()
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.custom_minimum_size = GRAPH_SIZE
	_graph.size = GRAPH_SIZE
	_graph.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE, 6)
	_graph.draw.connect(_draw_graph)
	add_child(_graph)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	DemoTheme.style_floating_label(_label)
	_label.add_theme_constant_override("outline_size", 3)
	_label.position = Vector2(4.0, 0.0)
	_graph.add_child(_label)

	var detail_size := Vector2(DETAIL_WIDTH, ROW_HEIGHT * (count + 1) + 6.0)
	_detail = Control.new()
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.custom_minimum_size = detail_size
	_detail.size = detail_size
	_detail.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE, 6)
	_detail.position.y = 6.0 + GRAPH_SIZE.y + 4.0
	_detail.visible = false
	_detail.draw.connect(_draw_detail)
	add_child(_detail)


func _exit_tree() -> void:
	if _viewport_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)


func _process(delta: float) -> void:
	var cpu_ms := (Performance.get_monitor(Performance.TIME_PROCESS)
			+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0 \
			+ RenderingServer.get_frame_setup_time_cpu() \
			+ RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid)
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
	_gpu_seen = _gpu_seen or gpu_ms > 0.0
	_read_frame(cpu_ms)

	_slice_cpu = maxf(_slice_cpu, cpu_ms)
	_slice_gpu = maxf(_slice_gpu, gpu_ms)
	_slice_frames += 1
	for i in ROWS.size():
		_slice_sum[i] += _now[i]
		_slice_max[i] = maxf(_slice_max[i], _now[i])
	_slice_elapsed += delta
	while _slice_elapsed >= WINDOW_SECONDS / SAMPLES:
		_slice_elapsed -= WINDOW_SECONDS / SAMPLES
		_cpu[_head] = _slice_cpu
		_gpu[_head] = _slice_gpu
		_ring_frames[_head] = _slice_frames
		for i in ROWS.size():
			_ring_sum[i][_head] = _slice_sum[i]
			_ring_max[i][_head] = _slice_max[i]
		_head = (_head + 1) % SAMPLES
		_slice_cpu = 0.0
		_slice_gpu = 0.0
		_slice_frames = 0
		_slice_sum.fill(0.0)
		_slice_max.fill(0.0)

	_elapsed += delta
	_frames += 1
	_sum_cpu += cpu_ms
	_sum_gpu += gpu_ms
	if _elapsed >= UPDATE_INTERVAL:
		_update_label()
		_update_budget()
		_elapsed = 0.0
		_frames = 0
		_sum_cpu = 0.0
		_sum_gpu = 0.0
	if _graph.visible:
		_graph.queue_redraw()
	if _detail.visible:
		_detail.queue_redraw()


func _update_budget() -> void:
	var refresh := DisplayServer.screen_get_refresh_rate()
	_budget_ms = 1000.0 / (refresh if refresh > 0.0 else FALLBACK_REFRESH)


func _update_label() -> void:
	var fps := _frames / _elapsed
	var cpu_load := _sum_cpu / _frames / _budget_ms
	var gpu_load := _sum_gpu / _frames / _budget_ms
	var text := "%d fps  CPU %d%%" % [roundi(fps), roundi(cpu_load * 100.0)]
	text += "  GPU %d%%" % roundi(gpu_load * 100.0) if _gpu_seen else "  GPU n/a"
	_label.text = text
	_label.add_theme_color_override("font_color", _color_for(maxf(cpu_load, gpu_load)))


## Fills _now with this frame's value for every row, summed over all surfaces.
func _read_frame(cpu_ms: float) -> void:
	var deformers := 0.0
	var queued := 0.0
	var puffs := 0.0
	var stamps := 0
	var stamp_px := 0.0
	var refill_px := 0.0
	_stamp_capacity = 0.0
	for surface: DeformableSurface in DeformableSurface.instances:
		var costs: Dictionary = surface.get_frame_costs()
		deformers += costs["deformers_ms"]
		queued += costs["queued_ms"]
		puffs += costs["puffs_ms"]
		stamp_px += costs["stamp_mpx"]
		refill_px += costs["refill_mpx"]
		stamps += surface.get_stamps_used()
		_stamp_capacity += surface.max_stamps_per_frame
	_now[0] = deformers
	_now[1] = queued
	_now[2] = puffs
	_now[3] = maxf(cpu_ms - deformers - queued - puffs, 0.0)
	_now[4] = float(stamps)
	_now[5] = stamp_px
	_now[6] = refill_px


## Average and maximum of row `i` across the window, including the slice in progress.
func _window_stats(i: int) -> Vector2:
	var total: float = _slice_sum[i]
	var frames := _slice_frames
	var peak: float = _slice_max[i]
	for k in SAMPLES:
		total += _ring_sum[i][k]
		frames += _ring_frames[k]
		peak = maxf(peak, _ring_max[i][k])
	return Vector2(total / maxf(frames, 1), peak)


# ---------------------------------------------------------------- drawing

func _draw_graph() -> void:
	_graph.draw_rect(Rect2(Vector2.ZERO, GRAPH_SIZE), BG_COLOR)

	var peak := 1.0
	for i in SAMPLES:
		peak = maxf(peak, maxf(_cpu[i], _gpu[i]) / _budget_ms)
	# Rise at once for spikes, settle back slowly so the scale doesn't flicker.
	_scale = peak if peak > _scale else lerpf(_scale, peak, 0.02)

	var limit_y := GRAPH_SIZE.y * (1.0 - 1.0 / _scale)
	_graph.draw_line(Vector2(0.0, limit_y), Vector2(GRAPH_SIZE.x, limit_y), LIMIT_COLOR)
	var half_y := GRAPH_SIZE.y * (1.0 - 0.5 / _scale)
	_graph.draw_line(Vector2(0.0, half_y), Vector2(GRAPH_SIZE.x, half_y), GRID_COLOR)

	_draw_series(_cpu, CPU_COLOR)
	if _gpu_seen:
		_draw_series(_gpu, GPU_COLOR)


func _draw_series(series: PackedFloat32Array, color: Color) -> void:
	var points := PackedVector2Array()
	points.resize(SAMPLES)
	var step := GRAPH_SIZE.x / float(SAMPLES - 1)
	for i in SAMPLES:
		var load_ratio := series[(_head + i) % SAMPLES] / _budget_ms
		points[i] = Vector2(step * i, GRAPH_SIZE.y * (1.0 - clampf(load_ratio / _scale, 0.0, 1.0)))
	_graph.draw_polyline(points, color, 1.5)


func _draw_detail() -> void:
	var font := ThemeDB.fallback_font
	var stats: Array[Vector2] = []
	var group_peak := 0.0001
	for i in ROWS.size():
		stats.append(_window_stats(i))
		if ROWS[i]["scale"] == Scale.GROUP:
			group_peak = maxf(group_peak, stats[i].y)

	_detail.draw_rect(Rect2(Vector2.ZERO, _detail.size), BG_COLOR)
	var name_width := 88.0
	var bar_x := name_width + 8.0
	var bar_width := 64.0
	var text_x := bar_x + bar_width + 6.0
	_detail.draw_string(font, Vector2(4.0, ROW_HEIGHT - 3.0), "operation",
			HORIZONTAL_ALIGNMENT_LEFT, name_width, DETAIL_FONT_SIZE, DIM_COLOR)
	_detail.draw_string(font, Vector2(text_x, ROW_HEIGHT - 3.0), "avg  /  max",
			HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL_FONT_SIZE, DIM_COLOR)

	for i in ROWS.size():
		var row: Dictionary = ROWS[i]
		var avg: float = stats[i].x
		var peak: float = stats[i].y
		var full := 0.0
		match row["scale"]:
			Scale.BUDGET:
				full = _budget_ms
			Scale.CAPACITY:
				full = maxf(_stamp_capacity, peak)
			Scale.GROUP:
				full = group_peak
		full = maxf(full, 0.0001)

		var y := ROW_HEIGHT * (i + 1) + 2.0
		var bar := Rect2(bar_x, y + 3.0, bar_width, ROW_HEIGHT - 8.0)
		var color: Color = row["color"]
		if row["scale"] != Scale.GROUP:
			color = _color_for(peak / full)
		_detail.draw_rect(bar, BAR_BACK_COLOR)
		_detail.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(avg / full, 0.0, 1.0), bar.size.y)), color)
		_detail.draw_rect(Rect2(bar.position.x + bar.size.x * clampf(peak / full, 0.0, 1.0) - 1.0,
				bar.position.y - 1.0, 1.0, bar.size.y + 2.0), MAX_COLOR)

		_detail.draw_string(font, Vector2(4.0, y + ROW_HEIGHT - 6.0), row["name"],
				HORIZONTAL_ALIGNMENT_LEFT, name_width, DETAIL_FONT_SIZE, TEXT_COLOR)
		var unit: String = row["unit"]
		var value_text := "%s / %s %s" % [_format(avg, row["dec"]), _format(peak, row["dec"]), unit]
		if i == STAMPS_ROW:
			value_text = "%s / %s of %s" % [_format(avg, 0), _format(peak, 0), _format(_stamp_capacity, 0)]
		_detail.draw_string(font, Vector2(text_x, y + ROW_HEIGHT - 6.0), value_text.strip_edges(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, DETAIL_FONT_SIZE, TEXT_COLOR)


static func _format(value: float, decimals: int) -> String:
	return ("%." + str(decimals) + "f") % value


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F3:
		_graph.visible = not _graph.visible
		if not _graph.visible:
			_detail.visible = false
	elif key.keycode == KEY_F4 and _graph.visible:
		_detail.visible = not _detail.visible


static func _color_for(load_ratio: float) -> Color:
	if load_ratio < 0.7:
		return GOOD_COLOR
	if load_ratio < 1.0:
		return OK_COLOR
	return BAD_COLOR
