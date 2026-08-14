extends SceneTree


const CATALOG_PATH: String = "res://resources/prototype_content_catalog.tres"
const PLANT_SCENE_PATH: String = "res://scenes/plant.tscn"
const TUNING_PATH: String = "res://resources/prototype_mvp_tuning.tres"

var _failures: int = 0
var _catalog: ContentCatalog


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_catalog = load(CATALOG_PATH) as ContentCatalog
	_test_water_position_stacking_decay_and_submersion()
	_test_exact_wetness_seconds_clamping()
	_test_birth_context_and_cultivation_segments()
	_test_cultivation_profile_boundaries()
	_test_reproduction_rules()
	_test_visual_hitbox_reproduction_contact()
	_test_automatic_spawning_capacity_and_mutation()
	_test_recipe_filtering_fallback_and_parent_requirements()
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
	var stream_center := state.add_plant(&"base_common", Vector2(0.5, 0.5), 1000, tuning)
	var stream_side := state.add_plant(&"base_common", Vector2(0.0, 0.5), 1000, tuning)

	GardenSimulator.apply_watering(state, tuning)
	_expect(is_equal_approx(state.water_level, tuning.water_level_per_press), "Water presses raise the pooled jar level.")
	_expect(upper.wetness > lower.wetness, "A plant nearer the top receives more direct watering.")
	_expect(stream_center.wetness > stream_side.wetness, "Direct watering falls off horizontally away from the stream.")
	_expect(
		stream_center.lifetime_direct_water_exposure > stream_side.lifetime_direct_water_exposure,
		"Two-dimensional direct-water dose is retained in each plant's cultivation history.",
	)
	_expect(
		state.cultivation_direct_water_exposure > 0.0,
		"The current environment records jar-wide direct watering.",
	)
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


func _test_exact_wetness_seconds_clamping() -> void:
	var drying_tuning := _make_tuning()
	drying_tuning.water_evaporation_per_second = 0.0
	drying_tuning.wetness_decay_per_second = 0.1
	drying_tuning.submerged_wetting_per_second = 0.0
	var drying_state := _empty_state(1500)
	var drying_plant := drying_state.add_plant(
		&"base_common",
		Vector2(0.5, 0.2),
		1500,
		drying_tuning,
	)
	drying_plant.wetness = 1.0
	GardenSimulator.advance_to(drying_state, 1520, drying_tuning)
	_expect(is_equal_approx(drying_plant.wetness, 0.0), "A drying plant clamps at zero mid-interval.")
	_expect(is_equal_approx(drying_plant.lifetime_wetness_seconds, 5.0), "Wetness-seconds integrate the exact triangle before a mid-interval dry clamp.")

	var wetting_tuning := _make_tuning()
	wetting_tuning.water_evaporation_per_second = 0.0
	wetting_tuning.wetness_decay_per_second = 0.0
	wetting_tuning.submerged_wetting_per_second = 0.2
	var wetting_state := _empty_state(1600)
	var wetting_plant := wetting_state.add_plant(
		&"base_common",
		Vector2(0.5, 0.9),
		1600,
		wetting_tuning,
	)
	wetting_state.water_level = 1.0
	GardenSimulator.advance_to(wetting_state, 1610, wetting_tuning)
	_expect(is_equal_approx(wetting_plant.wetness, 1.0), "A submerged plant clamps at full wetness mid-interval.")
	_expect(is_equal_approx(wetting_plant.lifetime_wetness_seconds, 7.5), "Wetness-seconds integrate the exact ramp plus saturated plateau.")
	_expect(is_equal_approx(wetting_plant.lifetime_submerged_fraction_seconds, 10.0), "Full submersion integrates one fractional second per elapsed second.")


