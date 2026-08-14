extends SceneTree


var _failures: int = 0


func _init() -> void:
	_test_new_game_seed()
	_test_lifecycle_boundaries_and_offline_time()
	_test_backward_clock()
	_test_serialization_round_trip()
	_test_schema_migration_and_validation()
	_test_minimum_recovery_and_protection()
	_test_save_file_handling()
	_test_normalized_position_mapping()
	_test_mouse_and_touch_dragging()

	if _failures == 0:
		print("Phase 2 tests passed.")
		quit(0)
	else:
		push_error("Phase 2 tests failed: %d" % _failures)
		quit(1)


func _test_new_game_seed() -> void:
	var state := GameState.create_new(1000)
	_expect(state.plants.size() == 5, "A new game starts with exactly five plants.")
	_expect(state.next_plant_sequence == 6, "The stable ID sequence advances past the seed plants.")
	for index in state.plants.size():
		var plant := state.plants[index]
		_expect(plant.instance_id == "plant_%06d" % (index + 1), "Seed IDs are stable and ordered.")
		_expect(plant.variant_id == PlantState.BASE_VARIANT_ID, "Seed plants use the base variant.")
		_expect(plant.position_normalized == GameState.INITIAL_PLANT_CENTERS[index], "Seed positions are normalized centers.")
		_expect(plant.birth_source == PlantState.SOURCE_INITIAL, "Seed plants record their initial source.")
		_expect(plant.birth_environment_id == GameState.DEFAULT_ENVIRONMENT_ID, "Seed plants record their birth environment.")


func _test_lifecycle_boundaries_and_offline_time() -> void:
	var tuning := _make_tuning()
	var state := GameState.create_new(1000)
	var plant := state.plants[0]

	GardenSimulator.advance_to(state, 1059, tuning)
	_expect(plant.get_lifecycle_stage(tuning) == PlantState.LifecycleStage.YOUNG, "A plant remains Young before the boundary.")
	GardenSimulator.advance_to(state, 1060, tuning)
	_expect(plant.get_lifecycle_stage(tuning) == PlantState.LifecycleStage.ADULT, "A plant becomes Adult at the exact boundary.")
	GardenSimulator.advance_to(state, 1180, tuning)
	_expect(plant.get_lifecycle_stage(tuning) == PlantState.LifecycleStage.OLD, "A plant becomes Old at the exact boundary.")

	var offline_state := GameState.create_new(2000)
	GardenSimulator.advance_to(offline_state, 2500, tuning)
	_expect(
		offline_state.plants[0].get_lifecycle_stage(tuning) == PlantState.LifecycleStage.OLD,
		"A long offline interval may advance directly from Young to Old.",
	)


func _test_backward_clock() -> void:
	var tuning := _make_tuning()
	var state := GameState.create_new(2000)
	state.plants[0].lifecycle_elapsed_seconds = 10.0
	var elapsed := GardenSimulator.advance_to(state, 1900, tuning)
	_expect(elapsed == 0.0, "Backward clock movement is clamped to zero elapsed time.")
	_expect(state.plants[0].lifecycle_elapsed_seconds == 10.0, "Backward clock movement cannot reduce plant age.")
	_expect(state.last_simulated_unix_seconds == 2000, "A backward clock cannot move the simulation checkpoint backward.")
	GardenSimulator.advance_to(state, 2000, tuning)
	_expect(state.plants[0].lifecycle_elapsed_seconds == 10.0, "Returning to the old checkpoint cannot grant duplicate growth.")


