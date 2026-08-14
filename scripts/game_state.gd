class_name GameState
extends RefCounted


const SCHEMA_VERSION: int = 4
const DEFAULT_JAR_ID: StringName = &"default_glass"
const DEFAULT_ENVIRONMENT_ID: StringName = &"forest"
const MINIMUM_RECOVERY_PLANTS: int = 2
const USE_SYSTEM_TIMEZONE_BIAS: int = 2147483647
const MIN_TIMEZONE_BIAS_MINUTES: int = -1440
const MAX_TIMEZONE_BIAS_MINUTES: int = 1440
const INITIAL_PLANT_CENTERS: Array[Vector2] = [
	Vector2(0.16, 0.52),
	Vector2(0.43, 0.66),
	Vector2(0.75, 0.51),
	Vector2(0.30, 0.81),
	Vector2(0.64, 0.80),
]
const RECOVERY_PLANT_CENTERS: Array[Vector2] = [
	Vector2(0.34, 0.76),
	Vector2(0.66, 0.76),
	Vector2(0.50, 0.62),
	Vector2(0.22, 0.58),
	Vector2(0.78, 0.58),
]

var last_simulated_unix_seconds: int = 0
var simulation_timezone_bias_minutes: int = 0
var next_plant_sequence: int = 1
var rng_state: int = 1
var plants: Array[PlantState] = []
var water_level: float = 0.0
var coins: int = 0
var discovered_variant_ids: Array[StringName] = []
var active_jar_id: StringName = DEFAULT_JAR_ID
var owned_jar_ids: Array[StringName] = [DEFAULT_JAR_ID]
var active_environment_id: StringName = DEFAULT_ENVIRONMENT_ID
var owned_environment_ids: Array[StringName] = [DEFAULT_ENVIRONMENT_ID]
var next_spawn_unix_seconds: int = 0
var reproduction_pair_progress: Dictionary = {}
## Jar-wide history for the currently selected environment. Plants retain
## their own lifetime counters when this segment resets.
var cultivation_environment_id: StringName = DEFAULT_ENVIRONMENT_ID
var cultivation_segment_started_at_unix_seconds: int = 0
var cultivation_sunlight_seconds: float = 0.0
var cultivation_moonlight_seconds: float = 0.0
var cultivation_direct_water_exposure: float = 0.0
var cultivation_water_level_seconds: float = 0.0
var cultivation_extreme_water_seconds: float = 0.0


static func create_new(
	now_unix_seconds: int,
	tuning: MvpTuning = null,
	timezone_bias_minutes: int = USE_SYSTEM_TIMEZONE_BIAS,
) -> GameState:
	var effective_tuning := tuning if tuning != null else MvpTuning.new()
	var state := GameState.new()
	state.last_simulated_unix_seconds = now_unix_seconds
	state.simulation_timezone_bias_minutes = _resolve_timezone_bias_minutes(timezone_bias_minutes)
	state.cultivation_environment_id = DEFAULT_ENVIRONMENT_ID
	state.cultivation_segment_started_at_unix_seconds = now_unix_seconds
	state.coins = effective_tuning.initial_coins
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(now_unix_seconds, 1) * 1103515245 + 12345
	state.rng_state = rng.state
	for center in INITIAL_PLANT_CENTERS:
		state.spawn_plant_with_context(
			PlantState.BASE_VARIANT_ID,
			center,
			now_unix_seconds,
			effective_tuning,
			PlantState.SOURCE_INITIAL,
		)
	state.discover_variant(PlantState.BASE_VARIANT_ID)
	state.schedule_next_spawn(now_unix_seconds, effective_tuning)
	return state


func add_plant(
	variant_id: StringName,
	position_normalized: Vector2,
	born_at_unix_seconds: int,
	tuning: MvpTuning,
) -> PlantState:
	# Kept as the backwards-compatible purchase path for the main controller.
	# Simulation births should call spawn_plant_with_context with an explicit
	# source and parent/recipe context.
	return spawn_plant_with_context(
		variant_id,
		position_normalized,
		born_at_unix_seconds,
		tuning,
		PlantState.SOURCE_PURCHASE,
	)


