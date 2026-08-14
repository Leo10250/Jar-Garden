class_name StallPanel
extends Control


signal close_requested
signal refresh_applied
signal buy_plant_requested(variant_id: StringName)
signal sell_plant_requested(instance_id: String)
signal jar_action_requested(jar_id: StringName)
signal environment_action_requested(environment_id: StringName)

enum PrimarySection {
	COLLECTION,
	MARKET,
	CUSTOMIZE,
}

enum StallPage {
	COLLECTION,
	BUY,
	SELL,
	JARS,
	PLACES,
}

const COLLECTION_TWO_COLUMN_BREAKPOINT: float = 560.0

@export var plant_scene: PackedScene
@export var item_card_scene: PackedScene

@onready var close_button: Button = %CloseButton
@onready var summary_label: Label = %Summary
@onready var header_row: HBoxContainer = %HeaderRow
@onready var summary_badge: PanelContainer = %SummaryBadge
@onready var compact_summary_slot: CenterContainer = %CompactSummarySlot
@onready var collection_button: Button = %CollectionButton
@onready var market_button: Button = %MarketButton
@onready var customize_button: Button = %CustomizeButton
@onready var secondary_navigation: PanelContainer = %SecondaryNavigation
@onready var market_segments: HBoxContainer = %MarketSegments
@onready var customize_segments: HBoxContainer = %CustomizeSegments
@onready var buy_button: Button = %BuyButton
@onready var sell_button: Button = %SellButton
@onready var jars_button: Button = %JarsButton
@onready var places_button: Button = %PlacesButton
@onready var tabs: TabContainer = %Tabs
@onready var collection_scroll: ScrollContainer = %Collection
@onready var collection_rows: GridContainer = %CollectionRows
@onready var buy_rows: VBoxContainer = %BuyRows
@onready var sell_rows: VBoxContainer = %SellRows
@onready var jar_rows: VBoxContainer = %JarRows
@onready var environment_rows: VBoxContainer = %EnvironmentRows

var _state: GameState
var _catalog: ContentCatalog
var _tuning: MvpTuning
var _active_capacity: int = 0
var _rebuild_queued: bool = false
var _primary_section: PrimarySection = PrimarySection.COLLECTION
var _market_page: StallPage = StallPage.BUY
var _customize_page: StallPage = StallPage.JARS
var _is_compact_header: bool = false


func _ready() -> void:
	close_button.pressed.connect(_request_close)
	collection_button.pressed.connect(_show_collection)
	market_button.pressed.connect(_show_market)
	customize_button.pressed.connect(_show_customize)
	buy_button.pressed.connect(_show_buy)
	sell_button.pressed.connect(_show_sell)
	jars_button.pressed.connect(_show_jars)
	places_button.pressed.connect(_show_places)
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_queue_responsive_layout)
	collection_scroll.resized.connect(_queue_responsive_layout)
	tabs.tabs_visible = false
	_apply_navigation_state()
	_queue_responsive_layout()
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
		_queue_responsive_layout()
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
		_queue_responsive_layout()
		call_deferred("_focus_close_button")


func _show_collection() -> void:
	_primary_section = PrimarySection.COLLECTION
	_apply_navigation_state()


func _show_market() -> void:
	_primary_section = PrimarySection.MARKET
	_apply_navigation_state()


func _show_customize() -> void:
	_primary_section = PrimarySection.CUSTOMIZE
	_apply_navigation_state()


func _show_buy() -> void:
	_market_page = StallPage.BUY
	_apply_navigation_state()


func _show_sell() -> void:
	_market_page = StallPage.SELL
	_apply_navigation_state()


func _show_jars() -> void:
	_customize_page = StallPage.JARS
	_apply_navigation_state()


func _show_places() -> void:
	_customize_page = StallPage.PLACES
	_apply_navigation_state()


