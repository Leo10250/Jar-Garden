extends SceneTree


const STALL_SCENE_PATH: String = "res://scenes/stall_panel.tscn"
const CATALOG_PATH: String = "res://resources/prototype_content_catalog.tres"
const TUNING_PATH: String = "res://resources/prototype_mvp_tuning.tres"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	root.size = Vector2i(720, 1280)
	var packed_scene := load(STALL_SCENE_PATH) as PackedScene
	var stall := packed_scene.instantiate() as StallPanel
	root.add_child(stall)
	await process_frame
	await process_frame

	var tabs := stall.get_node("SafeMargin/Modal/ContentMargin/Layout/Tabs") as TabContainer
	var collection_button := stall.get_node("%CollectionButton") as Button
	var market_button := stall.get_node("%MarketButton") as Button
	var customize_button := stall.get_node("%CustomizeButton") as Button
	var buy_button := stall.get_node("%BuyButton") as Button
	var sell_button := stall.get_node("%SellButton") as Button
	var jars_button := stall.get_node("%JarsButton") as Button
	var places_button := stall.get_node("%PlacesButton") as Button
	var secondary_navigation := stall.get_node("%SecondaryNavigation") as PanelContainer
	var market_segments := stall.get_node("%MarketSegments") as HBoxContainer
	var customize_segments := stall.get_node("%CustomizeSegments") as HBoxContainer
	var collection_rows := stall.get_node("%CollectionRows") as GridContainer

	_expect(stall.theme != null, "The Stall inherits the centralized UI Theme resource.")
	var modal := stall.get_node("SafeMargin/Modal") as PanelContainer
	var modal_style := modal.get_theme_stylebox(&"panel") as StyleBoxFlat
	var selected_segment_style := market_button.get_theme_stylebox(&"pressed") as StyleBoxFlat
	_expect(modal_style != null and modal_style.bg_color.is_equal_approx(Color(0.976, 0.949, 0.886, 0.99)), "The warm-cream modal style comes from the shared Theme.")
	_expect(selected_segment_style != null and selected_segment_style.bg_color.is_equal_approx(Color(0.451, 0.651, 0.561, 1.0)), "Segmented controls inherit the shared sage selected style.")
	_expect(not tabs.tabs_visible, "Native TabContainer labels stay hidden behind custom navigation.")
	for button in [
		collection_button,
		market_button,
		customize_button,
		buy_button,
		sell_button,
		jars_button,
		places_button,
	]:
		_expect(button.custom_minimum_size.y >= 48.0, "%s has a mobile-sized touch target." % button.name)

	var catalog := load(CATALOG_PATH) as ContentCatalog
	var tuning := load(TUNING_PATH) as MvpTuning
	var state := GameState.create_new(int(Time.get_unix_time_from_system()), tuning)
	state.coins = 1000
	var emitted: Dictionary = {}
	stall.buy_plant_requested.connect(func(variant_id: StringName) -> void: emitted[&"buy"] = variant_id)
	stall.sell_plant_requested.connect(func(instance_id: String) -> void: emitted[&"sell"] = instance_id)
	stall.jar_action_requested.connect(func(jar_id: StringName) -> void: emitted[&"jar"] = jar_id)
	stall.environment_action_requested.connect(func(environment_id: StringName) -> void: emitted[&"place"] = environment_id)
	stall.refresh(state, catalog, tuning, catalog.get_jar(state.active_jar_id).capacity)
	stall.open_panel()
	await process_frame
	await process_frame

	_expect(collection_rows.get_child_count() == catalog.plant_variants.size(), "Collection creates one reusable card for each variant.")
	_expect(collection_rows.columns == 2, "Reference-width Collection uses two columns.")
	_expect(collection_rows.get_child(0) is StallItemCard, "Collection entries use the reusable StallItemCard scene.")

	market_button.pressed.emit()
	_expect(secondary_navigation.visible and market_segments.visible, "Market opens its Buy/Sell segmented control.")
	_expect(not customize_segments.visible and tabs.current_tab == 1, "Market defaults to the Buy page.")
	sell_button.pressed.emit()
	_expect(tabs.current_tab == 2, "Sell selects the Sell page without exposing native tabs.")
	customize_button.pressed.emit()
	_expect(secondary_navigation.visible and customize_segments.visible, "Customize opens its Jars/Places segmented control.")
	_expect(not market_segments.visible and tabs.current_tab == 3, "Customize defaults to the Jars page.")
	places_button.pressed.emit()
	_expect(tabs.current_tab == 4, "Places selects the environment page.")

	market_button.pressed.emit()
	var buy_rows := stall.get_node("%BuyRows") as VBoxContainer
	_press_card_action(buy_rows.get_child(0) as StallItemCard)
	_expect(emitted.get(&"buy", &"") == &"base_common", "Buy cards preserve the public plant request signal.")
	sell_button.pressed.emit()
	var sell_rows := stall.get_node("%SellRows") as VBoxContainer
	_press_card_action(sell_rows.get_child(0) as StallItemCard)
	_expect(emitted.get(&"sell", "") == state.plants[0].instance_id, "Sell cards preserve the public instance request signal.")
	customize_button.pressed.emit()
	var jar_rows := stall.get_node("%JarRows") as VBoxContainer
	_press_card_action(jar_rows.get_child(1) as StallItemCard)
	_expect(emitted.get(&"jar", &"") == &"moss_glass", "Jar cards preserve the public jar request signal.")
	places_button.pressed.emit()
	var environment_rows := stall.get_node("%EnvironmentRows") as VBoxContainer
	_press_card_action(environment_rows.get_child(1) as StallItemCard)
	_expect(emitted.get(&"place", &"") == &"indoor_window", "Place cards preserve the public environment request signal.")

	collection_button.pressed.emit()
	_expect(not secondary_navigation.visible and tabs.current_tab == 0, "Collection hides secondary navigation.")

	var narrow_viewport := SubViewport.new()
	narrow_viewport.size = Vector2i(480, 900)
	root.add_child(narrow_viewport)
	var narrow_stall := packed_scene.instantiate() as StallPanel
	narrow_viewport.add_child(narrow_stall)
	narrow_stall.refresh(state, catalog, tuning, catalog.get_jar(state.active_jar_id).capacity)
	narrow_stall.open_panel()
	await process_frame
	await process_frame
	await process_frame
	var narrow_collection_rows := narrow_stall.get_node("%CollectionRows") as GridContainer
	_expect(narrow_collection_rows.columns == 1, "Narrow Collection collapses to one column.")
	var narrow_header_row := narrow_stall.get_node("%HeaderRow") as HBoxContainer
	var compact_summary_slot := narrow_stall.get_node("%CompactSummarySlot") as CenterContainer
	var narrow_summary_badge := narrow_stall.get_node("%SummaryBadge") as PanelContainer
	_expect(narrow_summary_badge.get_parent() == compact_summary_slot, "Narrow header moves its summary below the title row.")
	_expect(narrow_header_row.get_combined_minimum_size().x <= narrow_header_row.size.x, "Narrow header does not require horizontal overflow.")
	var narrow_market_button := narrow_stall.get_node("%MarketButton") as Button
	narrow_market_button.pressed.emit()
	await process_frame
	var narrow_buy_rows := narrow_stall.get_node("%BuyRows") as VBoxContainer
	if narrow_buy_rows.get_child_count() > 0:
		var first_buy_card := narrow_buy_rows.get_child(0) as StallItemCard
		_expect(first_buy_card != null and first_buy_card.is_compact_layout(), "Narrow action cards move their button below the content.")
	else:
		_expect(false, "The default discovered plant creates a Buy card.")

	var safe_insets := SafeAreaContainer.calculate_safe_insets(
		Vector2i(1000, 2000),
		Vector2i.ZERO,
		Rect2i(0, 100, 1000, 1800),
		Vector2(500, 1000),
	)
	_expect(safe_insets.is_equal_approx(Vector4(0, 50, 0, 50)), "Safe-area pixels convert into viewport-space margins.")
	await _test_scaled_text_accessibility(packed_scene, state, catalog, tuning)

	narrow_viewport.queue_free()
	stall.queue_free()
	await process_frame
	if _failures == 0:
		print("Stall UI tests passed.")
		quit(0)
	else:
		push_error("Stall UI tests failed: %d" % _failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func _press_card_action(card: StallItemCard) -> void:
	var wide_button := card.get_node("%WideActionButton") as Button
	var compact_button := card.get_node("%CompactActionButton") as Button
	var action_button: Button = wide_button if wide_button.visible else compact_button
	action_button.pressed.emit()


func _test_scaled_text_accessibility(
	packed_scene: PackedScene,
	state: GameState,
	catalog: ContentCatalog,
	tuning: MvpTuning,
) -> void:
	var viewport_size := Vector2i(640, 1136)
	var viewport := SubViewport.new()
	viewport.name = "ScaledTextStallViewport"
	viewport.size = viewport_size
	root.add_child(viewport)
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var stall := packed_scene.instantiate() as StallPanel
	viewport.add_child(stall)
	stall.refresh(state, catalog, tuning, catalog.get_jar(state.active_jar_id).capacity)
	stall.open_panel()
	await process_frame
	await process_frame
	_scale_ui_text(stall, 1.40)
	await process_frame
	await process_frame
	await process_frame

	var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var modal := stall.get_node("SafeMargin/Modal") as PanelContainer
	var header := stall.get_node("SafeMargin/Modal/ContentMargin/Layout/Header") as PanelContainer
	var header_row := stall.get_node("%HeaderRow") as HBoxContainer
	var title := stall.get_node("SafeMargin/Modal/ContentMargin/Layout/Header/HeaderMargin/HeaderStack/HeaderRow/TitleStack/Title") as Label
	var subtitle := stall.get_node("SafeMargin/Modal/ContentMargin/Layout/Header/HeaderMargin/HeaderStack/HeaderRow/TitleStack/Subtitle") as Label
	var summary := stall.get_node("%Summary") as Label
	var close_button := stall.get_node("%CloseButton") as Button
	_expect(_contains_rect(viewport_rect, modal.get_global_rect()), "The 40%-enlarged Stall remains inside 640x1136.")
	_expect(header_row.get_combined_minimum_size().x <= header_row.size.x + 1.0, "The enlarged Stall header does not require horizontal overflow.")
	_expect_text_control_fits(title, "Enlarged Stall title")
	_expect_text_control_fits(subtitle, "Enlarged Stall subtitle")
	_expect_text_control_fits(summary, "Enlarged Stall summary")
	_expect_text_control_fits(close_button, "Enlarged Stall close action")
	_expect(
		header.get_global_rect().end.y
			<= (stall.get_node("SafeMargin/Modal/ContentMargin/Layout/PrimaryNavigation") as Control).get_global_rect().position.y + 1.0,
		"The enlarged header does not crowd the primary navigation.",
	)

	var collection_button := stall.get_node("%CollectionButton") as Button
	var market_button := stall.get_node("%MarketButton") as Button
	var customize_button := stall.get_node("%CustomizeButton") as Button
	var buy_button := stall.get_node("%BuyButton") as Button
	var sell_button := stall.get_node("%SellButton") as Button
	var jars_button := stall.get_node("%JarsButton") as Button
	var places_button := stall.get_node("%PlacesButton") as Button
	var primary_segments := stall.get_node(
		"SafeMargin/Modal/ContentMargin/Layout/PrimaryNavigation/PrimaryNavigationMargin/PrimarySegments"
	) as HBoxContainer
	var market_segments := stall.get_node("%MarketSegments") as HBoxContainer
	var customize_segments := stall.get_node("%CustomizeSegments") as HBoxContainer
	_expect_navigation_group_fits(
		primary_segments,
		[collection_button, market_button, customize_button],
		"enlarged primary navigation",
	)

	collection_button.pressed.emit()
	await process_frame
	_expect_stall_sections_do_not_overlap(stall, false, "Collection")
	_expect_scroll_has_no_horizontal_overflow(
		stall.get_node("SafeMargin/Modal/ContentMargin/Layout/Tabs/Collection") as ScrollContainer,
		stall.get_node("%CollectionRows") as Container,
		"Collection",
	)
	_expect_first_visible_card_text(stall.get_node("%CollectionRows") as Container, "Collection")

	market_button.pressed.emit()
	await process_frame
	_expect_navigation_group_fits(market_segments, [buy_button, sell_button], "enlarged Market navigation")
	_expect_stall_sections_do_not_overlap(stall, true, "Market / Buy")
	_expect_scroll_has_no_horizontal_overflow(
		stall.get_node("SafeMargin/Modal/ContentMargin/Layout/Tabs/Buy Plants") as ScrollContainer,
		stall.get_node("%BuyRows") as Container,
		"Buy",
	)
	_expect_first_visible_card_text(stall.get_node("%BuyRows") as Container, "Buy")

	sell_button.pressed.emit()
	await process_frame
	_expect_stall_sections_do_not_overlap(stall, true, "Market / Sell")
	_expect_scroll_has_no_horizontal_overflow(
		stall.get_node("SafeMargin/Modal/ContentMargin/Layout/Tabs/Sell Plants") as ScrollContainer,
		stall.get_node("%SellRows") as Container,
		"Sell",
	)
	_expect_first_visible_card_text(stall.get_node("%SellRows") as Container, "Sell")

	customize_button.pressed.emit()
	await process_frame
	_expect_navigation_group_fits(customize_segments, [jars_button, places_button], "enlarged Customize navigation")
	_expect_stall_sections_do_not_overlap(stall, true, "Customize / Jars")
	_expect_scroll_has_no_horizontal_overflow(
		stall.get_node("SafeMargin/Modal/ContentMargin/Layout/Tabs/Jars") as ScrollContainer,
		stall.get_node("%JarRows") as Container,
		"Jars",
	)
	_expect_first_visible_card_text(stall.get_node("%JarRows") as Container, "Jars")

	places_button.pressed.emit()
	await process_frame
	_expect_stall_sections_do_not_overlap(stall, true, "Customize / Places")
	_expect_scroll_has_no_horizontal_overflow(
		stall.get_node("SafeMargin/Modal/ContentMargin/Layout/Tabs/Environments") as ScrollContainer,
		stall.get_node("%EnvironmentRows") as Container,
		"Places",
	)
	_expect_first_visible_card_text(stall.get_node("%EnvironmentRows") as Container, "Places")

	viewport.queue_free()
	TranslationServer.set_locale(original_locale)
	await process_frame
	await process_frame


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


func _expect_navigation_group_fits(
	segments: HBoxContainer,
	buttons: Array,
	description: String,
) -> void:
	_expect(
		segments.get_combined_minimum_size().x <= segments.size.x + 1.0,
		"The %s does not require horizontal overflow." % description,
	)
	var segments_rect := segments.get_global_rect()
	var previous_end_x := segments_rect.position.x
	for raw_button in buttons:
		var button := raw_button as Button
		var button_rect := button.get_global_rect()
		_expect(_contains_rect(segments_rect, button_rect), "%s keeps %s inside its rail." % [description.capitalize(), button.text])
		_expect(button_rect.position.x + 1.0 >= previous_end_x, "%s buttons do not overlap." % description.capitalize())
		_expect_text_control_fits(button, "%s %s" % [description.capitalize(), button.text])
		previous_end_x = button_rect.end.x


func _expect_stall_sections_do_not_overlap(
	stall: StallPanel,
	secondary_visible: bool,
	description: String,
) -> void:
	var primary := stall.get_node("SafeMargin/Modal/ContentMargin/Layout/PrimaryNavigation") as Control
	var secondary := stall.get_node("%SecondaryNavigation") as Control
	var tabs := stall.get_node("SafeMargin/Modal/ContentMargin/Layout/Tabs") as Control
	_expect(secondary.visible == secondary_visible, "%s exposes the expected navigation level." % description)
	if secondary_visible:
		_expect(primary.get_global_rect().end.y <= secondary.get_global_rect().position.y + 1.0, "%s primary and secondary navigation do not overlap." % description)
		_expect(secondary.get_global_rect().end.y <= tabs.get_global_rect().position.y + 1.0, "%s secondary navigation does not crowd the content." % description)
	else:
		_expect(primary.get_global_rect().end.y <= tabs.get_global_rect().position.y + 1.0, "%s primary navigation does not crowd the content." % description)


func _expect_scroll_has_no_horizontal_overflow(
	scroll: ScrollContainer,
	content: Container,
	description: String,
) -> void:
	_expect(
		scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"%s keeps horizontal scrolling disabled at 140%% text." % description,
	)
	_expect(not scroll.get_h_scroll_bar().visible, "%s does not expose a horizontal scrollbar at 140%% text." % description)
	_expect(scroll.scroll_horizontal == 0, "%s has no horizontal scroll offset at 140%% text." % description)
	_expect(
		content.get_combined_minimum_size().x <= scroll.size.x + 1.0,
		"%s content fits the ScrollContainer width at 140%% text (minimum=%s, scroll=%s)." % [
			description,
			content.get_combined_minimum_size(),
			scroll.size,
		],
	)
	_expect(content.size.x <= scroll.size.x + 1.0, "%s content has no hidden horizontal overflow at 140%% text." % description)


func _expect_first_visible_card_text(container: Container, description: String) -> void:
	if container.get_child_count() == 0:
		_expect(false, "%s has a card for enlarged-text validation." % description)
		return
	var card := container.get_child(0) as StallItemCard
	if card == null:
		_expect(false, "%s uses a StallItemCard for enlarged-text validation." % description)
		return
	for node_name in ["CollectionTitle", "ListTitle", "WideActionButton", "CompactActionButton"]:
		var control := card.get_node("%%%s" % node_name) as Control
		if control.is_visible_in_tree():
			_expect_text_control_fits(control, "%s first-card %s" % [description, node_name])


func _expect_text_control_fits(control: Control, description: String) -> void:
	var minimum := control.get_combined_minimum_size()
	_expect(
		minimum.x <= control.size.x + 1.0 and minimum.y <= control.size.y + 1.0,
		"%s is not clipped (minimum=%s, actual=%s)." % [description, minimum, control.size],
	)
	if control is Label:
		var label := control as Label
		if label.max_lines_visible > 0:
			_expect(
				label.get_line_count() <= label.max_lines_visible,
				"%s fits within its configured line limit (%d/%d)." % [
					description,
					label.get_line_count(),
					label.max_lines_visible,
				],
			)


func _contains_rect(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(1.0).encloses(inner)
