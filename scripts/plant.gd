class_name PlantView
extends Control


signal drag_finished(instance_id: String, normalized_center: Vector2)
signal position_canonicalized(instance_id: String, normalized_center: Vector2)

enum DragSource {
	NONE,
	TOUCH,
	MOUSE,
}


const VIEW_CENTER: Vector2 = Vector2(48.0, 44.0)
const CONTACT_SQUEEZE_SECONDS: float = 0.06
const CONTACT_REBOUND_SECONDS: float = 0.07
const CONTACT_SETTLE_SECONDS: float = 0.07
const DEFAULT_YOUNG_SCALE: float = 0.78
const DEFAULT_ADULT_SCALE: float = 1.0
const DEFAULT_OLD_SCALE: float = 0.92
const DEFAULT_YOUNG_MOTION_PERIOD: float = 1.35
const DEFAULT_ADULT_MOTION_PERIOD: float = 1.9
const DEFAULT_OLD_MOTION_PERIOD: float = 2.8
const DEFAULT_IDLE_BOB_PIXELS: float = 1.4
const DEFAULT_IDLE_SQUASH: float = 0.018
const HITBOX_POINT_COUNT: int = 20


var _drag_source: DragSource = DragSource.NONE
var _active_touch_index: int = -1
var _resting_z_index: int = 0
var _instance_id: String = ""
var _normalized_center: Vector2 = Vector2(0.5, 0.5)
var _is_bound: bool = false
var _interaction_enabled: bool = true
var _definition: PlantVariantDefinition
var _lifecycle_stage: PlantState.LifecycleStage = PlantState.LifecycleStage.ADULT
var _presentation_wetness: float = 0.0
var _is_mystery: bool = false
var _motion_elapsed_seconds: float = 0.0
var _hitbox_points: PackedVector2Array = PackedVector2Array()
var _active_contacts: Dictionary = {}
var _drag_blocked_contacts: Dictionary = {}
var _contact_tween: Tween

@onready var hitbox_area: Area2D = $Hitbox
@onready var collision_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var visual_root: Node2D = $VisualRoot
@onready var idle_motion: Node2D = $VisualRoot/IdleMotion
@onready var contact_motion: Node2D = $VisualRoot/IdleMotion/ContactMotion
@onready var back_texture_sprite: Sprite2D = $VisualRoot/IdleMotion/ContactMotion/BackTexture
@onready var main_texture_sprite: Sprite2D = $VisualRoot/IdleMotion/ContactMotion/MainTexture
@onready var texture_wetness: Sprite2D = $VisualRoot/IdleMotion/ContactMotion/TextureWetness
@onready var fallback_visual: Node2D = $VisualRoot/IdleMotion/ContactMotion/Fallback
@onready var body: Polygon2D = $VisualRoot/IdleMotion/ContactMotion/Fallback/Body
@onready var wetness_overlay: Polygon2D = $VisualRoot/IdleMotion/ContactMotion/Fallback/WetnessOverlay
@onready var body_outline: Line2D = $VisualRoot/IdleMotion/ContactMotion/Fallback/BodyOutline
@onready var left_eye: Polygon2D = $VisualRoot/IdleMotion/ContactMotion/Fallback/LeftEye
@onready var right_eye: Polygon2D = $VisualRoot/IdleMotion/ContactMotion/Fallback/RightEye
@onready var mouth: Line2D = $VisualRoot/IdleMotion/ContactMotion/Fallback/Mouth
@onready var leaf_cap: Polygon2D = $VisualRoot/IdleMotion/ContactMotion/Fallback/LeafCap
@onready var sun_hat: Polygon2D = $VisualRoot/IdleMotion/ContactMotion/Fallback/SunHat
@onready var watering_can: Node2D = $VisualRoot/IdleMotion/ContactMotion/Fallback/WateringCan
@onready var front_texture_sprite: Sprite2D = $VisualRoot/IdleMotion/ContactMotion/FrontTexture
@onready var mystery_mark: Label = $VisualRoot/IdleMotion/ContactMotion/MysteryMark