func _apply_navigation_state() -> void:
	if not is_node_ready():
		return
	collection_button.button_pressed = _primary_section == PrimarySection.COLLECTION
	market_button.button_pressed = _primary_section == PrimarySection.MARKET
	customize_button.button_pressed = _primary_section == PrimarySection.CUSTOMIZE
	buy_button.button_pressed = _market_page == StallPage.BUY
	sell_button.button_pressed = _market_page == StallPage.SELL
	jars_button.button_pressed = _customize_page == StallPage.JARS
	places_button.button_pressed = _customize_page == StallPage.PLACES

	secondary_navigation.visible = _primary_section != PrimarySection.COLLECTION
	market_segments.visible = _primary_section == PrimarySection.MARKET
	customize_segments.visible = _primary_section == PrimarySection.CUSTOMIZE
	match _primary_section:
		PrimarySection.COLLECTION:
			tabs.current_tab = StallPage.COLLECTION
		PrimarySection.MARKET:
			tabs.current_tab = _market_page
		PrimarySection.CUSTOMIZE:
			tabs.current_tab = _customize_page
	_queue_responsive_layout()


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
	_update_responsive_layout()
	refresh_applied.emit()


func _rebuild_all_rows() -> void:
	_clear_rows(collection_rows)
	_clear_rows(buy_rows)
	_clear_rows(sell_rows)
	_clear_rows(jar_rows)
	_clear_rows(environment_rows)

	if _state == null or _catalog == null or _tuning == null:
		summary_label.text = tr("UI_STALL_UNAVAILABLE")
		_add_empty_message(collection_rows, tr("UI_STALL_NOT_READY"))
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
	if _is_compact_header:
		summary_label.text = tr("UI_SUMMARY_COMPACT") % [
			_state.coins,
			_state.plants.size(),
			_active_capacity,
		]
	else:
		summary_label.text = tr("UI_SUMMARY_WIDE") % [
			_state.coins,
			_state.plants.size(),
			_active_capacity,
		]


