class_name GardenSimulator
extends RefCounted


const EVENT_EPSILON: float = 0.001
const INTEGRATION_EPSILON: float = 0.000000001


static func advance_to(
	state: GameState,
	now_unix_seconds: int,
	tuning: MvpTuning,
	catalog: ContentCatalog = null,
	jar_definition: JarDefinition = null,
	environment_definition: EnvironmentDefinition = null,
) -> float:
	if state.last_simulated_unix_seconds <= 0:
		state.last_simulated_unix_seconds = now_unix_seconds
		return 0.0
	if now_unix_seconds <= state.last_simulated_unix_seconds:
		return 0.0

	var start_time := float(state.last_simulated_unix_seconds)
	var end_time := float(now_unix_seconds)
	var elapsed_seconds := end_time - start_time
	if catalog == null:
		_advance_continuous(
			state,
			elapsed_seconds,
			tuning,
			jar_definition,
			environment_definition,
		)
		state.last_simulated_unix_seconds = now_unix_seconds
		return elapsed_seconds

	var capacity := jar_definition.capacity if jar_definition != null else 12
	if state.next_spawn_unix_seconds <= 0:
		state.schedule_next_spawn(int(start_time), tuning)

	var current_time := start_time
	var processed_events: int = 0
	var batch_checkpoint_time: float = INF
	while current_time < end_time - EVENT_EPSILON:
		if state.plants.size() >= capacity:
			_cleanup_ineligible_pair_progress(state, [])
			_advance_continuous(
				state,
				end_time - current_time,
				tuning,
				jar_definition,
				environment_definition,
			)
			_skip_spawn_backlog_while_full(state, now_unix_seconds, tuning)
			current_time = end_time
			break

		if (
			processed_events >= maxi(tuning.maximum_events_per_advance, 1)
			and batch_checkpoint_time == INF
		):
			# GameState stores an integer checkpoint. Finish only the current
			# integer-second slice; the next advance resumes from that exact,
			# persisted boundary. Choosing the next boundary also guarantees that
			# a batch which handled an event at its start still makes time progress.
			batch_checkpoint_time = minf(
				end_time,
				float(floori(current_time) + 1),
			)

		var eligible_pairs := _get_eligible_pairs(state, tuning, capacity)
		_cleanup_ineligible_pair_progress(state, eligible_pairs)
		var next_event_time := minf(end_time, batch_checkpoint_time)

		if state.next_spawn_unix_seconds <= now_unix_seconds:
			next_event_time = minf(
				next_event_time,
				maxf(float(state.next_spawn_unix_seconds), current_time),
			)

		var lifecycle_delay := _get_next_lifecycle_boundary_delay(state, tuning)
		if lifecycle_delay < INF:
			next_event_time = minf(next_event_time, current_time + lifecycle_delay)

		for pair in eligible_pairs:
			var progress := float(state.reproduction_pair_progress.get(pair.key, 0.0))
			var attempt_delay := maxf(tuning.reproduction_attempt_seconds - progress, 0.0)
			next_event_time = minf(next_event_time, current_time + attempt_delay)

		var step_seconds := maxf(next_event_time - current_time, 0.0)
		if step_seconds > EVENT_EPSILON:
			_advance_continuous(
				state,
				step_seconds,
				tuning,
				jar_definition,
				environment_definition,
			)
			for pair in eligible_pairs:
				state.reproduction_pair_progress[pair.key] = float(
					state.reproduction_pair_progress.get(pair.key, 0.0)
				) + step_seconds
			current_time = next_event_time

		if current_time >= batch_checkpoint_time - EVENT_EPSILON:
			# Events exactly at this checkpoint remain due and are processed on the
			# next batch. Continuous state and pair progress are already current.
			break

		var handled_event: bool = false
		if state.next_spawn_unix_seconds <= int(floor(current_time + EVENT_EPSILON)):
			_attempt_environmental_spawn(
				state,
				int(round(current_time)),
				tuning,
				catalog,
				jar_definition,
				environment_definition,
				capacity,
			)
			state.schedule_next_spawn(int(round(current_time)), tuning)
			handled_event = true

		for pair in eligible_pairs:
			var progress := float(state.reproduction_pair_progress.get(pair.key, 0.0))
			if progress + EVENT_EPSILON < tuning.reproduction_attempt_seconds:
				continue
			state.reproduction_pair_progress[pair.key] = maxf(
				progress - tuning.reproduction_attempt_seconds,
				0.0,
			)
			_attempt_reproduction(
				state,
				pair.first,
				pair.second,
				int(round(current_time)),
				tuning,
				catalog,
				jar_definition,
				environment_definition,
				capacity,
			)
			handled_event = true

		if handled_event:
			processed_events += 1
		elif step_seconds <= EVENT_EPSILON:
			# A lifecycle boundary can be exactly at the current instant. Nudge the
			# pure state clock so the next iteration observes the new stage.
			var nudge := minf(EVENT_EPSILON, end_time - current_time)
			_advance_continuous(
				state,
				nudge,
				tuning,
				jar_definition,
				environment_definition,
			)
			current_time += nudge

	if current_time >= end_time - EVENT_EPSILON:
		state.last_simulated_unix_seconds = now_unix_seconds
	else:
		state.last_simulated_unix_seconds = int(round(current_time))
	return float(state.last_simulated_unix_seconds) - start_time


