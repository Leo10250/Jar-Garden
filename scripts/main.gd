extends Control


const MAX_SIMULATION_BATCHES_PER_UPDATE: int = 8

@export var plant_scene: PackedScene
@export var tuning: MvpTuning
@export var content_catalog: ContentCatalog
@export var save_path: String = LocalSave.DEFAULT_SAVE_PATH

@onready var safe_area: SafeAreaContainer = $SafeArea
@onready var plant_bounds: Control = $SafeArea/GameArea/JarSlot/Jar/PlantBounds
@onready var simulation_timer: Timer = $SimulationTimer
@onready var autosave_timer: Timer = $AutosaveTimer
@onready var water_button: Button = $SafeArea/GameArea/BottomBar/WaterButton
@onready var stall_button: Button = $SafeArea/GameArea/BottomBar/StallButton
@onready var stall_panel: StallPanel = $StallPanel
@onready var water_level_visual: ColorRect = $SafeArea/GameArea/JarSlot/Jar/PlantBounds/WaterLevel
@onready var water_foreground_visual: ColorRect = $SafeArea/GameArea/JarSlot/Jar/PlantBounds/WaterForeground
@onready var water_effects: WaterEffects = $SafeArea/GameArea/JarSlot/Jar/PlantBounds/WaterEffects
@onready var coins_label: Button = $SafeArea/GameArea/StatusBar/CoinsLabel
@onready var water_label: Button = $SafeArea/GameArea/StatusBar/WaterLabel
@onready var light_label: Button = $SafeArea/GameArea/StatusBar/LightLabel
@onready var capacity_label: Button = $SafeArea/GameArea/StatusBar/CapacityLabel
@onready var sun_moon: Panel = $SafeArea/GameArea/JarSlot/Jar/SunSlot/SunMoon
@onready var sky: ColorRect = $ForestBackdrop/Sky
@onready var mist: ColorRect = $ForestBackdrop/Mist
@onready var background_far: TextureRect = $ForestBackdrop/FarLayer
@onready var background_mid: TextureRect = $ForestBackdrop/MidLayer
@onready var background_front: TextureRect = $ForestBackdrop/FrontLayer
@onready var night_tint: ColorRect = $ForestBackdrop/NightTint
@onready var indoor_window: Control = $ForestBackdrop/IndoorWindow
@onready var rainforest_vines: Control = $ForestBackdrop/RainforestVines
@onready var glass_back: Panel = $SafeArea/GameArea/JarSlot/Jar/GlassBack
@onready var jar_outline: Panel = $SafeArea/GameArea/JarSlot/Jar/JarOutline
@onready var toast_panel: PanelContainer = $ToastSafeArea/ToastLayer/ToastPanel
@onready var toast_label: Label = $ToastSafeArea/ToastLayer/ToastPanel/ToastLabel
@onready var save_error_overlay: Control = $SaveErrorOverlay
@onready var save_error_message: Label = %SaveErrorMessage
@onready var save_error_close_button: Button = %SaveErrorCloseButton

var game_state: GameState
var _plant_views: Dictionary = {}
var _is_initialized: bool = false
var _saving_enabled: bool = true
var _simulation_caught_up: bool = true
var _stall_state_changed_during_last_advance: bool = false
var _stall_presented_signature: String = ""
var _toast_tween: Tween
var _background_actions_suspended: bool = false
var _water_button_was_disabled: bool = false
var _stall_button_was_disabled: bool = false
var _water_button_focus_mode_before_stall: int = Control.FOCUS_ALL
var _stall_button_focus_mode_before_stall: int = Control.FOCUS_ALL


