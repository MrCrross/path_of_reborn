class_name CombatResultView
extends PanelContainer

signal claim_requested
signal choice_requested(entry_id: String, action: String)
signal item_requested(item_id: String, aspect_id: String, quantity: int)

const XP_COLOR := Color("9fd18a")
const SWIPE_THRESHOLD: float = 18.0
const SWIPE_VERTICAL_LIMIT: float = 10.0

var rows: VBoxContainer
var claim_button: Button
var scroll: ScrollContainer
var card: PanelContainer
var store_button: Button
var equip_button: Button
var detail_button: Button
var _session: GameSession
var _result: Dictionary = {}
var _entry: Dictionary = {}
var _model: Dictionary = {}
var _processing: bool = false
var _pointer: Dictionary = {}
var _origin: Vector2 = Vector2.ZERO
var _drag: Vector2 = Vector2.ZERO
var _axis: String = ""

func _ready() -> void:
	theme_type_variation = &"HudPanel"
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 24)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.add_child(scroll)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 1)
	scroll.add_child(rows)
	card = PanelContainer.new()
	card.name = "RewardCard"
	card.theme_type_variation = &"EquipmentPanel"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	card.gui_input.connect(_on_card_input)
	column.add_child(card)
	var hints := Label.new()
	hints.name = "SwipeHints"
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hints.clip_text = true
	hints.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hints.add_theme_font_size_override("font_size", 7)
	hints.add_theme_color_override("font_color", AppTheme.COLOR_TEXT_DIM)
	column.add_child(hints)
	# Основные действия — жестами по карточке: tap/влево «Взять», вправо «Надеть».
	# Кнопки остаются невидимыми программными якорями для клавиатурного доступа.
	var actions := HBoxContainer.new()
	actions.visible = false
	column.add_child(actions)
	store_button = Button.new()
	store_button.text = "Взять"
	store_button.accessibility_name = "Взять"
	store_button.custom_minimum_size = Vector2(0, 30)
	store_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	store_button.pressed.connect(_choose.bind("store"))
	store_button.hide()
	store_button.focus_mode = Control.FOCUS_NONE
	actions.add_child(store_button)
	equip_button = Button.new()
	equip_button.text = "Надеть"
	equip_button.accessibility_name = "Надеть"
	equip_button.custom_minimum_size = Vector2(0, 30)
	equip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_button.theme_type_variation = &"PrimaryButton"
	equip_button.pressed.connect(_choose.bind("equip"))
	equip_button.hide()
	equip_button.focus_mode = Control.FOCUS_NONE
	actions.add_child(equip_button)
	detail_button = Button.new()
	detail_button.text = "i"
	detail_button.accessibility_name = "Подробнее о находке"
	detail_button.custom_minimum_size = Vector2(24, 24)
	detail_button.add_theme_font_size_override("font_size", 9)
	detail_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	detail_button.pressed.connect(_open_details)
	column.add_child(detail_button)
	claim_button = Button.new()
	claim_button.name = "ClaimButton"
	claim_button.custom_minimum_size = Vector2(0, 30)
	claim_button.theme_type_variation = &"PrimaryButton"
	claim_button.add_theme_font_size_override("font_size", 9)
	claim_button.text = "Повторить получение"
	claim_button.tooltip_text = "Повторить запись того же результата"
	claim_button.accessibility_name = claim_button.tooltip_text
	claim_button.pressed.connect(func() -> void: claim_requested.emit())
	claim_button.hide()
	column.add_child(claim_button)

func present(session: GameSession, result: Dictionary) -> void:
	_session = session
	_result = result
	_processing = false
	_pointer = {}
	_axis = ""
	claim_button.hide()
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for child: Node in card.get_children():
		card.remove_child(child)
		child.queue_free()
	_entry = _next_entry()
	var xp: int = int(result.get("xp", 0))
	if xp > 0:
		rows.add_child(_line("+%d XP" % xp, XP_COLOR))
		var preview: Dictionary = session.hero.preview_level_gain(xp)
		if int(preview.get("levels_gained", 0)) > 0:
			rows.add_child(_line("Уровень %d · выбор на Тропе" % int(preview.get("level", 0)), AppTheme.COLOR_ACCENT))
	var echoes: int = int(result.get("echo_gained", false)) + int(result.get("trial_echo_gained", false))
	if echoes > 0:
		rows.add_child(_line("+%d Эхо · счётчик" % echoes, AppTheme.COLOR_MAGIC))
	if _entry.is_empty():
		return
	_build_card()
	var remaining: int = 0
	for entry: Dictionary in result.get("items", []):
		if not result.get("choices", {}).has(entry.get("entry_id", "")):
			remaining += 1
	var hints: Label = get_node("SwipeHints") if has_node("SwipeHints") else null
	if hints == null:
		hints = find_child("SwipeHints", true, false) as Label
	if hints != null:
		var hint_text: String = "tap или влево — Взять"
		if equip_button.visible:
			hint_text += "\nвправо — Надеть"
		hints.text = "%s · осталось %d" % [hint_text, remaining]
	show()
	card.grab_focus()

