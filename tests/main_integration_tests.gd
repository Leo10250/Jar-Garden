extends SceneTree


const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"

var _failures: int = 0
var _test_save_path: String


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_save_path = TestTempPaths.make_path("main_integration")
	var main := _instantiate_main()
	await process_frame
	await process_frame

	var state: GameState = main.get("game_state")
	var tuning: MvpTuning = main.get("tuning")
	var catalog: ContentCatalog = main.get("content_catalog")
	_expect(state != null, "The main controller initializes a game state.")
	_expect(state.plants.size() == 5, "The main scene creates exactly five initial plants from state.")
	_expect(_count_plant_views(main) == 5, "Five state plants produce five draggable views.")

	var water_button := main.get_node("SafeArea/GameArea/BottomBar/WaterButton") as Button
	water_button.pressed.emit()
	_expect(state.water_level > 0.0, "The visible Water button changes pooled water state.")

	var first_plant := state.plants[0]
	var first_view := main.get_node(
		"SafeArea/GameArea/JarSlot/Jar/PlantBounds/%s" % first_plant.instance_id
	) as PlantView
	first_view.set_normalized_center(Vector2(0.5, 0.5))
	first_view.drag_finished.emit(first_plant.instance_id, first_view.get_normalized_center())
	_expect(first_plant.position_normalized.is_equal_approx(Vector2(0.5, 0.5)), "A completed drag commits normalized position to runtime state.")

	var coins_before_buy := state.coins
	main.call("_on_buy_plant_requested", &"base_common")
	_expect(state.plants.size() == 6, "A discovered young plant can be bought below capacity.")
	_expect(state.coins == coins_before_buy - catalog.get_variant(&"base_common").young_buy_price, "Buying deducts the configured young price.")

	var count_before_locked_buy := state.plants.size()
	main.call("_on_buy_plant_requested", &"blush_color")
	_expect(state.plants.size() == count_before_locked_buy, "An undiscovered variant cannot be bought.")

	var bought_id: String = state.plants[state.plants.size() - 1].instance_id
	var coins_before_young_sale := state.coins
	main.call("_on_sell_plant_requested", bought_id)
	_expect(state.coins == coins_before_young_sale + 1, "Selling a Young plant always earns one coin.")

	var adult := state.plants[0]
	adult.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	var adult_definition := catalog.get_variant(adult.variant_id)
	var coins_before_adult_sale := state.coins
	main.call("_on_sell_plant_requested", adult.instance_id)
	_expect(state.coins == coins_before_adult_sale + adult_definition.adult_sell_value, "Selling an Adult uses its configured variant value.")

	state.coins = 200
	main.call("_on_jar_action_requested", &"moss_glass")
	_expect(state.owns_jar(&"moss_glass") and state.active_jar_id == &"moss_glass", "A purchased jar becomes owned and selectable.")
	main.call("_on_environment_action_requested", &"indoor_window")
	_expect(
		state.owns_environment(&"indoor_window") and state.active_environment_id == &"indoor_window",
		"A purchased environment becomes owned and active.",
	)
	var indoor_window := main.get_node("ForestBackdrop/IndoorWindow") as Control
	_expect(indoor_window.visible, "Selecting the indoor environment visibly changes the background composition.")

	while state.plants.size() <= catalog.get_jar(&"default_glass").capacity:
		state.add_plant(&"base_common", Vector2(0.5, 0.5), int(Time.get_unix_time_from_system()), tuning)
	main.call("_sync_plant_views")
	main.call("_on_jar_action_requested", &"default_glass")
	_expect(state.active_jar_id == &"moss_glass", "A lower-capacity jar cannot be selected while too many plants occupy the garden.")

	var stall_button := main.get_node("SafeArea/GameArea/BottomBar/StallButton") as Button
	stall_button.pressed.emit()
	var stall_panel := main.get_node("StallPanel") as StallPanel
	_expect(stall_panel.visible, "The visible Stall button opens the collection/economy overlay.")
	await process_frame
	var collection_rows := stall_panel.get_node("SafeMargin/Modal/ContentMargin/Layout/Tabs/Collection/CollectionRows") as GridContainer
	_expect(collection_rows.get_child_count() == catalog.plant_variants.size(), "The collection shows one entry for every configured variant.")
	_expect(_tree_contains_label_text(collection_rows, "Unknown Variant"), "Undiscovered collection entries use a mystery presentation.")
	stall_panel.hide()
	await process_frame

	state.coins = 123
	main.call("_save_game")
	var saved_plant_count := state.plants.size()
	main.queue_free()
	await process_frame
	await process_frame

	var restored_main := _instantiate_main()
	await process_frame
	await process_frame
	var restored_state: GameState = restored_main.get("game_state")
	_expect(restored_state.coins == 123, "Coins survive closing and reopening the main scene.")
	_expect(restored_state.plants.size() == saved_plant_count, "Plant additions and sales survive closing and reopening.")
	_expect(restored_state.active_jar_id == &"moss_glass", "Active jar selection survives closing and reopening.")
	_expect(restored_state.active_environment_id == &"indoor_window", "Active environment selection survives closing and reopening.")
	_expect(restored_state.find_plant(state.plants[0].instance_id) != null, "Stable plant instance IDs survive a main-scene restart.")
	restored_main.queue_free()
	await process_frame
	await process_frame
	await _test_missing_content_reconciliation()
	await _test_invalid_save_blocks_unsaved_play()
	await _test_incomplete_catch_up_locks_positions()
	await _test_stall_requotes_before_sale()
	await _test_recovery_sales_through_main()
	await _test_full_jar_survives_water_animation()
	_cleanup_test_save()
	for cleanup_frame in 4:
		await process_frame

	if _failures == 0:
		print("Main integration tests passed.")
		quit(0)
	else:
		push_error("Main integration tests failed: %d" % _failures)
		quit(1)


