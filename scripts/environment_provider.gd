class_name EnvironmentProvider
extends RefCounted


const DAY: StringName = &"day"
const NIGHT: StringName = &"night"


## Returns a small offline environment snapshot for an arbitrary Unix timestamp.
## Day boundaries are caller-owned placeholder tuning, not permanent design values.
static func get_environment(
	unix_timestamp: int,
	weather_label: String,
	day_start_hour: int,
	day_end_hour: int,
) -> Dictionary:
	return get_environment_with_timezone_bias(
		unix_timestamp,
		weather_label,
		day_start_hour,
		day_end_hour,
		get_current_timezone_bias_minutes(),
	)


## Deterministic seam for simulation and tests. The bias is minutes east of UTC.
static func get_environment_with_timezone_bias(
	unix_timestamp: int,
	weather_label: String,
	day_start_hour: int,
	day_end_hour: int,
	timezone_bias_minutes: int,
) -> Dictionary:
	var local_hour := get_local_hour_with_timezone_bias(
		unix_timestamp,
		timezone_bias_minutes,
	)
	var light_state := get_light_state_for_hour(
		local_hour,
		day_start_hour,
		day_end_hour,
	)
	var local_weather_label := weather_label.strip_edges()
	return {
		"light_state": light_state,
		"local_hour": local_hour,
		"weather_label": local_weather_label,
		"display_label": get_display_label(light_state, local_weather_label),
	}


static func get_current_timezone_bias_minutes() -> int:
	var timezone := Time.get_time_zone_from_system()
	return int(timezone.get("bias", 0))


static func get_local_hour(unix_timestamp: int) -> int:
	return get_local_hour_with_timezone_bias(
		unix_timestamp,
		get_current_timezone_bias_minutes(),
	)


static func get_local_hour_with_timezone_bias(
	unix_timestamp: int,
	timezone_bias_minutes: int,
) -> int:
	var local_timestamp := unix_timestamp + timezone_bias_minutes * 60
	var local_datetime := Time.get_datetime_dict_from_unix_time(local_timestamp)
	return int(local_datetime.get("hour", 0))


## The start boundary is inclusive and the end boundary is exclusive.
## A wrapped interval (for example, 20 through 6) is supported as well.
static func get_light_state_for_hour(
	local_hour: int,
	day_start_hour: int,
	day_end_hour: int,
) -> StringName:
	if not _is_valid_hour(local_hour):
		push_error("Local hour must be between 0 and 23.")
		return NIGHT
	if not _is_valid_hour(day_start_hour) or not _is_valid_hour(day_end_hour):
		push_error("Day boundary hours must be between 0 and 23.")
		return NIGHT
	if day_start_hour == day_end_hour:
		push_error("Day start and end hours must be different.")
		return NIGHT

	var is_day: bool
	if day_start_hour < day_end_hour:
		is_day = local_hour >= day_start_hour and local_hour < day_end_hour
	else:
		is_day = local_hour >= day_start_hour or local_hour < day_end_hour
	return DAY if is_day else NIGHT


static func get_display_label(light_state: StringName, weather_label: String) -> String:
	var light_label := "Day" if light_state == DAY else "Night"
	var local_weather_label := weather_label.strip_edges()
	if local_weather_label.is_empty():
		return light_label
	return "%s - %s" % [light_label, local_weather_label]


static func _is_valid_hour(hour: int) -> bool:
	return hour >= 0 and hour < 24
