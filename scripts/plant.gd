class_name PlantView
extends Control


signal drag_finished(instance_id: String, normalized_center: Vector2)
signal position_canonicalized(instance_id: String, normalized_center: Vector2)

enum DragSource {
	NONE,
	TOUCH,
	MOUSE,
}


var _drag_source: DragSource = DragSource.NONE
var _active_touch_index: int = -1
var _resting_z_index: int = 0
var _instance_id: String = ""
var _normalized_center: Vector2 = Vector2(0.5, 0.5)
var _is_bound: bool = false
var _interaction_enabled: bool = true
var _definition: PlantVariantDefinition
var _presentation_wetness: float = 0.0
var _is_mystery: bool = false

@onready var body: Polygon2D = $Visual/Body
@onready var wetness_overlay: Polygon2D = $Visual/WetnessOverlay
@onready var body_outline: Line2D = $Visual/BodyOutline
@onready var left_eye: Polygon2D = $Visual/LeftEye
@onready var right_eye: Polygon2D = $Visual/RightEye
@onready var mouth: Line2D = $Visual/Mouth
@onready var leaf_cap: Polygon2D = $Visual/LeafCap
@onready var sun_hat: Polygon2D = $Visual/SunHat
@onready var watering_can: Node2D = $Visual/WateringCan
@onready var mystery_mark: Label = $Visual/MysteryMark


func _ready() -> void:
	var bounds := get_parent_control()
	if bounds != null and not bounds.resized.is_connected(_on_bounds_resized):
		bounds.resized.connect(_on_bounds_resized)
	_apply_visual_state()
	call_deferred("_apply_normalized_center")


func bind_plant(instance_id: String, normalized_center: Vector2) -> void:
	_instance_id = instance_id
	_normalized_center = normalized_center.clamp(Vector2.ZERO, Vector2.ONE)
	_is_bound = true
	call_deferred("_apply_normalized_center")


func set_normalized_center(normalized_center: Vector2) -> void:
	_normalized_center = normalized_center.clamp(Vector2.ZERO, Vector2.ONE)
	_apply_normalized_center()


func apply_variant_definition(definition: PlantVariantDefinition) -> void:
	_definition = definition
	_apply_visual_state()


func apply_presentation(
	definition: PlantVariantDefinition,
	_lifecycle_stage: PlantState.LifecycleStage,
	wetness: float,
) -> void:
	_definition = definition
	_presentation_wetness = clampf(wetness, 0.0, 1.0)
	_apply_visual_state()


func set_mystery(is_mystery: bool) -> void:
	_is_mystery = is_mystery
	_apply_visual_state()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	if not enabled:
		cancel_active_drag()


func _apply_visual_state() -> void:
	if not is_node_ready():
		return
	var body_color := Color(0.985, 0.985, 0.97, 1.0)
	var head_accessory: StringName = &"none"
	var equipment: StringName = &"none"
	if _definition != null:
		body_color = _definition.body_color
		head_accessory = _definition.head_accessory
		equipment = _definition.equipment
	if _is_mystery:
		body_color = Color(0.16, 0.22, 0.20, 1.0)
	body.color = body_color
	body_outline.default_color = Color(0.32, 0.4, 0.36, 1.0) if _is_mystery else Color(0.61, 0.66, 0.64, 1.0)
	wetness_overlay.color.a = 0.0 if _is_mystery else _presentation_wetness * 0.42
	left_eye.visible = not _is_mystery
	right_eye.visible = not _is_mystery
	mouth.visible = not _is_mystery
	leaf_cap.visible = not _is_mystery and head_accessory == &"leaf_cap"
	sun_hat.visible = not _is_mystery and head_accessory == &"sun_hat"
	watering_can.visible = not _is_mystery and equipment == &"watering_can"
	mystery_mark.visible = _is_mystery


func get_normalized_center() -> Vector2:
	var bounds := get_parent_control()
	if bounds == null:
		return _normalized_center
	return position_to_normalized_center(position, bounds.size, size)


func is_dragging() -> bool:
	return _drag_source != DragSource.NONE


func cancel_active_drag() -> void:
	if _drag_source == DragSource.NONE:
		return
	_drag_source = DragSource.NONE
	_active_touch_index = -1
	z_index = _resting_z_index
	_normalized_center = get_normalized_center()


func _gui_input(event: InputEvent) -> void:
	if not _interaction_enabled:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _drag_source == DragSource.NONE:
			_begin_drag(DragSource.TOUCH, event.index)
			accept_event()
	elif _drag_source == DragSource.TOUCH and event.index == _active_touch_index:
		_end_drag()
		accept_event()


func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	if _drag_source != DragSource.TOUCH or event.index != _active_touch_index:
		return

	_move_by(event.relative)
	accept_event()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		if _drag_source == DragSource.NONE:
			_begin_drag(DragSource.MOUSE)
			accept_event()
	elif _drag_source == DragSource.MOUSE:
		_end_drag()
		accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _drag_source != DragSource.MOUSE:
		return
	if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		_end_drag()
		return

	_move_by(event.relative)
	accept_event()


func _begin_drag(source: DragSource, touch_index: int = -1) -> void:
	_drag_source = source
	_active_touch_index = touch_index
	_resting_z_index = z_index
	z_index = 10


func _end_drag() -> void:
	if _drag_source == DragSource.NONE:
		return
	_drag_source = DragSource.NONE
	_active_touch_index = -1
	z_index = _resting_z_index
	_normalized_center = get_normalized_center()
	if _is_bound:
		drag_finished.emit(_instance_id, _normalized_center)


func _move_by(delta: Vector2) -> void:
	position += delta
	_clamp_to_parent()
	_normalized_center = get_normalized_center()


func _clamp_to_parent() -> void:
	var bounds := get_parent_control()
	if bounds == null:
		return
	position = position.clamp(Vector2.ZERO, (bounds.size - size).max(Vector2.ZERO))


func _apply_normalized_center() -> void:
	var bounds := get_parent_control()
	if bounds == null or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var requested_center := _normalized_center
	position = normalized_center_to_position(_normalized_center, bounds.size, size)
	_normalized_center = position_to_normalized_center(position, bounds.size, size)
	if _is_bound and not requested_center.is_equal_approx(_normalized_center):
		position_canonicalized.emit(_instance_id, _normalized_center)


func _on_bounds_resized() -> void:
	_apply_normalized_center()


static func normalized_center_to_position(
	normalized_center: Vector2,
	bounds_size: Vector2,
	plant_size: Vector2,
) -> Vector2:
	var maximum_position := (bounds_size - plant_size).max(Vector2.ZERO)
	var desired_position := normalized_center.clamp(Vector2.ZERO, Vector2.ONE) * bounds_size
	desired_position -= plant_size * 0.5
	return desired_position.clamp(Vector2.ZERO, maximum_position)


static func position_to_normalized_center(
	top_left_position: Vector2,
	bounds_size: Vector2,
	plant_size: Vector2,
) -> Vector2:
	if bounds_size.x <= 0.0 or bounds_size.y <= 0.0:
		return Vector2(0.5, 0.5)
	var clamped_position := top_left_position.clamp(
		Vector2.ZERO,
		(bounds_size - plant_size).max(Vector2.ZERO),
	)
	return ((clamped_position + plant_size * 0.5) / bounds_size).clamp(
		Vector2.ZERO,
		Vector2.ONE,
	)