func spawn_plant_with_context(
	variant_id: StringName,
	position_normalized: Vector2,
	born_at_unix_seconds: int,
	tuning: MvpTuning,
	source: StringName,
	parent_instance_ids: Array[String] = [],
	parent_variant_ids: Array[StringName] = [],
	recipe_id: StringName = &"",
) -> PlantState:
	if cultivation_environment_id != active_environment_id:
		reset_cultivation_segment(active_environment_id, born_at_unix_seconds)
	var plant := PlantState.new()
	plant.instance_id = _allocate_instance_id()
	plant.variant_id = variant_id
	plant.born_at_unix_seconds = born_at_unix_seconds
	plant.position_normalized = position_normalized.clamp(Vector2.ZERO, Vector2.ONE)
	plant.birth_source = source if source in PlantState.VALID_BIRTH_SOURCES else PlantState.SOURCE_PURCHASE
	plant.birth_environment_id = active_environment_id
	var birth_snapshot := EnvironmentProvider.get_environment_with_timezone_bias(
		born_at_unix_seconds,
		"",
		tuning.day_start_hour,
		tuning.day_end_hour,
		simulation_timezone_bias_minutes,
	)
	plant.birth_light_state = birth_snapshot.light_state
	plant.birth_water_level = water_level
	plant.birth_recipe_id = recipe_id
	plant.parent_instance_ids.assign(parent_instance_ids)
	plant.parent_variant_ids.assign(parent_variant_ids)
	plant.cultivation_environment_id = active_environment_id
	plant.cultivation_segment_started_at_unix_seconds = born_at_unix_seconds
	plant.wetness = _get_initial_submersion(
		water_level,
		plant.position_normalized.y,
		tuning.plant_water_footprint_height,
	)
	plant.reproduction_limit = roll_int_range(
		tuning.reproduction_limit_min,
		maxi(tuning.reproduction_limit_max, tuning.reproduction_limit_min),
	)
	plants.append(plant)
	discover_variant(variant_id)
	return plant


func remove_plant(instance_id: String, tuning: MvpTuning = null) -> bool:
	if not can_remove_plant(instance_id):
		return false
	for index in plants.size():
		if plants[index].instance_id != instance_id:
			continue
		plants.remove_at(index)
		_remove_pair_progress_for(instance_id)
		ensure_minimum_recovery(tuning)
		return true
	return false


## Recovery-born plants are protected only while they form the last viable pair.
## UI can query this before presenting Sell/Delete; remove_plant enforces it.
func can_remove_plant(instance_id: String) -> bool:
	var plant := find_plant(instance_id)
	return can_sell_plant(plant)


## An ecology anchor is one of the free recovery plants currently required to
## keep the jar viable. Recovery plants stop being anchors once a third plant
## exists, but controllers must still award them zero sale value so the safety
## net cannot become a coin source.
func is_ecology_anchor(plant: PlantState) -> bool:
	return (
		plant != null
		and plant.birth_source == PlantState.SOURCE_RECOVERY
		and plants.size() <= MINIMUM_RECOVERY_PLANTS
	)


func can_sell_plant(plant: PlantState) -> bool:
	if plant == null or find_plant(plant.instance_id) != plant:
		return false
	return not is_ecology_anchor(plant)


func needs_minimum_recovery() -> bool:
	return plants.size() < MINIMUM_RECOVERY_PLANTS


## Immediately and deterministically restores a viable pair. The stable source
## marker plus can_remove_plant prevent repeatedly selling the free safety net.
func ensure_minimum_recovery(
	tuning: MvpTuning = null,
	event_unix_seconds: int = -1,
) -> Array[PlantState]:
	var spawned: Array[PlantState] = []
	if not needs_minimum_recovery():
		return spawned
	var effective_tuning := tuning if tuning != null else MvpTuning.new()
	var birth_time := event_unix_seconds
	if birth_time < 0:
		birth_time = last_simulated_unix_seconds
	while plants.size() < MINIMUM_RECOVERY_PLANTS:
		var plant := spawn_plant_with_context(
			PlantState.BASE_VARIANT_ID,
			_get_safest_recovery_position(),
			birth_time,
			effective_tuning,
			PlantState.SOURCE_RECOVERY,
		)
		spawned.append(plant)
	return spawned


