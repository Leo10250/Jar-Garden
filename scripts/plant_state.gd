class_name PlantState
extends RefCounted


enum LifecycleStage {
	YOUNG,
	ADULT,
	OLD,
}


const BASE_VARIANT_ID: StringName = &"base_common"
const SOURCE_INITIAL: StringName = &"initial"
const SOURCE_PURCHASE: StringName = &"purchase"
const SOURCE_REPRODUCTION: StringName = &"reproduction"
const SOURCE_ENVIRONMENTAL: StringName = &"environmental"
const SOURCE_RECOVERY: StringName = &"recovery"
const VALID_BIRTH_SOURCES: Array[StringName] = [
	SOURCE_INITIAL,
	SOURCE_PURCHASE,
	SOURCE_REPRODUCTION,
	SOURCE_ENVIRONMENTAL,
	SOURCE_RECOVERY,
]
const LIGHT_DAY: StringName = &"day"
const LIGHT_NIGHT: StringName = &"night"

var instance_id: String = ""
var variant_id: StringName = BASE_VARIANT_ID
var born_at_unix_seconds: int = 0
var lifecycle_elapsed_seconds: float = 0.0
var position_normalized: Vector2 = Vector2(0.5, 0.5)
var wetness: float = 0.0
var reproduction_count: int = 0
var reproduction_limit: int = 3

## Immutable context recorded when this runtime plant instance is created.
var birth_source: StringName = SOURCE_INITIAL
var birth_environment_id: StringName = &"forest"
var birth_light_state: StringName = LIGHT_DAY
var birth_water_level: float = 0.0
var birth_recipe_id: StringName = &""
var parent_instance_ids: Array[String] = []
var parent_variant_ids: Array[StringName] = []

## Lifetime cultivation history. Direct-water exposure is a normalized dose;
## wetness/submerged fields are exact integrals of their normalized values over
## elapsed seconds, while both light fields are ordinary elapsed seconds.
var lifetime_sunlight_seconds: float = 0.0
var lifetime_moonlight_seconds: float = 0.0
var lifetime_direct_water_exposure: float = 0.0
var lifetime_wetness_seconds: float = 0.0
var lifetime_submerged_fraction_seconds: float = 0.0

## History accumulated only in the current selectable environment. These
## counters reset when the environment changes; lifetime history does not.
var cultivation_environment_id: StringName = &"forest"
var cultivation_segment_started_at_unix_seconds: int = 0
var cultivation_sunlight_seconds: float = 0.0
var cultivation_moonlight_seconds: float = 0.0
var cultivation_direct_water_exposure: float = 0.0
var cultivation_wetness_seconds: float = 0.0
var cultivation_submerged_fraction_seconds: float = 0.0


func get_lifecycle_stage(tuning: MvpTuning) -> LifecycleStage:
	if lifecycle_elapsed_seconds < tuning.young_duration_seconds:
		return LifecycleStage.YOUNG
	if lifecycle_elapsed_seconds < tuning.young_duration_seconds + tuning.adult_duration_seconds:
		return LifecycleStage.ADULT
	return LifecycleStage.OLD


func get_lifecycle_stage_name(tuning: MvpTuning) -> String:
	match get_lifecycle_stage(tuning):
		LifecycleStage.YOUNG:
			return "Young"
		LifecycleStage.ADULT:
			return "Adult"
		_:
			return "Old"


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"variant_id": String(variant_id),
		"born_at_unix_seconds": born_at_unix_seconds,
		"lifecycle_elapsed_seconds": lifecycle_elapsed_seconds,
		"wetness": wetness,
		"reproduction_count": reproduction_count,
		"reproduction_limit": reproduction_limit,
		"birth_source": String(birth_source),
		"birth_environment_id": String(birth_environment_id),
		"birth_light_state": String(birth_light_state),
		"birth_water_level": birth_water_level,
		"birth_recipe_id": String(birth_recipe_id),
		"parent_instance_ids": parent_instance_ids.duplicate(),
		"parent_variant_ids": _string_names_to_strings(parent_variant_ids),
		"lifetime_sunlight_seconds": lifetime_sunlight_seconds,
		"lifetime_moonlight_seconds": lifetime_moonlight_seconds,
		"lifetime_direct_water_exposure": lifetime_direct_water_exposure,
		"lifetime_wetness_seconds": lifetime_wetness_seconds,
		"lifetime_submerged_fraction_seconds": lifetime_submerged_fraction_seconds,
		"cultivation_environment_id": String(cultivation_environment_id),
		"cultivation_segment_started_at_unix_seconds": cultivation_segment_started_at_unix_seconds,
		"cultivation_sunlight_seconds": cultivation_sunlight_seconds,
		"cultivation_moonlight_seconds": cultivation_moonlight_seconds,
		"cultivation_direct_water_exposure": cultivation_direct_water_exposure,
		"cultivation_wetness_seconds": cultivation_wetness_seconds,
		"cultivation_submerged_fraction_seconds": cultivation_submerged_fraction_seconds,
		"position_normalized": {
			"x": position_normalized.x,
			"y": position_normalized.y,
		},
	}


