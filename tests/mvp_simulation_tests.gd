extends SceneTree


const CATALOG_PATH: String = "res://resources/prototype_content_catalog.tres"
const PLANT_SCENE_PATH: String = "res://scenes/plant.tscn"

var _failures: int = 0
var _catalog: ContentCatalog


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_catalog = load(CATALOG_PATH) as ContentCatalog
	_test_water_position_stacking_decay_and_submersion()
	_test_reproduction_rules()
	_test_automatic_spawning_capacity_and_mutation()
	_test_online_and_offline_equivalence()
	_test_event_cap_catch_up_equivalence()
	_test_full_jar_does_not_bank_spawn_backlog()
	_test_water_offline_equivalence_across_evaporation_boundaries()
	_test_full_state_round_trip()
	_test_variant_presentation()

	if _failures == 0:
		print("MVP simulation tests passed.")
		quit(0)
	else:
		push_error("MVP simulation tests failed: %d" % _failures)
		quit(1)


func _test_water_position_stacking_decay_and_submersion() -> void:
	var tuning := _make_tuning()
	var state := _empty_state(1000)
	var upper := state.add_plant(&"base_common", Vector2(0.4, 0.2), 1000, tuning)
	var lower := state.add_plant(&"base_common", Vector2(0.4, 0.8), 1000, tuning)

	GardenSimulator.apply_watering(state, tuning)
	_expect(is_equal_approx(state.water_level, tuning.water_level_per_press), "Water presses raise the pooled jar level.")
	_expect(upper.wetness > lower.wetness, "A plant nearer the top receives more direct watering.")
	var first_upper_wetness := upper.wetness
	GardenSimulator.apply_watering(state, tuning)
	_expect(upper.wetness > first_upper_wetness, "Repeated watering stacks plant wetness.")
	for press in 8:
		GardenSimulator.apply_watering(state, tuning)
	_expect(is_equal_approx(state.water_level, 1.0), "Repeated watering reaches the extreme full level.")
	_expect(is_equal_approx(GardenSimulator.get_submersion_fraction(state, upper, tuning), 1.0), "A full jar completely submerges an upper plant.")
	_expect(is_equal_approx(GardenSimulator.get_submersion_fraction(state, lower, tuning), 1.0), "A full jar completely submerges a lower plant.")

	var previous_level := state.water_level
	GardenSimulator.advance_to(state, 1010, tuning)
	_expect(state.water_level < previous_level, "Water evaporates with real elapsed time.")


func _test_reproduction_rules() -> void:
	var tuning := _make_tuning()
	tuning.reproduction_base_success_chance = 1.0
	tuning.same_variant_success_multiplier = 2.0
	tuning.reproduction_attempt_seconds = 5.0
	tuning.spawn_base_success_chance = 0.0
	var jar := _catalog.get_jar(&"default_glass")
	var environment := _catalog.get_environment(&"forest")

	var adult_state := _empty_state(2000)
	var first := adult_state.add_plant(&"base_common", Vector2(0.45, 0.55), 2000, tuning)
	var second := adult_state.add_plant(&"base_common", Vector2(0.50, 0.57), 2000, tuning)
	first.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	second.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	GardenSimulator.advance_to(adult_state, 2005, tuning, _catalog, jar, environment)
	_expect(adult_state.plants.size() == 3, "Two touching adults can create one young plant after elapsed time.")
	_expect(first.reproduction_count == 1 and second.reproduction_count == 1, "A successful birth increments both adult reproduction counts.")
	_expect(adult_state.plants[2].get_lifecycle_stage(tuning) == PlantState.LifecycleStage.YOUNG, "A reproduced plant starts Young.")

	var young_state := _empty_state(3000)
	young_state.add_plant(&"base_common", Vector2(0.45, 0.55), 3000, tuning)
	young_state.add_plant(&"base_common", Vector2(0.50, 0.57), 3000, tuning)
	GardenSimulator.advance_to(young_state, 3005, tuning, _catalog, jar, environment)
	_expect(young_state.plants.size() == 2, "Young plants cannot reproduce.")

	var separated_state := _empty_state(4000)
	var separated_first := separated_state.add_plant(&"base_common", Vector2(0.1, 0.1), 4000, tuning)
	var separated_second := separated_state.add_plant(&"base_common", Vector2(0.9, 0.9), 4000, tuning)
	separated_first.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	separated_second.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	separated_state.reproduction_pair_progress[
		GameState.make_pair_key(separated_first.instance_id, separated_second.instance_id)
	] = 4.0
	GardenSimulator.advance_to(separated_state, 4001, tuning, _catalog, jar, environment)
	_expect(separated_state.reproduction_pair_progress.is_empty(), "Separating adults resets their prototype pair progress.")

	var full_jar := JarDefinition.new()
	full_jar.capacity = 2
	var full_state := _empty_state(5000)
	var full_first := full_state.add_plant(&"base_common", Vector2(0.45, 0.55), 5000, tuning)
	var full_second := full_state.add_plant(&"base_common", Vector2(0.50, 0.57), 5000, tuning)
	full_first.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	full_second.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	GardenSimulator.advance_to(full_state, 5010, tuning, _catalog, full_jar, environment)
	_expect(full_state.plants.size() == 2, "Reproduction cannot exceed jar capacity.")
	_expect(full_state.reproduction_pair_progress.is_empty(), "A full jar does not bank a later reproduction burst.")


