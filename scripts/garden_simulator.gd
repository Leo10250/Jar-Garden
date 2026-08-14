class_name GardenSimulator
extends RefCounted


const EVENT_EPSILON: float = 0.001
const INTEGRATION_EPSILON: float = 0.000000001
const PROFILE_EPSILON: float = 0.000001
const HITBOX_POINT_COUNT: int = 20


static func advance_to(
	state: GameState,
	now_unix_seconds: int,
	tuning: MvpTuning,
	catalog: ContentCatalog = null,
	jar_definition: JarDefinition = null,
	environment_definition: EnvironmentDefinition = null,
) -> float:
	var current_environment_id := (
		environment_definition.id
		if environment_definition != null and not String(environment_definition.id).is_empty()
		else state.active_environment_id
	)
	if current_environment_id != state.active_environment_id:
		state.active_environment_id = current_environment_id
	if state.cultivation_environment_id != current_environment_id:
		state.reset_cultivation_segment(
			current_environment_id,
			maxi(state.last_simulated_unix_seconds, 0),
		)
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
			start_time,
			end_time,
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
				current_time,
				end_time,
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

		var eligible_pairs := _get_eligible_pairs(state, tuning, capacity, catalog)
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
				current_time,
				next_event_time,
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
				current_time,
				current_time + nudge,
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


## Caller should advance through the old environment first, then use this seam
## at the same checkpoint. advance_to also detects direct active-ID changes as a
## compatibility fallback for existing controllers.
static func settle_environment_change(
	state: GameState,
	new_environment_id: StringName,
	at_unix_seconds: int,
) -> void:
	var safe_environment_id := (
		new_environment_id
		if not String(new_environment_id).is_empty()
		else GameState.DEFAULT_ENVIRONMENT_ID
	)
	if (
		state.active_environment_id == safe_environment_id
		and state.cultivation_environment_id == safe_environment_id
	):
		return
	var safe_checkpoint := maxi(at_unix_seconds, state.last_simulated_unix_seconds)
	state.active_environment_id = safe_environment_id
	state.reset_cultivation_segment(safe_environment_id, safe_checkpoint)


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
	if state.cultivation_environment_id != state.active_environment_id:
		state.reset_cultivation_segment(
			state.active_environment_id,
			state.last_simulated_unix_seconds,
		)
	var direct_water_dose := maxf(tuning.water_level_per_press, 0.0)
	state.water_level = clampf(
		state.water_level + direct_water_dose,
		0.0,
		1.0,
	)
	# This is poured dose rather than retained level: watering a full jar still
	# exposes the garden and its plants to the stream.
	state.cultivation_direct_water_exposure += direct_water_dose
	for plant in state.plants:
		var topness := 1.0 - clampf(plant.position_normalized.y, 0.0, 1.0)
		var vertical_multiplier := lerpf(
			tuning.bottom_watering_multiplier,
			1.0,
			topness,
		)
		var horizontal_distance := absf(
			plant.position_normalized.x - tuning.watering_stream_x_normalized
		)
		var horizontal_closeness := 1.0 - clampf(
			horizontal_distance / maxf(tuning.watering_horizontal_reach, 0.001),
			0.0,
			1.0,
		)
		var horizontal_multiplier := lerpf(
			tuning.side_watering_multiplier,
			1.0,
			horizontal_closeness,
		)
		var exposure := tuning.top_wetness_per_press * vertical_multiplier * horizontal_multiplier
		plant.wetness = clampf(
			plant.wetness + exposure,
			0.0,
			1.0,
		)
		plant.add_direct_water_exposure(exposure)


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
	start_unix_seconds: float,
	end_unix_seconds: float,
	tuning: MvpTuning,
	jar_definition: JarDefinition,
	environment_definition: EnvironmentDefinition,
) -> void:
	var elapsed_seconds := maxf(end_unix_seconds - start_unix_seconds, 0.0)
	if elapsed_seconds <= 0.0:
		return
	var light_durations := EnvironmentProvider.get_light_durations_between(
		start_unix_seconds,
		end_unix_seconds,
		tuning.day_start_hour,
		tuning.day_end_hour,
		state.simulation_timezone_bias_minutes,
	)
	var sunlight_seconds: float = light_durations.sunlight_seconds
	var moonlight_seconds: float = light_durations.moonlight_seconds
	state.cultivation_sunlight_seconds += sunlight_seconds
	state.cultivation_moonlight_seconds += moonlight_seconds
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
	var water_present_seconds := elapsed_seconds
	if water_loss_per_second > 0.0:
		water_present_seconds = minf(
			elapsed_seconds,
			starting_water_level / water_loss_per_second,
		)
	var water_level_after_present_interval := maxf(
		starting_water_level - water_loss_per_second * water_present_seconds,
		0.0,
	)
	state.cultivation_water_level_seconds += (
		(starting_water_level + water_level_after_present_interval)
		* 0.5
		* water_present_seconds
	)
	if starting_water_level >= tuning.extreme_wetness_threshold:
		var extreme_seconds := elapsed_seconds
		if water_loss_per_second > 0.0:
			extreme_seconds = minf(
				elapsed_seconds,
				maxf(
					(starting_water_level - tuning.extreme_wetness_threshold)
					/ water_loss_per_second,
					0.0,
				),
			)
		state.cultivation_extreme_water_seconds += extreme_seconds
	state.water_level = maxf(
		starting_water_level - water_loss_per_second * elapsed_seconds,
		0.0,
	)

	for plant in state.plants:
		plant.lifecycle_elapsed_seconds += elapsed_seconds
		plant.add_light_exposure(sunlight_seconds, moonlight_seconds)
		var water_exposure := _advance_plant_wetness(
			plant,
			starting_water_level,
			water_loss_per_second,
			elapsed_seconds,
			maxf(tuning.wetness_decay_per_second, 0.0) * evaporation_modifier,
			maxf(tuning.submerged_wetting_per_second, 0.0),
			tuning.plant_water_footprint_height,
		)
		plant.add_wetness_exposure(float(water_exposure.wetness_seconds))
		plant.add_submerged_fraction_exposure(
			float(water_exposure.submerged_fraction_seconds)
		)


