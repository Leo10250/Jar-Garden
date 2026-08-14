extends Control


const BASE_MARGIN_LEFT: int = 32
const BASE_MARGIN_TOP: int = 36
const BASE_MARGIN_RIGHT: int = 32
const BASE_MARGIN_BOTTOM: int = 40
const MOBILE_PLATFORMS: PackedStringArray = ["Android", "iOS"]

@onready var safe_area: MarginContainer = $SafeArea


func _ready() -> void:
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _apply_safe_area() -> void:
	var margins := Vector4(
		BASE_MARGIN_LEFT,
		BASE_MARGIN_TOP,
		BASE_MARGIN_RIGHT,
		BASE_MARGIN_BOTTOM,
	)

	if OS.get_name() in MOBILE_PLATFORMS:
		margins += _get_mobile_safe_insets()

	safe_area.add_theme_constant_override("margin_left", int(round(margins.x)))
	safe_area.add_theme_constant_override("margin_top", int(round(margins.y)))
	safe_area.add_theme_constant_override("margin_right", int(round(margins.z)))
	safe_area.add_theme_constant_override("margin_bottom", int(round(margins.w)))


func _get_mobile_safe_insets() -> Vector4:
	var window_size_pixels: Vector2i = DisplayServer.window_get_size()
	if window_size_pixels.x <= 0 or window_size_pixels.y <= 0:
		return Vector4.ZERO

	var safe_rect_pixels: Rect2i = DisplayServer.get_display_safe_area()
	var window_position_pixels: Vector2i = DisplayServer.window_get_position()
	var safe_start: Vector2i = safe_rect_pixels.position - window_position_pixels
	var safe_end: Vector2i = safe_rect_pixels.end - window_position_pixels
	var viewport_size: Vector2 = get_viewport_rect().size
	var pixel_to_viewport := Vector2(
		viewport_size.x / float(window_size_pixels.x),
		viewport_size.y / float(window_size_pixels.y),
	)

	return Vector4(
		maxf(float(safe_start.x), 0.0) * pixel_to_viewport.x,
		maxf(float(safe_start.y), 0.0) * pixel_to_viewport.y,
		maxf(float(window_size_pixels.x - safe_end.x), 0.0) * pixel_to_viewport.x,
		maxf(float(window_size_pixels.y - safe_end.y), 0.0) * pixel_to_viewport.y,
	)