func _instantiate_main(
	custom_save_path: String = "",
	custom_tuning: MvpTuning = null,
) -> Control:
	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene
	var main := packed_scene.instantiate() as Control
	main.set("save_path", _test_save_path if custom_save_path.is_empty() else custom_save_path)
	if custom_tuning != null:
		main.set("tuning", custom_tuning)
	root.add_child(main)
	return main


func _test_missing_content_reconciliation() -> void:
	var save_path := TestTempPaths.make_path("missing_content")
	var tuning := MvpTuning.new()
	var state := GameState.create_new(1000, tuning, 0)
	state.active_jar_id = &"retired_jar"
	state.owned_jar_ids.append(&"retired_jar")
	state.active_environment_id = &"retired_place"
	state.owned_environment_ids.append(&"retired_place")
	state.plants[0].variant_id = &"retired_blob"
	_expect(LocalSave.save_state(state, save_path, tuning) == OK, "A legacy-content fixture can be saved.")

	var main := _instantiate_main(save_path)
	await process_frame
	await process_frame
	var restored: GameState = main.get("game_state")
	_expect(restored.active_jar_id == GameState.DEFAULT_JAR_ID, "A missing active jar falls back to the catalog default.")
	_expect(restored.active_environment_id == GameState.DEFAULT_ENVIRONMENT_ID, "A missing active environment falls back to the catalog default.")
	_expect(&"retired_jar" in restored.owned_jar_ids, "Unknown owned jar metadata is preserved for future recovery.")
	_expect(&"retired_place" in restored.owned_environment_ids, "Unknown owned environment metadata is preserved for future recovery.")

	var retired_plant_id: String = restored.plants[0].instance_id
	var coins_before_sale := restored.coins
	main.call("_on_sell_plant_requested", retired_plant_id)
	_expect(restored.find_plant(retired_plant_id) == null, "A plant with missing catalog data can still be sold to free capacity.")
	_expect(restored.coins == coins_before_sale + 1, "A missing variant uses the safe one-coin fallback sale value.")
	main.queue_free()
	await process_frame
	await process_frame
	_remove_save_files(save_path)


