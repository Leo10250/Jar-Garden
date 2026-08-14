extends SceneTree


const CATALOG_PATH: String = "res://resources/prototype_content_catalog.tres"
const EXPECTED_VARIANT_IDS := [
	&"base_common",
	&"leaf_cap",
	&"moss_cushion",
	&"moonbell",
	&"blush_color",
	&"tiny_gardener",
	&"sunpatch",
	&"rainbell",
	&"fern_curl",
	&"glow_pod",
]
const EXPECTED_ENVIRONMENT_IDS := [&"forest", &"indoor_window", &"rainforest"]

var _failures: int = 0


func _init() -> void:
	var catalog := load(CATALOG_PATH) as ContentCatalog
	_expect(catalog != null, "The production content catalog loads.")
	if catalog == null:
		_finish()
		return

	_test_plant_assets(catalog)
	_test_environment_assets(catalog)
	_test_minimum_jar_capacity(catalog)
	_finish()


func _test_plant_assets(catalog: ContentCatalog) -> void:
	_expect(
		catalog.plant_variants.size() == EXPECTED_VARIANT_IDS.size(),
		"The catalog contains exactly ten plant variants.",
	)
	var silhouette_signatures: Dictionary = {}
	for index in EXPECTED_VARIANT_IDS.size():
		if index >= catalog.plant_variants.size():
			continue
		var definition := catalog.plant_variants[index]
		var expected_id: StringName = EXPECTED_VARIANT_IDS[index]
		_expect(definition != null, "Plant definition %s exists." % expected_id)
		if definition == null:
			continue
		_expect(definition.id == expected_id, "Plant order is stable at index %d." % index)
		var key_prefix := "PLANT_%s" % String(expected_id).to_upper()
		_expect(
			definition.display_name_key == StringName("%s_NAME" % key_prefix),
			"Plant %s has the expected name key." % expected_id,
		)
		_expect(
			definition.description_key == StringName("%s_DESCRIPTION" % key_prefix),
			"Plant %s has the expected description key." % expected_id,
		)
		_expect(
			definition.undiscovered_hint_key == StringName("%s_HINT" % key_prefix),
			"Plant %s has the expected discovery hint key." % expected_id,
		)
		_expect(
			definition.discovered_recipe_key == StringName("%s_RECIPE" % key_prefix),
			"Plant %s has the expected recipe key." % expected_id,
		)
		_expect(definition.visual != null, "Plant %s has data-driven visual art." % expected_id)
		if definition.visual == null:
			continue
		var visual := definition.visual
		_expect(visual.main_texture != null, "Plant %s has a main texture." % expected_id)
		if visual.main_texture != null:
			_expect(
				visual.main_texture.get_size() == Vector2(512.0, 512.0),
				"Plant %s uses the normalized 512px canvas." % expected_id,
			)
			_expect(
				visual.main_texture.resource_path == "res://assets/plants/%s.png" % expected_id,
				"Plant %s is bound to the matching PNG." % expected_id,
			)
		_expect(
			visual.hitbox_polygon.size() >= 3,
			"Plant %s has an authored silhouette hitbox." % expected_id,
		)
		_expect(
			visual.visual_scale.x >= 0.15 and visual.visual_scale.x <= 0.25,
			"Plant %s is scaled for the mobile plant view." % expected_id,
		)
		silhouette_signatures[_polygon_signature(visual.hitbox_polygon)] = true

	_expect(
		silhouette_signatures.size() == 7,
		"The ten plants intentionally resolve to seven collision silhouette families.",
	)
	_expect(
		_same_geometry(catalog.get_variant(&"base_common"), catalog.get_variant(&"blush_color")),
		"Base and Blush share the round dumpling family.",
	)
	_expect(
		_same_geometry(catalog.get_variant(&"moonbell"), catalog.get_variant(&"rainbell")),
		"Moonbell and Rainbell share the bell-drop family.",
	)
	_expect(
		_same_geometry(catalog.get_variant(&"sunpatch"), catalog.get_variant(&"glow_pod")),
		"Sunpatch and Glow Pod share the tall-pod family.",
	)


func _test_environment_assets(catalog: ContentCatalog) -> void:
	_expect(
		catalog.environments.size() == EXPECTED_ENVIRONMENT_IDS.size(),
		"The catalog contains exactly three layered environments.",
	)
	for index in EXPECTED_ENVIRONMENT_IDS.size():
		if index >= catalog.environments.size():
			continue
		var definition := catalog.environments[index]
		var expected_id: StringName = EXPECTED_ENVIRONMENT_IDS[index]
		_expect(definition != null and definition.id == expected_id, "Environment order is stable.")
		if definition == null:
			continue
		var key_prefix := "ENV_%s" % String(expected_id).to_upper()
		_expect(definition.display_name_key == StringName("%s_NAME" % key_prefix), "Environment name key matches.")
		_expect(definition.description_key == StringName("%s_DESCRIPTION" % key_prefix), "Environment description key matches.")
		_expect(definition.weather_label_key == StringName("%s_WEATHER" % key_prefix), "Environment weather key matches.")
		for texture in [definition.far_texture, definition.mid_texture, definition.front_texture]:
			_expect(texture != null, "Environment %s has every portrait layer." % expected_id)
			if texture != null:
				_expect(texture.get_size() == Vector2(720.0, 1280.0), "Environment layers are 720×1280.")
		_expect(definition.thumbnail_texture != null, "Environment %s has a thumbnail." % expected_id)
		if definition.thumbnail_texture != null:
			_expect(
				definition.thumbnail_texture.get_size() == Vector2(256.0, 455.0),
				"Environment thumbnails are 256×455.",
			)


func _test_minimum_jar_capacity(catalog: ContentCatalog) -> void:
	_expect(not catalog.jars.is_empty(), "The catalog contains at least one jar.")
	for jar in catalog.jars:
		_expect(jar != null and jar.capacity >= 2, "Every catalog jar can hold at least two plants.")


func _same_geometry(first: PlantVariantDefinition, second: PlantVariantDefinition) -> bool:
	return (
		first != null
		and second != null
		and first.visual != null
		and second.visual != null
		and first.visual.hitbox_polygon == second.visual.hitbox_polygon
		and first.visual.hitbox_size == second.visual.hitbox_size
	)


func _polygon_signature(points: PackedVector2Array) -> String:
	var parts := PackedStringArray()
	for point in points:
		parts.append("%.2f:%.2f" % [point.x, point.y])
	return ",".join(parts)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func _finish() -> void:
	if _failures == 0:
		print("Content asset tests passed.")
		quit(0)
	else:
		push_error("Content asset tests failed: %d" % _failures)
		quit(1)
