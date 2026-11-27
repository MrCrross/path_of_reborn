class_name CombatResultView
extends PanelContainer

signal claim_requested
signal summary_acknowledged
signal choice_requested(entry_id: String, action: String)
signal item_requested(entry: Dictionary)

const XP_COLOR := Color("9fd18a")
const SWIPE_THRESHOLD: float = 18.0
const SWIPE_VERTICAL_LIMIT: float = 10.0
const CARD_PADDING := 5

var rows: VBoxContainer
var summary_button: Button
var claim_button: Button
var card: PanelContainer
var detail_button: Button
var _summary_panel: PanelContainer
var _detail_anchor: Control
var _session: GameSession
var _entry: Dictionary = {}
var _can_equip: bool = false
var _processing: bool = false
var _pointer: Dictionary = {}
var _origin: Vector2 = Vector2.ZERO
var _drag: Vector2 = Vector2.ZERO
var _axis: String = ""

func _ready() -> void:
	theme_type_variation = &"ArenaPanel"
	minimum_size_changed.connect(_fit_to_content)
	_summary_panel = PanelContainer.new()
	_summary_panel.theme_type_variation = &"HudPanel"
	add_child(_summary_panel)
	var column := _padded_column(_summary_panel)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 1)
	column.add_child(rows)
	summary_button = _action_button("ОК")
	summary_button.pressed.connect(func() -> void: summary_acknowledged.emit())
	column.add_child(summary_button)
	claim_button = _action_button("Готово")
	claim_button.name = "ClaimButton"
	claim_button.custom_minimum_size.x = 42
	claim_button.pressed.connect(func() -> void: claim_requested.emit())
	column.add_child(claim_button)
	_summary_panel.hide()

	card = PanelContainer.new()
	card.name = "RewardCard"
	card.theme_type_variation = &"HudPanel"
	card.focus_mode = Control.FOCUS_ALL
	card.gui_input.connect(_on_card_input)
	add_child(card)
	card.hide()
	detail_button = Button.new()
	UiIcons.apply(detail_button, "info", "Подробнее о находке")
	detail_button.theme_type_variation = &"HudIconButton"
	detail_button.add_theme_constant_override("icon_max_width", 14)
	detail_button.add_theme_color_override("icon_normal_color", Color.WHITE)
	_detail_anchor = Control.new()
	_detail_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_detail_anchor)
	_detail_anchor.add_child(detail_button)
	detail_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	detail_button.offset_left = -26
	detail_button.offset_right = -2
	detail_button.offset_top = 2
	detail_button.offset_bottom = 26
	detail_button.pressed.connect(_open_details)

func present(session: GameSession, result: Dictionary) -> void:
	_session = session
	_entry = {}
	_reset_input()
	_show_summary(summary_button)
	_line(rows, "Итоги боя", AppTheme.COLOR_TEXT, 10)
	_line(rows, "HP %d/%d" % [session.hero.current_hp, session.hero.max_hp], AppTheme.COLOR_HERO_HP)
	var xp: int = int(result.get("xp", 0))
	var echoes: int = session.battle_echo_reward(result)
	_line(rows, "+%d XP   ·   +%d Эхо" % [xp, echoes], AppTheme.COLOR_MAGIC)

func present_guild_report(session: GameSession, reward: Dictionary, title: String = "Первое задание", echo_flag: String = GameSession.GROVE_ECHOES_GRANTED, skill: String = "Точный выпад I") -> void:
	_session = session
	_show_summary(claim_button)
	claim_button.text = "Получить награды"
	_line(rows, title, AppTheme.COLOR_TEXT, 10)
	var xp: int = int(reward.get("xp", 0))
	var echoes: int = int(reward["echoes"]) if not session.memory_flags.get(echo_flag, false) else 0
	if xp > 0 or echoes > 0:
		_line(rows, "+%d XP   ·   +%d Эхо" % [xp, echoes] if xp > 0 else "+%d Эхо" % echoes, AppTheme.COLOR_MAGIC)
	_line(rows, UiText.astra(int(reward["silver"]), GameSession.SILVER) + " астр", AppTheme.COLOR_ACCENT)
	var preview: Dictionary = session.hero.preview_level_gain(xp)
	_line(rows, "Уровень · %d" % int(preview["level"]), XP_COLOR)
	if not skill.is_empty():
		_line(rows, skill, AppTheme.COLOR_TEXT)

func present_next(result: Dictionary) -> bool:
	_reset_input()
	_entry = _next_entry(result)
	if _entry.is_empty():
		_present_progress(int(result.get("xp", 0)))
		return false
	for child: Node in card.get_children():
		if child != _detail_anchor:
			card.remove_child(child)
			child.queue_free()
	_summary_panel.hide()
	_build_card()
	card.show()
	card.grab_focus()
	return true

func can_claim() -> bool:
	return claim_button.is_visible_in_tree()

func _reset_input() -> void:
	_processing = false
	_pointer = {}
	_axis = ""
	_reset_card()