static func _advance_plant_wetness(
	plant: PlantState,
	starting_water_level: float,
	water_loss_per_second: float,
	elapsed_seconds: float,
	wetness_decay_per_second: float,
	submerged_wetting_per_second: float,
	plant_footprint_height: float,
) -> Dictionary:
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
	var wetness_seconds: float = 0.0
	var submerged_fraction_seconds: float = 0.0
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
		submerged_fraction_seconds += average_submersion * segment_seconds
		var wetness_result := _integrate_clamped_wetness_segment(
			wetness,
			submerged_wetting_per_second * start_submersion - wetness_decay_per_second,
			submerged_wetting_per_second * end_submersion - wetness_decay_per_second,
			segment_seconds,
		)
		wetness = float(wetness_result.final_wetness)
		wetness_seconds += float(wetness_result.wetness_seconds)
		segment_start = segment_end
	plant.wetness = wetness
	return {
		"wetness_seconds": wetness_seconds,
		"submerged_fraction_seconds": submerged_fraction_seconds,
	}


## Integrates normalized wetness exactly for a segment whose wetness rate is
## linear. Clamp-hit times are solved on the analytic quadratic, so one long
## offline step and many foreground steps accumulate the same wetness-seconds.
static func _integrate_clamped_wetness_segment(
	starting_wetness: float,
	starting_rate: float,
	ending_rate: float,
	elapsed_seconds: float,
) -> Dictionary:
	var safe_elapsed := maxf(elapsed_seconds, 0.0)
	var safe_wetness := clampf(starting_wetness, 0.0, 1.0)
	if safe_elapsed <= INTEGRATION_EPSILON:
		return {
			"final_wetness": safe_wetness,
			"wetness_seconds": 0.0,
		}

	if (
		(starting_rate < -INTEGRATION_EPSILON and ending_rate > INTEGRATION_EPSILON)
		or (starting_rate > INTEGRATION_EPSILON and ending_rate < -INTEGRATION_EPSILON)
	):
		var zero_rate_fraction := clampf(
			-starting_rate / (ending_rate - starting_rate),
			0.0,
			1.0,
		)
		var first_seconds := safe_elapsed * zero_rate_fraction
		var first := _integrate_clamped_wetness_segment(
			safe_wetness,
			starting_rate,
			0.0,
			first_seconds,
		)
		var second := _integrate_clamped_wetness_segment(
			float(first.final_wetness),
			0.0,
			ending_rate,
			safe_elapsed - first_seconds,
		)
		return {
			"final_wetness": float(second.final_wetness),
			"wetness_seconds": (
				float(first.wetness_seconds) + float(second.wetness_seconds)
			),
		}

	var rate_slope := (ending_rate - starting_rate) / safe_elapsed
	var raw_final_wetness := _get_unclamped_wetness_at(
		safe_wetness,
		starting_rate,
		rate_slope,
		safe_elapsed,
	)
	var is_non_decreasing := (
		starting_rate >= -INTEGRATION_EPSILON
		and ending_rate >= -INTEGRATION_EPSILON
	)
	var is_non_increasing := (
		starting_rate <= INTEGRATION_EPSILON
		and ending_rate <= INTEGRATION_EPSILON
	)

	if is_non_decreasing and safe_wetness >= 1.0 - INTEGRATION_EPSILON:
		return {
			"final_wetness": 1.0,
			"wetness_seconds": safe_elapsed,
		}
	if is_non_increasing and safe_wetness <= INTEGRATION_EPSILON:
		return {
			"final_wetness": 0.0,
			"wetness_seconds": 0.0,
		}

	if is_non_decreasing and raw_final_wetness > 1.0:
		var upper_hit_seconds := _find_wetness_clamp_time(
			safe_wetness,
			starting_rate,
			rate_slope,
			safe_elapsed,
			1.0,
			true,
		)
		return {
			"final_wetness": 1.0,
			"wetness_seconds": clampf(
				_integrate_unclamped_wetness(
					safe_wetness,
					starting_rate,
					rate_slope,
					upper_hit_seconds,
				) + safe_elapsed - upper_hit_seconds,
				0.0,
				safe_elapsed,
			),
		}
	if is_non_increasing and raw_final_wetness < 0.0:
		var lower_hit_seconds := _find_wetness_clamp_time(
			safe_wetness,
			starting_rate,
			rate_slope,
			safe_elapsed,
			0.0,
			false,
		)
		return {
			"final_wetness": 0.0,
			"wetness_seconds": clampf(
				_integrate_unclamped_wetness(
					safe_wetness,
					starting_rate,
					rate_slope,
					lower_hit_seconds,
				),
				0.0,
				safe_elapsed,
			),
		}

	return {
		"final_wetness": clampf(raw_final_wetness, 0.0, 1.0),
		"wetness_seconds": clampf(
			_integrate_unclamped_wetness(
				safe_wetness,
				starting_rate,
				rate_slope,
				safe_elapsed,
			),
			0.0,
			safe_elapsed,
		),
	}