static func _skip_spawn_backlog_while_full(
	state: GameState,
	through_unix_seconds: int,
	tuning: MvpTuning,
) -> void:
	if state.next_spawn_unix_seconds > through_unix_seconds:
		return
	# A full jar cannot accept an environmental spawn. Move its opportunity
	# clock to the first future deterministic retry without consuming chance or
	# RNG rolls. Anchoring retries to the existing timestamp makes foreground
	# and offline catch-up equivalent and prevents a burst after a later sale.
	var retry_seconds := maxi(
		roundi(maxf(tuning.spawn_interval_min_seconds, tuning.spawn_interval_max_seconds)),
		1,
	)
	var overdue_seconds := through_unix_seconds - state.next_spawn_unix_seconds
	var skipped_retries := floori(float(overdue_seconds) / float(retry_seconds)) + 1
	state.next_spawn_unix_seconds += skipped_retries * retry_seconds


static func apply_watering(state: GameState, tuning: MvpTuning) -> void:
	state.water_level = clampf(
		state.water_level + tuning.water_level_per_press,
		0.0,
		1.0,
	)
	for plant in state.plants:
		var topness := 1.0 - clampf(plant.position_normalized.y, 0.0, 1.0)
		var position_multiplier := lerpf(
			tuning.bottom_watering_multiplier,
			1.0,
			topness,
		)
		plant.wetness = clampf(
			plant.wetness + tuning.top_wetness_per_press * position_multiplier,
			0.0,
			1.0,
		)


static func get_submersion_fraction(
	state: GameState,
	plant: PlantState,
	tuning: MvpTuning,
) -> float:
	return _get_submersion_for_level(
		state.water_level,
		plant.position_normalized.y,
		tuning.plant_water_footprint_height,
	)


static func get_water_state_label(state: GameState, tuning: MvpTuning) -> String:
	if state.water_level >= 0.98:
		return "Submerged"
	var highest_wetness: float = 0.0
	for plant in state.plants:
		highest_wetness = maxf(highest_wetness, plant.wetness)
	if highest_wetness >= tuning.extreme_wetness_threshold:
		return "Very wet"
	if state.water_level > 0.05 or highest_wetness > 0.15:
		return "Moist"
	return "Dry"


static func _advance_continuous(
	state: GameState,
	elapsed_seconds: float,
	tuning: MvpTuning,
	jar_definition: JarDefinition,
	environment_definition: EnvironmentDefinition,
) -> void:
	if elapsed_seconds <= 0.0:
		return
	var evaporation_modifier := 1.0
	if jar_definition != null:
		evaporation_modifier *= jar_definition.evaporation_modifier
	if environment_definition != null:
		evaporation_modifier *= environment_definition.evaporation_modifier
	evaporation_modifier = maxf(evaporation_modifier, 0.0)
	var starting_water_level := clampf(state.water_level, 0.0, 1.0)
	var water_loss_per_second := (
		maxf(tuning.water_evaporation_per_second, 0.0) * evaporation_modifier
	)
	state.water_level = maxf(
		starting_water_level - water_loss_per_second * elapsed_seconds,
		0.0,
	)

	for plant in state.plants:
		plant.lifecycle_elapsed_seconds += elapsed_seconds
		_advance_plant_wetness(
			plant,
			starting_water_level,
			water_loss_per_second,
			elapsed_seconds,
			maxf(tuning.wetness_decay_per_second, 0.0) * evaporation_modifier,
			maxf(tuning.submerged_wetting_per_second, 0.0),
			tuning.plant_water_footprint_height,
		)


