extends SceneTree


const Provider = preload("res://scripts/environment_provider.gd")

var _failures: int = 0


func _init() -> void:
	_test_day_boundaries_with_positive_bias()
	_test_negative_bias_wraps_to_previous_day()
	_test_wrapped_day_window()
	_test_environment_labels_are_offline_inputs()
	_test_exact_light_durations_across_boundaries()
	_test_light_durations_are_chunking_equivalent()

	if _failures == 0:
		print("Environment provider tests passed.")
		quit(0)
	else:
		push_error("Environment provider tests failed: %d" % _failures)
		quit(1)


func _test_day_boundaries_with_positive_bias() -> void:
	var bias_minutes := 120
	var before_start := Provider.get_environment_with_timezone_bias(
		4 * 3600,
		"Clear",
		7,
		19,
		bias_minutes,
	)
	var at_start := Provider.get_environment_with_timezone_bias(
		5 * 3600,
		"Clear",
		7,
		19,
		bias_minutes,
	)
	var before_end := Provider.get_environment_with_timezone_bias(
		16 * 3600,
		"Clear",
		7,
		19,
		bias_minutes,
	)
	var at_end := Provider.get_environment_with_timezone_bias(
		17 * 3600,
		"Clear",
		7,
		19,
		bias_minutes,
	)

	_expect(before_start.light_state == Provider.NIGHT, "The hour before day start is night.")
	_expect(at_start.local_hour == 7, "The explicit timezone bias determines local hour.")
	_expect(at_start.light_state == Provider.DAY, "Day start is inclusive.")
	_expect(before_end.light_state == Provider.DAY, "The hour before day end is day.")
	_expect(at_end.light_state == Provider.NIGHT, "Day end is exclusive.")


func _test_negative_bias_wraps_to_previous_day() -> void:
	var snapshot := Provider.get_environment_with_timezone_bias(
		2 * 3600,
		"Humid",
		7,
		19,
		-300,
	)
	_expect(snapshot.local_hour == 21, "A negative timezone bias can wrap to the previous day.")
	_expect(snapshot.light_state == Provider.NIGHT, "The wrapped local hour determines light state.")


func _test_wrapped_day_window() -> void:
	_expect(
		Provider.get_light_state_for_hour(22, 20, 6) == Provider.DAY,
		"A day window may wrap across midnight.",
	)
	_expect(
		Provider.get_light_state_for_hour(6, 20, 6) == Provider.NIGHT,
		"A wrapped day window still uses an exclusive end.",
	)


func _test_environment_labels_are_offline_inputs() -> void:
	var day_snapshot := Provider.get_environment_with_timezone_bias(
		12 * 3600,
		"  Clear  ",
		7,
		19,
		0,
	)
	var night_snapshot := Provider.get_environment_with_timezone_bias(
		22 * 3600,
		"Humid",
		7,
		19,
		0,
	)

	_expect(typeof(day_snapshot.light_state) == TYPE_STRING_NAME, "Light state is a stable StringName.")
	_expect(day_snapshot.light_state == &"day", "Day uses the stable day identifier.")
	_expect(day_snapshot.weather_label == "Clear", "Weather is a trimmed caller-provided label.")
	_expect(day_snapshot.display_label == "Day - Clear", "Day display label includes local weather.")
	_expect(night_snapshot.light_state == &"night", "Night uses the stable night identifier.")
	_expect(night_snapshot.display_label == "Night - Humid", "Night display label includes local weather.")


func _test_exact_light_durations_across_boundaries() -> void:
	# Local interval 05:30 -> 19:30 with day 06:00 -> 18:00.
	var durations := Provider.get_light_durations_between(
		5.5 * 3600.0,
		19.5 * 3600.0,
		6,
		18,
		0,
	)
	_expect(
		is_equal_approx(float(durations.sunlight_seconds), 12.0 * 3600.0),
		"Light accumulation splits exactly at both day boundaries.",
	)
	_expect(
		is_equal_approx(float(durations.moonlight_seconds), 2.0 * 3600.0),
		"The remainder of a boundary-spanning interval is moonlight.",
	)

	var wrapped := Provider.get_light_durations_between(
		19.0 * 3600.0,
		31.0 * 3600.0,
		20,
		6,
		0,
	)
	_expect(
		is_equal_approx(float(wrapped.sunlight_seconds), 10.0 * 3600.0),
		"Wrapped light windows accumulate exactly across midnight.",
	)


func _test_light_durations_are_chunking_equivalent() -> void:
	var whole := Provider.get_light_durations_between(12345.25, 345678.75, 7, 19, 330)
	var first := Provider.get_light_durations_between(12345.25, 200000.5, 7, 19, 330)
	var second := Provider.get_light_durations_between(200000.5, 345678.75, 7, 19, 330)
	_expect(
		is_equal_approx(
			float(whole.sunlight_seconds),
			float(first.sunlight_seconds) + float(second.sunlight_seconds),
		),
		"One offline light interval matches chunked foreground accumulation.",
	)
	_expect(
		is_equal_approx(
			float(whole.moonlight_seconds),
			float(first.moonlight_seconds) + float(second.moonlight_seconds),
		),
		"Moonlight accumulation is also chunking equivalent.",
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