func find_plant(instance_id: String) -> PlantState:
	for plant in plants:
		if plant.instance_id == instance_id:
			return plant
	return null


func discover_variant(variant_id: StringName) -> bool:
	if variant_id in discovered_variant_ids:
		return false
	discovered_variant_ids.append(variant_id)
	return true


func owns_jar(jar_id: StringName) -> bool:
	return jar_id in owned_jar_ids


func owns_environment(environment_id: StringName) -> bool:
	return environment_id in owned_environment_ids


func reset_cultivation_segment(
	environment_id: StringName,
	started_at_unix_seconds: int,
) -> void:
	var safe_environment := environment_id if not String(environment_id).is_empty() else DEFAULT_ENVIRONMENT_ID
	cultivation_environment_id = safe_environment
	cultivation_segment_started_at_unix_seconds = maxi(started_at_unix_seconds, 0)
	cultivation_sunlight_seconds = 0.0
	cultivation_moonlight_seconds = 0.0
	cultivation_direct_water_exposure = 0.0
	cultivation_water_level_seconds = 0.0
	cultivation_extreme_water_seconds = 0.0
	for plant in plants:
		plant.reset_cultivation_segment(safe_environment, started_at_unix_seconds)


func roll_float() -> float:
	var rng := _make_rng()
	var value := rng.randf()
	rng_state = rng.state
	return value


func roll_float_range(minimum: float, maximum: float) -> float:
	var rng := _make_rng()
	var value := rng.randf_range(minimum, maximum)
	rng_state = rng.state
	return value


func roll_int_range(minimum: int, maximum: int) -> int:
	var rng := _make_rng()
	var value := rng.randi_range(minimum, maximum)
	rng_state = rng.state
	return value


func schedule_next_spawn(from_unix_seconds: int, tuning: MvpTuning) -> void:
	var delay := roll_float_range(
		minf(tuning.spawn_interval_min_seconds, tuning.spawn_interval_max_seconds),
		maxf(tuning.spawn_interval_min_seconds, tuning.spawn_interval_max_seconds),
	)
	next_spawn_unix_seconds = from_unix_seconds + maxi(roundi(delay), 1)


func to_dict() -> Dictionary:
	var serialized_plants: Array[Dictionary] = []
	for plant in plants:
		serialized_plants.append(plant.to_dict())

	return {
		"schema_version": SCHEMA_VERSION,
		"last_simulated_unix_seconds": last_simulated_unix_seconds,
		"simulation_timezone_bias_minutes": simulation_timezone_bias_minutes,
		"next_plant_sequence": next_plant_sequence,
		# JSON numbers cannot exactly preserve Godot's signed 64-bit RNG state.
		"rng_state": str(rng_state),
		"plants": serialized_plants,
		"water_level": water_level,
		"coins": coins,
		"discovered_variant_ids": _string_names_to_strings(discovered_variant_ids),
		"active_jar_id": String(active_jar_id),
		"owned_jar_ids": _string_names_to_strings(owned_jar_ids),
		"active_environment_id": String(active_environment_id),
		"owned_environment_ids": _string_names_to_strings(owned_environment_ids),
		"next_spawn_unix_seconds": next_spawn_unix_seconds,
		"reproduction_pair_progress": reproduction_pair_progress.duplicate(true),
		"cultivation_environment_id": String(cultivation_environment_id),
		"cultivation_segment_started_at_unix_seconds": cultivation_segment_started_at_unix_seconds,
		"cultivation_sunlight_seconds": cultivation_sunlight_seconds,
		"cultivation_moonlight_seconds": cultivation_moonlight_seconds,
		"cultivation_direct_water_exposure": cultivation_direct_water_exposure,
		"cultivation_water_level_seconds": cultivation_water_level_seconds,
		"cultivation_extreme_water_seconds": cultivation_extreme_water_seconds,
	}


