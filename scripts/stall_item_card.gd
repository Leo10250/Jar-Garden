class_name StallItemCard
extends PanelContainer


const COMPACT_ACTION_BREAKPOINT: float = 520.0
const COLLECTION_CARD_HEIGHT: float = 238.0
const LIST_CARD_HEIGHT: float = 126.0
const COMPACT_LIST_CARD_HEIGHT: float = 202.0

@onready var collection_layout: VBoxContainer = %CollectionLayout
@onready var collection_preview: CenterContainer = %CollectionPreview
@onready var collection_title: Label = %CollectionTitle
@onready var collection_subtitle: Label = %CollectionSubtitle
@onready var list_layout: VBoxContainer = %ListLayout
@onready var list_preview: CenterContainer = %ListPreview
@onready var list_title: Label = %ListTitle
@onready var list_subtitle: Label = %ListSubtitle
@onready var wide_action_button: Button = %WideActionButton
@onready var compact_action_button: Button = %CompactActionButton

var _preview: Control
var _title: String = ""
var _subtitle: String = ""
var _action_text: String = ""
var _action_disabled: bool = false
var _action: Callable = Callable()
var _collection_mode: bool = false
var _is_configured: bool = false
var _is_compact: bool = false


func _ready() -> void:
	wide_action_button.pressed.connect(_invoke_action)
	compact_action_button.pressed.connect(_invoke_action)
	resized.connect(_apply_responsive_layout)
	if _is_configured:
		_apply_configuration()
	else:
		_apply_responsive_layout()


func configure(
	preview: Control,
	title: String,
	subtitle: String,
	action_text: String = "",
	action_disabled: bool = false,
	action: Callable = Callable(),
	collection_mode: bool = false,
) -> void:
	_preview = preview
	_title = title
	_subtitle = subtitle
	_action_text = action_text
	_action_disabled = action_disabled
	_action = action
	_collection_mode = collection_mode
	_is_configured = true
	if is_node_ready():
		_apply_configuration()


func is_compact_layout() -> bool:
	return _is_compact


func _apply_configuration() -> void:
	collection_layout.visible = _collection_mode
	list_layout.visible = not _collection_mode
	collection_title.text = _title
	collection_subtitle.text = _subtitle
	list_title.text = _title
	list_subtitle.text = _subtitle
	wide_action_button.text = _action_text
	compact_action_button.text = _action_text
	wide_action_button.disabled = _action_disabled
	compact_action_button.disabled = _action_disabled

	var preview_host: CenterContainer = collection_preview if _collection_mode else list_preview
	for child in collection_preview.get_children():
		if child != _preview:
			child.queue_free()
	for child in list_preview.get_children():
		if child != _preview:
			child.queue_free()
	if _preview != null and _preview.get_parent() != preview_host:
		if _preview.get_parent() != null:
			_preview.reparent(preview_host)
		else:
			preview_host.add_child(_preview)
	_apply_responsive_layout()


func _apply_responsive_layout() -> void:
	if not is_node_ready():
		return
	if _collection_mode:
		_is_compact = false
		custom_minimum_size = Vector2(0.0, COLLECTION_CARD_HEIGHT)
		wide_action_button.hide()
		compact_action_button.hide()
		return

	var has_action := not _action_text.is_empty()
	_is_compact = has_action and size.x > 0.0 and size.x < COMPACT_ACTION_BREAKPOINT
	wide_action_button.visible = has_action and not _is_compact
	compact_action_button.visible = has_action and _is_compact
	custom_minimum_size = Vector2(
		0.0,
		COMPACT_LIST_CARD_HEIGHT if _is_compact else LIST_CARD_HEIGHT,
	)


func _invoke_action() -> void:
	if _action_disabled or not _action.is_valid():
		return
	_action.call()