func _test_invalid_save_blocks_unsaved_play() -> void:
	var save_path := TestTempPaths.make_path("invalid_main")
	var malformed_text := "{preserve-this-invalid-save"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		_expect(false, "The invalid-save fixture can be created.")
		return
	file.store_string(malformed_text)
	file.close()

	var main := _instantiate_main(save_path)
	await process_frame
	await process_frame
	var overlay := main.get_node("SaveErrorOverlay") as Control
	var water_button := main.get_node("SafeArea/GameArea/BottomBar/WaterButton") as Button
	var stall_button := main.get_node("SafeArea/GameArea/BottomBar/StallButton") as Button
	var state: GameState = main.get("game_state")
	var water_before := state.water_level
	_expect(overlay.visible, "An unreadable save shows a blocking, player-visible recovery message.")
	_expect(water_button.disabled and stall_button.disabled, "Gameplay actions are disabled while saving is unsafe.")
	main.call("_on_water_button_pressed")
	_expect(is_equal_approx(state.water_level, water_before), "A blocked session cannot create unsaved water progress.")

	var preserved_file := FileAccess.open(save_path, FileAccess.READ)
	_expect(preserved_file != null, "The unreadable primary save is preserved on disk.")
	if preserved_file != null:
		_expect(preserved_file.get_as_text() == malformed_text, "The unreadable save is not silently overwritten.")
		preserved_file.close()
	main.queue_free()
	await process_frame
	await process_frame
	_remove_save_files(save_path)


