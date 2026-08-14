class_name EnvironmentProvider
extends RefCounted


const DAY: StringName = &"day"
const NIGHT: StringName = &"night"
const SECONDS_PER_HOUR: float = 3600.0
const SECONDS_PER_DAY: float = 86400.0


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


## Returns exact elapsed sunlight/moonlight seconds for an arbitrary interval.
## The calculation is periodic and does not loop once per simulated day, so a
## long offline interval and many short foreground intervals remain equivalent.
static func get_light_durations_between(
	start_unix_seconds: float,
	end_unix_seconds: float,
	day_start_hour: int,
	day_end_hour: int,
	timezone_bias_minutes: int,
) -> Dictionary:
	var elapsed_seconds := maxf(end_unix_seconds - start_unix_seconds, 0.0)
	if elapsed_seconds <= 0.0:
		return {
			"sunlight_seconds": 0.0,
			"moonlight_seconds": 0.0,
		}
	if (
		not _is_valid_hour(day_start_hour)
		or not _is_valid_hour(day_end_hour)
		or day_start_hour == day_end_hour
	):
		push_error("Day start and end hours must be different values between 0 and 23.")
		return {
			"sunlight_seconds": 0.0,
			"moonlight_seconds": elapsed_seconds,
		}

	var day_ranges: Array[Vector2] = []
	var start_second := float(day_start_hour) * SECONDS_PER_HOUR
	var end_second := float(day_end_hour) * SECONDS_PER_HOUR
	if start_second < end_second:
		day_ranges.append(Vector2(start_second, end_second))
	else:
		day_ranges.append(Vector2(0.0, end_second))
		day_ranges.append(Vector2(start_second, SECONDS_PER_DAY))

	var sunlight_per_day: float = 0.0
	for day_range in day_ranges:
		sunlight_per_day += day_range.y - day_range.x
	var full_days := floori(elapsed_seconds / SECONDS_PER_DAY)
	var sunlight_seconds := float(full_days) * sunlight_per_day
	var remainder_seconds := elapsed_seconds - float(full_days) * SECONDS_PER_DAY
	var local_cycle_start := fposmod(
		start_unix_seconds + float(timezone_bias_minutes) * 60.0,
		SECONDS_PER_DAY,
	)
	var first_piece_seconds := minf(
		remainder_seconds,
		SECONDS_PER_DAY - local_cycle_start,
	)
	sunlight_seconds += _get_day_overlap(
		local_cycle_start,
		local_cycle_start + first_piece_seconds,
		day_ranges,
	)
	var wrapped_seconds := remainder_seconds - first_piece_seconds
	if wrapped_seconds > 0.0:
		sunlight_seconds += _get_day_overlap(0.0, wrapped_seconds, day_ranges)

	sunlight_seconds = clampf(sunlight_seconds, 0.0, elapsed_seconds)
	return {
		"sunlight_seconds": sunlight_seconds,
		"moonlight_seconds": elapsed_seconds - sunlight_seconds,
	}


static func _get_day_overlap(
	interval_start: float,
	interval_end: float,
	day_ranges: Array[Vector2],
) -> float:
	var overlap: float = 0.0
	for day_range in day_ranges:
		overlap += maxf(
			minf(interval_end, day_range.y) - maxf(interval_start, day_range.x),
			0.0,
		)
	return overlap


static func _is_valid_hour(hour: int) -> bool:
	return hour >= 0 and hour < 24