func _test_automatic_spawning_capacity_and_mutation() -> void:
	var tuning := _make_tuning()
	tuning.spawn_base_success_chance = 1.0
	tuning.spawn_mutation_chance = 0.0
	tuning.spawn_interval_min_seconds = 100.0
	tuning.spawn_interval_max_seconds = 100.0
	var jar := _catalog.get_jar(&"default_glass")
	var environment := _catalog.get_environment(&"forest")

	var state := _empty_state(6000)
	state.water_level = 1.0
	state.next_spawn_unix_seconds = 6001
	GardenSimulator.advance_to(state, 6002, tuning, _catalog, jar, environment)
	_expect(state.plants.size() == 1, "An elapsed environmental opportunity can spawn a plant.")
	_expect(state.plants[0].variant_id == PlantState.BASE_VARIANT_ID, "A normal environmental spawn creates the common plant.")

	var full_jar := JarDefinition.new()
	full_jar.capacity = 1
	state.next_spawn_unix_seconds = 6003
	GardenSimulator.advance_to(state, 6004, tuning, _catalog, full_jar, environment)
	_expect(state.plants.size() == 1, "Automatic spawning stops at jar capacity.")
	_expect(state.next_spawn_unix_seconds > 6004, "A full jar schedules a future check instead of backlogging spawns.")

	var mutation_state := _empty_state(7000)
	mutation_state.water_level = 1.0
	mutation_state.next_spawn_unix_seconds = 7001
	tuning.spawn_mutation_chance = 1.0
	tuning.day_mutation_multiplier = 2.0
	tuning.night_mutation_multiplier = 2.0
	GardenSimulator.advance_to(mutation_state, 7002, tuning, _catalog, jar, environment)
	_expect(mutation_state.plants.size() == 1, "A forced mutation opportunity still creates one plant.")
	if not mutation_state.plants.is_empty():
		var variant_id := mutation_state.plants[0].variant_id
		_expect(variant_id != PlantState.BASE_VARIANT_ID, "Mutation selection can create a visibly distinct variant.")
		_expect(variant_id in mutation_state.discovered_variant_ids, "A first mutation is registered in the collection atomically.")


func _test_online_and_offline_equivalence() -> void:
	var tuning := _make_tuning()
	tuning.reproduction_base_success_chance = 1.0
	tuning.same_variant_success_multiplier = 2.0
	tuning.reproduction_attempt_seconds = 5.0
	tuning.spawn_base_success_chance = 0.0
	var original := _empty_state(8000)
	var first := original.add_plant(&"base_common", Vector2(0.45, 0.55), 8000, tuning)
	var second := original.add_plant(&"base_common", Vector2(0.50, 0.57), 8000, tuning)
	first.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	second.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	var online := GameState.from_dict(original.to_dict(), 8000, tuning)
	var offline := GameState.from_dict(original.to_dict(), 8000, tuning)
	var jar := _catalog.get_jar(&"default_glass")
	var environment := _catalog.get_environment(&"forest")

	for timestamp in range(8001, 8021):
		GardenSimulator.advance_to(online, timestamp, tuning, _catalog, jar, environment)
	GardenSimulator.advance_to(offline, 8020, tuning, _catalog, jar, environment)
	_expect(online.plants.size() == offline.plants.size(), "Foreground ticks and one offline interval produce the same birth count.")
	_expect(online.rng_state == offline.rng_state, "Foreground and offline simulation consume the same persisted RNG sequence.")
	for index in mini(online.plants.size(), offline.plants.size()):
		_expect(
			is_equal_approx(
				online.plants[index].lifecycle_elapsed_seconds,
				offline.plants[index].lifecycle_elapsed_seconds,
			),
			"Foreground and offline lifecycle age remain equivalent.",
		)