func _build_collection_rows() -> void:
	if _catalog.plant_variants.is_empty():
		_add_empty_message(collection_rows, tr("UI_NO_VARIANTS"))
		return

	for definition in _catalog.plant_variants:
		if definition == null:
			continue
		var discovered: bool = definition.id in _state.discovered_variant_ids
		if discovered:
			_add_card(
				collection_rows,
				_make_plant_preview(definition),
				_localized_content_name(definition),
				tr("UI_COLLECTION_DISCOVERED_DETAILS") % [
					_localized_rarity(definition.rarity),
					_localized_content_description(definition),
					_localized_resource_key(definition, &"discovered_recipe_key", ""),
				],
				"",
				false,
				Callable(),
				true,
			)
		else:
			var poetic_hint := _localized_resource_key(
				definition,
				&"undiscovered_hint_key",
				tr("PLANT_BASE_COMMON_HINT"),
			)
			_add_card(
				collection_rows,
				_make_mystery_preview(),
				tr("UI_UNKNOWN_VARIANT"),
				tr("UI_COLLECTION_UNKNOWN_DETAILS") % poetic_hint,
				"",
				false,
				Callable(),
				true,
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
		var action_text: String = tr("UI_BUY_PRICE") % definition.young_buy_price
		if jar_is_full:
			action_text = tr("UI_JAR_FULL")
		elif not can_afford:
			action_text = tr("UI_NEED_COINS") % definition.young_buy_price
		_add_card(
			buy_rows,
			_make_plant_preview(definition),
			_localized_content_name(definition),
			tr("UI_YOUNG_DISCOVERED") % _localized_rarity(definition.rarity),
			action_text,
			disabled,
			_emit_buy_plant.bind(definition.id),
		)

	if shown_count == 0:
		_add_empty_message(buy_rows, tr("UI_NO_BUYABLE_PLANTS"))


func _build_sell_rows() -> void:
	if _state.plants.is_empty():
		_add_empty_message(sell_rows, tr("UI_NO_SELLABLE_PLANTS"))
		return

	for plant in _state.plants:
		var definition: PlantVariantDefinition = _catalog.get_variant(plant.variant_id)
		var stage: PlantState.LifecycleStage = plant.get_lifecycle_stage(_tuning)
		var stage_name: String = _localized_stage(plant.get_lifecycle_stage_name(_tuning))
		var sell_value: int = 1
		if stage == PlantState.LifecycleStage.ADULT and definition != null:
			sell_value = definition.adult_sell_value
		if plant.birth_source == PlantState.SOURCE_RECOVERY:
			sell_value = 0
		var is_anchor := _state.is_ecology_anchor(plant)
		var can_sell := _state.can_sell_plant(plant)

		var title := String(plant.variant_id)
		var subtitle := "%s • %s" % [stage_name, plant.instance_id]
		var preview: Control
		var action_text: String = (
			tr("UI_ECOLOGY_ANCHOR") if is_anchor else tr("UI_SELL_PRICE") % sell_value
		)
		if definition != null:
			title = _localized_content_name(definition)
			preview = _make_plant_preview(definition)
		else:
			preview = _make_mystery_preview()
			subtitle = tr("UI_MISSING_VARIANT") % stage_name
			action_text = tr("UI_SELL_PRICE") % sell_value
		if is_anchor:
			subtitle = "%s • %s" % [stage_name, tr("UI_ECOLOGY_ANCHOR")]

		_add_card(
			sell_rows,
			preview,
			title,
			subtitle,
			action_text,
			not can_sell,
			_emit_sell_plant.bind(plant.instance_id),
		)


func _build_jar_rows() -> void:
	if _catalog.jars.is_empty():
		_add_empty_message(jar_rows, tr("UI_NO_JARS"))
		return

	for definition in _catalog.jars:
		if definition == null:
			continue
		var is_active: bool = definition.id == _state.active_jar_id
		var is_owned: bool = _state.owns_jar(definition.id)
		var disabled: bool = is_active
		var action_text: String
		if is_active:
			action_text = tr("UI_ACTIVE")
		elif is_owned:
			action_text = tr("UI_OWNED_USE")
		else:
			action_text = tr("UI_BUY_PRICE") % definition.price
		if not is_owned and _state.coins < definition.price:
			disabled = true
			action_text = tr("UI_NEED_COINS") % definition.price
		_add_card(
			jar_rows,
			_make_swatch_preview(definition.glass_fill_color, tr("UI_PREVIEW_JAR")),
			_localized_content_name(definition),
			tr("UI_CAPACITY_DESCRIPTION") % [
				definition.capacity,
				_localized_content_description(definition),
			],
			action_text,
			disabled,
			_emit_jar_action.bind(definition.id),
		)


func _build_environment_rows() -> void:
	if _catalog.environments.is_empty():
		_add_empty_message(environment_rows, tr("UI_NO_ENVIRONMENTS"))
		return

	for definition in _catalog.environments:
		if definition == null:
			continue
		var is_active: bool = definition.id == _state.active_environment_id
		var is_owned: bool = _state.owns_environment(definition.id)
		var disabled: bool = is_active
		var action_text: String
		if is_active:
			action_text = tr("UI_ACTIVE")
		elif is_owned:
			action_text = tr("UI_OWNED_USE")
		else:
			action_text = tr("UI_BUY_PRICE") % definition.price
		if not is_owned and _state.coins < definition.price:
			disabled = true
			action_text = tr("UI_NEED_COINS") % definition.price
		var preview := _make_swatch_preview(
			definition.accent_color,
			tr("UI_PREVIEW_PLACE"),
		)
		var thumbnail: Texture2D = definition.get("thumbnail_texture") as Texture2D
		if thumbnail != null:
			preview.queue_free()
			preview = _make_texture_preview(thumbnail)
		_add_card(
			environment_rows,
			preview,
			_localized_content_name(definition),
			tr("UI_ENVIRONMENT_DESCRIPTION") % [
				_localized_resource_key(
					definition,
					&"weather_label_key",
					definition.local_weather_label,
				),
				_localized_content_description(definition),
			],
			action_text,
			disabled,
			_emit_environment_action.bind(definition.id),
		)


func _add_card(
	container: Container,
	preview: Control,
	title: String,
	subtitle: String,
	action_text: String = "",
	action_disabled: bool = false,
	action: Callable = Callable(),
	collection_mode: bool = false,
) -> void:
	if item_card_scene == null:
		preview.queue_free()
		_add_empty_message(container, tr("UI_CARD_UNAVAILABLE"))
		return
	var card := item_card_scene.instantiate() as StallItemCard
	if card == null:
		preview.queue_free()
		_add_empty_message(container, tr("UI_CARD_UNAVAILABLE"))
		return
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(card)
	card.configure(
		preview,
		title,
		subtitle,
		action_text,
		action_disabled,
		action,
		collection_mode,
	)


func _add_empty_message(container: Container, message: String) -> void:
	var label := Label.new()
	label.custom_minimum_size = Vector2(0.0, 104.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.theme_type_variation = &"StallEmptyLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = message
	container.add_child(label)


func _make_plant_preview(definition: PlantVariantDefinition) -> Control:
	if plant_scene == null:
		return _make_swatch_preview(definition.body_color, tr("UI_PREVIEW_PLANT"))
	var preview_node := plant_scene.instantiate()
	if not preview_node is Control:
		preview_node.free()
		return _make_swatch_preview(definition.body_color, tr("UI_PREVIEW_PLANT"))
	var preview := preview_node as Control
	if preview.has_method(&"apply_variant_definition"):
		preview.call(&"apply_variant_definition", definition)
	if preview.has_method(&"set_interaction_enabled"):
		preview.call(&"set_interaction_enabled", false)
	_disable_preview_interaction(preview)
	return preview


func _make_mystery_preview() -> Control:
	if plant_scene == null:
		return _make_swatch_preview(Color(0.13, 0.20, 0.17, 1.0), "?")
	var preview_node := plant_scene.instantiate()
	if not preview_node is Control:
		preview_node.free()
		return _make_swatch_preview(Color(0.13, 0.20, 0.17, 1.0), "?")
	var preview := preview_node as Control
	if preview.has_method(&"set_mystery"):
		preview.call(&"set_mystery", true)
	if preview.has_method(&"set_interaction_enabled"):
		preview.call(&"set_interaction_enabled", false)
	_disable_preview_interaction(preview)
	return preview


func _make_swatch_preview(color: Color, mark: String) -> Control:
	var host := CenterContainer.new()
	host.custom_minimum_size = Vector2(108.0, 92.0)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(92.0, 78.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme_type_variation = &"PreviewFrame"
	var swatch := ColorRect.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.color = color
	frame.add_child(swatch)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"PreviewMarkLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = mark
	swatch.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(frame)
	return host


func _make_texture_preview(texture: Texture2D) -> Control:
	var host := CenterContainer.new()
	host.custom_minimum_size = Vector2(108.0, 92.0)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(92.0, 78.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme_type_variation = &"PreviewFrame"
	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(86.0, 72.0)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(image)
	host.add_child(frame)
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


func _queue_responsive_layout() -> void:
	if is_node_ready():
		call_deferred("_update_responsive_layout")


func _update_responsive_layout() -> void:
	if not is_node_ready():
		return
	var available_width := collection_scroll.size.x
	if available_width <= 0.0:
		available_width = tabs.size.x
	collection_rows.columns = 2 if available_width >= COLLECTION_TWO_COLUMN_BREAKPOINT else 1
	_apply_responsive_header(available_width < COLLECTION_TWO_COLUMN_BREAKPOINT)


func _apply_responsive_header(compact: bool) -> void:
	compact_summary_slot.visible = compact
	var target: Container = compact_summary_slot if compact else header_row
	if summary_badge.get_parent() != target:
		summary_badge.reparent(target, false)
		if not compact:
			header_row.move_child(summary_badge, close_button.get_index())
	summary_badge.custom_minimum_size = Vector2(0.0, 52.0) if compact else Vector2(176.0, 64.0)
	summary_badge.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL if compact else Control.SIZE_SHRINK_CENTER
	)
	if _is_compact_header == compact:
		return
	_is_compact_header = compact
	if _state != null:
		_refresh_summary()


func _format_id(value: StringName) -> String:
	return String(value).replace("_", " ").capitalize()


func _localized_content_name(definition: Resource) -> String:
	return _localized_resource_key(
		definition,
		&"display_name_key",
		str(definition.get("display_name")),
	)


func _localized_content_description(definition: Resource) -> String:
	return _localized_resource_key(
		definition,
		&"description_key",
		str(definition.get("description")),
	)


func _localized_resource_key(
	definition: Resource,
	property_name: StringName,
	fallback: String,
) -> String:
	if definition == null:
		return fallback
	var raw_key: Variant = definition.get(property_name)
	if raw_key != null and not str(raw_key).is_empty():
		return tr(str(raw_key))
	return fallback


func _localized_rarity(rarity: StringName) -> String:
	var key := "RARITY_%s" % String(rarity).to_upper()
	var translated := tr(key)
	return _format_id(rarity) if translated == key else translated


func _localized_stage(stage_name: String) -> String:
	var key := "STAGE_%s" % stage_name.to_upper()
	var translated := tr(key)
	return stage_name if translated == key else translated


func _clear_rows(container: Container) -> void:
	for child in container.get_children():
		# Rebuilds are frame-deferred, so an originating Button signal has
		# completed before its card is released.
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