func _build_card() -> void:
	var item_id: String = String(_entry.get("item_id", ""))
	var aspect_id: String = String(_entry.get("aspect_id", ""))
	var quantity: int = int(_entry.get("quantity", 1))
	_model = EquipmentModel.for_reward(_session, item_id, aspect_id, quantity, _entry)
	var definition: ItemDefinition = _model["definition"]
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)
	var title: String = definition.display_name if quantity <= 1 else "%s ×%d" % [definition.display_name, quantity]
	var name_label := _card_label(column, title, 10, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.accessibility_name = title
	var icon := TextureRect.new()
	icon.texture = ArtMap.item_icon(item_id, aspect_id)
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(icon)
	if definition.slot_id.is_empty():
		var total: int = int(_entry.get("sale_price_copper", definition.sale_price_copper)) * quantity
		_card_label(column, "Цена: %s" % UiText.astra(total), 9, HORIZONTAL_ALIGNMENT_CENTER)
	elif _model.get("current_item") == null:
		for bonus: Dictionary in _model.get("bonuses", []):
			_card_label(column, "%s %+d" % [bonus["label"], int(bonus["amount"])], 9, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		for delta: Dictionary in _model.get("deltas", []):
			var difference: int = int(delta["after"]) - int(delta["before"])
			var lower_better: bool = definition.lower_is_better_stats.has(String(delta["stat_id"]))
			var improved: bool = difference < 0 if lower_better else difference > 0
			var arrow: String = "=" if difference == 0 else ("↑" if improved else "↓")
			var label := _card_label(column, "%s %d  %s" % [delta["label"], int(delta["after"]), arrow], 9, HORIZONTAL_ALIGNMENT_CENTER)
			label.add_theme_color_override("font_color", AppTheme.COLOR_TEXT_DIM.darkened(0.5) if difference == 0 else (AppTheme.COLOR_HERO_HP.darkened(0.5) if improved else AppTheme.COLOR_DANGER.darkened(0.35)))
	card.accessibility_name = "Находка: касание или влево — Взять%s" % (", вправо — Надеть" if not definition.slot_id.is_empty() else "")
	card.tooltip_text = card.accessibility_name
	store_button.disabled = false
	equip_button.visible = not definition.slot_id.is_empty()
	equip_button.disabled = not equip_button.visible
	detail_button.disabled = false

func _next_entry() -> Dictionary:
	for entry: Dictionary in _result.get("items", []):
		if not _result.get("choices", {}).has(entry.get("entry_id", "")):
			return entry
	return {}

func _choose(action: String) -> void:
	if _processing or _entry.is_empty():
		return
	if action == "equip" and not equip_button.visible:
		return
	_processing = true
	store_button.disabled = true
	equip_button.disabled = true
	detail_button.disabled = true
	choice_requested.emit(String(_entry["entry_id"]), action)

func _open_details() -> void:
	if _processing or _entry.is_empty():
		return
	item_requested.emit(String(_entry["item_id"]), String(_entry["aspect_id"]), int(_entry["quantity"]))

func _on_card_input(event: InputEvent) -> void:
	if _processing or _entry.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("primary"):
			get_viewport().set_input_as_handled()
			_choose("store")
		elif event.is_action("secondary") and equip_button.visible:
			get_viewport().set_input_as_handled()
			_choose("equip")
		return
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
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

func fit_to_view(view_height: float) -> void:
	var height: float = clampf(164.0, 132.0, maxf(132.0, view_height - 92.0))
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_bottom = -2.0
	offset_top = offset_bottom - height

func show_write_error() -> void:
	_processing = false
	claim_button.text = "Не удалось сохранить. Повторить"
	claim_button.show()
	store_button.disabled = true
	equip_button.disabled = true
	show()
	claim_button.grab_focus()

func _card_label(parent: Node, text: String, font_size: int, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", AppTheme.COLOR_ACCENT_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _line(text: String, color: Color) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