func _ready() -> void:
	var bounds := get_parent_control()
	if bounds != null and not bounds.resized.is_connected(_on_bounds_resized):
		bounds.resized.connect(_on_bounds_resized)
	if not hitbox_area.area_entered.is_connected(_on_hitbox_area_entered):
		hitbox_area.area_entered.connect(_on_hitbox_area_entered)
	if not hitbox_area.area_exited.is_connected(_on_hitbox_area_exited):
		hitbox_area.area_exited.connect(_on_hitbox_area_exited)
	_apply_visual_state()
	_apply_interaction_state()
	call_deferred("_apply_normalized_center")


func _process(delta: float) -> void:
	var motion_period := _get_motion_period_seconds()
	_motion_elapsed_seconds = fmod(
		_motion_elapsed_seconds + maxf(delta, 0.0),
		motion_period,
	)
	var phase := (_motion_elapsed_seconds / motion_period) * TAU
	var bob_pixels := _get_idle_bob_pixels()
	var squash_amount := _get_idle_squash_amount()
	var breath := sin(phase) * squash_amount
	idle_motion.position = Vector2(0.0, sin(phase) * bob_pixels)
	idle_motion.scale = Vector2(1.0 + breath, 1.0 - breath)


func bind_plant(instance_id: String, normalized_center: Vector2) -> void:
	_instance_id = instance_id
	_normalized_center = normalized_center.clamp(Vector2.ZERO, Vector2.ONE)
	_is_bound = true
	call_deferred("_apply_normalized_center")


func set_normalized_center(normalized_center: Vector2) -> void:
	_normalized_center = normalized_center.clamp(Vector2.ZERO, Vector2.ONE)
	_apply_normalized_center()


## Collection and shop previews use this same rendering entry point as the jar.
## A definition-only preview is shown at the Adult presentation scale.
func apply_variant_definition(definition: PlantVariantDefinition) -> void:
	_definition = definition
	_lifecycle_stage = PlantState.LifecycleStage.ADULT
	_presentation_wetness = 0.0
	_apply_visual_state()


func apply_presentation(
	definition: PlantVariantDefinition,
	lifecycle_stage: PlantState.LifecycleStage,
	wetness: float,
) -> void:
	_definition = definition
	_lifecycle_stage = lifecycle_stage
	_presentation_wetness = clampf(wetness, 0.0, 1.0)
	_apply_visual_state()


func set_mystery(is_mystery: bool) -> void:
	_is_mystery = is_mystery
	_apply_visual_state()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	_apply_interaction_state()
	if not enabled:
		cancel_active_drag()
		clear_contact_states()


func _apply_interaction_state() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if _interaction_enabled else Control.MOUSE_FILTER_IGNORE
	if not is_node_ready():
		return
	hitbox_area.input_pickable = _interaction_enabled
	hitbox_area.set_deferred(&"monitoring", _interaction_enabled)
	hitbox_area.set_deferred(&"monitorable", _interaction_enabled)
	collision_shape.set_deferred(&"disabled", not _interaction_enabled)