static func _advance_plant_wetness(
	plant: PlantState,
	starting_water_level: float,
	water_loss_per_second: float,
	elapsed_seconds: float,
	wetness_decay_per_second: float,
	submerged_wetting_per_second: float,
	plant_footprint_height: float,
) -> void:
	var footprint_height := maxf(plant_footprint_height, 0.001)
	var plant_bottom := plant.position_normalized.y + footprint_height * 0.5
	var partial_submersion_start_level := 1.0 - plant_bottom
	var full_submersion_start_level := partial_submersion_start_level + footprint_height
	var boundaries: Array[float] = [0.0, elapsed_seconds]

	if water_loss_per_second > 0.0:
		_append_water_crossing_time(
			boundaries,
			starting_water_level,
			water_loss_per_second,
			full_submersion_start_level,
			elapsed_seconds,
		)
		_append_water_crossing_time(
			boundaries,
			starting_water_level,
			water_loss_per_second,
			partial_submersion_start_level,
			elapsed_seconds,
		)
		_append_water_crossing_time(
			boundaries,
			starting_water_level,
			water_loss_per_second,
			0.0,
			elapsed_seconds,
		)

		# Net wetness rate is monotonic while water evaporates. Splitting at its
		# one possible zero crossing makes clamping at 0/1 analytically exact,
		# including a plant that saturates and later dries during one long step.
		if submerged_wetting_per_second > 0.0:
			var zero_rate_submersion := (
				wetness_decay_per_second / submerged_wetting_per_second
			)
			if zero_rate_submersion > 0.0 and zero_rate_submersion < 1.0:
				_append_water_crossing_time(
					boundaries,
					starting_water_level,
					water_loss_per_second,
					partial_submersion_start_level
						+ footprint_height * zero_rate_submersion,
					elapsed_seconds,
				)

	boundaries.sort()
	var wetness := clampf(plant.wetness, 0.0, 1.0)
	var segment_start := boundaries[0]
	for segment_end in boundaries.slice(1):
		if segment_end <= segment_start + INTEGRATION_EPSILON:
			continue
		var start_level := maxf(
			starting_water_level - water_loss_per_second * segment_start,
			0.0,
		)
		var end_level := maxf(
			starting_water_level - water_loss_per_second * segment_end,
			0.0,
		)
		var start_submersion := _get_submersion_for_level(
			start_level,
			plant.position_normalized.y,
			footprint_height,
		)
		var end_submersion := _get_submersion_for_level(
			end_level,
			plant.position_normalized.y,
			footprint_height,
		)
		var segment_seconds: float = segment_end - segment_start
		var average_submersion := (start_submersion + end_submersion) * 0.5
		wetness = clampf(
			wetness
				+ (
					submerged_wetting_per_second * average_submersion
					- wetness_decay_per_second
				) * segment_seconds,
			0.0,
			1.0,
		)
		segment_start = segment_end
	plant.wetness = wetness


static func _append_water_crossing_time(
	boundaries: Array[float],
	starting_water_level: float,
	water_loss_per_second: float,
	water_level: float,
	elapsed_seconds: float,
) -> void:
	var crossing_time := (starting_water_level - water_level) / water_loss_per_second
	if (
		crossing_time > INTEGRATION_EPSILON
		and crossing_time < elapsed_seconds - INTEGRATION_EPSILON
	):
		boundaries.append(crossing_time)


static func _get_submersion_for_level(
	water_level: float,
	plant_center_y: float,
	plant_footprint_height: float,
) -> float:
	var water_surface_y := 1.0 - clampf(water_level, 0.0, 1.0)
	var plant_top := plant_center_y - plant_footprint_height * 0.5
	var plant_bottom := plant_center_y + plant_footprint_height * 0.5
	if water_surface_y >= plant_bottom:
		return 0.0
	if water_surface_y <= plant_top:
		return 1.0
	return clampf(
		(plant_bottom - water_surface_y) / maxf(plant_footprint_height, 0.001),
		0.0,
		1.0,
	)