func _test_event_cap_catch_up_equivalence() -> void:
	var tuning := _make_tuning()
	tuning.spawn_interval_min_seconds = 1.0
	tuning.spawn_interval_max_seconds = 1.0
	tuning.spawn_base_success_chance = 0.0
	tuning.maximum_events_per_advance = 2
	var original := _empty_state(10000)
	original.next_spawn_unix_seconds = 10001
	var online := GameState.from_dict(original.to_dict(), 10000, tuning)
	var catch_up := GameState.from_dict(original.to_dict(), 10000, tuning)
	var jar := _catalog.get_jar(&"default_glass")
	var environment := _catalog.get_environment(&"forest")

	for timestamp in range(10001, 10021):
		GardenSimulator.advance_to(online, timestamp, tuning, _catalog, jar, environment)

	var batches: int = 0
	while catch_up.last_simulated_unix_seconds < 10020 and batches < 32:
		var previous_checkpoint := catch_up.last_simulated_unix_seconds
		GardenSimulator.advance_to(catch_up, 10020, tuning, _catalog, jar, environment)
		_expect(
			catch_up.last_simulated_unix_seconds > previous_checkpoint,
			"A capped catch-up batch advances its persisted checkpoint.",
		)
		batches += 1

	_expect(catch_up.last_simulated_unix_seconds == 10020, "Repeated capped batches eventually reach the requested time.")
	_expect(catch_up.rng_state == online.rng_state, "Capped catch-up preserves every RNG-consuming spawn opportunity.")
	_expect(catch_up.next_spawn_unix_seconds == online.next_spawn_unix_seconds, "Capped catch-up preserves the spawn schedule.")
	_expect(catch_up.plants.size() == online.plants.size(), "Capped catch-up matches foreground spawn results.")


func _test_full_jar_does_not_bank_spawn_backlog() -> void:
	var tuning := _make_tuning()
	tuning.spawn_interval_min_seconds = 3.0
	tuning.spawn_interval_max_seconds = 3.0
	tuning.spawn_base_success_chance = 1.0
	tuning.spawn_mutation_chance = 0.0
	tuning.day_spawn_multiplier = 3.0
	tuning.night_spawn_multiplier = 3.0
	tuning.water_evaporation_per_second = 0.0
	tuning.maximum_events_per_advance = 1
	var jar := JarDefinition.new()
	jar.capacity = 1
	var environment := _catalog.get_environment(&"forest")
	var original := _empty_state(11000)
	original.add_plant(&"base_common", Vector2(0.5, 0.6), 11000, tuning)
	original.water_level = 1.0
	original.next_spawn_unix_seconds = 11001
	var online := GameState.from_dict(original.to_dict(), 11000, tuning)
	var offline := GameState.from_dict(original.to_dict(), 11000, tuning)
	var rng_before_full_interval := original.rng_state

	for timestamp in range(11001, 11101):
		GardenSimulator.advance_to(online, timestamp, tuning, _catalog, jar, environment)
	GardenSimulator.advance_to(offline, 11100, tuning, _catalog, jar, environment)
	_expect(offline.last_simulated_unix_seconds == 11100, "A full jar can fast-forward without event-cap backlog.")
	_expect(offline.next_spawn_unix_seconds == online.next_spawn_unix_seconds, "Full-jar retry timing is call-cadence independent.")
	_expect(offline.rng_state == rng_before_full_interval and online.rng_state == rng_before_full_interval, "Suppressed full-jar opportunities do not consume hidden RNG rolls.")

	var next_opportunity := offline.next_spawn_unix_seconds
	online.remove_plant(online.plants[0].instance_id)
	offline.remove_plant(offline.plants[0].instance_id)
	GardenSimulator.advance_to(online, next_opportunity - 1, tuning, _catalog, jar, environment)
	GardenSimulator.advance_to(offline, next_opportunity - 1, tuning, _catalog, jar, environment)
	_expect(online.plants.is_empty() and offline.plants.is_empty(), "Selling from a full jar does not release an overdue spawn burst.")
	GardenSimulator.advance_to(online, next_opportunity, tuning, _catalog, jar, environment)
	GardenSimulator.advance_to(offline, next_opportunity, tuning, _catalog, jar, environment)
	_expect(online.plants.size() == 1 and offline.plants.size() == 1, "Only the next scheduled opportunity can fill space after a sale.")
	_expect(online.rng_state == offline.rng_state, "Full-jar fast-forward and foreground play retain the same future RNG stream.")