func _apply_visual_state() -> void:
	if not is_node_ready():
		return
	var visual := _get_visual_definition()
	var body_color := Color(0.985, 0.985, 0.97, 1.0)
	var head_accessory: StringName = &"none"
	var equipment: StringName = &"none"
	if _definition != null:
		body_color = _definition.body_color
		head_accessory = _definition.head_accessory
		equipment = _definition.equipment

	var has_main_texture := visual != null and visual.main_texture != null
	back_texture_sprite.texture = visual.back_texture if visual != null else null
	main_texture_sprite.texture = visual.main_texture if visual != null else null
	texture_wetness.texture = visual.main_texture if visual != null else null
	front_texture_sprite.texture = visual.front_texture if visual != null else null
	back_texture_sprite.visible = not _is_mystery and back_texture_sprite.texture != null
	main_texture_sprite.visible = not _is_mystery and has_main_texture
	texture_wetness.visible = not _is_mystery and has_main_texture and _presentation_wetness > 0.0
	front_texture_sprite.visible = not _is_mystery and front_texture_sprite.texture != null
	texture_wetness.modulate = Color(0.27, 0.72, 0.92, _presentation_wetness * 0.34)

	fallback_visual.visible = _is_mystery or not has_main_texture
	if _is_mystery:
		body_color = Color(0.16, 0.22, 0.20, 1.0)
	body.color = body_color
	body_outline.default_color = (
		Color(0.32, 0.4, 0.36, 1.0)
		if _is_mystery
		else Color(0.61, 0.66, 0.64, 1.0)
	)
	wetness_overlay.color.a = 0.0 if _is_mystery else _presentation_wetness * 0.42
	left_eye.visible = not _is_mystery
	right_eye.visible = not _is_mystery
	mouth.visible = not _is_mystery
	leaf_cap.visible = not _is_mystery and head_accessory == &"leaf_cap"
	sun_hat.visible = not _is_mystery and head_accessory == &"sun_hat"
	watering_can.visible = not _is_mystery and equipment == &"watering_can"
	mystery_mark.visible = _is_mystery

	var visual_offset := visual.visual_offset if visual != null else Vector2.ZERO
	var authored_scale := visual.visual_scale if visual != null else Vector2.ONE
	var lifecycle_scale := _get_lifecycle_scale()
	visual_root.position = VIEW_CENTER + visual_offset
	visual_root.scale = authored_scale * lifecycle_scale
	_apply_hitbox_geometry(visual, visual_offset, lifecycle_scale)


func _apply_hitbox_geometry(
	visual: PlantVisualDefinition,
	visual_offset: Vector2,
	lifecycle_scale: float,
) -> void:
	var hitbox_offset := Vector2.ZERO
	var next_points: PackedVector2Array
	if visual == null:
		next_points = _scaled_polygon(_make_fallback_hitbox_polygon(), lifecycle_scale)
	else:
		hitbox_offset = visual.hitbox_offset
		if visual.hitbox_polygon.size() >= 3:
			next_points = _scaled_polygon(visual.hitbox_polygon, lifecycle_scale)
		else:
			var size_pixels := Vector2(
				maxf(absf(visual.hitbox_size.x), 1.0),
				maxf(absf(visual.hitbox_size.y), 1.0),
			) * lifecycle_scale
			next_points = _make_ellipse_polygon(size_pixels)

	next_points = Geometry2D.convex_hull(next_points)
	var next_position := VIEW_CENTER + visual_offset + hitbox_offset * lifecycle_scale
	if next_points == _hitbox_points and hitbox_area.position.is_equal_approx(next_position):
		return
	_hitbox_points = next_points
	hitbox_area.position = next_position
	var shape := ConvexPolygonShape2D.new()
	shape.points = _hitbox_points
	collision_shape.shape = shape


func _has_point(point: Vector2) -> bool:
	if not is_node_ready() or _hitbox_points.size() < 3:
		return Rect2(Vector2.ZERO, size).has_point(point)
	return Geometry2D.is_point_in_polygon(point - hitbox_area.position, _hitbox_points)


## Stable drag/collision geometry for Main. Values are in global canvas space;
## the visual-only contact animation never changes them or the saved position.
func get_drag_collision_geometry() -> Dictionary:
	var polygon_global := get_hitbox_polygon_global()
	return {
		"plant_instance_id": _instance_id,
		"center": get_hitbox_center_global(),
		"size": _get_polygon_bounds(polygon_global).size,
		"polygon": polygon_global,
		"area": hitbox_area,
	}


func get_hitbox_center_global() -> Vector2:
	return hitbox_area.to_global(Vector2.ZERO)