static func _get_unclamped_wetness_at(
	starting_wetness: float,
	starting_rate: float,
	rate_slope: float,
	elapsed_seconds: float,
) -> float:
	return (
		starting_wetness
		+ starting_rate * elapsed_seconds
		+ 0.5 * rate_slope * elapsed_seconds * elapsed_seconds
	)


static func _integrate_unclamped_wetness(
	starting_wetness: float,
	starting_rate: float,
	rate_slope: float,
	elapsed_seconds: float,
) -> float:
	return (
		starting_wetness * elapsed_seconds
		+ 0.5 * starting_rate * elapsed_seconds * elapsed_seconds
		+ rate_slope * elapsed_seconds * elapsed_seconds * elapsed_seconds / 6.0
	)


static func _find_wetness_clamp_time(
	starting_wetness: float,
	starting_rate: float,
	rate_slope: float,
	elapsed_seconds: float,
	target_wetness: float,
	is_increasing: bool,
) -> float:
	var lower := 0.0
	var upper := elapsed_seconds
	# Bisection solves the analytic quadratic without the cancellation problems
	# of selecting between two near-equal quadratic roots.
	for iteration in 64:
		var midpoint := (lower + upper) * 0.5
		var midpoint_wetness := _get_unclamped_wetness_at(
			starting_wetness,
			starting_rate,
			rate_slope,
			midpoint,
		)
		if (midpoint_wetness < target_wetness) == is_increasing:
			lower = midpoint
		else:
			upper = midpoint
	return (lower + upper) * 0.5


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
	catalog: ContentCatalog,
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
			if not _plants_have_reproduction_contact(first, second, tuning, catalog):
				continue
			pairs.append({
				"key": GameState.make_pair_key(first.instance_id, second.instance_id),
				"first": first,
				"second": second,
			})
	return pairs