static func from_dict(
	data: Dictionary,
	fallback_now_unix_seconds: int,
	tuning: MvpTuning = null,
	fallback_timezone_bias_minutes: int = USE_SYSTEM_TIMEZONE_BIAS,
) -> GameState:
	var effective_tuning := tuning if tuning != null else MvpTuning.new()
	var resolved_timezone_bias := _resolve_timezone_bias_minutes(fallback_timezone_bias_minutes)
	var migrated_data := _migrate_to_current_schema(
		data,
		effective_tuning,
		resolved_timezone_bias,
	)
	if migrated_data.is_empty():
		return null

	var raw_plants: Variant = migrated_data.get("plants", [])
	if typeof(raw_plants) != TYPE_ARRAY:
		return null
	var raw_last_simulated: Variant = migrated_data.get(
		"last_simulated_unix_seconds",
		fallback_now_unix_seconds,
	)
	var raw_next_sequence: Variant = migrated_data.get("next_plant_sequence", 1)
	var raw_rng_state: Variant = migrated_data.get("rng_state", "1")
	var raw_timezone_bias: Variant = migrated_data.get(
		"simulation_timezone_bias_minutes",
		resolved_timezone_bias,
	)
	var raw_next_spawn: Variant = migrated_data.get(
		"next_spawn_unix_seconds",
		int(raw_last_simulated) + roundi(effective_tuning.spawn_interval_min_seconds),
	)
	var raw_coins: Variant = migrated_data.get("coins", effective_tuning.initial_coins)
	var raw_cultivation_environment: Variant = migrated_data.get(
		"cultivation_environment_id",
		String(DEFAULT_ENVIRONMENT_ID),
	)
	var raw_cultivation_start: Variant = migrated_data.get(
		"cultivation_segment_started_at_unix_seconds",
		raw_last_simulated,
	)
	if (
		not _is_integer(raw_last_simulated)
		or not _is_integer(raw_next_sequence)
		or not _is_serialized_int64(raw_rng_state)
		or not _is_valid_timezone_bias(raw_timezone_bias)
		or not _is_integer(raw_next_spawn)
		or not _is_integer(raw_coins)
		or typeof(raw_cultivation_environment) != TYPE_STRING
		or String(raw_cultivation_environment).is_empty()
		or not _is_integer(raw_cultivation_start)
	):
		return null
	var raw_water_level: Variant = migrated_data.get("water_level", 0.0)
	if not _is_finite_number(raw_water_level):
		return null

	var state := GameState.new()
	state.last_simulated_unix_seconds = maxi(int(raw_last_simulated), 0)
	state.simulation_timezone_bias_minutes = int(raw_timezone_bias)
	state.next_plant_sequence = maxi(int(raw_next_sequence), 1)
	var parsed_rng_state := int(raw_rng_state)
	state.rng_state = parsed_rng_state if parsed_rng_state != 0 else 1
	state.next_spawn_unix_seconds = maxi(int(raw_next_spawn), 0)
	state.coins = maxi(int(raw_coins), 0)
	state.water_level = clampf(float(raw_water_level), 0.0, 1.0)
	state.cultivation_environment_id = StringName(String(raw_cultivation_environment))
	state.cultivation_segment_started_at_unix_seconds = maxi(int(raw_cultivation_start), 0)
	var cultivation_counter_keys: Array[String] = [
		"cultivation_sunlight_seconds",
		"cultivation_moonlight_seconds",
		"cultivation_direct_water_exposure",
		"cultivation_water_level_seconds",
		"cultivation_extreme_water_seconds",
	]
	for key in cultivation_counter_keys:
		var raw_counter: Variant = migrated_data.get(key, 0.0)
		if not _is_finite_number(raw_counter) or float(raw_counter) < 0.0:
			return null
		state.set(key, float(raw_counter))

	var default_reproduction_limit := clampi(
		3,
		effective_tuning.reproduction_limit_min,
		maxi(effective_tuning.reproduction_limit_max, effective_tuning.reproduction_limit_min),
	)
	var seen_ids: Dictionary = {}
	for raw_plant in raw_plants:
		if typeof(raw_plant) != TYPE_DICTIONARY:
			return null
		var plant := PlantState.from_dict(
			raw_plant,
			default_reproduction_limit,
			state.cultivation_environment_id,
			state.cultivation_segment_started_at_unix_seconds,
		)
		if plant == null or seen_ids.has(plant.instance_id):
			return null
		seen_ids[plant.instance_id] = true
		state.plants.append(plant)

	var raw_discoveries: Variant = migrated_data.get("discovered_variant_ids", [])
	var raw_owned_jars: Variant = migrated_data.get("owned_jar_ids", [])
	var raw_owned_environments: Variant = migrated_data.get("owned_environment_ids", [])
	if (
		not _is_string_array(raw_discoveries)
		or not _is_string_array(raw_owned_jars)
		or not _is_string_array(raw_owned_environments)
	):
		return null
	var discoveries: Array[StringName] = _parse_string_name_array(raw_discoveries)
	var owned_jars: Array[StringName] = _parse_string_name_array(raw_owned_jars)
	var owned_environments: Array[StringName] = _parse_string_name_array(raw_owned_environments)
	state.discovered_variant_ids.assign(discoveries)
	for plant in state.plants:
		state.discover_variant(plant.variant_id)
	state.active_jar_id = StringName(String(migrated_data.get("active_jar_id", DEFAULT_JAR_ID)))
	state.owned_jar_ids.assign(owned_jars)
	if not state.owns_jar(state.active_jar_id):
		state.owned_jar_ids.append(state.active_jar_id)
	state.active_environment_id = StringName(String(
		migrated_data.get("active_environment_id", DEFAULT_ENVIRONMENT_ID)
	))
	state.owned_environment_ids.assign(owned_environments)
	if not state.owns_environment(state.active_environment_id):
		state.owned_environment_ids.append(state.active_environment_id)

	var raw_pair_progress: Variant = migrated_data.get("reproduction_pair_progress", {})
	if typeof(raw_pair_progress) != TYPE_DICTIONARY:
		return null
	for pair_key in raw_pair_progress:
		var raw_progress: Variant = raw_pair_progress[pair_key]
		if typeof(pair_key) != TYPE_STRING or not _is_finite_number(raw_progress):
			return null
		state.reproduction_pair_progress[String(pair_key)] = maxf(float(raw_progress), 0.0)

	state._advance_sequence_past_existing_ids()
	state.ensure_minimum_recovery(effective_tuning, state.last_simulated_unix_seconds)
	return state