func get_hitbox_size() -> Vector2:
	if _hitbox_points.is_empty():
		return Vector2.ZERO
	var bounds := _get_polygon_bounds(_hitbox_points)
	return bounds.size


func get_hitbox_polygon_local() -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in _hitbox_points:
		result.append(hitbox_area.position + point)
	return result


func get_hitbox_polygon_global() -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in _hitbox_points:
		result.append(hitbox_area.to_global(point))
	return result


func hitbox_overlaps(other: PlantView) -> bool:
	if other == null or other == self:
		return false
	return _convex_polygons_overlap(
		get_hitbox_polygon_global(),
		other.get_hitbox_polygon_global(),
	)


## Call once per contact update. Repeated `true` calls do not replay the bounce;
## a matching `false` re-arms it for the next contact.
func set_contact_state(
	contact_id: String,
	is_touching: bool,
	other_center_global: Vector2 = Vector2.ZERO,
) -> void:
	if contact_id.is_empty():
		return
	if not is_touching:
		_active_contacts.erase(contact_id)
		return
	if _active_contacts.has(contact_id):
		return
	_active_contacts[contact_id] = true
	var direction := other_center_global - get_hitbox_center_global()
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT
	play_contact_bounce(direction)


func clear_contact_states() -> void:
	_active_contacts.clear()


## Approximately 0.2 seconds: squeeze/tilt, rebound, then settle. Only the
## ContactMotion child is animated, so normalized and saved positions are safe.
func play_contact_bounce(contact_direction: Vector2 = Vector2.RIGHT) -> void:
	if not is_node_ready():
		return
	if _contact_tween != null and _contact_tween.is_valid():
		_contact_tween.kill()
	contact_motion.scale = Vector2.ONE
	contact_motion.rotation = 0.0
	var tilt_sign := -1.0 if contact_direction.x >= 0.0 else 1.0
	var squeeze_scale := Vector2(1.10, 0.84)
	var rebound_scale := Vector2(0.96, 1.06)
	_contact_tween = create_tween()
	_contact_tween.set_trans(Tween.TRANS_QUAD)
	_contact_tween.set_ease(Tween.EASE_OUT)
	_contact_tween.tween_property(
		contact_motion,
		"scale",
		squeeze_scale,
		CONTACT_SQUEEZE_SECONDS,
	)
	_contact_tween.parallel().tween_property(
		contact_motion,
		"rotation",
		deg_to_rad(7.0) * tilt_sign,
		CONTACT_SQUEEZE_SECONDS,
	)
	_contact_tween.tween_property(
		contact_motion,
		"scale",
		rebound_scale,
		CONTACT_REBOUND_SECONDS,
	)
	_contact_tween.parallel().tween_property(
		contact_motion,
		"rotation",
		deg_to_rad(-2.5) * tilt_sign,
		CONTACT_REBOUND_SECONDS,
	)
	_contact_tween.tween_property(
		contact_motion,
		"scale",
		Vector2.ONE,
		CONTACT_SETTLE_SECONDS,
	)
	_contact_tween.parallel().tween_property(
		contact_motion,
		"rotation",
		0.0,
		CONTACT_SETTLE_SECONDS,
	)


func is_contact_bouncing() -> bool:
	return _contact_tween != null and _contact_tween.is_valid() and _contact_tween.is_running()


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
	_clear_drag_blocked_contacts()
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
	# Keep the dragged plant above its neighbours, but below the foreground
	# water layer so submerged portions remain visually underwater.
	z_index = 6


func _end_drag() -> void:
	if _drag_source == DragSource.NONE:
		return
	_drag_source = DragSource.NONE
	_active_touch_index = -1
	z_index = _resting_z_index
	_clear_drag_blocked_contacts()
	_normalized_center = get_normalized_center()
	if _is_bound:
		drag_finished.emit(_instance_id, _normalized_center)