static func _plants_have_reproduction_contact(
	first: PlantState,
	second: PlantState,
	tuning: MvpTuning,
	catalog: ContentCatalog,
) -> bool:
	if catalog == null:
		return _has_legacy_contact(first, second, tuning)
	var first_definition := catalog.get_variant(first.variant_id)
	var second_definition := catalog.get_variant(second.variant_id)
	if (
		first_definition == null
		or second_definition == null
		or first_definition.visual == null
		or second_definition.visual == null
	):
		return _has_legacy_contact(first, second, tuning)

	var canonical_bounds := Vector2(
		maxf(tuning.reproduction_canonical_plant_bounds_size.x, 0.0),
		maxf(tuning.reproduction_canonical_plant_bounds_size.y, 0.0),
	)
	if canonical_bounds.x <= 0.0 or canonical_bounds.y <= 0.0:
		return _has_legacy_contact(first, second, tuning)
	var first_polygon := _get_canonical_hitbox_polygon(
		first,
		first_definition.visual,
		canonical_bounds,
	)
	var second_polygon := _get_canonical_hitbox_polygon(
		second,
		second_definition.visual,
		canonical_bounds,
	)
	return _convex_polygons_overlap(first_polygon, second_polygon)


static func _has_legacy_contact(
	first: PlantState,
	second: PlantState,
	tuning: MvpTuning,
) -> bool:
	return (
		first.position_normalized.distance_to(second.position_normalized)
		<= tuning.reproduction_contact_distance
	)