static func from_dict(
	data: Dictionary,
	default_reproduction_limit: int = 3,
	default_environment_id: StringName = &"forest",
	default_segment_start_unix_seconds: int = 0,
) -> PlantState:
	var raw_instance_id: Variant = data.get("instance_id", "")
	if typeof(raw_instance_id) != TYPE_STRING or String(raw_instance_id).is_empty():
		return null

	var raw_variant_id: Variant = data.get("variant_id", String(BASE_VARIANT_ID))
	if typeof(raw_variant_id) != TYPE_STRING or String(raw_variant_id).is_empty():
		raw_variant_id = String(BASE_VARIANT_ID)

	var raw_elapsed: Variant = data.get("lifecycle_elapsed_seconds", 0.0)
	if typeof(raw_elapsed) != TYPE_INT and typeof(raw_elapsed) != TYPE_FLOAT:
		return null
	var elapsed := float(raw_elapsed)
	if not is_finite(elapsed):
		return null
	var raw_wetness: Variant = data.get("wetness", 0.0)
	if not _is_finite_number(raw_wetness):
		return null
	var raw_reproduction_count: Variant = data.get("reproduction_count", 0)
	var raw_reproduction_limit: Variant = data.get(
		"reproduction_limit",
		default_reproduction_limit,
	)
	if not _is_integer(raw_reproduction_count) or not _is_integer(raw_reproduction_limit):
		return null

	var raw_birth_source: Variant = data.get("birth_source", String(SOURCE_INITIAL))
	var raw_birth_environment: Variant = data.get(
		"birth_environment_id",
		String(default_environment_id),
	)
	var raw_birth_light: Variant = data.get("birth_light_state", String(LIGHT_DAY))
	var raw_birth_recipe: Variant = data.get("birth_recipe_id", "")
	var raw_cultivation_environment: Variant = data.get(
		"cultivation_environment_id",
		String(default_environment_id),
	)
	if (
		typeof(raw_birth_source) != TYPE_STRING
		or typeof(raw_birth_environment) != TYPE_STRING
		or typeof(raw_birth_light) != TYPE_STRING
		or typeof(raw_birth_recipe) != TYPE_STRING
		or typeof(raw_cultivation_environment) != TYPE_STRING
		or String(raw_birth_environment).is_empty()
		or String(raw_cultivation_environment).is_empty()
	):
		return null
	var parsed_birth_source := StringName(String(raw_birth_source))
	var parsed_birth_light := StringName(String(raw_birth_light))
	if parsed_birth_source not in VALID_BIRTH_SOURCES:
		return null
	if parsed_birth_light != LIGHT_DAY and parsed_birth_light != LIGHT_NIGHT:
		return null

	var raw_parent_instance_ids: Variant = data.get("parent_instance_ids", [])
	var raw_parent_variant_ids: Variant = data.get("parent_variant_ids", [])
	if not _is_string_array(raw_parent_instance_ids, false):
		return null
	if not _is_string_array(raw_parent_variant_ids, false):
		return null

	var exposure_keys: Array[String] = [
		"birth_water_level",
		"lifetime_sunlight_seconds",
		"lifetime_moonlight_seconds",
		"lifetime_direct_water_exposure",
		"lifetime_wetness_seconds",
		"lifetime_submerged_fraction_seconds",
		"cultivation_sunlight_seconds",
		"cultivation_moonlight_seconds",
		"cultivation_direct_water_exposure",
		"cultivation_wetness_seconds",
		"cultivation_submerged_fraction_seconds",
	]
	var legacy_exposure_keys := {
		"lifetime_submerged_fraction_seconds": "lifetime_submerged_seconds",
		"cultivation_submerged_fraction_seconds": "cultivation_submerged_seconds",
	}
	var exposure_values: Dictionary = {}
	for key in exposure_keys:
		var legacy_key: String = String(legacy_exposure_keys.get(key, ""))
		var raw_value: Variant = data.get(
			key,
			data.get(legacy_key, 0.0) if not legacy_key.is_empty() else 0.0,
		)
		if not _is_finite_number(raw_value) or float(raw_value) < 0.0:
			return null
		exposure_values[key] = float(raw_value)

	var raw_segment_start: Variant = data.get(
		"cultivation_segment_started_at_unix_seconds",
		default_segment_start_unix_seconds,
	)
	if not _is_integer(raw_segment_start):
		return null

	var raw_position: Variant = data.get("position_normalized", {})
	if typeof(raw_position) != TYPE_DICTIONARY:
		return null
	var position_data: Dictionary = raw_position
	var raw_x: Variant = position_data.get("x", 0.5)
	var raw_y: Variant = position_data.get("y", 0.5)
	if not _is_finite_number(raw_x) or not _is_finite_number(raw_y):
		return null

	var plant := PlantState.new()
	plant.instance_id = String(raw_instance_id)
	plant.variant_id = StringName(String(raw_variant_id))
	var raw_born_at: Variant = data.get("born_at_unix_seconds", 0)
	if typeof(raw_born_at) != TYPE_INT and typeof(raw_born_at) != TYPE_FLOAT:
		return null
	if not is_finite(float(raw_born_at)) or not is_equal_approx(float(raw_born_at), floorf(float(raw_born_at))):
		return null
	plant.born_at_unix_seconds = maxi(int(raw_born_at), 0)
	plant.lifecycle_elapsed_seconds = maxf(elapsed, 0.0)
	plant.wetness = clampf(float(raw_wetness), 0.0, 1.0)
	plant.reproduction_count = maxi(int(raw_reproduction_count), 0)
	plant.reproduction_limit = maxi(int(raw_reproduction_limit), 1)
	plant.birth_source = parsed_birth_source
	plant.birth_environment_id = StringName(String(raw_birth_environment))
	plant.birth_light_state = parsed_birth_light
	plant.birth_water_level = clampf(float(exposure_values.birth_water_level), 0.0, 1.0)
	plant.birth_recipe_id = StringName(String(raw_birth_recipe))
	plant.parent_instance_ids.assign(raw_parent_instance_ids)
	plant.parent_variant_ids.assign(_parse_string_name_array(raw_parent_variant_ids))
	plant.lifetime_sunlight_seconds = float(exposure_values.lifetime_sunlight_seconds)
	plant.lifetime_moonlight_seconds = float(exposure_values.lifetime_moonlight_seconds)
	plant.lifetime_direct_water_exposure = float(exposure_values.lifetime_direct_water_exposure)
	plant.lifetime_wetness_seconds = float(exposure_values.lifetime_wetness_seconds)
	plant.lifetime_submerged_fraction_seconds = float(
		exposure_values.lifetime_submerged_fraction_seconds
	)
	plant.cultivation_environment_id = StringName(String(raw_cultivation_environment))
	plant.cultivation_segment_started_at_unix_seconds = maxi(int(raw_segment_start), 0)
	plant.cultivation_sunlight_seconds = float(exposure_values.cultivation_sunlight_seconds)
	plant.cultivation_moonlight_seconds = float(exposure_values.cultivation_moonlight_seconds)
	plant.cultivation_direct_water_exposure = float(
		exposure_values.cultivation_direct_water_exposure
	)
	plant.cultivation_wetness_seconds = float(exposure_values.cultivation_wetness_seconds)
	plant.cultivation_submerged_fraction_seconds = float(
		exposure_values.cultivation_submerged_fraction_seconds
	)
	plant.position_normalized = Vector2(
		clampf(float(raw_x), 0.0, 1.0),
		clampf(float(raw_y), 0.0, 1.0),
	)
	return plant