func _move_by(delta: Vector2) -> void:
	var starting_position := position
	position += delta
	_clamp_to_parent()
	var requested_position := position
	var blockers := _get_overlapping_sibling_plants()
	if not blockers.is_empty():
		var starting_blockers := _get_overlapping_sibling_plants_at(starting_position)
		if starting_blockers.is_empty():
			var safe_ratio := 0.0
			var blocked_ratio := 1.0
			for search_step in 10:
				var candidate_ratio := (safe_ratio + blocked_ratio) * 0.5
				position = starting_position.lerp(requested_position, candidate_ratio)
				if _get_overlapping_sibling_plants().is_empty():
					safe_ratio = candidate_ratio
				else:
					blocked_ratio = candidate_ratio
			position = starting_position.lerp(requested_position, safe_ratio)
		else:
			# Existing migrated overlaps may always move outward; only reject a
			# motion that introduces a new neighbor into the overlap set.
			for blocker in blockers:
				if blocker not in starting_blockers:
					position = starting_position
					break
		_update_drag_blocked_contacts(blockers)
	else:
		_clear_drag_blocked_contacts()
	_normalized_center = get_normalized_center()


func _clamp_to_parent() -> void:
	var bounds := get_parent_control()
	if bounds == null:
		return
	position = position.clamp(Vector2.ZERO, (bounds.size - size).max(Vector2.ZERO))


func _get_overlapping_sibling_plants_at(candidate_position: Vector2) -> Array[PlantView]:
	var previous_position := position
	position = candidate_position
	var overlaps := _get_overlapping_sibling_plants()
	position = previous_position
	return overlaps


func _get_overlapping_sibling_plants() -> Array[PlantView]:
	var overlaps: Array[PlantView] = []
	var parent := get_parent()
	if parent == null:
		return overlaps
	for sibling in parent.get_children():
		if sibling == self or not sibling is PlantView:
			continue
		var other := sibling as PlantView
		if not other._interaction_enabled:
			continue
		if hitbox_overlaps(other):
			overlaps.append(other)
	return overlaps


func _update_drag_blocked_contacts(blockers: Array[PlantView]) -> void:
	var current_ids: Dictionary = {}
	for blocker in blockers:
		if blocker == null:
			continue
		var contact_id := blocker._instance_id
		if contact_id.is_empty():
			contact_id = str(blocker.get_instance_id())
		current_ids[contact_id] = blocker
		_drag_blocked_contacts[contact_id] = blocker
		set_contact_state(contact_id, true, blocker.get_hitbox_center_global())
		blocker.set_contact_state(
			_instance_id if not _instance_id.is_empty() else str(get_instance_id()),
			true,
			get_hitbox_center_global(),
		)
	for contact_id in _drag_blocked_contacts.keys():
		if current_ids.has(contact_id):
			continue
		var other: PlantView = _drag_blocked_contacts[contact_id]
		set_contact_state(contact_id, false)
		if is_instance_valid(other):
			other.set_contact_state(
				_instance_id if not _instance_id.is_empty() else str(get_instance_id()),
				false,
			)
		_drag_blocked_contacts.erase(contact_id)


func _clear_drag_blocked_contacts() -> void:
	for contact_id in _drag_blocked_contacts.keys():
		var other: PlantView = _drag_blocked_contacts[contact_id]
		set_contact_state(contact_id, false)
		if is_instance_valid(other):
			other.set_contact_state(
				_instance_id if not _instance_id.is_empty() else str(get_instance_id()),
				false,
			)
	_drag_blocked_contacts.clear()


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


func _on_hitbox_area_entered(other_area: Area2D) -> void:
	if not _interaction_enabled:
		return
	var other_view := other_area.get_parent() as PlantView
	if other_view == null or other_view == self:
		return
	set_contact_state(
		str(other_area.get_instance_id()),
		true,
		other_view.get_hitbox_center_global(),
	)