func _test_water_offline_equivalence_across_evaporation_boundaries() -> void:
	var tuning := _make_tuning()
	tuning.water_evaporation_per_second = 0.01
	tuning.wetness_decay_per_second = 0.001
	tuning.submerged_wetting_per_second = 0.02
	tuning.plant_water_footprint_height = 0.2
	var original := _empty_state(12000)
	var ordinary := original.add_plant(&"base_common", Vector2(0.5, 0.9), 12000, tuning)
	var saturated := original.add_plant(&"base_common", Vector2(0.6, 0.9), 12000, tuning)
	original.water_level = 0.2
	ordinary.wetness = 0.3
	saturated.wetness = 0.95
	var online := GameState.from_dict(original.to_dict(), 12000, tuning)
	var offline := GameState.from_dict(original.to_dict(), 12000, tuning)

	for timestamp in range(12001, 12101):
		GardenSimulator.advance_to(online, timestamp, tuning)
	GardenSimulator.advance_to(offline, 12100, tuning)

	_expect(is_equal_approx(online.water_level, 0.0) and is_equal_approx(offline.water_level, 0.0), "Water reaches zero consistently across short and long advances.")
	for index in online.plants.size():
		_expect(
			is_equal_approx(online.plants[index].wetness, offline.plants[index].wetness),
			"Wetness integration is foreground/offline equivalent across water crossings and zero.",
		)
	_expect(is_equal_approx(offline.plants[0].wetness, 0.4), "Partial submersion is integrated over the evaporating water surface.")
	_expect(offline.plants[1].wetness > 0.9 and offline.plants[1].wetness < 1.0, "A plant can saturate and then resume drying within one offline interval.")


func _test_full_state_round_trip() -> void:
	var tuning := _make_tuning()
	var state := GameState.create_new(9000, tuning)
	state.water_level = 0.73
	state.coins = 47
	state.discover_variant(&"blush_color")
	state.owned_jar_ids.append(&"moss_glass")
	state.active_jar_id = &"moss_glass"
	state.owned_environment_ids.append(&"indoor_window")
	state.active_environment_id = &"indoor_window"
	state.reproduction_pair_progress["plant_000001|plant_000002"] = 3.25
	state.plants[0].wetness = 0.66
	state.plants[0].reproduction_count = 1
	var restored := GameState.from_dict(state.to_dict(), 9000, tuning)
	_expect(restored != null, "The complete MVP state schema loads after serialization.")
	if restored == null:
		return
	_expect(is_equal_approx(restored.water_level, 0.73), "Pooled water persists.")
	_expect(restored.coins == 47, "Coins persist.")
	_expect(&"blush_color" in restored.discovered_variant_ids, "Discoveries persist.")
	_expect(restored.active_jar_id == &"moss_glass" and restored.owns_jar(&"moss_glass"), "Jar ownership and selection persist.")
	_expect(restored.active_environment_id == &"indoor_window" and restored.owns_environment(&"indoor_window"), "Environment ownership and selection persist.")
	_expect(is_equal_approx(restored.plants[0].wetness, 0.66), "Per-plant wetness persists.")
	_expect(restored.plants[0].reproduction_count == 1, "Per-plant reproduction usage persists.")


func _test_variant_presentation() -> void:
	var packed_scene := load(PLANT_SCENE_PATH) as PackedScene
	var preview := packed_scene.instantiate() as PlantView
	root.add_child(preview)
	var definition := _catalog.get_variant(&"tiny_gardener")
	preview.apply_variant_definition(definition)
	_expect(preview.body.color.is_equal_approx(definition.body_color), "Variant definitions change the visible blob body color.")
	_expect(preview.sun_hat.visible, "A headwear selector produces an obvious visible placeholder.")
	_expect(preview.watering_can.visible, "An equipment selector produces an obvious visible placeholder.")
	preview.free()


func _empty_state(now_unix_seconds: int) -> GameState:
	var state := GameState.new()
	state.last_simulated_unix_seconds = now_unix_seconds
	state.next_spawn_unix_seconds = now_unix_seconds + 100000
	state.rng_state = 123456789
	state.discover_variant(PlantState.BASE_VARIANT_ID)
	return state


func _make_tuning() -> MvpTuning:
	var tuning := MvpTuning.new()
	tuning.young_duration_seconds = 10.0
	tuning.adult_duration_seconds = 100.0
	tuning.reproduction_attempt_seconds = 5.0
	tuning.spawn_interval_min_seconds = 100.0
	tuning.spawn_interval_max_seconds = 100.0
	tuning.maximum_events_per_advance = 128
	return tuning


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
