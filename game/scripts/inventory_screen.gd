extends Control

signal navigate_requested(destination: String)

var session: GameSession
var filter_id: String = ""

@onready var stats_text: Label = %StatsText
@onready var upgrade_row: HBoxContainer = %UpgradeRow
@onready var strength_upgrade: Button = %StrengthUpgrade
@onready var hp_upgrade: Button = %HpUpgrade
@onready var format_option: OptionButton = %FormatOption
@onready var type_filter: OptionButton = %TypeFilter
@onready var items_list: GridContainer = %ItemsList
@onready var details_layer: Control = %DetailsLayer
@onready var empty_label: Label = %EmptyLabel
@onready var equipment_strip: EquipmentStrip = %EquipmentStrip
@onready var details: ItemDetailsView = %Details
@onready var detail_icon: TextureRect = details.icon_rect
@onready var detail_name: Label = details.name_label
@onready var equipped_badge: Label = details.equipped_badge
@onready var detail_meta: Label = details.meta_label
@onready var detail_description: Label = details.description_label
@onready var detail_compare: Label = details.compare_label
@onready var equip_action: Button = details.action_button
@onready var detail_close: Button = details.close_button
@onready var back_button: Button = %BackButton
@onready var receive_fx: TextureRect = %ReceiveFx

var _receive_fx_tween: Tween
var _selected_id: String = ""
## Карточки пересобираются только при смене состава/фильтра, а не на каждый тик.
var _built_signature: String = ""
var _focus_guard := ModalFocus.new()

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	if details_layer.visible:
		_close_details()
		return true
	navigate_requested.emit("world")
	return true

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	UiIcons.apply(back_button, "back", "К пути")
	UiIcons.apply(%StatsButton, "info", "Персонажи")
	equipment_strip.configure(session)
	equipment_strip.item_requested.connect(_on_item_pressed)
	equipment_strip.empty_slot_requested.connect(_on_equipment_slot_pressed)
	details.configure(session, true)
	details.close_requested.connect(_close_details)
	details.action_requested.connect(_on_equipment_action)
	type_filter.add_item("Все типы")
	type_filter.add_item("Оружие")
	type_filter.add_item("Амулеты")
	type_filter.add_item("Материалы")
	type_filter.add_item("Кристаллы Эха")
	type_filter.add_item("Сюжетные")
	stats_text.hide()
	upgrade_row.hide()
	format_option.hide()
	_refresh_list()
	_refresh_details()
	if session.pending_receive_fx:
		session.pending_receive_fx = false
		_play_receive_fx()
	back_button.grab_focus()

func _on_filter_selected(index: int) -> void:
	_close_details()
	filter_id = ["", "weapon", "charm", "material", "echo", "quest"][index]
	_built_signature = ""
	_refresh_list()
	_refresh_details()

func _on_back_pressed() -> void:
	navigate_requested.emit("world")

func _on_strength_upgrade_pressed() -> void:
	if session.choose_upgrade("strength"):
		_refresh_stats()
		_refresh_details()

func _on_hp_upgrade_pressed() -> void:
	if session.choose_upgrade("max_hp"):
		_refresh_stats()
		_refresh_details()

func _on_format_selected(index: int) -> void:
	# Смена формата применяется со следующего боя; предпочтение живёт
	# вне Checkpoint и переживает новую игру.
	session.set_combat_format(
		GameSession.COMBAT_FORMAT_ACTIVE if index == 1 else GameSession.COMBAT_FORMAT_AUTO
	)
	_refresh_stats()

func open_item(instance_id: String) -> void:
	_on_item_pressed(instance_id)

func _on_item_pressed(instance_id: String) -> void:
	# Tap открывает подробности; экипировка — только явной кнопкой.
	if session.inventory.get_item(instance_id) == null:
		return
	_selected_id = instance_id
	if not details_layer.visible:
		details_layer.show()
		_focus_guard.capture(details_layer)
	_refresh_details()
	detail_close.grab_focus()

func _on_equipment_slot_pressed(slot_id: String) -> void:
	var index: int = 1 if slot_id == "weapon" else 2
	type_filter.select(index)
	_on_filter_selected(index)