func _on_hitbox_area_exited(other_area: Area2D) -> void:
	set_contact_state(str(other_area.get_instance_id()), false)


func _get_visual_definition() -> PlantVisualDefinition:
	if _definition == null:
		return null
	return _definition.visual


func _get_lifecycle_scale() -> float:
	var visual := _get_visual_definition()
	if visual != null:
		return visual.get_lifecycle_scale(_lifecycle_stage)
	match _lifecycle_stage:
		PlantState.LifecycleStage.YOUNG:
			return DEFAULT_YOUNG_SCALE
		PlantState.LifecycleStage.OLD:
			return DEFAULT_OLD_SCALE
		_:
			return DEFAULT_ADULT_SCALE


func _get_motion_period_seconds() -> float:
	var visual := _get_visual_definition()
	if visual != null:
		return maxf(visual.get_motion_period_seconds(_lifecycle_stage), 0.2)
	match _lifecycle_stage:
		PlantState.LifecycleStage.YOUNG:
			return DEFAULT_YOUNG_MOTION_PERIOD
		PlantState.LifecycleStage.OLD:
			return DEFAULT_OLD_MOTION_PERIOD
		_:
			return DEFAULT_ADULT_MOTION_PERIOD


func _get_idle_bob_pixels() -> float:
	var visual := _get_visual_definition()
	return maxf(visual.idle_bob_pixels, 0.0) if visual != null else DEFAULT_IDLE_BOB_PIXELS


func _get_idle_squash_amount() -> float:
	var visual := _get_visual_definition()
	return clampf(visual.idle_squash_amount, 0.0, 0.2) if visual != null else DEFAULT_IDLE_SQUASH


static func _make_fallback_hitbox_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-40.0, 28.0),
		Vector2(-42.0, 12.0),
		Vector2(-38.0, -8.0),
		Vector2(-28.0, -24.0),
		Vector2(-14.0, -33.0),
		Vector2(0.0, -36.0),
		Vector2(14.0, -33.0),
		Vector2(28.0, -24.0),
		Vector2(38.0, -8.0),
		Vector2(42.0, 12.0),
		Vector2(40.0, 28.0),
		Vector2(28.0, 35.0),
		Vector2(-28.0, 35.0),
	])


static func _scaled_polygon(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	for point in points:
		scaled.append(point * amount)
	return scaled


static func _make_ellipse_polygon(size_pixels: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius := size_pixels * 0.5
	for point_index in HITBOX_POINT_COUNT:
		var angle := TAU * float(point_index) / float(HITBOX_POINT_COUNT)
		points.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points


static func _get_polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


static func _convex_polygons_overlap(
	first: PackedVector2Array,
	second: PackedVector2Array,
) -> bool:
	if first.size() < 3 or second.size() < 3:
		return false
	return (
		_not_separated_on_any_axis(first, first, second)
		and _not_separated_on_any_axis(second, first, second)
	)


static func _not_separated_on_any_axis(
	axis_source: PackedVector2Array,
	first: PackedVector2Array,
	second: PackedVector2Array,
) -> bool:
	for point_index in axis_source.size():
		var edge := axis_source[(point_index + 1) % axis_source.size()] - axis_source[point_index]
		if edge.length_squared() <= 0.000001:
			continue
		var axis := Vector2(-edge.y, edge.x).normalized()
		var first_range := _project_polygon(first, axis)
		var second_range := _project_polygon(second, axis)
		if first_range.y < second_range.x - 0.01 or second_range.y < first_range.x - 0.01:
			return false
	return true


static func _project_polygon(points: PackedVector2Array, axis: Vector2) -> Vector2:
	var minimum := points[0].dot(axis)
	var maximum := minimum
	for point in points:
		var projection := point.dot(axis)
		minimum = minf(minimum, projection)
		maximum = maxf(maximum, projection)
	return Vector2(minimum, maximum)


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
