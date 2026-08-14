extends SceneTree


const PLANT_SCENE_PATH: String = "res://scenes/plant.tscn"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var host := Control.new()
	host.size = Vector2(480.0, 320.0)
	root.add_child(host)

	var packed_scene := load(PLANT_SCENE_PATH) as PackedScene
	var textured := packed_scene.instantiate() as PlantView
	var fallback := packed_scene.instantiate() as PlantView
	host.add_child(textured)
	host.add_child(fallback)
	await process_frame

	var visual := PlantVisualDefinition.new()
	visual.back_texture = _make_texture(Color(0.2, 0.4, 0.3, 1.0))
	visual.main_texture = _make_texture(Color(0.9, 0.8, 0.7, 1.0))
	visual.front_texture = _make_texture(Color(0.7, 0.4, 0.2, 1.0))
	visual.visual_offset = Vector2(4.0, -3.0)
	visual.visual_scale = Vector2(1.2, 0.8)
	visual.hitbox_size = Vector2(60.0, 40.0)
	visual.hitbox_offset = Vector2(2.0, 1.0)
	visual.young_scale = 0.5
	visual.adult_scale = 1.0
	visual.old_scale = 0.85
	visual.young_motion_period_seconds = 0.8

	var definition := PlantVariantDefinition.new()
	definition.id = &"layered_test"
	definition.visual = visual
	textured.apply_presentation(
		definition,
		PlantState.LifecycleStage.YOUNG,
		0.5,
	)

	_expect(textured.back_texture_sprite.visible, "The data-driven back texture is visible.")
	_expect(textured.main_texture_sprite.visible, "The data-driven main texture is visible.")
	_expect(textured.front_texture_sprite.visible, "The data-driven front texture is visible.")
	_expect(not textured.fallback_visual.visible, "A main texture replaces the fallback blob.")
	_expect(textured.texture_wetness.visible, "Textured plants reuse the wetness presentation layer.")
	_expect(
		textured.visual_root.position.is_equal_approx(Vector2(52.0, 41.0)),
		"The authored visual offset is applied around the plant center.",
	)
	_expect(
		textured.visual_root.scale.is_equal_approx(Vector2(0.6, 0.4)),
		"Authored and Young lifecycle scales compose.",
	)
	_expect(
		textured.get_hitbox_size().is_equal_approx(Vector2(30.0, 20.0)),
		"The Young hitbox follows the configured lifecycle scale.",
	)
	_expect(
		textured.call("_has_point", textured.hitbox_area.position),
		"The center of the collision silhouette is clickable.",
	)
	_expect(
		not textured.call(
			"_has_point",
			textured.hitbox_area.position + textured.get_hitbox_size() * 0.5,
		),
		"The transparent corner outside the rounded collision silhouette is not clickable.",
	)

	var legacy_definition := PlantVariantDefinition.new()
	legacy_definition.id = &"legacy_fallback"
	legacy_definition.body_color = Color(0.72, 0.86, 0.78, 1.0)
	legacy_definition.head_accessory = &"sun_hat"
	legacy_definition.equipment = &"watering_can"
	fallback.apply_variant_definition(legacy_definition)
	fallback.set_interaction_enabled(false)
	_expect(fallback.fallback_visual.visible, "Missing artwork keeps the cute fallback blob.")
	_expect(fallback.body.color.is_equal_approx(legacy_definition.body_color), "Fallback tint remains compatible.")
	_expect(fallback.sun_hat.visible and fallback.watering_can.visible, "Legacy placeholder accessories remain compatible.")

	textured.apply_presentation(
		definition,
		PlantState.LifecycleStage.ADULT,
		0.0,
	)
	textured.position = Vector2(80.0, 80.0)
	fallback.position = Vector2(115.0, 80.0)
	_expect(textured.hitbox_overlaps(fallback), "The public drag geometry detects touching plant silhouettes.")
	fallback.position = Vector2(300.0, 80.0)
	_expect(not textured.hitbox_overlaps(fallback), "Separated plant silhouettes do not collide.")

	fallback.set_interaction_enabled(true)
	textured.position = Vector2(80.0, 80.0)
	fallback.position = Vector2(220.0, 80.0)
	var requested_drag_position := textured.position + Vector2(120.0, 0.0)
	textured.call("_move_by", Vector2(120.0, 0.0))
	_expect(
		textured.position.x < requested_drag_position.x,
		"Dragging stops at the first silhouette contact instead of deeply penetrating.",
	)
	_expect(
		not textured.hitbox_overlaps(fallback),
		"The resolved drag position remains just outside the neighboring hitbox.",
	)
	_expect(
		textured.get_hitbox_center_global().distance_to(fallback.get_hitbox_center_global()) < 100.0,
		"Collision resolution still allows the plants to rest close enough to touch.",
	)

	var saved_position := textured.position
	textured.set_contact_state("test_contact", true, textured.get_hitbox_center_global() + Vector2.RIGHT)
	await create_timer(0.23).timeout
	_expect(textured.position.is_equal_approx(saved_position), "Contact bounce never changes the saved Control position.")
	_expect(textured.contact_motion.scale.is_equal_approx(Vector2.ONE), "The contact bounce settles at its neutral scale.")
	_expect(is_zero_approx(textured.contact_motion.rotation), "The contact bounce settles at its neutral rotation.")

	textured.set_contact_state("test_contact", true, textured.get_hitbox_center_global() + Vector2.RIGHT)
	await create_timer(0.03).timeout
	_expect(not textured.is_contact_bouncing(), "Continuous contact does not replay the first-contact bounce.")
	textured.set_contact_state("test_contact", false)
	textured.set_contact_state("test_contact", true, textured.get_hitbox_center_global() + Vector2.RIGHT)
	await create_timer(0.03).timeout
	_expect(textured.is_contact_bouncing(), "Leaving contact re-arms the next first-contact bounce.")

	host.queue_free()
	await process_frame
	if _failures == 0:
		print("Plant visual tests passed.")
		quit(0)
	else:
		push_error("Plant visual tests failed: %d" % _failures)
		quit(1)


func _make_texture(color: Color) -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