## Mirrors PlantView's authored hitbox geometry in a deterministic canonical
## PlantBounds coordinate space. Reproduction only considers Adult plants, so
## the authored adult scale is the lifecycle scale used here.
static func _get_canonical_hitbox_polygon(
	plant: PlantState,
	visual: PlantVisualDefinition,
	canonical_bounds: Vector2,
) -> PackedVector2Array:
	var adult_scale := maxf(
		visual.get_lifecycle_scale(PlantState.LifecycleStage.ADULT),
		0.01,
	)
	var local_points := PackedVector2Array()
	if visual.hitbox_polygon.size() >= 3:
		for point in visual.hitbox_polygon:
			local_points.append(point * adult_scale)
	else:
		var hitbox_size := Vector2(
			maxf(absf(visual.hitbox_size.x), 1.0),
			maxf(absf(visual.hitbox_size.y), 1.0),
		) * adult_scale
		var radius := hitbox_size * 0.5
		for point_index in HITBOX_POINT_COUNT:
			var angle := TAU * float(point_index) / float(HITBOX_POINT_COUNT)
			local_points.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	local_points = Geometry2D.convex_hull(local_points)
	var center := (
		plant.position_normalized.clamp(Vector2.ZERO, Vector2.ONE) * canonical_bounds
		+ visual.visual_offset
		+ visual.hitbox_offset * adult_scale
	)
	var translated := PackedVector2Array()
	for point in local_points:
		translated.append(center + point)
	return translated


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
		var edge := (
			axis_source[(point_index + 1) % axis_source.size()]
			- axis_source[point_index]
		)
		if edge.length_squared() <= PROFILE_EPSILON:
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
	var birth_recipe_id: StringName = &""
	var mutation_chance := _get_mutation_chance(
		state,
		event_unix_seconds,
		tuning.reproduction_mutation_chance,
		tuning,
		environment_definition,
	)
	if state.roll_float() < mutation_chance:
		var parents: Array[PlantState] = [first, second]
		var recipe_result := _choose_recipe_mutation(
			state,
			catalog,
			tuning,
			PlantState.SOURCE_REPRODUCTION,
			parents,
			tuning.mutation_fallback_variant_id,
		)
		offspring_variant = recipe_result.variant_id
		birth_recipe_id = recipe_result.recipe_id

	var midpoint := (first.position_normalized + second.position_normalized) * 0.5
	var jitter := Vector2(
		state.roll_float_range(-tuning.offspring_position_jitter, tuning.offspring_position_jitter),
		state.roll_float_range(-tuning.offspring_position_jitter, tuning.offspring_position_jitter),
	)
	state.spawn_plant_with_context(
		offspring_variant,
		(midpoint + jitter).clamp(Vector2(0.08, 0.08), Vector2(0.92, 0.92)),
		event_unix_seconds,
		tuning,
		PlantState.SOURCE_REPRODUCTION,
		[first.instance_id, second.instance_id],
		[first.variant_id, second.variant_id],
		birth_recipe_id,
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
	var birth_recipe_id: StringName = &""
	var mutation_chance := _get_mutation_chance(
		state,
		event_unix_seconds,
		tuning.spawn_mutation_chance,
		tuning,
		environment_definition,
	)
	if state.roll_float() < mutation_chance:
		var recipe_result := _choose_recipe_mutation(
			state,
			catalog,
			tuning,
			PlantState.SOURCE_ENVIRONMENTAL,
			[],
			tuning.mutation_fallback_variant_id,
		)
		variant_id = recipe_result.variant_id
		birth_recipe_id = recipe_result.recipe_id

	var spawn_center := Vector2(
		state.roll_float_range(0.14, 0.86),
		state.roll_float_range(0.30, 0.86),
	)
	state.spawn_plant_with_context(
		variant_id,
		spawn_center,
		event_unix_seconds,
		tuning,
		PlantState.SOURCE_ENVIRONMENTAL,
		[],
		[],
		birth_recipe_id,
	)


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


## Public read-only profile used by natural spawning and useful for UI/debug.
## Jar water level is already a normalized whole-jar moisture/submersion proxy.
static func get_jar_cultivation_profile(
	state: GameState,
	tuning: MvpTuning,
) -> Dictionary:
	var segment_seconds := (
		state.cultivation_sunlight_seconds + state.cultivation_moonlight_seconds
	)
	var average_water_level := 0.0
	if segment_seconds > PROFILE_EPSILON:
		average_water_level = clampf(
			state.cultivation_water_level_seconds / segment_seconds,
			0.0,
			1.0,
		)
	var profile := _make_cultivation_profile(
		segment_seconds,
		state.cultivation_sunlight_seconds,
		state.cultivation_moonlight_seconds,
		average_water_level,
		average_water_level,
		tuning,
	)
	profile["environment_id"] = state.cultivation_environment_id
	return profile


## Reproduction averages each parent's normalized segment profile. Both parents
## must independently have a fully settled minimum-length cultivation segment.
static func get_parent_cultivation_profile(
	parents: Array[PlantState],
	tuning: MvpTuning,
) -> Dictionary:
	if parents.size() != 2:
		return _make_unready_cultivation_profile()
	var average_segment_seconds := 0.0
	var average_day_share := 0.0
	var average_night_share := 0.0
	var average_wetness := 0.0
	var average_submerged_fraction := 0.0
	var all_ready := true
	var shared_environment_id := parents[0].cultivation_environment_id
	for parent in parents:
		var segment_seconds := (
			parent.cultivation_sunlight_seconds + parent.cultivation_moonlight_seconds
		)
		if (
			segment_seconds + PROFILE_EPSILON
			< tuning.mutation_minimum_cultivation_seconds
		):
			all_ready = false
		if parent.cultivation_environment_id != shared_environment_id:
			all_ready = false
		average_segment_seconds += segment_seconds / float(parents.size())
		if segment_seconds <= PROFILE_EPSILON:
			continue
		average_day_share += (
			parent.cultivation_sunlight_seconds / segment_seconds / float(parents.size())
		)
		average_night_share += (
			parent.cultivation_moonlight_seconds / segment_seconds / float(parents.size())
		)
		average_wetness += (
			parent.cultivation_wetness_seconds / segment_seconds / float(parents.size())
		)
		average_submerged_fraction += (
			parent.cultivation_submerged_fraction_seconds
			/ segment_seconds
			/ float(parents.size())
		)
	var profile := _make_cultivation_profile_from_shares(
		average_segment_seconds,
		average_day_share,
		average_night_share,
		average_wetness,
		average_submerged_fraction,
		tuning,
		all_ready,
	)
	profile["environment_id"] = shared_environment_id
	return profile


static func _make_cultivation_profile(
	segment_seconds: float,
	sunlight_seconds: float,
	moonlight_seconds: float,
	average_wetness: float,
	average_submerged_fraction: float,
	tuning: MvpTuning,
) -> Dictionary:
	var day_share := 0.0
	var night_share := 0.0
	if segment_seconds > PROFILE_EPSILON:
		day_share = sunlight_seconds / segment_seconds
		night_share = moonlight_seconds / segment_seconds
	return _make_cultivation_profile_from_shares(
		segment_seconds,
		day_share,
		night_share,
		average_wetness,
		average_submerged_fraction,
		tuning,
		true,
	)


static func _make_cultivation_profile_from_shares(
	segment_seconds: float,
	day_share: float,
	night_share: float,
	average_wetness: float,
	average_submerged_fraction: float,
	tuning: MvpTuning,
	additional_ready_condition: bool,
) -> Dictionary:
	var safe_day_share := clampf(day_share, 0.0, 1.0)
	var safe_night_share := clampf(night_share, 0.0, 1.0)
	var light_state := PlantMutationRecipe.LIGHT_BALANCED
	var dominance_share := clampf(tuning.mutation_light_dominance_share, 0.5, 1.0)
	if safe_day_share + PROFILE_EPSILON >= dominance_share:
		light_state = EnvironmentProvider.DAY
	elif safe_night_share + PROFILE_EPSILON >= dominance_share:
		light_state = EnvironmentProvider.NIGHT

	var safe_wetness := clampf(average_wetness, 0.0, 1.0)
	var safe_submerged := clampf(average_submerged_fraction, 0.0, 1.0)
	var dry_to_moist := clampf(tuning.mutation_dry_to_moist_threshold, 0.0, 1.0)
	var moist_to_wet := clampf(
		maxf(tuning.mutation_moist_to_wet_threshold, dry_to_moist),
		0.0,
		1.0,
	)
	var moisture_state := PlantMutationRecipe.WATER_WET
	if safe_wetness < dry_to_moist:
		moisture_state = PlantMutationRecipe.WATER_DRY
	elif safe_wetness < moist_to_wet:
		moisture_state = PlantMutationRecipe.WATER_MOIST
	var is_submerged := (
		safe_submerged + PROFILE_EPSILON
		>= clampf(tuning.mutation_submerged_average_threshold, 0.0, 1.0)
	)

	return {
		"ready": (
			additional_ready_condition
			and segment_seconds + PROFILE_EPSILON
				>= tuning.mutation_minimum_cultivation_seconds
		),
		"segment_seconds": maxf(segment_seconds, 0.0),
		"day_share": safe_day_share,
		"night_share": safe_night_share,
		"average_wetness": safe_wetness,
		"average_submerged_fraction": safe_submerged,
		"light_state": light_state,
		"moisture_state": moisture_state,
		"is_submerged": is_submerged,
		"water_state": (
			PlantMutationRecipe.WATER_SUBMERGED if is_submerged else moisture_state
		),
	}


static func _make_unready_cultivation_profile() -> Dictionary:
	return {
		"ready": false,
		"segment_seconds": 0.0,
		"day_share": 0.0,
		"night_share": 0.0,
		"average_wetness": 0.0,
		"average_submerged_fraction": 0.0,
		"light_state": PlantMutationRecipe.LIGHT_BALANCED,
		"moisture_state": PlantMutationRecipe.WATER_DRY,
		"is_submerged": false,
		"water_state": PlantMutationRecipe.WATER_DRY,
		"environment_id": StringName(),
	}


static func _choose_recipe_mutation(
	state: GameState,
	catalog: ContentCatalog,
	tuning: MvpTuning,
	source: StringName,
	parents: Array[PlantState],
	fallback_variant_id: StringName,
) -> Dictionary:
	var safe_fallback := fallback_variant_id
	if catalog == null or catalog.get_variant(safe_fallback) == null:
		safe_fallback = PlantState.BASE_VARIANT_ID
	var fallback_result := {
		"variant_id": safe_fallback,
		"recipe_id": StringName(),
	}
	if catalog == null:
		return fallback_result
	var profile := (
		get_parent_cultivation_profile(parents, tuning)
		if source == PlantState.SOURCE_REPRODUCTION
		else get_jar_cultivation_profile(state, tuning)
	)
	if (
		not bool(profile.ready)
		or StringName(profile.environment_id) != state.active_environment_id
	):
		return fallback_result

	var eligible_recipes: Array[PlantMutationRecipe] = []
	var total_weight: float = 0.0
	for recipe in tuning.mutation_recipes:
		if (
			recipe == null
			or String(recipe.id).is_empty()
			or String(recipe.target_variant_id).is_empty()
			or catalog.get_variant(recipe.target_variant_id) == null
			or not recipe.supports_source(source)
			or recipe.weight <= 0.0
		):
			continue
		if (
			not String(recipe.required_environment_id).is_empty()
			and recipe.required_environment_id != state.active_environment_id
		):
			continue
		if (
			not String(recipe.required_light_state).is_empty()
			and recipe.required_light_state != StringName(profile.light_state)
		):
			continue
		if (
			not String(recipe.required_water_state).is_empty()
			and not _profile_matches_water_requirement(
				profile,
				recipe.required_water_state,
			)
		):
			continue
		if not _parents_satisfy_recipe(parents, recipe.required_parent_variant_ids):
			continue
		eligible_recipes.append(recipe)
		total_weight += recipe.weight
	if total_weight <= 0.0:
		return fallback_result

	var selection := state.roll_float_range(0.0, total_weight)
	for recipe in eligible_recipes:
		selection -= recipe.weight
		if selection <= 0.0:
			return {
				"variant_id": recipe.target_variant_id,
				"recipe_id": recipe.id,
			}
	return fallback_result


static func _profile_matches_water_requirement(
	profile: Dictionary,
	required_water_state: StringName,
) -> bool:
	if required_water_state == PlantMutationRecipe.WATER_SUBMERGED:
		return bool(profile.is_submerged)
	return required_water_state == StringName(profile.moisture_state)


static func _parents_satisfy_recipe(
	parents: Array[PlantState],
	required_variant_ids: Array[StringName],
) -> bool:
	if required_variant_ids.is_empty():
		return true
	if parents.size() != required_variant_ids.size():
		return false
	var remaining: Array[StringName] = []
	for parent in parents:
		remaining.append(parent.variant_id)
	for required_variant_id in required_variant_ids:
		var matching_index := remaining.find(required_variant_id)
		if matching_index < 0:
			return false
		remaining.remove_at(matching_index)
	return remaining.is_empty()