func _test_birth_context_and_cultivation_segments() -> void:
	var tuning := _make_tuning()
	tuning.water_evaporation_per_second = 0.0
	var start_time := 5 * 3600 + 30 * 60
	var end_time := 19 * 3600 + 30 * 60
	var state := _empty_state(start_time)
	state.water_level = 0.4
	var plant := state.spawn_plant_with_context(
		&"base_common",
		Vector2(0.5, 0.9),
		start_time,
		tuning,
		PlantState.SOURCE_REPRODUCTION,
		["parent_a", "parent_b"],
		[&"base_common", &"blush_color"],
		&"test_recipe",
	)
	_expect(plant.birth_source == PlantState.SOURCE_REPRODUCTION, "A newborn records its creation source.")
	_expect(plant.birth_environment_id == &"forest", "A newborn records its current environment.")
	_expect(plant.birth_light_state == PlantState.LIGHT_NIGHT, "A newborn records the exact light state at birth.")
	_expect(is_equal_approx(plant.birth_water_level, 0.4), "A newborn records the pooled water level at birth.")
	_expect(plant.parent_instance_ids == ["parent_a", "parent_b"], "A reproduction birth retains stable parent IDs.")
	_expect(plant.parent_variant_ids == [&"base_common", &"blush_color"], "A reproduction birth retains parent variants.")
	_expect(plant.birth_recipe_id == &"test_recipe", "A recipe-shaped birth records the selected recipe.")
	_expect(is_equal_approx(plant.wetness, 1.0), "A newborn placed under the current water surface starts submerged, not dry.")

	GardenSimulator.advance_to(state, end_time, tuning)
	_expect(is_equal_approx(state.cultivation_sunlight_seconds, 12.0 * 3600.0), "Jar sunlight history splits exactly at day boundaries.")
	_expect(is_equal_approx(state.cultivation_moonlight_seconds, 2.0 * 3600.0), "Jar moonlight history covers the remaining elapsed time.")
	_expect(is_equal_approx(plant.lifetime_sunlight_seconds, 12.0 * 3600.0), "A newborn receives sunlight throughout its lifetime interval.")
	_expect(is_equal_approx(plant.cultivation_moonlight_seconds, 2.0 * 3600.0), "A newborn receives current-environment moonlight history.")
	_expect(is_equal_approx(plant.lifetime_submerged_fraction_seconds, float(end_time - start_time)), "A submerged newborn accumulates fractional submersion over elapsed time.")
	_expect(is_equal_approx(plant.lifetime_wetness_seconds, float(end_time - start_time)), "A fully wet newborn accumulates normalized wetness-seconds.")
	_expect(is_equal_approx(state.cultivation_water_level_seconds, 0.4 * float(end_time - start_time)), "Jar water history integrates pooled level over time.")

	var lifetime_sunlight_before_switch := plant.lifetime_sunlight_seconds
	GardenSimulator.settle_environment_change(state, &"indoor_window", end_time)
	_expect(state.active_environment_id == &"indoor_window", "Environment settlement changes the active environment atomically.")
	_expect(state.cultivation_environment_id == &"indoor_window", "The new jar cultivation segment uses the selected environment.")
	_expect(is_equal_approx(state.cultivation_sunlight_seconds, 0.0), "Environment settlement resets jar segment history.")
	_expect(plant.cultivation_environment_id == &"indoor_window", "Every existing plant starts a segment in the new environment.")
	_expect(is_equal_approx(plant.cultivation_sunlight_seconds, 0.0), "Plant current-segment history resets on an environment change.")
	_expect(is_equal_approx(plant.cultivation_wetness_seconds, 0.0), "Environment changes reset current wetness-seconds.")
	_expect(is_equal_approx(plant.cultivation_submerged_fraction_seconds, 0.0), "Environment changes reset current fractional submersion.")
	_expect(is_equal_approx(plant.lifetime_sunlight_seconds, lifetime_sunlight_before_switch), "Environment changes preserve lifetime cultivation history.")
	GardenSimulator.advance_to(state, end_time + 3600, tuning)
	_expect(is_equal_approx(plant.cultivation_moonlight_seconds, 3600.0), "Only post-switch exposure enters the new environment segment.")


