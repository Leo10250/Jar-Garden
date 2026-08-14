class_name GameState
extends RefCounted


const SCHEMA_VERSION: int = 3
const DEFAULT_JAR_ID: StringName = &"default_glass"
const DEFAULT_ENVIRONMENT_ID: StringName = &"forest"
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


static func create_new(
	now_unix_seconds: int,
	tuning: MvpTuning = null,
	timezone_bias_minutes: int = USE_SYSTEM_TIMEZONE_BIAS,
) -> GameState:
	var effective_tuning := tuning if tuning != null else MvpTuning.new()
	var state := GameState.new()
	state.last_simulated_unix_seconds = now_unix_seconds
	state.simulation_timezone_bias_minutes = _resolve_timezone_bias_minutes(timezone_bias_minutes)
	state.coins = effective_tuning.initial_coins
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(now_unix_seconds, 1) * 1103515245 + 12345
	state.rng_state = rng.state
	for center in INITIAL_PLANT_CENTERS:
		state.add_plant(PlantState.BASE_VARIANT_ID, center, now_unix_seconds, effective_tuning)
	state.discover_variant(PlantState.BASE_VARIANT_ID)
	state.schedule_next_spawn(now_unix_seconds, effective_tuning)
	return state


func add_plant(
	variant_id: StringName,
	position_normalized: Vector2,
	born_at_unix_seconds: int,
	tuning: MvpTuning,
) -> PlantState:
	var plant := PlantState.new()
	plant.instance_id = _allocate_instance_id()
	plant.variant_id = variant_id
	plant.born_at_unix_seconds = born_at_unix_seconds
	plant.position_normalized = position_normalized.clamp(Vector2.ZERO, Vector2.ONE)
	plant.reproduction_limit = roll_int_range(
		tuning.reproduction_limit_min,
		maxi(tuning.reproduction_limit_max, tuning.reproduction_limit_min),
	)
	plants.append(plant)
	discover_variant(variant_id)
	return plant


func remove_plant(instance_id: String) -> bool:
	for index in plants.size():
		if plants[index].instance_id != instance_id:
			continue
		plants.remove_at(index)
		_remove_pair_progress_for(instance_id)
		return true
	return false


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
	if (
		not _is_integer(raw_last_simulated)
		or not _is_integer(raw_next_sequence)
		or not _is_serialized_int64(raw_rng_state)
		or not _is_valid_timezone_bias(raw_timezone_bias)
		or not _is_integer(raw_next_spawn)
		or not _is_integer(raw_coins)
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

	var default_reproduction_limit := clampi(
		3,
		effective_tuning.reproduction_limit_min,
		maxi(effective_tuning.reproduction_limit_max, effective_tuning.reproduction_limit_min),
	)
	var seen_ids: Dictionary = {}
	for raw_plant in raw_plants:
		if typeof(raw_plant) != TYPE_DICTIONARY:
			return null
		var plant := PlantState.from_dict(raw_plant, default_reproduction_limit)
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
		var current := data.duplicate(true)
		# Early schema-v3 development saves predated this field. Freeze the device
		# bias once when they are first loaded, then persist it on the next save.
		if not current.has("simulation_timezone_bias_minutes"):
			current["simulation_timezone_bias_minutes"] = fallback_timezone_bias_minutes
		return current
	if schema_version != 1 and schema_version != 2:
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
	var legacy_rng_state: Variant = migrated.get("rng_state", 1)
	if not _is_integer(legacy_rng_state):
		return {}
	migrated["rng_state"] = str(int(legacy_rng_state))
	migrated["simulation_timezone_bias_minutes"] = fallback_timezone_bias_minutes
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