func _test_serialization_round_trip() -> void:
	var state := GameState.create_new(3000, null, 330)
	state.plants[0].lifecycle_elapsed_seconds = 73.5
	state.plants[0].position_normalized = Vector2(0.21, 0.87)
	state.plants[0].lifetime_sunlight_seconds = 123.5
	state.plants[0].cultivation_direct_water_exposure = 0.75
	state.plants[0].lifetime_wetness_seconds = 44.5
	state.plants[0].cultivation_submerged_fraction_seconds = 12.25
	state.rng_state = 9007199254740993
	var restored := GameState.from_dict(state.to_dict(), 9999)

	_expect(restored != null, "A valid state dictionary loads.")
	if restored == null:
		return
	_expect(restored.plants.size() == 5, "All plants survive a state round trip.")
	_expect(restored.plants[0].instance_id == "plant_000001", "Stable IDs survive a state round trip.")
	_expect(restored.plants[0].variant_id == PlantState.BASE_VARIANT_ID, "Variant IDs survive a state round trip.")
	_expect(restored.plants[0].born_at_unix_seconds == 3000, "Birth timestamps survive a state round trip.")
	_expect(is_equal_approx(restored.plants[0].lifecycle_elapsed_seconds, 73.5), "Lifecycle age survives a state round trip.")
	_expect(restored.plants[0].position_normalized.is_equal_approx(Vector2(0.21, 0.87)), "Normalized position survives a state round trip.")
	_expect(is_equal_approx(restored.plants[0].lifetime_sunlight_seconds, 123.5), "Lifetime cultivation history survives a state round trip.")
	_expect(is_equal_approx(restored.plants[0].cultivation_direct_water_exposure, 0.75), "Current-environment cultivation history survives a state round trip.")
	_expect(is_equal_approx(restored.plants[0].lifetime_wetness_seconds, 44.5), "Normalized lifetime wetness-seconds survive a state round trip.")
	_expect(is_equal_approx(restored.plants[0].cultivation_submerged_fraction_seconds, 12.25), "Current fractional submersion-seconds survive a state round trip.")
	_expect(restored.last_simulated_unix_seconds == 3000, "The simulation checkpoint survives a state round trip.")
	_expect(restored.rng_state == 9007199254740993, "RNG state survives a dictionary round trip beyond JSON's exact-number range.")
	_expect(restored.simulation_timezone_bias_minutes == 330, "The frozen simulation timezone survives a state round trip.")
	_expect(restored.next_plant_sequence == 6, "The next stable ID sequence survives a state round trip.")

	var duplicated := state.to_dict()
	var duplicate_plants: Array = duplicated["plants"]
	duplicate_plants.append(duplicate_plants[0].duplicate(true))
	var deduplicated := GameState.from_dict(duplicated, 3000)
	_expect(deduplicated == null, "Duplicate saved instance IDs reject the whole save instead of dropping data.")


func _test_schema_migration_and_validation() -> void:
	var state := GameState.create_new(3500, null, -480)
	var serialized := state.to_dict()
	_expect(
		typeof(serialized["rng_state"]) == TYPE_STRING,
		"Schema v4 serializes RNG state as a decimal string.",
	)
	_expect(
		serialized["simulation_timezone_bias_minutes"] == -480,
		"A new game freezes the explicitly supplied simulation timezone bias.",
	)

	var legacy_v2 := serialized.duplicate(true)
	legacy_v2["schema_version"] = 2
	legacy_v2["rng_state"] = 123456789
	legacy_v2.erase("simulation_timezone_bias_minutes")
	var migrated_v2 := GameState.from_dict(legacy_v2, 3500, null, 345)
	_expect(migrated_v2 != null, "A valid numeric schema-v2 RNG state migrates to schema v4.")
	if migrated_v2 != null:
		_expect(migrated_v2.rng_state == 123456789, "Schema-v2 migration preserves its numeric RNG state.")
		_expect(
			migrated_v2.simulation_timezone_bias_minutes == 345,
			"A legacy save freezes the explicit migration timezone bias.",
		)
		_expect(
			typeof(migrated_v2.to_dict()["rng_state"]) == TYPE_STRING,
			"A migrated save is re-serialized with the schema-v4 RNG representation.",
		)

	var early_v3 := serialized.duplicate(true)
	early_v3["schema_version"] = 3
	early_v3.erase("simulation_timezone_bias_minutes")
	var defaulted_v3 := GameState.from_dict(early_v3, 3500, null, 60)
	_expect(
		defaulted_v3 != null and defaulted_v3.simulation_timezone_bias_minutes == 60,
		"An early schema-v3 save freezes the explicit fallback timezone bias once.",
	)
	if defaulted_v3 != null:
		_expect(
			defaulted_v3.cultivation_environment_id == defaulted_v3.active_environment_id,
			"Schema-v3 migration starts a v4 cultivation segment in the active environment.",
		)
		_expect(
			is_equal_approx(defaulted_v3.plants[0].lifetime_sunlight_seconds, 0.0),
			"Unknown legacy cultivation history migrates conservatively to zero.",
		)
		_expect(
			is_equal_approx(defaulted_v3.plants[0].lifetime_wetness_seconds, 0.0)
			and is_equal_approx(
				defaulted_v3.plants[0].lifetime_submerged_fraction_seconds,
				0.0,
			),
			"Schema-v3 migration does not invent wetness or submersion history.",
		)

	var malformed_rng := serialized.duplicate(true)
	malformed_rng["rng_state"] = "9007199254740993oops"
	_expect(
		GameState.from_dict(malformed_rng, 3500, null, -480) == null,
		"A malformed schema-v4 RNG decimal string rejects the save.",
	)
	var numeric_v4_rng := serialized.duplicate(true)
	numeric_v4_rng["rng_state"] = 123456789
	_expect(
		GameState.from_dict(numeric_v4_rng, 3500, null, -480) == null,
		"Schema v4 rejects a numeric RNG field that could lose 64-bit precision in JSON.",
	)
	var invalid_timezone := serialized.duplicate(true)
	invalid_timezone["simulation_timezone_bias_minutes"] = "330"
	_expect(
		GameState.from_dict(invalid_timezone, 3500, null, -480) == null,
		"A malformed persisted simulation timezone bias rejects the save.",
	)