static func make_pair_key(first_id: String, second_id: String) -> String:
	return "%s|%s" % [first_id, second_id] if first_id < second_id else "%s|%s" % [second_id, first_id]


static func _migrate_to_current_schema(
	data: Dictionary,
	tuning: MvpTuning,
	fallback_timezone_bias_minutes: int,
) -> Dictionary:
	var schema_version := int(data.get("schema_version", 0))
	if schema_version == SCHEMA_VERSION:
		return data.duplicate(true)
	if schema_version != 1 and schema_version != 2 and schema_version != 3:
		return {}

	var migrated := data.duplicate(true)
	if schema_version == 1:
		migrated["rng_state"] = maxi(int(data.get("last_simulated_unix_seconds", 1)), 1) * 1103515245 + 12345
		migrated["water_level"] = 0.0
		migrated["coins"] = tuning.initial_coins
		migrated["discovered_variant_ids"] = [String(PlantState.BASE_VARIANT_ID)]
		migrated["active_jar_id"] = String(DEFAULT_JAR_ID)
		migrated["owned_jar_ids"] = [String(DEFAULT_JAR_ID)]
		migrated["active_environment_id"] = String(DEFAULT_ENVIRONMENT_ID)
		migrated["owned_environment_ids"] = [String(DEFAULT_ENVIRONMENT_ID)]
		migrated["next_spawn_unix_seconds"] = int(data.get("last_simulated_unix_seconds", 0)) + roundi(
			tuning.spawn_interval_min_seconds
		)
		migrated["reproduction_pair_progress"] = {}
	if schema_version <= 2:
		var legacy_rng_state: Variant = migrated.get("rng_state", 1)
		if not _is_integer(legacy_rng_state):
			return {}
		migrated["rng_state"] = str(int(legacy_rng_state))
		migrated["simulation_timezone_bias_minutes"] = fallback_timezone_bias_minutes
	elif not migrated.has("simulation_timezone_bias_minutes"):
		# Early schema-v3 development saves predated this field. Freeze the device
		# bias once when they are first loaded, then persist it on the next save.
		migrated["simulation_timezone_bias_minutes"] = fallback_timezone_bias_minutes

	var environment_id := String(migrated.get(
		"active_environment_id",
		String(DEFAULT_ENVIRONMENT_ID),
	))
	if environment_id.is_empty():
		environment_id = String(DEFAULT_ENVIRONMENT_ID)
	var segment_start := maxi(int(migrated.get("last_simulated_unix_seconds", 0)), 0)
	migrated["cultivation_environment_id"] = environment_id
	migrated["cultivation_segment_started_at_unix_seconds"] = segment_start
	migrated["cultivation_sunlight_seconds"] = 0.0
	migrated["cultivation_moonlight_seconds"] = 0.0
	migrated["cultivation_direct_water_exposure"] = 0.0
	migrated["cultivation_water_level_seconds"] = 0.0
	migrated["cultivation_extreme_water_seconds"] = 0.0

	var raw_plants: Variant = migrated.get("plants", [])
	if typeof(raw_plants) != TYPE_ARRAY:
		return {}
	var timezone_bias := int(migrated.get(
		"simulation_timezone_bias_minutes",
		fallback_timezone_bias_minutes,
	))
	for raw_plant in raw_plants:
		if typeof(raw_plant) != TYPE_DICTIONARY:
			return {}
		var plant_data: Dictionary = raw_plant
		var born_at := maxi(int(plant_data.get("born_at_unix_seconds", segment_start)), 0)
		var snapshot := EnvironmentProvider.get_environment_with_timezone_bias(
			born_at,
			"",
			tuning.day_start_hour,
			tuning.day_end_hour,
			timezone_bias,
		)
		plant_data["birth_source"] = String(PlantState.SOURCE_INITIAL)
		plant_data["birth_environment_id"] = environment_id
		plant_data["birth_light_state"] = String(snapshot.light_state)
		plant_data["birth_water_level"] = 0.0
		plant_data["birth_recipe_id"] = ""
		plant_data["parent_instance_ids"] = []
		plant_data["parent_variant_ids"] = []
		plant_data["lifetime_sunlight_seconds"] = 0.0
		plant_data["lifetime_moonlight_seconds"] = 0.0
		plant_data["lifetime_direct_water_exposure"] = 0.0
		plant_data["lifetime_wetness_seconds"] = 0.0
		plant_data["lifetime_submerged_fraction_seconds"] = 0.0
		plant_data["cultivation_environment_id"] = environment_id
		plant_data["cultivation_segment_started_at_unix_seconds"] = segment_start
		plant_data["cultivation_sunlight_seconds"] = 0.0
		plant_data["cultivation_moonlight_seconds"] = 0.0
		plant_data["cultivation_direct_water_exposure"] = 0.0
		plant_data["cultivation_wetness_seconds"] = 0.0
		plant_data["cultivation_submerged_fraction_seconds"] = 0.0
	migrated["schema_version"] = SCHEMA_VERSION
	return migrated