func _test_incomplete_catch_up_locks_positions() -> void:
	var save_path := TestTempPaths.make_path("catch_up_main")
	var tuning := MvpTuning.new()
	tuning.young_duration_seconds = 100000.0
	tuning.spawn_interval_min_seconds = 1.0
	tuning.spawn_interval_max_seconds = 1.0
	tuning.spawn_base_success_chance = 0.0
	tuning.maximum_events_per_advance = 1
	var now := int(Time.get_unix_time_from_system())
	var state := GameState.create_new(now - 100, tuning, 0)
	state.next_spawn_unix_seconds = now - 99
	_expect(LocalSave.save_state(state, save_path, tuning) == OK, "A behind-checkpoint fixture can be saved.")

	var main := _instantiate_main(save_path, tuning)
	await process_frame
	await process_frame
	var restored: GameState = main.get("game_state")
	var first_state := restored.plants[0]
	var first_view := main.get_node(
		"SafeArea/GameArea/JarSlot/Jar/PlantBounds/%s" % first_state.instance_id
	) as PlantView
	var original_center := first_state.position_normalized
	_expect(not bool(main.get("_simulation_caught_up")), "A deliberately event-heavy load remains resumably behind after its bounded first update.")
	_expect(first_view.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Plant interaction is disabled while offline history is still catching up.")
	first_view.drag_finished.emit(first_state.instance_id, Vector2(0.55, 0.55))
	_expect(first_state.position_normalized.is_equal_approx(original_center), "A forced drag signal cannot rewrite unprocessed offline position history.")

	for batch in 32:
		if bool(main.call("_advance_to_now")):
			break
	_expect(bool(main.get("_simulation_caught_up")), "Repeated bounded updates finish the resumable catch-up.")
	_expect(first_view.mouse_filter == Control.MOUSE_FILTER_STOP, "Plant interaction is restored after catch-up finishes.")
	first_view.set_normalized_center(Vector2(0.55, 0.55))
	var committed_center := first_view.get_normalized_center()
	first_view.drag_finished.emit(first_state.instance_id, committed_center)
	_expect(first_state.position_normalized.is_equal_approx(committed_center), "A post-catch-up drag commits normally.")
	main.queue_free()
	await process_frame
	await process_frame
	_remove_save_files(save_path)


func _test_stall_requotes_before_sale() -> void:
	var save_path := TestTempPaths.make_path("stall_requote")
	var main := _instantiate_main(save_path)
	await process_frame
	await process_frame
	var state: GameState = main.get("game_state")
	var tuning: MvpTuning = main.get("tuning")
	var plant := state.plants[0]
	plant.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	main.call("_refresh_stall")
	var stall_panel := main.get_node("StallPanel") as StallPanel
	stall_panel.open_panel()
	await process_frame

	plant.lifecycle_elapsed_seconds = (
		tuning.young_duration_seconds + tuning.adult_duration_seconds - 0.25
	)
	state.last_simulated_unix_seconds = int(Time.get_unix_time_from_system()) - 1
	state.next_spawn_unix_seconds = state.last_simulated_unix_seconds + 100000
	var coins_before := state.coins
	main.call("_on_sell_plant_requested", plant.instance_id)
	_expect(state.find_plant(plant.instance_id) != null, "A sale is paused if elapsed simulation changed the displayed lifecycle quote.")
	_expect(state.coins == coins_before, "A stale displayed quote cannot execute at a different payout.")
	await process_frame
	var sell_rows := stall_panel.get_node("SafeMargin/Modal/ContentMargin/Layout/Tabs/Sell Plants/SellRows") as VBoxContainer
	_expect(_tree_contains_label_fragment(sell_rows, "Old"), "The open Stall refreshes the plant's new lifecycle stage.")
	_expect(_tree_contains_button_text(sell_rows, "Sell • 1"), "The refreshed Stall shows the matching Old sale value.")
	stall_panel.close_panel()
	main.queue_free()
	await process_frame
	await process_frame
	_remove_save_files(save_path)


func _test_recovery_sales_through_main() -> void:
	var save_path := TestTempPaths.make_path("recovery_sale_main")
	var main := _instantiate_main(save_path)
	await process_frame
	await process_frame
	var state: GameState = main.get("game_state")
	var tuning: MvpTuning = main.get("tuning")
	state.plants.clear()
	state.reproduction_pair_progress.clear()
	var now := int(Time.get_unix_time_from_system())
	state.last_simulated_unix_seconds = now
	state.next_spawn_unix_seconds = now + 100000
	var recovery_ids: Array[String] = []
	for center in [Vector2(0.30, 0.72), Vector2(0.50, 0.58), Vector2(0.70, 0.72)]:
		var recovery := state.spawn_plant_with_context(
			PlantState.BASE_VARIANT_ID,
			center,
			now,
			tuning,
			PlantState.SOURCE_RECOVERY,
		)
		recovery_ids.append(recovery.instance_id)
	state.coins = 37
	main.call("_sync_plant_views")
	await process_frame

	var coins_before_sale := state.coins
	main.call("_on_sell_plant_requested", recovery_ids[0])
	_expect(
		state.find_plant(recovery_ids[0]) == null,
		"A recovery plant is sellable through Main while more than two plants remain.",
	)
	_expect(
		state.coins == coins_before_sale,
		"Selling a non-anchor recovery plant through Main never awards coins.",
	)
	_expect(state.plants.size() == 2, "Selling the third recovery plant leaves the viable anchor pair.")

	for anchor_id in recovery_ids.slice(1):
		main.call("_on_sell_plant_requested", anchor_id)
		_expect(
			state.find_plant(anchor_id) != null,
			"Each plant in the final recovery pair is protected by Main's sale handler.",
		)
	_expect(state.plants.size() == 2, "Neither of the final two ecology anchors can be sold.")
	_expect(state.coins == coins_before_sale, "Blocked anchor sales do not change the coin balance.")

	main.queue_free()
	await process_frame
	await process_frame
	_remove_save_files(save_path)


func _test_full_jar_survives_water_animation() -> void:
	var save_path := TestTempPaths.make_path("full_jar_water_main")
	var prototype := load("res://resources/prototype_mvp_tuning.tres") as MvpTuning
	var tuning := prototype.duplicate(true) as MvpTuning
	tuning.foreground_tick_seconds = 0.05
	tuning.spawn_base_success_chance = 0.0
	var main := _instantiate_main(save_path, tuning)
	await process_frame
	await process_frame
	var state: GameState = main.get("game_state")
	var now := int(Time.get_unix_time_from_system())
	state.next_spawn_unix_seconds = now + 100000
	while state.plants.size() < 12:
		var index := state.plants.size()
		var column := index % 4
		var row := index / 4
		state.add_plant(
			PlantState.BASE_VARIANT_ID,
			Vector2(0.18 + float(column) * 0.21, 0.34 + float(row) * 0.22),
			now,
			tuning,
		)
	main.call("_sync_plant_views")
	await process_frame
	_expect(state.plants.size() == 12, "The full-jar fixture contains exactly twelve plants.")
	_expect(_count_plant_views(main) == 12, "Synchronizing a full jar creates all twelve PlantViews.")

	var loop_probe := {"ticks": 0}
	var simulation_timer := main.get_node("SimulationTimer") as Timer
	simulation_timer.timeout.connect(func() -> void:
		loop_probe["ticks"] = int(loop_probe.ticks) + 1
	)
	simulation_timer.start(tuning.foreground_tick_seconds)
	var water_effects := main.get_node(
		"SafeArea/GameArea/JarSlot/Jar/PlantBounds/WaterEffects"
	) as WaterEffects
	var visual_level_before := water_effects.get_visual_level()
	main.call("_on_water_button_pressed")
	_expect(water_effects.is_level_animating(), "Watering a full jar starts the visible water-level tween.")
	await create_timer(0.20).timeout

	_expect(int(loop_probe.ticks) > 0, "The main simulation timer continues advancing during water animation.")
	simulation_timer.stop()
	await create_timer(0.55).timeout
	_expect(
		water_effects.get_visual_level() > visual_level_before,
		"The water visual advances instead of remaining a color-only state change.",
	)
	_expect(
		is_equal_approx(
			water_effects.get_visual_level(),
			water_effects.get_target_level(),
		),
		"The short run allows the visible water-level tween to reach its target.",
	)
	_expect(state.plants.size() == 12, "Watering and short simulation do not remove full-jar plant state.")
	_expect(_count_plant_views(main) == 12, "All twelve PlantViews remain after the water tween and main-loop ticks.")

	main.queue_free()
	await process_frame
	await process_frame
	_remove_save_files(save_path)


func _count_plant_views(main: Control) -> int:
	var count: int = 0
	var bounds := main.get_node("SafeArea/GameArea/JarSlot/Jar/PlantBounds")
	for child in bounds.get_children():
		if child is PlantView:
			count += 1
	return count


func _tree_contains_label_text(node: Node, expected_text: String) -> bool:
	if node is Label and (node as Label).text == expected_text:
		return true
	for child in node.get_children():
		if _tree_contains_label_text(child, expected_text):
			return true
	return false


func _tree_contains_label_fragment(node: Node, expected_fragment: String) -> bool:
	if node is Label and expected_fragment in (node as Label).text:
		return true
	for child in node.get_children():
		if _tree_contains_label_fragment(child, expected_fragment):
			return true
	return false


func _tree_contains_button_text(node: Node, expected_text: String) -> bool:
	if node is Button and (node as Button).text == expected_text:
		return true
	for child in node.get_children():
		if _tree_contains_button_text(child, expected_text):
			return true
	return false


func _cleanup_test_save() -> void:
	_remove_save_files(_test_save_path)


func _remove_save_files(path_without_suffix: String) -> void:
	for suffix in ["", LocalSave.BACKUP_SUFFIX, LocalSave.TEMP_SUFFIX]:
		var path: String = path_without_suffix + String(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