func _test_minimum_recovery_and_protection() -> void:
	var tuning := _make_tuning()
	var state := GameState.create_new(3700, tuning, 0)
	var original_ids: Array[String] = []
	for plant in state.plants:
		original_ids.append(plant.instance_id)
	for instance_id in original_ids:
		_expect(state.remove_plant(instance_id, tuning), "Every original plant can be sold or deleted.")

	_expect(
		state.plants.size() == GameState.MINIMUM_RECOVERY_PLANTS,
		"Removing every original plant deterministically restores a viable pair.",
	)
	_expect(
		not state.plants[0].position_normalized.is_equal_approx(state.plants[1].position_normalized),
		"Recovery plants use distinct safe positions.",
	)
	for plant in state.plants:
		_expect(plant.birth_source == PlantState.SOURCE_RECOVERY, "Safety-net plants record their recovery source.")
		_expect(state.is_ecology_anchor(plant), "The last recovery pair is explicitly queryable as ecology anchors.")
		_expect(not state.can_sell_plant(plant), "Ecology anchors are not offered for sale.")
		_expect(not state.can_remove_plant(plant.instance_id), "The last recovery pair cannot be sold repeatedly for coins.")
		_expect(not state.remove_plant(plant.instance_id, tuning), "Removal enforces recovery-pair protection.")

	var extra := state.spawn_plant_with_context(
		PlantState.BASE_VARIANT_ID,
		Vector2(0.5, 0.4),
		3700,
		tuning,
		PlantState.SOURCE_PURCHASE,
	)
	_expect(extra != null and state.plants.size() == 3, "A normal third plant can join the recovery pair.")
	var former_anchor := state.plants[0]
	_expect(not state.is_ecology_anchor(former_anchor), "Recovery plants stop being anchors once the jar has a third plant.")
	_expect(state.can_sell_plant(former_anchor), "A non-anchor recovery plant can be removed with a controller-enforced zero payout.")
	_expect(state.remove_plant(former_anchor.instance_id, tuning), "A non-anchor recovery plant can be removed.")
	_expect(state.plants.size() == 2, "Removing a non-anchor leaves a viable pair without spawning extras.")

	var serialized_empty := state.to_dict()
	serialized_empty["plants"] = []
	var loaded_empty := GameState.from_dict(serialized_empty, 3700, tuning, 0)
	_expect(
		loaded_empty != null and loaded_empty.plants.size() == GameState.MINIMUM_RECOVERY_PLANTS,
		"An empty persisted state is repaired deterministically during load.",
	)


