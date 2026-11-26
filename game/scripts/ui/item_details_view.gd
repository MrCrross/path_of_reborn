class_name ItemDetailsView
extends PanelContainer

signal close_requested
signal action_requested(instance_id: String, slot_id: String, equipped: bool)

var session: GameSession
var character_id: String = "haruto"
var allow_actions: bool = false
var model: Dictionary = {}
var icon_rect: TextureRect
var name_label: Label
var equipped_badge: Label
var meta_label: Label
var description_label: Label
var compare_label: Label
var close_button: Button
var action_button: Button
var scroll: ScrollContainer

var _comparison_box: VBoxContainer

func configure(game_session: GameSession, actions_enabled: bool = false, selected_character_id: String = "haruto") -> void:
	session = game_session
	allow_actions = actions_enabled
	character_id = selected_character_id
	if is_node_ready():
		_refresh_action()

func _ready() -> void:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	name_label = _label(top, 10, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button = Button.new()
	UiIcons.apply(close_button, "close", "Закрыть карточку предмета")
	close_button.pressed.connect(func() -> void: close_requested.emit())
	top.add_child(close_button)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 3)
	scroll.add_child(content)
	icon_rect = _icon(content, 40)
	meta_label = _label(content, 8, true)
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equipped_badge = _label(content, 8)
	equipped_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equipped_badge.add_theme_color_override("font_color", AppTheme.COLOR_HERO_HP)
	description_label = _label(content, 8, true)
	_comparison_box = VBoxContainer.new()
	_comparison_box.add_theme_constant_override("separation", 3)
	content.add_child(_comparison_box)
	compare_label = _label(_comparison_box, 8, true)
	action_button = Button.new()
	action_button.custom_minimum_size = Vector2(64, 24)
	action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	action_button.theme_type_variation = &"PrimaryButton"
	action_button.pressed.connect(_on_action_pressed)
	column.add_child(action_button)
	_refresh_action()

func present_instance(instance_id: String) -> bool:
	return present(EquipmentModel.for_instance(session, instance_id, character_id))

func present_reward(item_id: String, aspect_id: String, quantity: int = 1, reward: Dictionary = {}) -> bool:
	return present(EquipmentModel.for_reward(session, item_id, aspect_id, quantity, reward, character_id))

func present(next_model: Dictionary) -> bool:
	if next_model.is_empty():
		return false
	model = next_model
	var definition: ItemDefinition = model["definition"]
	icon_rect.texture = model["icon"]
	icon_rect.visible = icon_rect.texture != null
	name_label.text = definition.display_name
	name_label.accessibility_name = definition.display_name
	equipped_badge.visible = bool(model["equipped"])
	equipped_badge.text = "Надето"
	var parts: Array[String] = ["Ур. %d" % int(model["level"]), UiText.rarity(definition.rarity_id), UiText.item_type(definition.type_id)]
	var aspect_label: String = UiText.aspect(String(model["aspect_id"]))
	if not aspect_label.is_empty():
		parts.append(aspect_label)
	if int(model["quantity"]) > 1:
		parts.append("×%d" % int(model["quantity"]))
	if bool(model["secured"]):
		parts.append("Закреплено")
	meta_label.text = " · ".join(parts)
	description_label.text = definition.description
	for child: Node in _comparison_box.get_children():
		if child != compare_label:
			_comparison_box.remove_child(child)
			child.queue_free()
	compare_label.text = ""
	_comparison_box.visible = true
	if definition.slot_id.is_empty():
		compare_label.text = "Продажа недоступна"
		if bool(model["sellable"]):
			var total: int = int(model["sale_price_copper"]) * int(model["quantity"])
			compare_label.text = "Цена продажи: %s" % UiText.astra(total)
			if int(model["quantity"]) > 1:
				compare_label.text += "\n%s за штуку" % UiText.astra(int(model["sale_price_copper"]))
	elif model["current_item"] == null or bool(model["equipped"]):
		compare_label.text = "Параметры предмета"
		for bonus: Dictionary in model["bonuses"]:
			_stat_line("%s %+d" % [bonus["label"], int(bonus["amount"])], AppTheme.COLOR_TEXT)
		if model["bonuses"].is_empty():
			_stat_line("Без модификаторов", AppTheme.COLOR_TEXT_DIM)
	else:
		compare_label.text = "Сейчас → после замены"
		for delta: Dictionary in model["deltas"]:
			var difference: int = int(delta["after"]) - int(delta["before"])
			var lower_better: bool = definition.lower_is_better_stats.has(String(delta["stat_id"]))
			var improved: bool = difference < 0 if lower_better else difference > 0
			var color: Color = AppTheme.COLOR_TEXT
			var marker: String = "="
			if difference != 0:
				marker = ("↑ +" if improved else "↓ −") + str(absi(difference))
				color = AppTheme.COLOR_HERO_HP if improved else AppTheme.COLOR_DANGER
			_stat_line("%s %d → %d  %s" % [delta["label"], int(delta["before"]), int(delta["after"]), marker], color)
		if model["deltas"].is_empty():
			_stat_line("Характеристики без изменений", AppTheme.COLOR_TEXT)
	_refresh_action()
	scroll.scroll_vertical = 0
	return true

func _refresh_action() -> void:
	if action_button == null:
		return
	var can_act: bool = allow_actions and not model.is_empty() and session != null and not session.in_combat and not session.awaiting_return and not session.has_pending_reward()
	action_button.visible = can_act and not String(model.get("slot_id", "")).is_empty()
	action_button.text = "Снять" if bool(model.get("equipped", false)) else "Надеть"
	action_button.accessibility_name = "%s: %s" % [action_button.text, name_label.text if name_label != null else "предмет"]

func _stat_line(text: String, color: Color) -> void:
	var label := _label(_comparison_box, 9, true)
	label.text = text
	label.add_theme_color_override("font_color", color)

func _on_action_pressed() -> void:
	if model.is_empty():
		return
	action_requested.emit(String(model["instance_id"]), String(model["slot_id"]), bool(model["equipped"]))

func _label(parent: Node, font_size: int, multiline: bool = false) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if multiline else TextServer.AUTOWRAP_OFF
	parent.add_child(label)
	return label

func _icon(parent: Node, extent: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(extent, extent)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon
