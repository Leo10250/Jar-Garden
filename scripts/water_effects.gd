class_name WaterEffects
extends Control


const LEVEL_TWEEN_SECONDS: float = 0.45
const POUR_SECONDS: float = 0.68
const RIPPLE_SECONDS: float = 0.82
const SURFACE_SEGMENTS: int = 28

@export_node_path("ColorRect") var back_water_path: NodePath
@export_node_path("ColorRect") var front_water_path: NodePath

var _back_water: ColorRect
var _front_water: ColorRect
var _visual_level: float = 0.0
var _target_level: float = 0.0
var _level_tween: Tween
var _pour_elapsed: float = POUR_SECONDS
var _wave_elapsed: float = 0.0
var _ripples: Array[float] = []
var _initialized: bool = false


func _ready() -> void:
	_back_water = get_node_or_null(back_water_path) as ColorRect
	_front_water = get_node_or_null(front_water_path) as ColorRect
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_level_to_layers()
	set_process(true)


func set_level(level: float, animate: bool = true) -> void:
	_target_level = clampf(level, 0.0, 1.0)
	if not is_node_ready():
		_visual_level = _target_level
		return
	if not _initialized or not animate:
		_initialized = true
		if _level_tween != null and _level_tween.is_valid():
			_level_tween.kill()
		_set_visual_level(_target_level)
		return
	if is_equal_approx(_target_level, _visual_level):
		return
	if _level_tween != null and _level_tween.is_valid():
		_level_tween.kill()
	_level_tween = create_tween()
	_level_tween.set_trans(Tween.TRANS_CUBIC)
	_level_tween.set_ease(Tween.EASE_OUT)
	_level_tween.tween_method(_set_visual_level, _visual_level, _target_level, LEVEL_TWEEN_SECONDS)


func play_pour() -> void:
	_pour_elapsed = 0.0
	_ripples.append(0.0)
	if _ripples.size() > 5:
		_ripples.pop_front()
	queue_redraw()


func get_visual_level() -> float:
	return _visual_level


func get_target_level() -> float:
	return _target_level


func is_level_animating() -> bool:
	return _level_tween != null and _level_tween.is_valid() and _level_tween.is_running()


func _set_visual_level(level: float) -> void:
	_visual_level = clampf(level, 0.0, 1.0)
	_apply_level_to_layers()
	queue_redraw()


func _apply_level_to_layers() -> void:
	var surface_anchor := 1.0 - _visual_level
	for layer in [_back_water, _front_water]:
		if layer == null:
			continue
		layer.anchor_top = surface_anchor
		layer.offset_top = 0.0


func _process(delta: float) -> void:
	_wave_elapsed = fmod(_wave_elapsed + maxf(delta, 0.0), 1000.0)
	if _pour_elapsed < POUR_SECONDS:
		_pour_elapsed += maxf(delta, 0.0)
	for ripple_index in range(_ripples.size() - 1, -1, -1):
		_ripples[ripple_index] += maxf(delta, 0.0)
		if _ripples[ripple_index] >= RIPPLE_SECONDS:
			_ripples.remove_at(ripple_index)
	if _visual_level > 0.0 or _pour_elapsed < POUR_SECONDS or not _ripples.is_empty():
		queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var surface_y := (1.0 - _visual_level) * size.y
	if _visual_level > 0.0:
		_draw_surface(surface_y)
	_draw_ripples(surface_y)
	if _pour_elapsed < POUR_SECONDS:
		_draw_pour(surface_y)


func _draw_surface(surface_y: float) -> void:
	var points := PackedVector2Array()
	for segment in range(SURFACE_SEGMENTS + 1):
		var ratio := float(segment) / float(SURFACE_SEGMENTS)
		var x := ratio * size.x
		var wave := sin(ratio * TAU * 2.0 + _wave_elapsed * 3.1) * 2.1
		wave += sin(ratio * TAU * 3.0 - _wave_elapsed * 2.2) * 0.9
		points.append(Vector2(x, surface_y + wave))
	draw_polyline(points, Color(0.82, 0.97, 1.0, 0.92), 4.0, true)
	draw_polyline(points, Color(0.24, 0.61, 0.75, 0.72), 1.6, true)


func _draw_ripples(surface_y: float) -> void:
	for age in _ripples:
		var progress := clampf(age / RIPPLE_SECONDS, 0.0, 1.0)
		var alpha := (1.0 - progress) * 0.72
		var radius_x := lerpf(8.0, 70.0, progress)
		var center := Vector2(size.x * 0.5, surface_y + 2.0)
		draw_arc(center, radius_x, PI, TAU, 32, Color(0.85, 0.98, 1.0, alpha), 3.0, true)


func _draw_pour(surface_y: float) -> void:
	var progress := clampf(_pour_elapsed / POUR_SECONDS, 0.0, 1.0)
	var fade := 1.0 - smoothstep(0.72, 1.0, progress)
	var stream_x := size.x * 0.5
	var stream_end := minf(surface_y, lerpf(0.0, surface_y, minf(progress * 3.2, 1.0)))
	if stream_end > 2.0:
		var stream_points := PackedVector2Array([
			Vector2(stream_x - 1.5, 0.0),
			Vector2(stream_x + sin(_wave_elapsed * 15.0) * 2.0, stream_end),
		])
		draw_polyline(stream_points, Color(0.72, 0.94, 1.0, 0.88 * fade), 8.0, true)
		draw_polyline(stream_points, Color(0.93, 1.0, 1.0, 0.78 * fade), 2.4, true)
	for drop_index in 3:
		var drop_phase := fmod(progress * 4.5 + float(drop_index) * 0.31, 1.0)
		var drop_y := lerpf(10.0, maxf(surface_y - 6.0, 12.0), drop_phase)
		var drop_x := stream_x + sin(float(drop_index) * 2.7 + _wave_elapsed * 8.0) * 6.0
		draw_circle(Vector2(drop_x, drop_y), 4.0 - drop_phase * 1.2, Color(0.82, 0.97, 1.0, 0.86 * fade))