func _test_cultivation_profile_boundaries() -> void:
	var tuning := _make_tuning()
	var state := _empty_state(100)
	_set_jar_profile(state, 59.0, 0.0, 0.3)
	var profile := GardenSimulator.get_jar_cultivation_profile(state, tuning)
	_expect(not bool(profile.ready), "A 59-second jar segment cannot unlock a mutation recipe.")

	_set_jar_profile(state, 39.0, 21.0, 0.199)
	profile = GardenSimulator.get_jar_cultivation_profile(state, tuning)
	_expect(bool(profile.ready), "A cultivation segment is eligible at exactly 60 settled seconds.")
	_expect(profile.light_state == EnvironmentProvider.DAY, "Exactly 65 percent daylight classifies as Day.")
	_expect(profile.moisture_state == PlantMutationRecipe.WATER_DRY, "Average wetness below 0.20 classifies as Dry.")

	_set_jar_profile(state, 21.0, 39.0, 0.2)
	profile = GardenSimulator.get_jar_cultivation_profile(state, tuning)
	_expect(profile.light_state == EnvironmentProvider.NIGHT, "Exactly 65 percent moonlight classifies as Night.")
	_expect(profile.moisture_state == PlantMutationRecipe.WATER_MOIST, "Average wetness at 0.20 classifies as Moist.")

	_set_jar_profile(state, 38.0, 22.0, 0.499)
	profile = GardenSimulator.get_jar_cultivation_profile(state, tuning)
	_expect(profile.light_state == PlantMutationRecipe.LIGHT_BALANCED, "Neither light share reaching 65 percent classifies as Balanced.")
	_expect(profile.moisture_state == PlantMutationRecipe.WATER_MOIST, "Average wetness below 0.50 remains Moist.")
	_expect(not bool(profile.is_submerged), "Average submersion below 0.50 is not Submerged.")

	_set_jar_profile(state, 30.0, 30.0, 0.5)
	profile = GardenSimulator.get_jar_cultivation_profile(state, tuning)
	_expect(profile.moisture_state == PlantMutationRecipe.WATER_WET, "Average wetness at 0.50 classifies as Wet.")
	_expect(bool(profile.is_submerged), "Average fractional submersion at 0.50 also satisfies Submerged.")

	var first_parent := PlantState.new()
	first_parent.cultivation_environment_id = &"forest"
	first_parent.cultivation_sunlight_seconds = 60.0
	first_parent.cultivation_wetness_seconds = 6.0
	first_parent.cultivation_submerged_fraction_seconds = 12.0
	var second_parent := PlantState.new()
	second_parent.cultivation_environment_id = &"forest"
	second_parent.cultivation_moonlight_seconds = 120.0
	second_parent.cultivation_wetness_seconds = 84.0
	second_parent.cultivation_submerged_fraction_seconds = 72.0
	var parents: Array[PlantState] = [first_parent, second_parent]
	var parent_profile := GardenSimulator.get_parent_cultivation_profile(parents, tuning)
	_expect(bool(parent_profile.ready), "Each parent independently satisfies the 60-second minimum.")
	_expect(is_equal_approx(float(parent_profile.average_wetness), 0.4), "Reproduction averages each parent's normalized wetness profile arithmetically.")
	_expect(is_equal_approx(float(parent_profile.average_submerged_fraction), 0.4), "Reproduction averages each parent's normalized submerged fraction arithmetically.")
	_expect(parent_profile.light_state == PlantMutationRecipe.LIGHT_BALANCED, "Opposite parent light profiles average to Balanced.")
	first_parent.cultivation_sunlight_seconds = 59.0
	parent_profile = GardenSimulator.get_parent_cultivation_profile(parents, tuning)
	_expect(not bool(parent_profile.ready), "One under-aged parent keeps the reproduction recipe profile unready.")


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
	_expect(adult_state.plants[2].birth_source == PlantState.SOURCE_REPRODUCTION, "Reproduced plants use the unified reproduction birth context.")
	_expect(adult_state.plants[2].parent_instance_ids == [first.instance_id, second.instance_id], "A reproduced plant records both stable parent IDs.")

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


