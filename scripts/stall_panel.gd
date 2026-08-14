class_name StallPanel
extends Control


signal close_requested
signal refresh_applied
signal buy_plant_requested(variant_id: StringName)
signal sell_plant_requested(instance_id: String)
signal jar_action_requested(jar_id: StringName)
signal environment_action_requested(environment_id: StringName)


const BASE_SAFE_MARGIN: int = 20
const MOBILE_PLATFORMS: PackedStringArray = ["Android", "iOS"]
const ROW_COLOR: Color = Color(0.15, 0.255, 0.20, 0.96)
const ACTION_COLOR: Color = Color(0.46, 0.68, 0.48, 1.0)
const SECONDARY_ACTION_COLOR: Color = Color(0.55, 0.63, 0.43, 1.0)

@export var plant_scene: PackedScene

@onready var safe_margin: MarginContainer = $SafeMargin
@onready var close_button: Button = %CloseButton
@onready var summary_label: Label = %Summary
@onready var tabs: TabContainer = %Tabs
@onready var collection_rows: VBoxContainer = %CollectionRows
@onready var buy_rows: VBoxContainer = %BuyRows
@onready var sell_rows: VBoxContainer = %SellRows
@onready var jar_rows: VBoxContainer = %JarRows
@onready var environment_rows: VBoxContainer = %EnvironmentRows

var _state: GameState
var _catalog: ContentCatalog
var _tuning: MvpTuning
var _active_capacity: int = 0
var _rebuild_queued: bool = false