func reset_cultivation_segment(
	environment_id: StringName,
	started_at_unix_seconds: int,
) -> void:
	cultivation_environment_id = environment_id
	cultivation_segment_started_at_unix_seconds = maxi(started_at_unix_seconds, 0)
	cultivation_sunlight_seconds = 0.0
	cultivation_moonlight_seconds = 0.0
	cultivation_direct_water_exposure = 0.0
	cultivation_wetness_seconds = 0.0
	cultivation_submerged_fraction_seconds = 0.0


func add_light_exposure(sunlight_seconds: float, moonlight_seconds: float) -> void:
	var safe_sunlight := maxf(sunlight_seconds, 0.0)
	var safe_moonlight := maxf(moonlight_seconds, 0.0)
	lifetime_sunlight_seconds += safe_sunlight
	lifetime_moonlight_seconds += safe_moonlight
	cultivation_sunlight_seconds += safe_sunlight
	cultivation_moonlight_seconds += safe_moonlight


func add_direct_water_exposure(exposure: float) -> void:
	var safe_exposure := maxf(exposure, 0.0)
	lifetime_direct_water_exposure += safe_exposure
	cultivation_direct_water_exposure += safe_exposure


func add_wetness_exposure(wetness_seconds: float) -> void:
	var safe_exposure := maxf(wetness_seconds, 0.0)
	lifetime_wetness_seconds += safe_exposure
	cultivation_wetness_seconds += safe_exposure


func add_submerged_fraction_exposure(submerged_fraction_seconds: float) -> void:
	var safe_exposure := maxf(submerged_fraction_seconds, 0.0)
	lifetime_submerged_fraction_seconds += safe_exposure
	cultivation_submerged_fraction_seconds += safe_exposure


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


static func _is_integer(value: Variant) -> bool:
	return _is_finite_number(value) and is_equal_approx(float(value), floorf(float(value)))


static func _is_string_array(value: Variant, require_non_empty: bool) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for raw_item in value:
		if typeof(raw_item) != TYPE_STRING:
			return false
		if require_non_empty and String(raw_item).is_empty():
			return false
	return true


static func _parse_string_name_array(values: Array) -> Array[StringName]:
	var parsed: Array[StringName] = []
	for value in values:
		parsed.append(StringName(String(value)))
	return parsed


static func _string_names_to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result