func _test_visual_hitbox_reproduction_contact() -> void:
	var tuning := _make_tuning()
	tuning.reproduction_attempt_seconds = 5.0
	tuning.reproduction_base_success_chance = 1.0
	tuning.same_variant_success_multiplier = 2.0
	tuning.reproduction_mutation_chance = 0.0
	tuning.spawn_base_success_chance = 0.0
	tuning.water_evaporation_per_second = 0.0

	var ellipse_catalog := _make_hitbox_catalog(Vector2(120.0, 80.0))
	var original := _empty_state(5500)
	var first := original.add_plant(&"base_common", Vector2(0.40, 0.55), 5500, tuning)
	var second := original.add_plant(&"base_common", Vector2(0.58, 0.55), 5500, tuning)
	_expect(
		_visible_hitboxes_overlap(
			ellipse_catalog.get_variant(&"base_common"),
			first.position_normalized,
			second.position_normalized,
			tuning.reproduction_canonical_plant_bounds_size,
		),
		"The rendered PlantView ellipse hitboxes overlap in canonical PlantBounds.",
	)
	first.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	second.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	var online := GameState.from_dict(original.to_dict(), 5500, tuning)
	var offline := GameState.from_dict(original.to_dict(), 5500, tuning)
	for timestamp in range(5501, 5506):
		GardenSimulator.advance_to(online, timestamp, tuning, ellipse_catalog)
	GardenSimulator.advance_to(offline, 5505, tuning, ellipse_catalog)
	_expect(online.plants.size() == 3 and offline.plants.size() == 3, "Visible ellipse hitboxes can reproduce even when legacy center distance is too large.")
	_expect(online.rng_state == offline.rng_state, "Visible hitbox contact produces the same deterministic result online and offline.")

	var polygon_catalog := _make_hitbox_catalog(
		Vector2(20.0, 20.0),
		PackedVector2Array([
			Vector2(-10.0, -10.0),
			Vector2(10.0, -10.0),
			Vector2(10.0, 10.0),
			Vector2(-10.0, 10.0),
		]),
	)
	var separated := _empty_state(5600)
	var separated_first := separated.add_plant(&"base_common", Vector2(0.45, 0.55), 5600, tuning)
	var separated_second := separated.add_plant(&"base_common", Vector2(0.55, 0.55), 5600, tuning)
	_expect(
		not _visible_hitboxes_overlap(
			polygon_catalog.get_variant(&"base_common"),
			separated_first.position_normalized,
			separated_second.position_normalized,
			tuning.reproduction_canonical_plant_bounds_size,
		),
		"The rendered authored PlantView polygons are separated in canonical PlantBounds.",
	)
	separated_first.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	separated_second.lifecycle_elapsed_seconds = tuning.young_duration_seconds
	GardenSimulator.advance_to(separated, 5610, tuning, polygon_catalog)
	_expect(separated.plants.size() == 2, "Separated authored polygons do not reproduce even when legacy center distance would qualify.")
	_expect(separated.reproduction_pair_progress.is_empty(), "Non-contacting visible hitboxes do not bank pair progress offline.")


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
	_expect(state.plants[0].birth_source == PlantState.SOURCE_ENVIRONMENTAL, "Automatic spawns use the unified environmental birth context.")
	_expect(state.plants[0].birth_water_level >= state.water_level, "Automatic spawns inherit the pooled water level at their birth instant before later evaporation.")
	_expect(state.plants[0].wetness > 0.0, "An automatic newborn immediately receives the water already covering its spawn position.")

	var full_jar := JarDefinition.new()
	full_jar.capacity = 1
	state.next_spawn_unix_seconds = 6003
	GardenSimulator.advance_to(state, 6004, tuning, _catalog, full_jar, environment)
	_expect(state.plants.size() == 1, "Automatic spawning stops at jar capacity.")
	_expect(state.next_spawn_unix_seconds > 6004, "A full jar schedules a future check instead of backlogging spawns.")

	var mutation_state := _empty_state(7000)
	mutation_state.water_level = 0.3
	mutation_state.cultivation_segment_started_at_unix_seconds = 6940
	_set_jar_profile(mutation_state, 60.0, 0.0, 0.3)
	mutation_state.next_spawn_unix_seconds = 7001
	tuning.spawn_mutation_chance = 1.0
	tuning.day_mutation_multiplier = 2.0
	tuning.night_mutation_multiplier = 2.0
	tuning.water_evaporation_per_second = 0.0
	GardenSimulator.advance_to(mutation_state, 7002, tuning, _catalog, jar, environment)
	_expect(mutation_state.plants.size() == 1, "A forced mutation opportunity still creates one plant.")
	if not mutation_state.plants.is_empty():
		var variant_id := mutation_state.plants[0].variant_id
		_expect(variant_id != PlantState.BASE_VARIANT_ID, "Mutation selection can create a visibly distinct variant.")
		_expect(variant_id in mutation_state.discovered_variant_ids, "A first mutation is registered in the collection atomically.")
		_expect(not String(mutation_state.plants[0].birth_recipe_id).is_empty(), "A visible mutation records its matched environment recipe.")