func _on_stats_pressed() -> void:
	navigate_requested.emit("characters")

func _on_details_dismiss(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		_close_details()

func _close_details() -> void:
	details_layer.hide()
	_focus_guard.restore()
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus == null or not focus.is_visible_in_tree():
		back_button.grab_focus()

func _on_detail_close_pressed() -> void:
	_close_details()

func _on_equipment_action(instance_id: String, _slot_id: String, _equipped: bool) -> void:
	_selected_id = instance_id
	_on_equip_action_pressed()

func _on_equip_action_pressed() -> void:
	var item: ItemInstance = session.inventory.get_item(_selected_id)
	if item == null:
		return
	var definition: ItemDefinition = session.get_item_definition(item.definition_id)
	if definition.slot_id.is_empty():
		return
	var changed: bool = false
	if session.inventory.is_equipped(_selected_id):
		changed = session.unequip_item(definition.slot_id)
	else:
		changed = session.equip_item(_selected_id)
	if not changed:
		return
	_built_signature = ""
	_refresh_list()
	if details_layer.visible:
		_focus_guard.capture(details_layer)
	_refresh_details()
	_refresh_stats()

func _refresh_stats() -> void:
	stats_text.hide()
	upgrade_row.hide()
	format_option.hide()

func _refresh_list() -> void:
	var items: Array = session.inventory.filter(filter_id)
	var signature: String = filter_id
	for item: ItemInstance in items:
		signature += "|%s:%d:%s" % [item.instance_id, item.quantity, session.inventory.is_equipped(item.instance_id)]
	if signature == _built_signature:
		return
	_built_signature = signature
	for child: Node in items_list.get_children():
		items_list.remove_child(child)
		child.queue_free()
	for item: ItemInstance in items:
		items_list.add_child(_build_card(item))
	empty_label.visible = items.is_empty()
	if not items.is_empty() and session.inventory.get_item(_selected_id) == null:
		_selected_id = ""

func _build_card(item: ItemInstance) -> Control:
	var definition: ItemDefinition = session.get_item_definition(item.definition_id)
	var card := Button.new()
	card.custom_minimum_size = Vector2(44, 52)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_theme_font_size_override("font_size", 9)
	var icon: Texture2D = ArtMap.item_icon(item.definition_id, item.aspect_id)
	if icon != null:
		card.icon = icon
		card.add_theme_constant_override("icon_max_width", 36)
		card.expand_icon = true
	var equipped: bool = session.inventory.is_equipped(item.instance_id)
	card.text = "?" if icon == null else ""
	card.tooltip_text = "%s · %s%s" % [definition.display_name, UiText.rarity(definition.rarity_id), " · Надето" if equipped else ""]
	card.accessibility_name = card.tooltip_text
	if equipped or item.quantity > 1:
		var badge := Label.new()
		badge.text = "✓" if equipped else str(item.quantity)
		badge.add_theme_font_size_override("font_size", 8)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(3, 1)
		card.add_child(badge)
	if item.instance_id == _selected_id:
		card.theme_type_variation = &"PrimaryButton"
	card.pressed.connect(_on_item_pressed.bind(item.instance_id))
	return card

func _refresh_details() -> void:
	var item: ItemInstance = session.inventory.get_item(_selected_id)
	if item == null:
		details_layer.hide()
		return
	details.present_instance(item.instance_id)

func _play_receive_fx() -> void:
	if _receive_fx_tween != null and _receive_fx_tween.is_valid():
		_receive_fx_tween.kill()
	receive_fx.modulate.a = 0.0
	receive_fx.scale = Vector2(0.6, 0.6)
	receive_fx.show()
	_receive_fx_tween = create_tween().set_parallel(true)
	_receive_fx_tween.tween_property(receive_fx, "modulate:a", 1.0, 0.15)
	_receive_fx_tween.tween_property(receive_fx, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fade := create_tween()
	fade.tween_property(receive_fx, "modulate:a", 0.0, 0.5).set_delay(0.7)
	fade.tween_callback(receive_fx.hide)
