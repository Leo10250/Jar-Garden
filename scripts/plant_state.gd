class_name PlantState
extends RefCounted


enum LifecycleStage {
	YOUNG,
	ADULT,
	OLD,
}


const BASE_VARIANT_ID: StringName = &"base_common"

var instance_id: String = ""
var variant_id: StringName = BASE_VARIANT_ID
var born_at_unix_seconds: int = 0
var lifecycle_elapsed_seconds: float = 0.0
var position_normalized: Vector2 = Vector2(0.5, 0.5)
var wetness: float = 0.0
var reproduction_count: int = 0
var reproduction_limit: int = 3


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
		"position_normalized": {
			"x": position_normalized.x,
			"y": position_normalized.y,
		},
	}


static func from_dict(data: Dictionary, default_reproduction_limit: int = 3) -> PlantState:
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
	plant.position_normalized = Vector2(
		clampf(float(raw_x), 0.0, 1.0),
		clampf(float(raw_y), 0.0, 1.0),
	)
	return plant


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


static func _is_integer(value: Variant) -> bool:
	return _is_finite_number(value) and is_equal_approx(float(value), floorf(float(value)))