func _test_save_file_handling() -> void:
	var test_path := TestTempPaths.make_path("phase2_test")
	var state := GameState.create_new(4000, null, -420)
	state.rng_state = 9007199254740993
	_expect(LocalSave.save_state(state, test_path) == OK, "A state can be written to local JSON.")
	var saved_file := FileAccess.open(test_path, FileAccess.READ)
	_expect(saved_file != null, "The written local JSON can be reopened through FileAccess.")
	if saved_file != null:
		var saved_json: Variant = JSON.parse_string(saved_file.get_as_text())
		saved_file.close()
		_expect(typeof(saved_json) == TYPE_DICTIONARY, "The written local save is valid JSON.")
		if typeof(saved_json) == TYPE_DICTIONARY:
			_expect(
				typeof(saved_json["rng_state"]) == TYPE_STRING
				and saved_json["rng_state"] == "9007199254740993",
				"FileAccess/JSON preserves an RNG state above 2^53 as an exact decimal string.",
			)
	state.plants[0].lifecycle_elapsed_seconds = 12.0
	_expect(LocalSave.save_state(state, test_path) == OK, "A replacement save keeps a last-good backup.")
	var restored := LocalSave.load_state(4000, test_path)
	_expect(restored != null and restored.plants.size() == 5, "A local JSON save can be loaded.")
	if restored != null:
		_expect(restored.rng_state == 9007199254740993, "Local save/load preserves an RNG state above 2^53 exactly.")
		_expect(restored.simulation_timezone_bias_minutes == -420, "Local save/load preserves the frozen simulation timezone.")

	var malformed_rng_path := test_path + ".malformed-rng"
	var malformed_rng_data := state.to_dict()
	malformed_rng_data["rng_state"] = "9007199254740993oops"
	var malformed_rng_file := FileAccess.open(malformed_rng_path, FileAccess.WRITE)
	_expect(malformed_rng_file != null, "A malformed-RNG test save can be created.")
	if malformed_rng_file != null:
		malformed_rng_file.store_string(JSON.stringify(malformed_rng_data))
		malformed_rng_file.close()
		var malformed_rng_result := LocalSave.load_state_result(4000, malformed_rng_path)
		_expect(
			malformed_rng_result.status == LocalSave.LoadStatus.INVALID,
			"Local loading rejects a malformed schema-v4 RNG decimal string.",
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(malformed_rng_path))

	var malformed_file := FileAccess.open(test_path, FileAccess.WRITE)
	if malformed_file != null:
		malformed_file.store_string("{malformed")
		malformed_file.close()
	var recovery := LocalSave.load_state_result(4000, test_path)
	_expect(recovery.status == LocalSave.LoadStatus.OK, "Malformed primary JSON recovers from the last-good backup.")
	_expect(recovery.recovered_from_backup, "Backup recovery is reported to the controller.")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path + LocalSave.BACKUP_SUFFIX))
	var missing := LocalSave.load_state_result(4000, test_path)
	_expect(missing.status == LocalSave.LoadStatus.NOT_FOUND, "A missing save is distinguished from invalid data.")

	var future_save_text := '{"schema_version":999,"future_data":"preserve"}'
	var future_file := FileAccess.open(test_path, FileAccess.WRITE)
	if future_file != null:
		future_file.store_string(future_save_text)
		future_file.close()
	var unsupported := LocalSave.load_state_result(4000, test_path)
	_expect(unsupported.status == LocalSave.LoadStatus.UNSUPPORTED, "A newer save schema is reported as unsupported instead of invalid.")
	_expect(LocalSave.save_state(state, test_path) == ERR_UNAVAILABLE, "Saving refuses to overwrite a newer unsupported schema.")
	var preserved_future := FileAccess.open(test_path, FileAccess.READ)
	if preserved_future != null:
		_expect(preserved_future.get_as_text() == future_save_text, "A newer unsupported save remains byte-for-byte preserved.")
		preserved_future.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))


