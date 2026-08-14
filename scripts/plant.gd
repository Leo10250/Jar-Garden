extends Control


enum DragSource {
	NONE,
	TOUCH,
	MOUSE,
}


var _drag_source: DragSource = DragSource.NONE
var _active_touch_index: int = -1
var _resting_z_index: int = 0


func _gui_input(event: InputEvent) -> void:
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
	_drag_source = DragSource.NONE
	_active_touch_index = -1
	z_index = _resting_z_index


func _move_by(delta: Vector2) -> void:
	position += delta
	_clamp_to_parent()


func _clamp_to_parent() -> void:
	var bounds: Control = get_parent_control()
	if bounds == null:
		return

	var maximum_x: float = maxf(bounds.size.x - size.x, 0.0)
	var maximum_y: float = maxf(bounds.size.y - size.y, 0.0)
	position = Vector2(
		clampf(position.x, 0.0, maximum_x),
		clampf(position.y, 0.0, maximum_y),
	)