static func _parse_string_name_array(value: Array) -> Array[StringName]:
	var parsed: Array[StringName] = []
	for raw_item in value:
		var item := StringName(String(raw_item))
		if item not in parsed:
			parsed.append(item)
	return parsed


static func _is_string_array(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for raw_item in value:
		if typeof(raw_item) != TYPE_STRING or String(raw_item).is_empty():
			return false
	return true


static func _string_names_to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result


static func _is_integer(value: Variant) -> bool:
	return _is_finite_number(value) and is_equal_approx(float(value), floorf(float(value)))


static func _is_serialized_int64(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var serialized := String(value)
	if not serialized.is_valid_int():
		return false
	# Requiring the canonical decimal form also rejects values outside Godot's
	# signed 64-bit integer range instead of accepting a clamped conversion.
	return serialized == str(int(serialized))


static func _is_valid_timezone_bias(value: Variant) -> bool:
	if not _is_integer(value):
		return false
	var bias := int(value)
	return bias >= MIN_TIMEZONE_BIAS_MINUTES and bias <= MAX_TIMEZONE_BIAS_MINUTES


static func _resolve_timezone_bias_minutes(requested_bias_minutes: int) -> int:
	if requested_bias_minutes != USE_SYSTEM_TIMEZONE_BIAS:
		return clampi(
			requested_bias_minutes,
			MIN_TIMEZONE_BIAS_MINUTES,
			MAX_TIMEZONE_BIAS_MINUTES,
		)
	var timezone := Time.get_time_zone_from_system()
	return clampi(
		int(timezone.get("bias", 0)),
		MIN_TIMEZONE_BIAS_MINUTES,
		MAX_TIMEZONE_BIAS_MINUTES,
	)


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


func _make_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	if rng_state == 0:
		rng.seed = 1
	else:
		rng.state = rng_state
	return rng


func _allocate_instance_id() -> String:
	var existing_ids: Dictionary = {}
	for plant in plants:
		existing_ids[plant.instance_id] = true

	var candidate := "plant_%06d" % next_plant_sequence
	while existing_ids.has(candidate):
		next_plant_sequence += 1
		candidate = "plant_%06d" % next_plant_sequence
	next_plant_sequence += 1
	return candidate


func _get_safest_recovery_position() -> Vector2:
	if plants.is_empty():
		return RECOVERY_PLANT_CENTERS[0]
	var safest_position := RECOVERY_PLANT_CENTERS[0]
	var safest_distance_squared := -1.0
	for candidate in RECOVERY_PLANT_CENTERS:
		var nearest_distance_squared := INF
		for plant in plants:
			nearest_distance_squared = minf(
				nearest_distance_squared,
				candidate.distance_squared_to(plant.position_normalized),
			)
		if nearest_distance_squared > safest_distance_squared:
			safest_distance_squared = nearest_distance_squared
			safest_position = candidate
	return safest_position


static func _get_initial_submersion(
	water_level: float,
	plant_center_y: float,
	plant_footprint_height: float,
) -> float:
	var footprint_height := maxf(plant_footprint_height, 0.001)
	var water_surface_y := 1.0 - clampf(water_level, 0.0, 1.0)
	var plant_top := plant_center_y - footprint_height * 0.5
	var plant_bottom := plant_center_y + footprint_height * 0.5
	if water_surface_y >= plant_bottom:
		return 0.0
	if water_surface_y <= plant_top:
		return 1.0
	return clampf(
		(plant_bottom - water_surface_y) / footprint_height,
		0.0,
		1.0,
	)


func _advance_sequence_past_existing_ids() -> void:
	var existing_ids: Dictionary = {}
	for plant in plants:
		existing_ids[plant.instance_id] = true
	while existing_ids.has("plant_%06d" % next_plant_sequence):
		next_plant_sequence += 1


func _remove_pair_progress_for(instance_id: String) -> void:
	for pair_key in reproduction_pair_progress.keys():
		var ids := String(pair_key).split("|", false, 1)
		if instance_id in ids:
			reproduction_pair_progress.erase(pair_key)