func _ready() -> void:
	simulation_timer.timeout.connect(_on_simulation_timer_timeout)
	autosave_timer.timeout.connect(_on_autosave_timer_timeout)
	water_button.pressed.connect(_on_water_button_pressed)
	stall_button.pressed.connect(_on_stall_button_pressed)
	stall_panel.buy_plant_requested.connect(_on_buy_plant_requested)
	stall_panel.sell_plant_requested.connect(_on_sell_plant_requested)
	stall_panel.jar_action_requested.connect(_on_jar_action_requested)
	stall_panel.environment_action_requested.connect(_on_environment_action_requested)
	stall_panel.close_requested.connect(_on_stall_panel_close_requested)
	stall_panel.visibility_changed.connect(_on_stall_panel_visibility_changed)
	stall_panel.refresh_applied.connect(_on_stall_refresh_applied)
	save_error_close_button.pressed.connect(_on_save_error_close_pressed)
	if tuning == null or plant_scene == null or content_catalog == null:
		push_error("Main requires its Plant scene, MVP tuning, and content catalog.")
		return

	simulation_timer.wait_time = tuning.foreground_tick_seconds
	autosave_timer.wait_time = tuning.autosave_interval_seconds
	_initialize_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(save_error_overlay) and save_error_overlay.visible:
			get_tree().quit()
			return
		if is_instance_valid(stall_panel) and stall_panel.visible:
			stall_panel.close_panel()
		else:
			get_tree().quit()
		return
	if not _is_initialized:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_checkpoint_and_save(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_advance_to_now()
		_save_game()


func _exit_tree() -> void:
	if _is_initialized and _saving_enabled:
		_checkpoint_and_save(true)


func _initialize_game() -> void:
	var now := int(Time.get_unix_time_from_system())
	var load_result := LocalSave.load_state_result(now, save_path, tuning)
	var save_load_error_message: String = ""
	if load_result.status == LocalSave.LoadStatus.OK:
		game_state = load_result.state
		_reconcile_content_state()
		var previous_count := game_state.plants.size()
		var previous_discoveries := game_state.discovered_variant_ids.duplicate()
		_simulation_caught_up = _advance_simulation_to(now)
		var discovery_name := _get_new_discovery_name(previous_discoveries)
		if not discovery_name.is_empty():
			_show_toast(tr("TOAST_NEW_DISCOVERY") % discovery_name)
		elif game_state.plants.size() > previous_count:
			_show_toast(tr("TOAST_AWAY_CHANGED"))
		if load_result.recovered_from_backup:
			push_warning(load_result.message)
	elif load_result.status == LocalSave.LoadStatus.NOT_FOUND:
		game_state = GameState.create_new(now, tuning)
		_reconcile_content_state()
		_simulation_caught_up = true
	else:
		game_state = GameState.create_new(now, tuning)
		_reconcile_content_state()
		_simulation_caught_up = true
		_saving_enabled = false
		save_load_error_message = tr("SAVE_LOAD_FAILED") + "\n\n" + load_result.message
		push_warning("Local save was preserved but could not be loaded: %s" % load_result.message)

	_sync_plant_views()
	_apply_content_presentation()
	_update_hud()
	_is_initialized = true
	if save_load_error_message.is_empty():
		_save_game()
	else:
		_show_save_error(save_load_error_message)


func _sync_plant_views() -> void:
	var state_by_id: Dictionary = {}
	for plant_state in game_state.plants:
		state_by_id[plant_state.instance_id] = plant_state

	for instance_id in _plant_views.keys():
		if state_by_id.has(instance_id):
			continue
		var removed_view: PlantView = _plant_views[instance_id]
		if is_instance_valid(removed_view):
			removed_view.queue_free()
		_plant_views.erase(instance_id)

	for plant_state in game_state.plants:
		var plant_view: PlantView
		if _plant_views.has(plant_state.instance_id):
			plant_view = _plant_views[plant_state.instance_id]
		else:
			plant_view = plant_scene.instantiate() as PlantView
			if plant_view == null:
				push_error("The configured Plant scene must use PlantView as its root script.")
				continue
			plant_bounds.add_child(plant_view)
			plant_view.name = plant_state.instance_id
			plant_view.drag_finished.connect(_on_plant_drag_finished)
			plant_view.position_canonicalized.connect(_on_plant_position_canonicalized)
			plant_view.bind_plant(plant_state.instance_id, plant_state.position_normalized)
			_plant_views[plant_state.instance_id] = plant_view
		var definition := content_catalog.get_variant(plant_state.variant_id)
		plant_view.apply_presentation(
			definition,
			plant_state.get_lifecycle_stage(tuning),
			plant_state.wetness,
		)
		plant_view.set_interaction_enabled(_saving_enabled and _simulation_caught_up)


func _on_plant_drag_finished(instance_id: String, normalized_center: Vector2) -> void:
	if not _saving_enabled or not _simulation_caught_up:
		return
	var plant_state := game_state.find_plant(instance_id)
	if plant_state == null:
		return
	if not _advance_to_now([instance_id]):
		_show_toast(tr("TOAST_CATCHING_UP"))
		return
	plant_state.position_normalized = normalized_center.clamp(Vector2.ZERO, Vector2.ONE)
	_update_hud()
	_save_game()


func _on_plant_position_canonicalized(
	instance_id: String,
	normalized_center: Vector2,
) -> void:
	if not _saving_enabled or not _simulation_caught_up:
		return
	var plant_state := game_state.find_plant(instance_id)
	if plant_state == null:
		return
	if not _advance_to_now([instance_id]):
		return
	plant_state.position_normalized = normalized_center
	_save_game()


func _on_simulation_timer_timeout() -> void:
	_advance_to_now()


func _on_water_button_pressed() -> void:
	if not _saving_enabled or stall_panel.visible:
		return
	if not _advance_to_now():
		_show_toast(tr("TOAST_CATCHING_UP"))
		return
	GardenSimulator.apply_watering(game_state, tuning)
	_sync_plant_views()
	_update_hud()
	water_effects.play_pour()
	_show_toast(tr("TOAST_WATERED"))
	_save_game()


func _on_stall_button_pressed() -> void:
	if not _saving_enabled or stall_panel.visible:
		return
	if not _advance_to_now():
		_show_toast(tr("TOAST_CATCHING_UP"))
		return
	_refresh_stall()
	stall_panel.open_panel()


func _on_buy_plant_requested(variant_id: StringName) -> void:
	if not _saving_enabled:
		return
	if not _advance_to_now():
		_show_toast(tr("TOAST_CATCHING_UP"))
		return
	if _stall_state_changed_during_last_advance:
		_show_toast(tr("TOAST_STALL_UPDATED"))
		return
	var definition := content_catalog.get_variant(variant_id)
	if definition == null or variant_id not in game_state.discovered_variant_ids:
		_show_toast(tr("TOAST_DISCOVER_FIRST"))
		return
	if game_state.plants.size() >= _get_active_capacity():
		_show_toast(tr("TOAST_JAR_FULL"))
		return
	if game_state.coins < definition.young_buy_price:
		_show_toast(tr("TOAST_NOT_ENOUGH_COINS"))
		return

	game_state.coins -= definition.young_buy_price
	game_state.spawn_plant_with_context(
		variant_id,
		_get_open_spawn_position(),
		game_state.last_simulated_unix_seconds,
		tuning,
		PlantState.SOURCE_PURCHASE,
	)
	_sync_plant_views()
	_update_hud()
	_show_toast(tr("TOAST_PLANT_JOINED") % _localized_content_name(definition))
	_save_game()
	_refresh_stall()


func _on_sell_plant_requested(instance_id: String) -> void:
	if not _saving_enabled:
		return
	if not _advance_to_now():
		_show_toast(tr("TOAST_CATCHING_UP"))
		return
	if _stall_state_changed_during_last_advance:
		_show_toast(tr("TOAST_STALL_UPDATED"))
		return
	var plant_state := game_state.find_plant(instance_id)
	if plant_state == null:
		return
	if not game_state.can_sell_plant(plant_state):
		_show_toast(tr("TOAST_ANCHOR_PROTECTED"))
		_refresh_stall()
		return
	var definition := content_catalog.get_variant(plant_state.variant_id)
	var sell_value: int = 1
	if (
		plant_state.get_lifecycle_stage(tuning) == PlantState.LifecycleStage.ADULT
		and definition != null
	):
		sell_value = definition.adult_sell_value
	if plant_state.birth_source == PlantState.SOURCE_RECOVERY:
		sell_value = 0
	if not game_state.remove_plant(instance_id, tuning):
		return
	game_state.coins += sell_value
	_sync_plant_views()
	_update_hud()
	_show_toast(tr("TOAST_SOLD") % sell_value)
	_save_game()
	_refresh_stall()


func _on_jar_action_requested(jar_id: StringName) -> void:
	if not _saving_enabled:
		return
	if not _advance_to_now():
		_show_toast(tr("TOAST_CATCHING_UP"))
		return
	if _stall_state_changed_during_last_advance:
		_show_toast(tr("TOAST_STALL_UPDATED"))
		return
	var definition := content_catalog.get_jar(jar_id)
	if definition == null:
		return
	if not game_state.owns_jar(jar_id):
		if game_state.coins < definition.price:
			_show_toast(tr("TOAST_NOT_ENOUGH_COINS"))
			return
		game_state.coins -= definition.price
		game_state.owned_jar_ids.append(jar_id)
	if game_state.plants.size() > definition.capacity:
		_show_toast(tr("TOAST_JAR_CAPACITY_BLOCKED"))
	else:
		game_state.active_jar_id = jar_id
		_show_toast(tr("TOAST_USING_JAR") % _localized_content_name(definition))
	_apply_content_presentation()
	_update_hud()
	_save_game()
	_refresh_stall()


func _on_environment_action_requested(environment_id: StringName) -> void:
	if not _saving_enabled:
		return
	if not _advance_to_now():
		_show_toast(tr("TOAST_CATCHING_UP"))
		return
	if _stall_state_changed_during_last_advance:
		_show_toast(tr("TOAST_STALL_UPDATED"))
		return
	var definition := content_catalog.get_environment(environment_id)
	if definition == null:
		return
	if not game_state.owns_environment(environment_id):
		if game_state.coins < definition.price:
			_show_toast(tr("TOAST_NOT_ENOUGH_COINS"))
			return
		game_state.coins -= definition.price
		game_state.owned_environment_ids.append(environment_id)
	GardenSimulator.settle_environment_change(
		game_state,
		environment_id,
		game_state.last_simulated_unix_seconds,
	)
	_apply_content_presentation()
	_update_hud()
	_show_toast(tr("TOAST_MOVED_ENVIRONMENT") % _localized_content_name(definition))
	_save_game()
	_refresh_stall()


func _on_autosave_timer_timeout() -> void:
	_checkpoint_and_save()


func _checkpoint_and_save(cancel_active_drags: bool = false) -> void:
	var pending_drag_positions: Dictionary = {}
	var excluded_instance_ids: Array[String] = []
	if cancel_active_drags:
		for instance_id in _plant_views:
			var plant_view: PlantView = _plant_views[instance_id]
			if not is_instance_valid(plant_view) or not plant_view.is_dragging():
				continue
			pending_drag_positions[instance_id] = plant_view.get_normalized_center()
			excluded_instance_ids.append(instance_id)
			plant_view.cancel_active_drag()
	var caught_up := _advance_to_now(excluded_instance_ids)
	if caught_up:
		for instance_id in pending_drag_positions:
			var plant_state := game_state.find_plant(instance_id)
			if plant_state != null:
				plant_state.position_normalized = pending_drag_positions[instance_id]
	_save_game()


func _advance_to_now(excluded_position_instance_ids: Array[String] = []) -> bool:
	if game_state == null:
		return false
	_stall_state_changed_during_last_advance = false
	_sync_positions_from_views(excluded_position_instance_ids)
	var previous_count := game_state.plants.size()
	var previous_discoveries := game_state.discovered_variant_ids.duplicate()
	var was_caught_up := _simulation_caught_up
	_simulation_caught_up = _advance_simulation_to(int(Time.get_unix_time_from_system()))
	_sync_plant_views()
	if _simulation_caught_up and not was_caught_up:
		_canonicalize_views_after_catch_up()
	_update_hud()
	var discovery_name := _get_new_discovery_name(previous_discoveries)
	if not discovery_name.is_empty():
		_show_toast(tr("TOAST_NEW_DISCOVERY") % discovery_name)
	elif game_state.plants.size() > previous_count:
		_show_toast(tr("TOAST_NEW_PLANT"))
	if stall_panel.visible and _get_stall_state_signature() != _stall_presented_signature:
		_stall_state_changed_during_last_advance = true
		_refresh_stall()
	return _simulation_caught_up


func _advance_simulation_to(target_unix_seconds: int) -> bool:
	var batches: int = 0
	while (
		game_state.last_simulated_unix_seconds < target_unix_seconds
		and batches < MAX_SIMULATION_BATCHES_PER_UPDATE
	):
		var previous_checkpoint := game_state.last_simulated_unix_seconds
		GardenSimulator.advance_to(
			game_state,
			target_unix_seconds,
			tuning,
			content_catalog,
			_get_active_jar_definition(),
			_get_active_environment_definition(),
		)
		batches += 1
		if game_state.last_simulated_unix_seconds <= previous_checkpoint:
			break
	return game_state.last_simulated_unix_seconds >= target_unix_seconds


func _on_stall_panel_visibility_changed() -> void:
	_set_background_actions_suspended(stall_panel.visible)


func _on_stall_panel_close_requested() -> void:
	call_deferred("_restore_stall_button_focus")


func _on_stall_refresh_applied() -> void:
	if game_state != null:
		_stall_presented_signature = _get_stall_state_signature()


func _set_background_actions_suspended(suspended: bool) -> void:
	if suspended == _background_actions_suspended:
		return
	_background_actions_suspended = suspended
	if suspended:
		_water_button_was_disabled = water_button.disabled
		_stall_button_was_disabled = stall_button.disabled
		_water_button_focus_mode_before_stall = water_button.focus_mode
		_stall_button_focus_mode_before_stall = stall_button.focus_mode
		water_button.disabled = true
		stall_button.disabled = true
		water_button.focus_mode = Control.FOCUS_NONE
		stall_button.focus_mode = Control.FOCUS_NONE
	else:
		water_button.disabled = _water_button_was_disabled
		stall_button.disabled = _stall_button_was_disabled
		water_button.focus_mode = _water_button_focus_mode_before_stall
		stall_button.focus_mode = _stall_button_focus_mode_before_stall


func _restore_stall_button_focus() -> void:
	if (
		not stall_panel.visible
		and is_instance_valid(stall_button)
		and not stall_button.disabled
		and stall_button.focus_mode != Control.FOCUS_NONE
	):
		stall_button.grab_focus()


func _save_game() -> void:
	if not _saving_enabled:
		return
	_sync_positions_from_views()
	var error := LocalSave.save_state(game_state, save_path, tuning)
	if error != OK:
		_saving_enabled = false
		var message := tr("SAVE_WRITE_FAILED") % error
		push_error(message)
		_show_save_error(message)


func _sync_positions_from_views(excluded_instance_ids: Array[String] = []) -> void:
	for instance_id in _plant_views:
		var plant_view: PlantView = _plant_views[instance_id]
		if not is_instance_valid(plant_view):
			continue
		if (
			not _simulation_caught_up
			or instance_id in excluded_instance_ids
			or plant_view.is_dragging()
		):
			continue
		var plant_state := game_state.find_plant(instance_id)
		if plant_state != null:
			plant_state.position_normalized = plant_view.get_normalized_center()


func _canonicalize_views_after_catch_up() -> void:
	for plant_state in game_state.plants:
		var plant_view: PlantView = _plant_views.get(plant_state.instance_id)
		if is_instance_valid(plant_view):
			plant_view.set_normalized_center(plant_state.position_normalized)


func _get_active_jar_definition() -> JarDefinition:
	return content_catalog.get_jar(game_state.active_jar_id) if game_state != null else null


func _get_active_environment_definition() -> EnvironmentDefinition:
	return content_catalog.get_environment(game_state.active_environment_id) if game_state != null else null


func _get_active_capacity() -> int:
	var jar_definition := _get_active_jar_definition()
	return jar_definition.capacity if jar_definition != null else 12


func _reconcile_content_state() -> void:
	var active_jar := content_catalog.get_jar(game_state.active_jar_id)
	if active_jar == null:
		active_jar = content_catalog.get_jar(GameState.DEFAULT_JAR_ID)
		if active_jar == null:
			active_jar = _get_first_jar_definition()
		if active_jar != null:
			game_state.active_jar_id = active_jar.id
	if active_jar != null and not game_state.owns_jar(active_jar.id):
		game_state.owned_jar_ids.append(active_jar.id)

	var active_environment := content_catalog.get_environment(game_state.active_environment_id)
	if active_environment == null:
		active_environment = content_catalog.get_environment(GameState.DEFAULT_ENVIRONMENT_ID)
		if active_environment == null:
			active_environment = _get_first_environment_definition()
		if active_environment != null:
			game_state.active_environment_id = active_environment.id
	if (
		active_environment != null
		and not game_state.owns_environment(active_environment.id)
	):
		game_state.owned_environment_ids.append(active_environment.id)
	game_state.ensure_minimum_recovery(tuning, game_state.last_simulated_unix_seconds)


func _get_first_jar_definition() -> JarDefinition:
	for definition in content_catalog.jars:
		if definition != null:
			return definition
	return null


func _get_first_environment_definition() -> EnvironmentDefinition:
	for definition in content_catalog.environments:
		if definition != null:
			return definition
	return null


func _get_new_discovery_name(previous_discoveries: Array) -> String:
	for variant_id in game_state.discovered_variant_ids:
		if variant_id in previous_discoveries:
			continue
		var definition := content_catalog.get_variant(variant_id)
		return _localized_content_name(definition) if definition != null else String(variant_id)
	return ""


func _get_open_spawn_position() -> Vector2:
	return Vector2(
		game_state.roll_float_range(0.14, 0.86),
		game_state.roll_float_range(0.25, 0.86),
	)


func _refresh_stall() -> void:
	if not is_instance_valid(stall_panel) or game_state == null:
		return
	stall_panel.refresh(game_state, content_catalog, tuning, _get_active_capacity())


func _get_stall_state_signature() -> String:
	var plant_parts: Array[String] = []
	for plant in game_state.plants:
		plant_parts.append("%s:%s:%d" % [
			plant.instance_id,
			String(plant.variant_id),
			int(plant.get_lifecycle_stage(tuning)),
		])
	return "%d|%s|%s|%s|%s|%s|%s" % [
		game_state.coins,
		String(game_state.active_jar_id),
		String(game_state.active_environment_id),
		str(game_state.discovered_variant_ids),
		str(game_state.owned_jar_ids),
		str(game_state.owned_environment_ids),
		",".join(plant_parts),
	]


func _update_hud() -> void:
	if game_state == null:
		return
	var jar_definition := _get_active_jar_definition()
	var environment_definition := _get_active_environment_definition()
	var capacity := jar_definition.capacity if jar_definition != null else 12
	coins_label.text = tr("UI_HUD_COINS") % game_state.coins
	var water_state_key := "WATER_%s" % GardenSimulator.get_water_state_label(
		game_state,
		tuning,
	).to_upper().replace(" ", "_")
	water_label.text = tr(water_state_key)
	capacity_label.text = tr("UI_HUD_CAPACITY") % [game_state.plants.size(), capacity]
	water_effects.set_level(game_state.water_level)

	var weather_label := (
		_localized_resource_key(
			environment_definition,
			&"weather_label_key",
			environment_definition.local_weather_label,
		)
		if environment_definition != null
		else tr("ENV_FOREST_WEATHER")
	)
	var environment_snapshot := EnvironmentProvider.get_environment_with_timezone_bias(
		int(Time.get_unix_time_from_system()),
		weather_label,
		tuning.day_start_hour,
		tuning.day_end_hour,
		game_state.simulation_timezone_bias_minutes,
	)
	var light_key := (
		"LIGHT_DAY"
		if environment_snapshot.light_state == EnvironmentProvider.DAY
		else "LIGHT_NIGHT"
	)
	light_label.text = "%s • %s" % [tr(light_key), weather_label]
	if environment_snapshot.light_state == EnvironmentProvider.DAY:
		sun_moon.self_modulate = Color(1.0, 0.94, 0.65, 1.0)
		night_tint.color = Color(0.098, 0.145, 0.282, 0.0)
	else:
		sun_moon.self_modulate = Color(0.58, 0.68, 0.92, 1.0)
		night_tint.color = Color(0.098, 0.145, 0.282, 0.22)


func _apply_content_presentation() -> void:
	var environment_definition := _get_active_environment_definition()
	if environment_definition != null:
		sky.color = environment_definition.sky_color
		mist.color = Color(environment_definition.accent_color, 0.08)
		background_far.texture = environment_definition.get("far_texture") as Texture2D
		background_mid.texture = environment_definition.get("mid_texture") as Texture2D
		background_front.texture = environment_definition.get("front_texture") as Texture2D
		indoor_window.visible = environment_definition.visual_style == &"indoor"
		rainforest_vines.visible = environment_definition.visual_style == &"rainforest"

	var jar_definition := _get_active_jar_definition()
	if jar_definition != null:
		var back_style := glass_back.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		back_style.bg_color = jar_definition.glass_fill_color
		glass_back.add_theme_stylebox_override("panel", back_style)
		var outline_style := jar_outline.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		outline_style.border_color = jar_definition.glass_border_color
		jar_outline.add_theme_stylebox_override("panel", outline_style)


func _show_toast(message: String) -> void:
	if not is_node_ready():
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	toast_label.text = message
	toast_panel.modulate.a = 1.0
	toast_panel.show()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.45)
	_toast_tween.tween_callback(toast_panel.hide)


func _show_save_error(message: String) -> void:
	simulation_timer.stop()
	autosave_timer.stop()
	if stall_panel.visible:
		stall_panel.close_panel()
	water_button.disabled = true
	stall_button.disabled = true
	water_button.focus_mode = Control.FOCUS_NONE
	stall_button.focus_mode = Control.FOCUS_NONE
	for plant_view in _plant_views.values():
		if is_instance_valid(plant_view):
			(plant_view as PlantView).set_interaction_enabled(false)
	save_error_message.text = message
	save_error_overlay.show()
	call_deferred("_focus_save_error_close_button")


func _focus_save_error_close_button() -> void:
	if save_error_overlay.visible:
		save_error_close_button.grab_focus()


func _on_save_error_close_pressed() -> void:
	get_tree().quit()


func _localized_content_name(definition: Resource) -> String:
	if definition == null:
		return ""
	return _localized_resource_key(
		definition,
		&"display_name_key",
		str(definition.get("display_name")),
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