func _test_recipe_filtering_fallback_and_parent_requirements() -> void:
	var configured_tuning := load(TUNING_PATH) as MvpTuning
	_expect(configured_tuning != null, "The prototype mutation recipe resource loads.")
	if configured_tuning != null:
		_expect(configured_tuning.mutation_recipes.size() == 9, "Nine non-base mutation recipes are data-driven in tuning.")
		var expected := {
			&"leaf_cap": [true, true, &"forest", &"day", &"moist", []],
			&"moss_cushion": [true, false, &"forest", &"balanced", &"wet", []],
			&"moonbell": [false, true, &"forest", &"night", &"moist", []],
			&"blush_color": [true, true, &"indoor_window", &"day", &"moist", []],
			&"tiny_gardener": [false, true, &"indoor_window", &"balanced", &"moist", [&"base_common", &"blush_color"]],
			&"sunpatch": [true, false, &"indoor_window", &"day", &"dry", []],
			&"rainbell": [true, true, &"rainforest", &"", &"submerged", []],
			&"fern_curl": [false, true, &"rainforest", &"day", &"wet", []],
			&"glow_pod": [true, false, &"rainforest", &"night", &"wet", []],
		}
		var configured_targets: Array[StringName] = []
		for recipe in configured_tuning.mutation_recipes:
			configured_targets.append(recipe.target_variant_id)
			var spec: Array = expected.get(recipe.target_variant_id, [])
			_expect(spec.size() == 6, "Every configured target belongs to the locked nine-recipe table.")
			if spec.size() != 6:
				continue
			_expect(recipe.allows_environmental == bool(spec[0]), "%s has the locked environmental source rule." % recipe.target_variant_id)
			_expect(recipe.allows_reproduction == bool(spec[1]), "%s has the locked reproduction source rule." % recipe.target_variant_id)
			_expect(recipe.required_environment_id == StringName(spec[2]), "%s has the locked environment rule." % recipe.target_variant_id)
			_expect(recipe.required_light_state == StringName(spec[3]), "%s has the locked light-profile rule." % recipe.target_variant_id)
			_expect(recipe.required_water_state == StringName(spec[4]), "%s has the locked water-profile rule." % recipe.target_variant_id)
			_expect(recipe.required_parent_variant_ids == spec[5], "%s has the locked unordered parent rule." % recipe.target_variant_id)
		_expect(configured_targets.size() == expected.size(), "The locked recipe table has no duplicate or missing targets.")
		for target in expected:
			_expect(target in configured_targets, "The locked recipe table includes %s." % target)

	var missing_recipe := PlantMutationRecipe.new()
	missing_recipe.id = &"missing_target"
	missing_recipe.target_variant_id = &"not_in_catalog"
	var fallback_tuning := _make_tuning()
	fallback_tuning.mutation_recipes = [missing_recipe]
	fallback_tuning.spawn_base_success_chance = 1.0
	fallback_tuning.spawn_mutation_chance = 1.0
	fallback_tuning.day_mutation_multiplier = 2.0
	fallback_tuning.night_mutation_multiplier = 2.0
	fallback_tuning.water_evaporation_per_second = 0.0
	var fallback_state := _empty_state(7200)
	fallback_state.water_level = 0.3
	_set_jar_profile(fallback_state, 60.0, 0.0, 0.3)
	fallback_state.next_spawn_unix_seconds = 7201
	GardenSimulator.advance_to(
		fallback_state,
		7202,
		fallback_tuning,
		_catalog,
		_catalog.get_jar(&"default_glass"),
		_catalog.get_environment(&"forest"),
	)
	_expect(fallback_state.plants.size() == 1, "An unavailable recipe target does not block the birth.")
	if not fallback_state.plants.is_empty():
		_expect(fallback_state.plants[0].variant_id == PlantState.BASE_VARIANT_ID, "Unavailable recipe targets deterministically use the configured base fallback.")
		_expect(String(fallback_state.plants[0].birth_recipe_id).is_empty(), "Fallback births do not claim an unavailable recipe.")

	var tiny_recipe := PlantMutationRecipe.new()
	tiny_recipe.id = &"tiny_pair_test"
	tiny_recipe.target_variant_id = &"tiny_gardener"
	tiny_recipe.allows_environmental = false
	tiny_recipe.allows_reproduction = true
	tiny_recipe.required_environment_id = &"indoor_window"
	tiny_recipe.required_light_state = PlantMutationRecipe.LIGHT_BALANCED
	tiny_recipe.required_water_state = PlantMutationRecipe.WATER_MOIST
	tiny_recipe.required_parent_variant_ids = [&"base_common", &"blush_color"]
	var pair_tuning := _make_tuning()
	pair_tuning.mutation_recipes = [tiny_recipe]
	pair_tuning.reproduction_attempt_seconds = 1.0
	pair_tuning.reproduction_base_success_chance = 1.0
	pair_tuning.same_variant_success_multiplier = 2.0
	pair_tuning.reproduction_mutation_chance = 1.0
	pair_tuning.day_reproduction_multiplier = 2.0
	pair_tuning.night_reproduction_multiplier = 2.0
	pair_tuning.day_mutation_multiplier = 2.0
	pair_tuning.night_mutation_multiplier = 2.0
	pair_tuning.spawn_base_success_chance = 0.0
	pair_tuning.water_evaporation_per_second = 0.0
	var pair_state := _empty_state(12 * 3600)
	pair_state.active_environment_id = &"indoor_window"
	pair_state.reset_cultivation_segment(&"indoor_window", 12 * 3600 - 60)
	pair_state.water_level = 0.0
	var blush_parent := pair_state.add_plant(&"blush_color", Vector2(0.48, 0.7), 12 * 3600, pair_tuning)
	var base_parent := pair_state.add_plant(&"base_common", Vector2(0.52, 0.7), 12 * 3600, pair_tuning)
	blush_parent.lifecycle_elapsed_seconds = pair_tuning.young_duration_seconds
	base_parent.lifecycle_elapsed_seconds = pair_tuning.young_duration_seconds
	_set_plant_profile(blush_parent, 30.0, 30.0, 0.3, 0.0)
	_set_plant_profile(base_parent, 30.0, 30.0, 0.3, 0.0)
	blush_parent.reproduction_limit = 1
	base_parent.reproduction_limit = 1
	pair_state.reproduction_pair_progress[
		GameState.make_pair_key(blush_parent.instance_id, base_parent.instance_id)
	] = pair_tuning.reproduction_attempt_seconds
	GardenSimulator.advance_to(
		pair_state,
		12 * 3600 + 1,
		pair_tuning,
		_catalog,
		_catalog.get_jar(&"default_glass"),
		_catalog.get_environment(&"indoor_window"),
	)
	_expect(pair_state.plants.size() == 3, "The reversed blush/common parent order can reproduce.")
	if pair_state.plants.size() == 3:
		var child := pair_state.plants[2]
		_expect(child.variant_id == &"tiny_gardener", "The unordered base-common plus blush-color requirement selects Tiny Gardener.")
		_expect(child.birth_recipe_id == &"tiny_pair_test", "The Tiny Gardener child records the matching parent recipe.")
		_expect(child.parent_variant_ids == [&"blush_color", &"base_common"], "Parent context preserves actual order while recipe matching remains unordered.")

	var wrong_pair_state := _empty_state(13 * 3600)
	wrong_pair_state.active_environment_id = &"indoor_window"
	wrong_pair_state.reset_cultivation_segment(&"indoor_window", 13 * 3600 - 60)
	wrong_pair_state.water_level = 0.0
	var wrong_first := wrong_pair_state.add_plant(&"blush_color", Vector2(0.48, 0.7), 13 * 3600, pair_tuning)
	var wrong_second := wrong_pair_state.add_plant(&"blush_color", Vector2(0.52, 0.7), 13 * 3600, pair_tuning)
	wrong_first.lifecycle_elapsed_seconds = pair_tuning.young_duration_seconds
	wrong_second.lifecycle_elapsed_seconds = pair_tuning.young_duration_seconds
	_set_plant_profile(wrong_first, 30.0, 30.0, 0.3, 0.0)
	_set_plant_profile(wrong_second, 30.0, 30.0, 0.3, 0.0)
	wrong_first.reproduction_limit = 1
	wrong_second.reproduction_limit = 1
	wrong_pair_state.reproduction_pair_progress[
		GameState.make_pair_key(wrong_first.instance_id, wrong_second.instance_id)
	] = pair_tuning.reproduction_attempt_seconds
	GardenSimulator.advance_to(
		wrong_pair_state,
		13 * 3600 + 1,
		pair_tuning,
		_catalog,
		_catalog.get_jar(&"default_glass"),
		_catalog.get_environment(&"indoor_window"),
	)
	_expect(wrong_pair_state.plants.size() == 3, "A non-matching parent pair can still reproduce normally.")
	if wrong_pair_state.plants.size() == 3:
		_expect(wrong_pair_state.plants[2].variant_id == PlantState.BASE_VARIANT_ID, "A forced mutation with the wrong parents uses the configured base fallback.")
		_expect(String(wrong_pair_state.plants[2].birth_recipe_id).is_empty(), "A parent-requirement fallback does not claim the Tiny Gardener recipe.")


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
	jar.capacity = 3
	var environment := _catalog.get_environment(&"forest")
	var original := _empty_state(11000)
	original.add_plant(&"base_common", Vector2(0.3, 0.6), 11000, tuning)
	original.add_plant(&"base_common", Vector2(0.5, 0.6), 11000, tuning)
	original.add_plant(&"base_common", Vector2(0.7, 0.6), 11000, tuning)
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
	_expect(online.plants.size() == 2 and offline.plants.size() == 2, "Selling from a full jar does not release an overdue spawn burst.")
	GardenSimulator.advance_to(online, next_opportunity, tuning, _catalog, jar, environment)
	GardenSimulator.advance_to(offline, next_opportunity, tuning, _catalog, jar, environment)
	_expect(online.plants.size() == 3 and offline.plants.size() == 3, "Only the next scheduled opportunity can fill space after a sale.")
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
		_expect(
			is_equal_approx(
				online.plants[index].lifetime_wetness_seconds,
				offline.plants[index].lifetime_wetness_seconds,
			),
			"Normalized wetness-seconds are foreground/offline equivalent.",
		)
		_expect(
			is_equal_approx(
				online.plants[index].lifetime_submerged_fraction_seconds,
				offline.plants[index].lifetime_submerged_fraction_seconds,
			),
			"Fractional submersion-seconds are foreground/offline equivalent.",
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
	GardenSimulator.settle_environment_change(state, &"indoor_window", 9000)
	state.reproduction_pair_progress["plant_000001|plant_000002"] = 3.25
	state.plants[0].wetness = 0.66
	state.plants[0].reproduction_count = 1
	state.cultivation_sunlight_seconds = 91.0
	state.cultivation_direct_water_exposure = 1.25
	state.plants[0].lifetime_moonlight_seconds = 42.0
	state.plants[0].lifetime_wetness_seconds = 17.25
	state.plants[0].cultivation_wetness_seconds = 8.25
	state.plants[0].cultivation_submerged_fraction_seconds = 7.5
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
	_expect(is_equal_approx(restored.cultivation_sunlight_seconds, 91.0), "Jar cultivation history persists.")
	_expect(is_equal_approx(restored.cultivation_direct_water_exposure, 1.25), "Jar direct-water history persists.")
	_expect(is_equal_approx(restored.plants[0].lifetime_moonlight_seconds, 42.0), "Plant lifetime light history persists.")
	_expect(is_equal_approx(restored.plants[0].lifetime_wetness_seconds, 17.25), "Plant lifetime wetness-seconds persist.")
	_expect(is_equal_approx(restored.plants[0].cultivation_wetness_seconds, 8.25), "Plant current wetness-seconds persist.")
	_expect(is_equal_approx(restored.plants[0].cultivation_submerged_fraction_seconds, 7.5), "Plant current fractional submersion persists.")

	var interim_v4 := state.to_dict()
	var interim_plant: Dictionary = interim_v4["plants"][0]
	interim_plant["lifetime_submerged_seconds"] = interim_plant["lifetime_submerged_fraction_seconds"]
	interim_plant["cultivation_submerged_seconds"] = interim_plant["cultivation_submerged_fraction_seconds"]
	interim_plant.erase("lifetime_submerged_fraction_seconds")
	interim_plant.erase("cultivation_submerged_fraction_seconds")
	var restored_interim := GameState.from_dict(interim_v4, 9000, tuning)
	_expect(
		restored_interim != null
		and is_equal_approx(
			restored_interim.plants[0].cultivation_submerged_fraction_seconds,
			7.5,
		),
		"Schema v4 accepts the current intermediate submerged-seconds key names.",
	)


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


func _set_jar_profile(
	state: GameState,
	sunlight_seconds: float,
	moonlight_seconds: float,
	average_water_level: float,
) -> void:
	var segment_seconds := sunlight_seconds + moonlight_seconds
	state.cultivation_sunlight_seconds = sunlight_seconds
	state.cultivation_moonlight_seconds = moonlight_seconds
	state.cultivation_water_level_seconds = average_water_level * segment_seconds
	state.water_level = average_water_level


func _set_plant_profile(
	plant: PlantState,
	sunlight_seconds: float,
	moonlight_seconds: float,
	average_wetness: float,
	average_submerged_fraction: float,
) -> void:
	var segment_seconds := sunlight_seconds + moonlight_seconds
	plant.cultivation_sunlight_seconds = sunlight_seconds
	plant.cultivation_moonlight_seconds = moonlight_seconds
	plant.cultivation_wetness_seconds = average_wetness * segment_seconds
	plant.cultivation_submerged_fraction_seconds = (
		average_submerged_fraction * segment_seconds
	)
	plant.wetness = average_wetness


func _make_hitbox_catalog(
	hitbox_size: Vector2,
	hitbox_polygon: PackedVector2Array = PackedVector2Array(),
) -> ContentCatalog:
	var visual := PlantVisualDefinition.new()
	visual.hitbox_size = hitbox_size
	visual.hitbox_polygon = hitbox_polygon
	visual.adult_scale = 1.0
	var definition := PlantVariantDefinition.new()
	definition.id = PlantState.BASE_VARIANT_ID
	definition.visual = visual
	definition.reproduction_difficulty = 1.0
	var catalog := ContentCatalog.new()
	catalog.plant_variants = [definition]
	return catalog


func _visible_hitboxes_overlap(
	definition: PlantVariantDefinition,
	first_position: Vector2,
	second_position: Vector2,
	bounds_size: Vector2,
) -> bool:
	var bounds := Control.new()
	bounds.size = bounds_size
	root.add_child(bounds)
	var packed_scene := load(PLANT_SCENE_PATH) as PackedScene
	var first_view := packed_scene.instantiate() as PlantView
	var second_view := packed_scene.instantiate() as PlantView
	bounds.add_child(first_view)
	bounds.add_child(second_view)
	first_view.apply_variant_definition(definition)
	second_view.apply_variant_definition(definition)
	first_view.set_normalized_center(first_position)
	second_view.set_normalized_center(second_position)
	var overlaps := first_view.hitbox_overlaps(second_view)
	bounds.free()
	return overlaps


func _empty_state(now_unix_seconds: int) -> GameState:
	var state := GameState.new()
	state.last_simulated_unix_seconds = now_unix_seconds
	state.simulation_timezone_bias_minutes = 0
	state.next_spawn_unix_seconds = now_unix_seconds + 100000
	state.rng_state = 123456789
	state.cultivation_environment_id = state.active_environment_id
	state.cultivation_segment_started_at_unix_seconds = now_unix_seconds
	state.discover_variant(PlantState.BASE_VARIANT_ID)
	return state


func _make_tuning() -> MvpTuning:
	var prototype := load(TUNING_PATH) as MvpTuning
	var tuning := prototype.duplicate(true) as MvpTuning
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