func _test_normalized_position_mapping() -> void:
	var bounds_size := Vector2(400.0, 700.0)
	var plant_size := Vector2(96.0, 88.0)
	var position := PlantView.normalized_center_to_position(Vector2(0.5, 0.5), bounds_size, plant_size)
	var restored := PlantView.position_to_normalized_center(position, bounds_size, plant_size)
	_expect(restored.is_equal_approx(Vector2(0.5, 0.5)), "Center positions map between normalized and pixel space.")

	var edge_position := PlantView.normalized_center_to_position(Vector2.ONE, bounds_size, plant_size)
	_expect(edge_position.x + plant_size.x <= bounds_size.x, "The complete plant width remains inside the jar.")
	_expect(edge_position.y + plant_size.y <= bounds_size.y, "The complete plant height remains inside the jar.")
	var canonical_edge := PlantView.position_to_normalized_center(edge_position, bounds_size, plant_size)
	var canonical_position := PlantView.normalized_center_to_position(canonical_edge, bounds_size, plant_size)
	_expect(canonical_position.is_equal_approx(edge_position), "A clamped edge center round-trips to the same visible position.")

	var resized_position := PlantView.normalized_center_to_position(Vector2(0.5, 0.5), Vector2(600.0, 900.0), plant_size)
	var resized_center := PlantView.position_to_normalized_center(resized_position, Vector2(600.0, 900.0), plant_size)
	_expect(resized_center.is_equal_approx(Vector2(0.5, 0.5)), "Normalized center placement survives a bounds resize.")


func _test_mouse_and_touch_dragging() -> void:
	var bounds := Control.new()
	bounds.size = Vector2(400.0, 700.0)
	root.add_child(bounds)
	var packed_scene := load("res://scenes/plant.tscn") as PackedScene
	var plant := packed_scene.instantiate() as PlantView
	bounds.add_child(plant)
	plant.bind_plant("drag_test", Vector2(0.5, 0.5))
	plant.set_normalized_center(Vector2(0.5, 0.5))
	var drag_results: Array[Vector2] = []
	plant.drag_finished.connect(func(_instance_id: String, center: Vector2) -> void:
		drag_results.append(center)
	)

	var mouse_press := InputEventMouseButton.new()
	mouse_press.button_index = MOUSE_BUTTON_LEFT
	mouse_press.pressed = true
	plant.call("_gui_input", mouse_press)
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	mouse_motion.relative = Vector2(1000.0, 1000.0)
	plant.call("_gui_input", mouse_motion)
	var mouse_release := InputEventMouseButton.new()
	mouse_release.button_index = MOUSE_BUTTON_LEFT
	mouse_release.pressed = false
	plant.call("_gui_input", mouse_release)
	_expect(plant.position.x > 200.0 and plant.position.y > 400.0, "Left-mouse motion visibly repositions the plant.")
	_expect(plant.position.x + plant.size.x <= bounds.size.x, "Mouse dragging clamps the complete plant width inside the jar.")
	_expect(plant.position.y + plant.size.y <= bounds.size.y, "Mouse dragging clamps the complete plant height inside the jar.")
	_expect(drag_results.size() == 1, "A completed left-mouse drag emits one committed position.")

	plant.set_normalized_center(Vector2(0.5, 0.5))
	var start_position := plant.position
	var touch_press := InputEventScreenTouch.new()
	touch_press.index = 2
	touch_press.pressed = true
	plant.call("_gui_input", touch_press)
	var unrelated_drag := InputEventScreenDrag.new()
	unrelated_drag.index = 3
	unrelated_drag.relative = Vector2(80.0, 60.0)
	plant.call("_gui_input", unrelated_drag)
	_expect(plant.position.is_equal_approx(start_position), "An unrelated finger cannot move the active plant.")
	var matching_drag := InputEventScreenDrag.new()
	matching_drag.index = 2
	matching_drag.relative = Vector2(-90.0, -70.0)
	plant.call("_gui_input", matching_drag)
	_expect(not plant.position.is_equal_approx(start_position), "The tracked touch finger moves the plant.")
	var unrelated_release := InputEventScreenTouch.new()
	unrelated_release.index = 3
	unrelated_release.pressed = false
	plant.call("_gui_input", unrelated_release)
	_expect(drag_results.size() == 1, "An unrelated finger cannot finish the active drag.")
	var matching_release := InputEventScreenTouch.new()
	matching_release.index = 2
	matching_release.pressed = false
	plant.call("_gui_input", matching_release)
	_expect(drag_results.size() == 2, "The tracked touch release commits exactly one position.")
	bounds.free()


func _make_tuning() -> MvpTuning:
	var tuning := MvpTuning.new()
	tuning.young_duration_seconds = 60.0
	tuning.adult_duration_seconds = 120.0
	return tuning


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
