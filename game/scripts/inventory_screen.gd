extends Control

signal navigate_requested(destination: String)

var session: GameSession
var filter_id: String = ""

@onready var type_filter: OptionButton = %TypeFilter
@onready var items_list: GridContainer = %ItemsList
@onready var details_layer: ItemDetailsOverlay = %DetailsLayer
@onready var empty_label: Label = %EmptyLabel
@onready var equipment_strip: EquipmentStrip = %EquipmentStrip
@onready var details: ItemDetailsView = details_layer.view
@onready var detail_compare: Label = details.compare_label
@onready var equip_action: Button = details.action_button
@onready var detail_close: Button = details.close_button
@onready var back_button: Button = %BackButton
@onready var receive_fx: TextureRect = %ReceiveFx

var _receive_fx_tween: Tween
var _focused_card_id: String = ""

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	if details_layer.visible:
		details_layer.dismiss()
		return true
	navigate_requested.emit("world")
	return true

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	UiIcons.apply(back_button, "back", "К пути")
	UiIcons.apply_texture(%StatsButton, ArtMap.texture(ArtMap.UI["characters"]), "Персонажи")
	equipment_strip.configure(session)
	equipment_strip.item_requested.connect(_on_item_pressed)
	equipment_strip.empty_slot_requested.connect(_on_equipment_slot_pressed)
	equipment_strip.familiar_requested.connect(func(_character_id: String) -> void: navigate_requested.emit("hero_profile"))
	details.configure(session, true)
	details_layer.dismissed.connect(_restore_card_focus)
	details.action_requested.connect(_on_equipment_action)
	_add_filter("", "Все типы")
	for type_id: String in UiText.TYPE_LABELS:
		_add_filter(type_id, UiText.item_type(type_id))
	_refresh_list()
	if session.pending_receive_fx:
		session.pending_receive_fx = false
		_play_receive_fx()
	back_button.grab_focus()

func _add_filter(id: String, caption: String) -> int:
	type_filter.add_item(caption)
	var index: int = type_filter.item_count - 1
	type_filter.set_item_metadata(index, id)
	return index

func _on_filter_selected(index: int) -> void:
	details_layer.dismiss()
	filter_id = type_filter.get_item_metadata(index)
	_refresh_list()

func open_item(instance_id: String) -> void:
	_on_item_pressed(instance_id)

func _on_item_pressed(instance_id: String) -> void:
	var opener: Control = get_viewport().gui_get_focus_owner()
	if not details_layer.visible:
		_focused_card_id = instance_id if opener != null and opener.get_parent() == items_list else ""
	details_layer.open_instance(instance_id)

func _on_equipment_slot_pressed(slot_id: String) -> void:
	for index: int in range(type_filter.item_count):
		if type_filter.get_item_metadata(index) == slot_id:
			type_filter.select(index)
			_on_filter_selected(index)
			return
	# Empty slots can precede the first authored item for that slot.
	var index: int = _add_filter(slot_id, UiText.slot(slot_id))
	type_filter.select(index)
	_on_filter_selected(index)

func _on_stats_pressed() -> void:
	navigate_requested.emit("characters")

func _restore_card_focus() -> void:
	if not _focused_card_id.is_empty():
		for card: Button in items_list.get_children():
			if card.get_meta("instance_id") == _focused_card_id:
				card.grab_focus()
				break
		_focused_card_id = ""
	if get_viewport().gui_get_focus_owner() == null:
		back_button.grab_focus()

func _on_equipment_action(instance_id: String, slot_id: String, equipped: bool) -> void:
	var changed: bool = session.unequip_item(slot_id) if equipped else session.equip_item(instance_id)
	if changed:
		_refresh_list()
		details_layer.isolate_focus()
		details.present_instance(instance_id)

func _refresh_list() -> void:
	var items: Array[ItemInstance]
	if EquipmentStrip.SLOT_IDS.has(filter_id):
		for item: ItemInstance in session.inventory.items:
			if session.get_item_definition(item.definition_id).slot_id == filter_id:
				items.append(item)
	else:
		items = session.inventory.filter(filter_id)
	for child: Node in items_list.get_children():
		items_list.remove_child(child)
		child.queue_free()
	for item: ItemInstance in items:
		items_list.add_child(_build_card(item))
	empty_label.visible = items.is_empty()
	empty_label.text = "Рюкзак пуст" if filter_id.is_empty() else "Подходящих предметов пока нет"

func _build_card(item: ItemInstance) -> Control:
	var definition: ItemDefinition = session.get_item_definition(item.definition_id)
	var card := Button.new()
	card.set_meta("instance_id", item.instance_id)
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
	UiIcons.tint(card, Color.WHITE)
	card.pressed.connect(_on_item_pressed.bind(item.instance_id))
	return card


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