func _show_summary(button: Button) -> void:
	card.hide()
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	summary_button.visible = button == summary_button
	claim_button.visible = button == claim_button
	_summary_panel.show()
	show()
	button.grab_focus()

func _present_progress(xp: int) -> void:
	var hero: CharacterState = _session.hero
	var preview: Dictionary = hero.preview_level_gain(xp)
	var level: int = int(preview["level"])
	var choices: int = int(preview["upgrade_choices"])
	var remaining: int = int(preview["xp_remaining"])
	claim_button.text = "Готово"
	_show_summary(claim_button)
	var heading: String = "Новый уровень · %d" % level if choices > 0 else "Уровень · %d" % level
	_line(rows, heading, AppTheme.COLOR_ACCENT, 10)
	var progress: String = "До ур. %d ост. %d XP" % [level + 1, remaining] if remaining > 0 else "Максимальный уровень"
	_line(rows, progress, XP_COLOR)
	if choices > 0:
		_line(rows, "Выбор ×%d: сила или макс. HP" % choices, AppTheme.COLOR_TEXT)
	for ability: AbilityDefinition in hero.definition.abilities:
		if hero.level < ability.unlock_level and ability.unlock_level <= level:
			_line(rows, "Открыто: %s" % ability.display_name, AppTheme.COLOR_MAGIC)

func _build_card() -> void:
	var item_id: String = String(_entry.get("item_id", ""))
	var aspect_id: String = String(_entry.get("aspect_id", ""))
	var quantity: int = int(_entry.get("quantity", 1))
	var model: Dictionary = EquipmentModel.for_reward(_session, item_id, aspect_id, quantity, _entry)
	var definition: ItemDefinition = model["definition"]
	_can_equip = not definition.slot_id.is_empty()
	var column := _padded_column(card)
	card.move_child(_detail_anchor, -1)
	var title: String = definition.display_name if quantity <= 1 else "%s ×%d" % [definition.display_name, quantity]
	var title_slot := MarginContainer.new()
	title_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_slot.add_theme_constant_override("margin_right", UiIcons.TOUCH_SIZE)
	column.add_child(title_slot)
	var name_label := _line(title_slot, title, AppTheme.COLOR_TEXT, 9, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.custom_minimum_size.y = UiIcons.TOUCH_SIZE - CARD_PADDING
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var item_row := HBoxContainer.new()
	item_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_row.add_theme_constant_override("separation", 6)
	column.add_child(item_row)
	var icon := TextureRect.new()
	icon.texture = ArtMap.item_icon(item_id, aspect_id)
	icon.custom_minimum_size = Vector2(34, 34)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_row.add_child(icon)
	var stats := VBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats.add_theme_constant_override("separation", 0)
	item_row.add_child(stats)
	if not _can_equip:
		var description: String = UiText.item_type(definition.type_id)
		if bool(model["sellable"]):
			var total: int = int(model["sale_price_copper"]) * quantity
			description = "Цена: %s" % UiText.astra(total)
		_line(stats, description, AppTheme.COLOR_TEXT, 9, HORIZONTAL_ALIGNMENT_LEFT)
	elif model.get("current_item") == null:
		for bonus: Dictionary in model.get("bonuses", []):
			_line(stats, "%s %+d" % [bonus["label"], int(bonus["amount"])], AppTheme.COLOR_TEXT, 9, HORIZONTAL_ALIGNMENT_LEFT)
	else:
		for delta: Dictionary in model.get("deltas", []):
			var difference: int = int(delta["after"]) - int(delta["before"])
			var lower_better: bool = definition.lower_is_better_stats.has(String(delta["stat_id"]))
			var improved: bool = difference < 0 if lower_better else difference > 0
			var arrow: String = "=" if difference == 0 else ("↑" if improved else "↓")
			var color: Color = AppTheme.COLOR_TEXT_DIM if difference == 0 else (AppTheme.COLOR_HERO_HP if improved else AppTheme.COLOR_DANGER)
			_line(stats, "%s %d %s" % [delta["label"], int(delta["after"]), arrow], color, 9, HORIZONTAL_ALIGNMENT_LEFT)
	card.tooltip_text = "Касание или влево — взять%s" % (", вправо — надеть" if _can_equip else "")
	card.accessibility_name = "%s. %s" % [title, card.tooltip_text]
	detail_button.disabled = false

func _next_entry(result: Dictionary) -> Dictionary:
	for entry: Dictionary in result.get("items", []):
		if not result.get("choices", {}).has(entry.get("entry_id", "")):
			return entry
	return {}

func _choose(action: String) -> void:
	if _processing or _entry.is_empty():
		return
	if action == "equip" and not _can_equip:
		return
	_processing = true
	detail_button.disabled = true
	choice_requested.emit(String(_entry["entry_id"]), action)

func _open_details() -> void:
	if _processing or _entry.is_empty():
		return
	item_requested.emit(_entry)

func _on_card_input(event: InputEvent) -> void:
	if _processing or _entry.is_empty():
		return
	if event is InputEventKey or event is InputEventJoypadButton:
		if event.is_action_pressed("primary") or event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			_choose("store")
		elif event.is_action_pressed("secondary") and _can_equip:
			get_viewport().set_input_as_handled()
			_choose("equip")
		return
	if event is InputEventMouseButton and (event.device == InputEvent.DEVICE_ID_EMULATION or event.button_index != MOUSE_BUTTON_LEFT):
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var kind: String = "touch" if event is InputEventScreenTouch else "mouse"
		var index: int = event.index if event is InputEventScreenTouch else event.button_index
		if event.pressed:
			if not _pointer.is_empty():
				return
			_pointer = {"kind": kind, "index": index, "device": event.device}
			# Координаты жеста храним во вьюпорте: gui_input даёт локальные
			# точки, а добор жеста в _input — вьюпортные.
			_origin = card.get_global_transform() * event.position
			_drag = Vector2.ZERO
			_axis = ""
			return
		if _pointer.is_empty() or _pointer["kind"] != kind or _pointer["index"] != index or _pointer["device"] != event.device:
			# Второй pointer/чужое отпускание отменяет кандидат: жест одного
			# пальца нельзя подтвердить отпусканием другого.
			if not _pointer.is_empty():
				_pointer = {}
				_axis = ""
				_reset_card()
			return
		_finish_gesture(card.get_global_transform() * event.position, event is InputEventScreenTouch and event.canceled)
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and not _pointer.is_empty():
		var matches: bool = (event is InputEventScreenDrag and _pointer["kind"] == "touch" and event.index == _pointer["index"]) or (event is InputEventMouseMotion and _pointer["kind"] == "mouse")
		if matches:
			_track_drag(card.get_global_transform() * event.position)

func _input(event: InputEvent) -> void:
	# Motion и release могут попасть мимо сдвинувшейся карточки (у мыши нет
	# implicit capture, как у touch), поэтому активный жест добираем здесь.
	# _input вызывается раньше gui_input, повторное отпускание в карточке
	# увидит пустой _pointer и проигнорируется.
	if _pointer.is_empty():
		return
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		var motion_matches: bool = (event is InputEventScreenDrag and _pointer["kind"] == "touch" and event.index == _pointer["index"] and event.device == _pointer["device"]) or (event is InputEventMouseMotion and _pointer["kind"] == "mouse")
		if motion_matches:
			_track_drag(event.position)
	elif event is InputEventScreenTouch or event is InputEventMouseButton:
		var release_matches: bool = (event is InputEventScreenTouch and _pointer["kind"] == "touch" and event.index == _pointer["index"] and event.device == _pointer["device"]) or (event is InputEventMouseButton and _pointer["kind"] == "mouse" and event.button_index == _pointer["index"])
		if release_matches and not event.pressed:
			_finish_gesture(event.position, event is InputEventScreenTouch and event.canceled)

func _track_drag(position: Vector2) -> void:
	_drag = position - _origin
	if _axis.is_empty() and _drag.length() >= 4.0:
		_axis = "horizontal" if absf(_drag.x) > absf(_drag.y) * 1.25 else "vertical"
	if _axis == "vertical" or (_axis == "horizontal" and absf(_drag.y) > SWIPE_VERTICAL_LIMIT and absf(_drag.y) > absf(_drag.x) * 0.75):
		_axis = "vertical"
		_reset_card()
	elif _axis == "horizontal":
		card.position.x = clampf(_drag.x, -28.0, 28.0)

func _finish_gesture(position: Vector2, canceled: bool) -> void:
	_drag = position - _origin
	_pointer = {}
	if not canceled and _axis == "horizontal" and absf(_drag.x) >= SWIPE_THRESHOLD:
		var action: String = "store" if _drag.x < 0 else "equip"
		card.position.x = 0
		_choose(action)
	elif not canceled and _axis.is_empty():
		# Короткое касание карточки — эквивалент явного «Взять».
		card.position.x = 0
		_choose("store")
	else:
		_reset_card()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pointer = {}
		_axis = ""
		if card != null:
			_reset_card()

func _reset_card() -> void:
	card.position.x = 0
	_drag = Vector2.ZERO

func _fit_to_content() -> void:
	var width := 154.0 if card != null and card.visible else 132.0
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = offset_bottom - get_combined_minimum_size().y

func show_write_error() -> void:
	claim_button.text = "Повторить запись"
	claim_button.grab_focus()

func _action_button(text: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(UiIcons.TOUCH_SIZE, UiIcons.TOUCH_SIZE)
	button.theme_type_variation = &"PrimaryButton"
	button.add_theme_font_size_override("font_size", 9)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.text = text
	return button

func _padded_column(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, CARD_PADDING)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)
	return column

func _line(parent: Node, text: String, color: Color, font_size: int = 8, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = alignment
	parent.add_child(label)
	return label