func _ready() -> void:
	close_button.pressed.connect(_request_close)
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_apply_safe_area)
	tabs.set_tab_title(0, "Collection")
	tabs.set_tab_title(1, "Buy")
	tabs.set_tab_title(2, "Sell")
	tabs.set_tab_title(3, "Jars")
	tabs.set_tab_title(4, "Places")
	_apply_safe_area()
	if _state != null and _catalog != null and _tuning != null:
		_queue_rebuild()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_request_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_focus_next"):
		_cycle_modal_focus(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_focus_prev"):
		_cycle_modal_focus(-1)
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	show()
	if is_node_ready():
		call_deferred("_focus_close_button")


func close_panel() -> void:
	_request_close()


func refresh(
	state: GameState,
	catalog: ContentCatalog,
	tuning: MvpTuning,
	active_capacity: int,
) -> void:
	_state = state
	_catalog = catalog
	_tuning = tuning
	_active_capacity = maxi(active_capacity, 0)
	if is_node_ready():
		_queue_rebuild()


func _request_close() -> void:
	if not visible:
		return
	hide()
	close_requested.emit()


func _on_visibility_changed() -> void:
	if visible and is_node_ready():
		call_deferred("_focus_close_button")


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_perform_queued_rebuild")


func _perform_queued_rebuild() -> void:
	_rebuild_queued = false
	if not is_node_ready():
		return
	_rebuild_all_rows()
	refresh_applied.emit()


func _rebuild_all_rows() -> void:
	_clear_rows(collection_rows)
	_clear_rows(buy_rows)
	_clear_rows(sell_rows)
	_clear_rows(jar_rows)
	_clear_rows(environment_rows)

	if _state == null or _catalog == null or _tuning == null:
		summary_label.text = "Stall data unavailable"
		_add_empty_message(collection_rows, "The garden stall is not ready yet.")
		_restore_modal_focus_after_rebuild()
		return

	_refresh_summary()
	_build_collection_rows()
	_build_buy_rows()
	_build_sell_rows()
	_build_jar_rows()
	_build_environment_rows()
	_restore_modal_focus_after_rebuild()


func _refresh_summary() -> void:
	summary_label.text = "%d coins  •  %d / %d plants" % [
		_state.coins,
		_state.plants.size(),
		_active_capacity,
	]


func _build_collection_rows() -> void:
	if _catalog.plant_variants.is_empty():
		_add_empty_message(collection_rows, "No plant variants are configured.")
		return

	for definition in _catalog.plant_variants:
		if definition == null:
			continue
		var discovered: bool = definition.id in _state.discovered_variant_ids
		if discovered:
			_add_row(
				collection_rows,
				_make_plant_preview(definition),
				definition.display_name,
				"%s • %s" % [_format_id(definition.rarity), definition.description],
			)
		else:
			_add_row(
				collection_rows,
				_make_mystery_preview(),
				"Unknown Variant",
				"Undiscovered • Keep caring for your jar to reveal this plant.",
			)


func _build_buy_rows() -> void:
	var shown_count: int = 0
	var jar_is_full: bool = _state.plants.size() >= _active_capacity
	for definition in _catalog.plant_variants:
		if definition == null or definition.id not in _state.discovered_variant_ids:
			continue
		shown_count += 1
		var can_afford: bool = _state.coins >= definition.young_buy_price
		var disabled: bool = jar_is_full or not can_afford
		var action_text: String = "Buy • %d" % definition.young_buy_price
		if jar_is_full:
			action_text = "Jar full"
		elif not can_afford:
			action_text = "Need %d" % definition.young_buy_price
		_add_row(
			buy_rows,
			_make_plant_preview(definition),
			definition.display_name,
			"Young plant • %s • Previously discovered" % _format_id(definition.rarity),
			action_text,
			disabled,
			_emit_buy_plant.bind(definition.id),
		)

	if shown_count == 0:
		_add_empty_message(buy_rows, "Discover a plant variant before buying its young form.")


func _build_sell_rows() -> void:
	if _state.plants.is_empty():
		_add_empty_message(sell_rows, "There are no plants in the jar to sell.")
		return

	for plant in _state.plants:
		var definition: PlantVariantDefinition = _catalog.get_variant(plant.variant_id)
		var stage: PlantState.LifecycleStage = plant.get_lifecycle_stage(_tuning)
		var stage_name: String = plant.get_lifecycle_stage_name(_tuning)
		var sell_value: int = 1
		if stage == PlantState.LifecycleStage.ADULT and definition != null:
			sell_value = definition.adult_sell_value

		var title := String(plant.variant_id)
		var subtitle := "%s • %s" % [stage_name, plant.instance_id]
		var preview: Control
		var disabled: bool = false
		var action_text: String = "Sell • %d" % sell_value
		if definition != null:
			title = definition.display_name
			preview = _make_plant_preview(definition)
		else:
			preview = _make_mystery_preview()
			subtitle = "%s • Missing variant data" % stage_name
			action_text = "Sell • 1"

		_add_row(
			sell_rows,
			preview,
			title,
			subtitle,
			action_text,
			disabled,
			_emit_sell_plant.bind(plant.instance_id),
		)


func _build_jar_rows() -> void:
	if _catalog.jars.is_empty():
		_add_empty_message(jar_rows, "No jars are configured.")
		return

	for definition in _catalog.jars:
		if definition == null:
			continue
		var is_active: bool = definition.id == _state.active_jar_id
		var is_owned: bool = _state.owns_jar(definition.id)
		var disabled: bool = is_active
		var action_text: String = ""
		if is_active:
			action_text = "Active"
		elif is_owned:
			action_text = "Owned • Use"
		else:
			action_text = "Buy • %d" % definition.price
		if not is_owned and _state.coins < definition.price:
			disabled = true
			action_text = "Need %d" % definition.price
		_add_row(
			jar_rows,
			_make_swatch_preview(definition.glass_fill_color, "Jar"),
			definition.display_name,
			"Capacity %d • %s" % [definition.capacity, definition.description],
			action_text,
			disabled,
			_emit_jar_action.bind(definition.id),
		)


func _build_environment_rows() -> void:
	if _catalog.environments.is_empty():
		_add_empty_message(environment_rows, "No environments are configured.")
		return

	for definition in _catalog.environments:
		if definition == null:
			continue
		var is_active: bool = definition.id == _state.active_environment_id
		var is_owned: bool = _state.owns_environment(definition.id)
		var disabled: bool = is_active
		var action_text: String = ""
		if is_active:
			action_text = "Active"
		elif is_owned:
			action_text = "Owned • Use"
		else:
			action_text = "Buy • %d" % definition.price
		if not is_owned and _state.coins < definition.price:
			disabled = true
			action_text = "Need %d" % definition.price
		_add_row(
			environment_rows,
			_make_swatch_preview(definition.accent_color, "Env"),
			definition.display_name,
			"%s • %s" % [definition.local_weather_label, definition.description],
			action_text,
			disabled,
			_emit_environment_action.bind(definition.id),
		)


func _add_row(
	container: VBoxContainer,
	preview: Control,
	title: String,
	subtitle: String,
	action_text: String = "",
	action_disabled: bool = false,
	action: Callable = Callable(),
) -> void:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0.0, 112.0)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_stylebox_override(&"panel", _make_row_style())
	container.add_child(row)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 14)
	margin.add_theme_constant_override(&"margin_top", 10)
	margin.add_theme_constant_override(&"margin_right", 12)
	margin.add_theme_constant_override(&"margin_bottom", 10)
	row.add_child(margin)

	var content := HBoxContainer.new()
	content.add_theme_constant_override(&"separation", 14)
	margin.add_child(content)
	content.add_child(preview)

	var text_stack := VBoxContainer.new()
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	text_stack.add_theme_constant_override(&"separation", 4)
	content.add_child(text_stack)

	var title_label := Label.new()
	title_label.add_theme_color_override(&"font_color", Color(0.95, 0.97, 0.88, 1.0))
	title_label.add_theme_font_size_override(&"font_size", 22)
	title_label.text = title
	text_stack.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle_label.add_theme_color_override(&"font_color", Color(0.72, 0.82, 0.72, 1.0))
	subtitle_label.add_theme_font_size_override(&"font_size", 16)
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.text = subtitle
	text_stack.add_child(subtitle_label)

	if action_text.is_empty():
		return
	var button := Button.new()
	button.custom_minimum_size = Vector2(142.0, 58.0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.disabled = action_disabled
	button.text = action_text
	button.add_theme_font_size_override(&"font_size", 18)
	button.add_theme_color_override(&"font_color", Color(0.075, 0.15, 0.10, 1.0))
	button.add_theme_color_override(&"font_disabled_color", Color(0.52, 0.58, 0.51, 1.0))
	button.add_theme_stylebox_override(&"normal", _make_action_style(ACTION_COLOR))
	button.add_theme_stylebox_override(&"hover", _make_action_style(SECONDARY_ACTION_COLOR))
	button.add_theme_stylebox_override(&"pressed", _make_action_style(Color(0.35, 0.52, 0.37, 1.0)))
	button.add_theme_stylebox_override(&"disabled", _make_action_style(Color(0.22, 0.29, 0.24, 1.0)))
	if action.is_valid():
		button.pressed.connect(action)
	content.add_child(button)


func _add_empty_message(container: VBoxContainer, message: String) -> void:
	var label := Label.new()
	label.custom_minimum_size = Vector2(0.0, 96.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override(&"font_color", Color(0.76, 0.82, 0.72, 1.0))
	label.add_theme_font_size_override(&"font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = message
	container.add_child(label)


func _make_plant_preview(definition: PlantVariantDefinition) -> Control:
	var host := CenterContainer.new()
	host.custom_minimum_size = Vector2(108.0, 92.0)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if plant_scene == null:
		host.add_child(_make_blob_panel(definition.body_color, ""))
		return host

	var preview_node := plant_scene.instantiate()
	if not preview_node is Control:
		preview_node.free()
		host.add_child(_make_blob_panel(definition.body_color, ""))
		return host

	var preview := preview_node as Control
	host.add_child(preview)
	if preview.has_method(&"apply_variant_definition"):
		preview.call(&"apply_variant_definition", definition)
	if preview.has_method(&"set_interaction_enabled"):
		preview.call(&"set_interaction_enabled", false)
	_disable_preview_interaction(preview)
	return host


func _make_mystery_preview() -> Control:
	var host := CenterContainer.new()
	host.custom_minimum_size = Vector2(108.0, 92.0)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_make_blob_panel(Color(0.105, 0.125, 0.115, 1.0), "?"))
	return host


func _make_blob_panel(color: Color, mark: String) -> PanelContainer:
	var blob := PanelContainer.new()
	blob.custom_minimum_size = Vector2(88.0, 76.0)
	blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.62, 0.68, 0.62, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(38)
	blob.add_theme_stylebox_override(&"panel", style)
	if not mark.is_empty():
		var mark_label := Label.new()
		mark_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark_label.add_theme_color_override(&"font_color", Color(0.76, 0.80, 0.72, 1.0))
		mark_label.add_theme_font_size_override(&"font_size", 36)
		mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark_label.text = mark
		blob.add_child(mark_label)
	return blob


func _make_swatch_preview(color: Color, mark: String) -> Control:
	var host := CenterContainer.new()
	host.custom_minimum_size = Vector2(108.0, 92.0)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var swatch := PanelContainer.new()
	swatch.custom_minimum_size = Vector2(84.0, 72.0)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.86, 0.92, 0.82, 0.75)
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	swatch.add_theme_stylebox_override(&"panel", style)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override(&"font_color", Color(0.96, 0.98, 0.92, 1.0))
	label.add_theme_font_size_override(&"font_size", 17)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = mark
	swatch.add_child(label)
	host.add_child(swatch)
	return host


func _disable_preview_interaction(node: Node) -> void:
	if node is Control:
		var control := node as Control
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
	node.set_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child in node.get_children():
		_disable_preview_interaction(child)


func _make_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_COLOR
	style.border_color = Color(0.34, 0.49, 0.38, 0.72)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	return style


func _make_action_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(16)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	return style


func _format_id(value: StringName) -> String:
	return String(value).replace("_", " ").capitalize()


func _clear_rows(container: VBoxContainer) -> void:
	for child in container.get_children():
		# Rebuilds are always frame-deferred, so the originating Button signal has
		# finished before old rows are released. Immediate freeing also avoids
		# orphaning queued rows after they have been detached from the scene tree.
		child.free()


func _focus_close_button() -> void:
	if visible and is_instance_valid(close_button):
		close_button.grab_focus()


func _restore_modal_focus_after_rebuild() -> void:
	if not visible:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null or not is_ancestor_of(focus_owner):
		close_button.grab_focus()


func _cycle_modal_focus(direction: int) -> void:
	var focusable_controls := _get_focusable_controls()
	if focusable_controls.is_empty():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	var current_index := focusable_controls.find(focus_owner)
	var next_index := 0 if direction > 0 else focusable_controls.size() - 1
	if current_index >= 0:
		next_index = posmod(current_index + direction, focusable_controls.size())
	focusable_controls[next_index].grab_focus()


func _get_focusable_controls() -> Array[Control]:
	var controls: Array[Control] = []
	_append_focusable_controls(self, controls)
	return controls


func _append_focusable_controls(node: Node, controls: Array[Control]) -> void:
	for child in node.get_children(true):
		if child is Control:
			var control := child as Control
			var is_disabled_button: bool = false
			if control is BaseButton:
				is_disabled_button = (control as BaseButton).disabled
			if (
				control.focus_mode != Control.FOCUS_NONE
				and control.is_visible_in_tree()
				and not is_disabled_button
			):
				controls.append(control)
		_append_focusable_controls(child, controls)


func _emit_buy_plant(variant_id: StringName) -> void:
	buy_plant_requested.emit(variant_id)


func _emit_sell_plant(instance_id: String) -> void:
	sell_plant_requested.emit(instance_id)


func _emit_jar_action(jar_id: StringName) -> void:
	jar_action_requested.emit(jar_id)


func _emit_environment_action(environment_id: StringName) -> void:
	environment_action_requested.emit(environment_id)


func _apply_safe_area() -> void:
	if not is_node_ready():
		return
	var margins := Vector4(
		BASE_SAFE_MARGIN,
		BASE_SAFE_MARGIN,
		BASE_SAFE_MARGIN,
		BASE_SAFE_MARGIN,
	)
	if OS.get_name() in MOBILE_PLATFORMS:
		margins += _get_mobile_safe_insets()
	safe_margin.add_theme_constant_override(&"margin_left", roundi(margins.x))
	safe_margin.add_theme_constant_override(&"margin_top", roundi(margins.y))
	safe_margin.add_theme_constant_override(&"margin_right", roundi(margins.z))
	safe_margin.add_theme_constant_override(&"margin_bottom", roundi(margins.w))


func _get_mobile_safe_insets() -> Vector4:
	var window_size_pixels := DisplayServer.window_get_size()
	if window_size_pixels.x <= 0 or window_size_pixels.y <= 0:
		return Vector4.ZERO
	var safe_rect_pixels := DisplayServer.get_display_safe_area()
	var window_position_pixels := DisplayServer.window_get_position()
	var safe_start := safe_rect_pixels.position - window_position_pixels
	var safe_end := safe_rect_pixels.end - window_position_pixels
	var viewport_size := get_viewport_rect().size
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