static func _get_eligible_pairs(
	state: GameState,
	tuning: MvpTuning,
	capacity: int,
) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	if state.plants.size() >= capacity:
		return pairs
	for first_index in state.plants.size():
		var first := state.plants[first_index]
		if not _can_reproduce(first, tuning):
			continue
		for second_index in range(first_index + 1, state.plants.size()):
			var second := state.plants[second_index]
			if not _can_reproduce(second, tuning):
				continue
			if first.position_normalized.distance_to(second.position_normalized) > tuning.reproduction_contact_distance:
				continue
			pairs.append({
				"key": GameState.make_pair_key(first.instance_id, second.instance_id),
				"first": first,
				"second": second,
			})
	return pairs


static func _can_reproduce(plant: PlantState, tuning: MvpTuning) -> bool:
	return (
		plant.get_lifecycle_stage(tuning) == PlantState.LifecycleStage.ADULT
		and plant.reproduction_count < plant.reproduction_limit
	)


static func _cleanup_ineligible_pair_progress(
	state: GameState,
	eligible_pairs: Array[Dictionary],
) -> void:
	var eligible_keys: Dictionary = {}
	for pair in eligible_pairs:
		eligible_keys[pair.key] = true
	for pair_key in state.reproduction_pair_progress.keys():
		if not eligible_keys.has(pair_key):
			state.reproduction_pair_progress.erase(pair_key)


static func _get_next_lifecycle_boundary_delay(
	state: GameState,
	tuning: MvpTuning,
) -> float:
	var next_delay := INF
	var old_boundary := tuning.young_duration_seconds + tuning.adult_duration_seconds
	for plant in state.plants:
		var delay := INF
		if plant.lifecycle_elapsed_seconds < tuning.young_duration_seconds:
			delay = tuning.young_duration_seconds - plant.lifecycle_elapsed_seconds
		elif plant.lifecycle_elapsed_seconds < old_boundary:
			delay = old_boundary - plant.lifecycle_elapsed_seconds
		if delay > EVENT_EPSILON:
			next_delay = minf(next_delay, delay)
	return next_delay


static func _attempt_reproduction(
	state: GameState,
	first: PlantState,
	second: PlantState,
	event_unix_seconds: int,
	tuning: MvpTuning,
	catalog: ContentCatalog,
	jar_definition: JarDefinition,
	environment_definition: EnvironmentDefinition,
	capacity: int,
) -> void:
	if state.plants.size() >= capacity:
		return
	if not _can_reproduce(first, tuning) or not _can_reproduce(second, tuning):
		return

	var chance := tuning.reproduction_base_success_chance
	if first.variant_id == second.variant_id:
		chance *= tuning.same_variant_success_multiplier
	var first_definition := catalog.get_variant(first.variant_id)
	var second_definition := catalog.get_variant(second.variant_id)
	var reproduction_difficulty := 1.0
	if first_definition != null:
		reproduction_difficulty = maxf(reproduction_difficulty, first_definition.reproduction_difficulty)
	if second_definition != null:
		reproduction_difficulty = maxf(reproduction_difficulty, second_definition.reproduction_difficulty)
	chance /= reproduction_difficulty
	chance *= lerpf(0.7, 1.25, (first.wetness + second.wetness) * 0.5)
	if jar_definition != null:
		chance *= jar_definition.reproduction_modifier
	if environment_definition != null:
		chance *= environment_definition.reproduction_modifier
	chance *= _get_light_multiplier(state, event_unix_seconds, tuning, false)
	if state.roll_float() > clampf(chance, 0.0, 1.0):
		return

	var offspring_variant := first.variant_id if state.roll_float() < 0.5 else second.variant_id
	var mutation_chance := _get_mutation_chance(
		state,
		event_unix_seconds,
		tuning.reproduction_mutation_chance,
		tuning,
		environment_definition,
	)
	if state.roll_float() < mutation_chance:
		offspring_variant = _choose_weighted_mutation(state, catalog, offspring_variant)

	var midpoint := (first.position_normalized + second.position_normalized) * 0.5
	var jitter := Vector2(
		state.roll_float_range(-tuning.offspring_position_jitter, tuning.offspring_position_jitter),
		state.roll_float_range(-tuning.offspring_position_jitter, tuning.offspring_position_jitter),
	)
	state.add_plant(
		offspring_variant,
		(midpoint + jitter).clamp(Vector2(0.08, 0.08), Vector2(0.92, 0.92)),
		event_unix_seconds,
		tuning,
	)
	first.reproduction_count += 1
	second.reproduction_count += 1


