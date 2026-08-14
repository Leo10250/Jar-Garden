extends SceneTree


const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const CATALOG_PATH: String = "res://resources/prototype_content_catalog.tres"
const VIEWPORT_SIZES := [
	Vector2i(720, 1280),
	Vector2i(640, 1136),
	Vector2i(720, 1440),
	Vector2i(720, 1560),
	Vector2i(720, 1600),
	Vector2i(853, 1280),
]
const LAYOUT_EPSILON: float = 1.0
const TOUCH_TARGET_MINIMUM: float = 48.0

var _failures: int = 0
var _save_paths: Array[String] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_translation_resources()
	_test_safe_area_calculation()
	_test_environment_art_resources()
	for raw_size in VIEWPORT_SIZES:
		await _test_layout_at_size(raw_size as Vector2i)
	await _test_scaled_text_main_layout()
	await _test_water_animation_and_pour_state()
	_cleanup_save_files()
	for cleanup_frame in 3:
		await process_frame

	if _failures == 0:
		print("Main visual tests passed across all target viewport sizes.")
		quit(0)
	else:
		push_error("Main visual tests failed: %d" % _failures)
		quit(1)


func _test_layout_at_size(viewport_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.name = "Viewport_%dx%d" % [viewport_size.x, viewport_size.y]
	viewport.size = viewport_size
	root.add_child(viewport)
	var main := _instantiate_main(
		"main_visual_%dx%d" % [viewport_size.x, viewport_size.y],
		viewport,
	)
	await process_frame
	await process_frame
	await process_frame

	var size_label := "%dx%d" % [viewport_size.x, viewport_size.y]
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var safe_area := main.get_node("SafeArea") as SafeAreaContainer
	var game_area := main.get_node("SafeArea/GameArea") as VBoxContainer
	var status_bar := main.get_node("SafeArea/GameArea/StatusBar") as GridContainer
	var jar_slot := main.get_node("SafeArea/GameArea/JarSlot") as AspectRatioContainer
	var jar := main.get_node("SafeArea/GameArea/JarSlot/Jar") as Control
	var plant_bounds := main.get_node("SafeArea/GameArea/JarSlot/Jar/PlantBounds") as Control
	var bottom_bar := main.get_node("SafeArea/GameArea/BottomBar") as HBoxContainer

	_expect(safe_area != null, "%s main content has a SafeAreaContainer." % size_label)
	_expect(
		main.get_node("ToastSafeArea") is SafeAreaContainer,
		"%s toast feedback has an independent safe-area container." % size_label,
	)
	_expect(
		main.get_node("SaveErrorOverlay/SafeMargin") is SafeAreaContainer,
		"%s blocking save UI has an independent safe-area container." % size_label,
	)
	_expect(
		main.get_node("ForestBackdrop").get_parent() == main,
		"%s the full-bleed backdrop stays outside the inset gameplay hierarchy." % size_label,
	)
	_expect(
		game_area.get_parent() == safe_area,
		"%s HUD, jar, and dock share one safe-area layout root." % size_label,
	)

	var game_rect := game_area.get_global_rect()
	var status_rect := status_bar.get_global_rect()
	var jar_slot_rect := jar_slot.get_global_rect()
	var jar_rect := jar.get_global_rect()
	var plant_rect := plant_bounds.get_global_rect()
	var dock_rect := bottom_bar.get_global_rect()
	_expect(
		_contains_rect(viewport_rect, game_rect),
		"%s safe gameplay content remains inside the viewport (viewport=%s, game=%s)." % [
			size_label,
			viewport_rect,
			game_rect,
		],
	)
	_expect(_contains_rect(game_rect, status_rect), "%s HUD remains inside the safe gameplay bounds." % size_label)
	_expect(_contains_rect(game_rect, jar_slot_rect), "%s jar slot remains inside the safe gameplay bounds." % size_label)
	_expect(_contains_rect(jar_slot_rect, jar_rect), "%s rendered jar remains inside its responsive slot." % size_label)
	_expect(_contains_rect(jar_rect, plant_rect), "%s plant interaction bounds remain inside the jar." % size_label)
	_expect(_contains_rect(game_rect, dock_rect), "%s bottom dock remains inside the safe gameplay bounds." % size_label)
	_expect(status_rect.end.y <= jar_slot_rect.position.y + LAYOUT_EPSILON, "%s HUD does not overlap the jar slot." % size_label)
	_expect(jar_slot_rect.end.y <= dock_rect.position.y + LAYOUT_EPSILON, "%s jar slot does not overlap the bottom dock." % size_label)
	_expect(status_rect.size.y >= 104.0, "%s HUD keeps its two-row readable height." % size_label)
	_expect(dock_rect.size.y >= 80.0, "%s dock keeps its intended visual height." % size_label)
	_expect(jar_rect.size.x >= TOUCH_TARGET_MINIMUM and jar_rect.size.y >= TOUCH_TARGET_MINIMUM, "%s jar remains meaningfully visible." % size_label)
	_expect(
		is_equal_approx(jar_rect.size.x / jar_rect.size.y, jar_slot.ratio),
		"%s the jar preserves its portrait aspect ratio." % size_label,
	)

	for node_name in ["CoinsLabel", "WaterLabel", "LightLabel", "CapacityLabel"]:
		var chip := status_bar.get_node(node_name) as Button
		_expect(_contains_rect(status_rect, chip.get_global_rect()), "%s %s stays inside the HUD grid." % [size_label, node_name])
		_expect(chip.size.y >= TOUCH_TARGET_MINIMUM, "%s %s has at least a 48dp visible target." % [size_label, node_name])
		_expect(chip.get_combined_minimum_size().y >= TOUCH_TARGET_MINIMUM, "%s %s declares a 48dp minimum." % [size_label, node_name])

	for node_name in ["WaterButton", "StallButton"]:
		var dock_button := bottom_bar.get_node(node_name) as Button
		_expect(_contains_rect(dock_rect, dock_button.get_global_rect()), "%s %s stays inside the bottom dock." % [size_label, node_name])
		_expect(dock_button.size.y >= TOUCH_TARGET_MINIMUM, "%s %s has at least a 48dp touch target." % [size_label, node_name])
		_expect(dock_button.get_combined_minimum_size().y >= TOUCH_TARGET_MINIMUM, "%s %s declares a 48dp minimum." % [size_label, node_name])
		_expect(dock_button.mouse_filter == Control.MOUSE_FILTER_STOP, "%s %s remains touch-interactive." % [size_label, node_name])

	_test_main_scene_layering(main, size_label)
	_test_runtime_environment_bindings(main, size_label)

	main.set("_saving_enabled", false)
	viewport.queue_free()
	await process_frame
	await process_frame


func _test_main_scene_layering(main: Control, size_label: String) -> void:
	var backdrop := main.get_node("ForestBackdrop") as Control
	var far_layer := main.get_node("ForestBackdrop/FarLayer") as TextureRect
	var mid_layer := main.get_node("ForestBackdrop/MidLayer") as TextureRect
	var front_layer := main.get_node("ForestBackdrop/FrontLayer") as TextureRect
	_expect(
		far_layer.get_index() < mid_layer.get_index() and mid_layer.get_index() < front_layer.get_index(),
		"%s background draw order is Far, Mid, then Front." % size_label,
	)
	for layer in [far_layer, mid_layer, front_layer]:
		_expect(layer.get_parent() == backdrop, "%s %s remains on the shared full-screen backdrop." % [size_label, layer.name])
		_expect(layer.texture != null, "%s %s has an active texture." % [size_label, layer.name])

	var plant_bounds := main.get_node("SafeArea/GameArea/JarSlot/Jar/PlantBounds") as Control
	var back_water := plant_bounds.get_node("WaterLevel") as ColorRect
	var front_water := plant_bounds.get_node("WaterForeground") as ColorRect
	var effects := plant_bounds.get_node("WaterEffects") as WaterEffects
	_expect(back_water.z_index < 0, "%s rear water renders behind plant views." % size_label)
	_expect(front_water.z_index > 0, "%s translucent foreground water renders over plant views." % size_label)
	_expect(effects.z_index > front_water.z_index, "%s animated water surface/pour renders over foreground water." % size_label)
	_expect(effects.back_water_path == NodePath("../WaterLevel"), "%s WaterEffects targets the rear water layer." % size_label)
	_expect(effects.front_water_path == NodePath("../WaterForeground"), "%s WaterEffects targets the foreground water layer." % size_label)
	_expect(effects.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s water visuals do not block plant dragging." % size_label)


func _test_scaled_text_main_layout() -> void:
	var viewport_size := Vector2i(640, 1136)
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var viewport := SubViewport.new()
	viewport.name = "ScaledTextMainViewport"
	viewport.size = viewport_size
	root.add_child(viewport)
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var main := _instantiate_main("main_visual_scaled_text", viewport)
	await process_frame
	await process_frame

	var game_area := main.get_node("SafeArea/GameArea") as VBoxContainer
	_scale_ui_text(game_area, 1.40)
	await process_frame
	await process_frame
	await process_frame

	var status_bar := main.get_node("SafeArea/GameArea/StatusBar") as GridContainer
	var jar_slot := main.get_node("SafeArea/GameArea/JarSlot") as AspectRatioContainer
	var bottom_bar := main.get_node("SafeArea/GameArea/BottomBar") as HBoxContainer
	var game_rect := game_area.get_global_rect()
	var status_rect := status_bar.get_global_rect()
	var jar_rect := jar_slot.get_global_rect()
	var dock_rect := bottom_bar.get_global_rect()
	_expect(
		_contains_rect(viewport_rect, game_rect),
		"640x1136 main layout stays in bounds with UI text enlarged by 40%%.",
	)
	_expect(
		status_rect.end.y <= jar_rect.position.y + LAYOUT_EPSILON,
		"Enlarged HUD text does not crowd into the jar.",
	)
	_expect(
		jar_rect.end.y <= dock_rect.position.y + LAYOUT_EPSILON,
		"The jar does not crowd into the enlarged bottom dock.",
	)
	_expect(
		status_bar.get_combined_minimum_size().x <= status_bar.size.x + LAYOUT_EPSILON,
		"The enlarged two-column HUD does not require horizontal overflow.",
	)
	_expect(
		bottom_bar.get_combined_minimum_size().x <= bottom_bar.size.x + LAYOUT_EPSILON,
		"The enlarged bottom dock does not require horizontal overflow.",
	)

	for path in [
		"SafeArea/GameArea/StatusBar/CoinsLabel",
		"SafeArea/GameArea/StatusBar/WaterLabel",
		"SafeArea/GameArea/StatusBar/LightLabel",
		"SafeArea/GameArea/StatusBar/CapacityLabel",
		"SafeArea/GameArea/BottomBar/WaterButton",
		"SafeArea/GameArea/BottomBar/StallButton",
	]:
		var button := main.get_node(path) as Button
		_expect_text_control_fits(button, "Enlarged main text %s" % button.name)

	main.set("_saving_enabled", false)
	viewport.queue_free()
	TranslationServer.set_locale(original_locale)
	await process_frame
	await process_frame


func _test_runtime_environment_bindings(main: Control, size_label: String) -> void:
	var state: GameState = main.get("game_state")
	var catalog: ContentCatalog = main.get("content_catalog")
	var far_layer := main.get_node("ForestBackdrop/FarLayer") as TextureRect
	var mid_layer := main.get_node("ForestBackdrop/MidLayer") as TextureRect
	var front_layer := main.get_node("ForestBackdrop/FrontLayer") as TextureRect
	var original_environment_id: StringName = state.active_environment_id
	for definition in catalog.environments:
		if definition == null:
			continue
		state.active_environment_id = definition.id
		main.call("_apply_content_presentation")
		_expect(far_layer.texture == definition.far_texture, "%s %s binds its far artwork." % [size_label, definition.id])
		_expect(mid_layer.texture == definition.mid_texture, "%s %s binds its mid artwork." % [size_label, definition.id])
		_expect(front_layer.texture == definition.front_texture, "%s %s binds its front artwork." % [size_label, definition.id])
	state.active_environment_id = original_environment_id
	main.call("_apply_content_presentation")


func _test_environment_art_resources() -> void:
	var catalog := load(CATALOG_PATH) as ContentCatalog
	_expect(catalog != null, "The prototype content catalog loads for visual validation.")
	if catalog == null:
		return
	var expected_directories := {
		&"forest": "forest",
		&"indoor_window": "indoor_window",
		&"rainforest": "rainforest",
	}
	_expect(catalog.environments.size() == expected_directories.size(), "The catalog exposes all three authored environments.")
	for environment_id: StringName in expected_directories:
		var definition := catalog.get_environment(environment_id)
		_expect(definition != null, "%s environment definition exists." % environment_id)
		if definition == null:
			continue
		var directory: String = expected_directories[environment_id]
		var textures := {
			"far": definition.far_texture,
			"mid": definition.mid_texture,
			"front": definition.front_texture,
			"thumbnail": definition.thumbnail_texture,
		}
		for layer_name: String in textures:
			var texture := textures[layer_name] as Texture2D
			var expected_path := "res://assets/environments/%s/%s.png" % [directory, layer_name]
			_expect(texture != null, "%s %s artwork loads." % [environment_id, layer_name])
			if texture != null:
				_expect(texture.resource_path == expected_path, "%s %s artwork points to its authored asset." % [environment_id, layer_name])


func _test_translation_resources() -> void:
	var configured: PackedStringArray = ProjectSettings.get_setting(
		"internationalization/locale/translations",
		PackedStringArray(),
	)
	_expect("res://localization/en.po" in configured, "English translation is registered in project settings.")
	_expect("res://localization/zh_CN.po" in configured, "Simplified Chinese translation is registered in project settings.")
	_expect(ProjectSettings.get_setting("internationalization/locale/fallback", "") == "en", "English is the configured localization fallback.")

	var expected_messages := {
		"res://localization/en.po": {
			"UI_WATER": "Water",
			"UI_STALL": "Stall",
			"UI_COLLECTION": "Collection",
			"UI_MARKET": "Market",
			"UI_CUSTOMIZE": "Customize",
			"TOAST_WATERED": "Water trickles into the jar",
		},
		"res://localization/zh_CN.po": {
			"UI_WATER": "加水",
			"UI_STALL": "小摊",
			"UI_COLLECTION": "图鉴",
			"UI_MARKET": "市场",
			"UI_CUSTOMIZE": "装扮",
			"TOAST_WATERED": "清水正流进罐子",
		},
	}
	for resource_path: String in expected_messages:
		var translation := load(resource_path) as Translation
		_expect(translation != null, "%s loads as a Translation resource." % resource_path)
		if translation == null:
			continue
		for message_id: String in expected_messages[resource_path]:
			_expect(
				String(translation.get_message(message_id)) == expected_messages[resource_path][message_id],
				"%s contains %s." % [resource_path, message_id],
			)

	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_expect(TranslationServer.translate(&"UI_WATER") == &"Water", "English UI lookup resolves through TranslationServer.")
	TranslationServer.set_locale("zh_CN")
	_expect(TranslationServer.translate(&"UI_WATER") == &"加水", "Chinese UI lookup resolves through TranslationServer.")
	TranslationServer.set_locale(original_locale)


func _test_safe_area_calculation() -> void:
	var insets := SafeAreaContainer.calculate_safe_insets(
		Vector2i(1170, 2532),
		Vector2i(120, 80),
		Rect2i(120, 167, 1170, 2358),
		Vector2(585, 1266),
	)
	_expect(
		insets.is_equal_approx(Vector4(0.0, 43.5, 0.0, 43.5)),
		"Safe-area conversion accounts for window position and viewport scale.",
	)


func _test_water_animation_and_pour_state() -> void:
	var host := Control.new()
	host.name = "WaterTestHost"
	host.size = Vector2(320.0, 600.0)
	var back_water := ColorRect.new()
	back_water.name = "WaterBack"
	back_water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var front_water := ColorRect.new()
	front_water.name = "WaterFront"
	front_water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var effects := WaterEffects.new()
	effects.name = "WaterEffects"
	effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effects.back_water_path = NodePath("../WaterBack")
	effects.front_water_path = NodePath("../WaterFront")
	host.add_child(back_water)
	host.add_child(front_water)
	host.add_child(effects)
	root.add_child(host)
	await process_frame
	await process_frame

	effects.set_level(0.34)
	_expect(is_equal_approx(effects.get_visual_level(), 0.34), "The first water-level assignment snaps immediately.")
	_expect(is_equal_approx(back_water.anchor_top, 0.66), "Initial snap moves the rear water layer immediately.")
	_expect(is_equal_approx(front_water.anchor_top, 0.66), "Initial snap moves the foreground water layer immediately.")

	effects.set_level(0.70)
	_expect(effects.is_level_animating(), "A later water-level update starts the 0.45 second transition.")
	await create_timer(0.16).timeout
	var pre_retarget_level := effects.get_visual_level()
	_expect(pre_retarget_level > 0.34 and pre_retarget_level < 0.70, "The water level is in flight before a continuous retarget.")
	effects.set_level(0.93)
	_expect(is_equal_approx(effects.get_visual_level(), pre_retarget_level), "Retargeting continues from the current visual water level without a jump.")
	_expect(is_equal_approx(effects.get_target_level(), 0.93), "The newest water target replaces the previous target.")
	await create_timer(WaterEffects.LEVEL_TWEEN_SECONDS + 0.10).timeout
	_expect(is_equal_approx(effects.get_visual_level(), 0.93), "A continuously retargeted water level catches the final target.")
	_expect(not effects.is_level_animating(), "The water-level tween settles after the configured duration.")
	_expect(is_equal_approx(back_water.anchor_top, 0.07), "The rear water layer finishes at the final level.")
	_expect(is_equal_approx(front_water.anchor_top, 0.07), "The foreground water layer finishes at the final level.")

	effects.play_pour()
	_expect(float(effects.get("_pour_elapsed")) <= 0.01, "Watering starts the visible pour state.")
	_expect((effects.get("_ripples") as Array).size() == 1, "Watering creates a surface ripple.")
	effects.call("_process", 0.20)
	effects.play_pour()
	_expect(float(effects.get("_pour_elapsed")) <= 0.01, "A repeated watering action restarts the pour state.")
	_expect((effects.get("_ripples") as Array).size() == 2, "Repeated watering can overlap ripple state.")
	effects.call("_process", WaterEffects.POUR_SECONDS + 0.05)
	_expect(float(effects.get("_pour_elapsed")) >= WaterEffects.POUR_SECONDS, "The pour state ends after its configured duration.")
	effects.call("_process", WaterEffects.RIPPLE_SECONDS + 0.05)
	_expect((effects.get("_ripples") as Array).is_empty(), "Ripple state expires cleanly after its configured duration.")

	host.queue_free()
	await process_frame


func _instantiate_main(save_stem: String, parent: Node) -> Control:
	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene
	var main := packed_scene.instantiate() as Control
	var save_path := TestTempPaths.make_path(save_stem)
	_save_paths.append(save_path)
	main.set("save_path", save_path)
	parent.add_child(main)
	return main


func _contains_rect(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(LAYOUT_EPSILON).encloses(inner)


func _scale_ui_text(node: Node, factor: float) -> void:
	if node is Label or node is BaseButton:
		var text_control := node as Control
		var current_size := text_control.get_theme_font_size(&"font_size")
		text_control.add_theme_font_size_override(
			&"font_size",
			maxi(1, ceili(float(current_size) * factor)),
		)
	for child in node.get_children():
		_scale_ui_text(child, factor)


func _expect_text_control_fits(control: Control, description: String) -> void:
	var minimum := control.get_combined_minimum_size()
	_expect(
		minimum.x <= control.size.x + LAYOUT_EPSILON
			and minimum.y <= control.size.y + LAYOUT_EPSILON,
		"%s is not clipped (minimum=%s, actual=%s)." % [description, minimum, control.size],
	)


func _cleanup_save_files() -> void:
	for save_path in _save_paths:
		for suffix in ["", LocalSave.BACKUP_SUFFIX, LocalSave.TEMP_SUFFIX]:
			var path: String = save_path + String(suffix)
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
