class_name SafeAreaContainer
extends MarginContainer


const MOBILE_PLATFORMS: PackedStringArray = ["Android", "iOS"]

@export var base_margins: Vector4 = Vector4(20.0, 20.0, 20.0, 20.0)
@export var include_display_safe_area: bool = true


func _ready() -> void:
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()


func apply_safe_area() -> void:
	var margins := base_margins
	if include_display_safe_area and OS.get_name() in MOBILE_PLATFORMS:
		margins += _get_mobile_safe_insets()
	add_theme_constant_override(&"margin_left", roundi(margins.x))
	add_theme_constant_override(&"margin_top", roundi(margins.y))
	add_theme_constant_override(&"margin_right", roundi(margins.z))
	add_theme_constant_override(&"margin_bottom", roundi(margins.w))


func _get_mobile_safe_insets() -> Vector4:
	var window_size_pixels := DisplayServer.window_get_size()
	if window_size_pixels.x <= 0 or window_size_pixels.y <= 0:
		return Vector4.ZERO
	var safe_rect_pixels := DisplayServer.get_display_safe_area()
	if safe_rect_pixels.size.x <= 0 or safe_rect_pixels.size.y <= 0:
		return Vector4.ZERO
	var viewport_size := get_viewport_rect().size
	return calculate_safe_insets(
		window_size_pixels,
		DisplayServer.window_get_position(),
		safe_rect_pixels,
		viewport_size,
	)


static func calculate_safe_insets(
	window_size_pixels: Vector2i,
	window_position_pixels: Vector2i,
	safe_rect_pixels: Rect2i,
	viewport_size: Vector2,
) -> Vector4:
	if (
		window_size_pixels.x <= 0
		or window_size_pixels.y <= 0
		or safe_rect_pixels.size.x <= 0
		or safe_rect_pixels.size.y <= 0
	):
		return Vector4.ZERO
	var safe_start := safe_rect_pixels.position - window_position_pixels
	var safe_end := safe_rect_pixels.end - window_position_pixels
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