static func _attempt_environmental_spawn(
	state: GameState,
	event_unix_seconds: int,
	tuning: MvpTuning,
	catalog: ContentCatalog,
	jar_definition: JarDefinition,
	environment_definition: EnvironmentDefinition,
	capacity: int,
) -> void:
	if state.plants.size() >= capacity:
		return
	var chance := tuning.spawn_base_success_chance
	chance *= lerpf(0.45, 1.25, state.water_level)
	chance *= _get_light_multiplier(state, event_unix_seconds, tuning, true)
	if jar_definition != null:
		chance *= jar_definition.spawn_modifier
	if environment_definition != null:
		chance *= environment_definition.spawn_modifier
	if state.roll_float() > clampf(chance, 0.0, 1.0):
		return

	var variant_id := PlantState.BASE_VARIANT_ID
	var mutation_chance := _get_mutation_chance(
		state,
		event_unix_seconds,
		tuning.spawn_mutation_chance,
		tuning,
		environment_definition,
	)
	if state.roll_float() < mutation_chance:
		variant_id = _choose_weighted_mutation(state, catalog, variant_id)

	var spawn_center := Vector2(
		state.roll_float_range(0.14, 0.86),
		state.roll_float_range(0.30, 0.86),
	)
	state.add_plant(variant_id, spawn_center, event_unix_seconds, tuning)


static func _get_light_multiplier(
	state: GameState,
	event_unix_seconds: int,
	tuning: MvpTuning,
	for_spawning: bool,
) -> float:
	var snapshot := _get_environment_snapshot(state, event_unix_seconds, tuning)
	var light_state: StringName = snapshot.light_state
	if for_spawning:
		return tuning.day_spawn_multiplier if light_state == EnvironmentProvider.DAY else tuning.night_spawn_multiplier
	return tuning.day_reproduction_multiplier if light_state == EnvironmentProvider.DAY else tuning.night_reproduction_multiplier


static func _get_mutation_chance(
	state: GameState,
	event_unix_seconds: int,
	base_chance: float,
	tuning: MvpTuning,
	environment_definition: EnvironmentDefinition,
) -> float:
	var snapshot := _get_environment_snapshot(state, event_unix_seconds, tuning)
	var light_state: StringName = snapshot.light_state
	var light_multiplier := tuning.day_mutation_multiplier if light_state == EnvironmentProvider.DAY else tuning.night_mutation_multiplier
	var environment_multiplier := environment_definition.mutation_modifier if environment_definition != null else 1.0
	var water_multiplier := lerpf(0.8, 1.35, state.water_level)
	return clampf(base_chance * light_multiplier * environment_multiplier * water_multiplier, 0.0, 1.0)


static func _get_environment_snapshot(
	state: GameState,
	event_unix_seconds: int,
	tuning: MvpTuning,
) -> Dictionary:
	return EnvironmentProvider.get_environment_with_timezone_bias(
		event_unix_seconds,
		"",
		tuning.day_start_hour,
		tuning.day_end_hour,
		state.simulation_timezone_bias_minutes,
	)


static func _choose_weighted_mutation(
	state: GameState,
	catalog: ContentCatalog,
	fallback_variant_id: StringName,
) -> StringName:
	var total_weight: float = 0.0
	for definition in catalog.plant_variants:
		if definition != null and definition.id != PlantState.BASE_VARIANT_ID:
			total_weight += maxf(definition.mutation_weight, 0.0)
	if total_weight <= 0.0:
		return fallback_variant_id

	var selection := state.roll_float_range(0.0, total_weight)
	for definition in catalog.plant_variants:
		if definition == null or definition.id == PlantState.BASE_VARIANT_ID:
			continue
		selection -= maxf(definition.mutation_weight, 0.0)
		if selection <= 0.0:
			return definition.id
	return fallback_variant_id
