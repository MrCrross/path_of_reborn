extends Control

signal navigate_requested(destination: String)
signal guild_order_requested(command: String, order_id: String)

var session: GameSession
var initial_order_id: String = ""
var _selected_id: String = ""
var _last_selected_id: String = ""
var _back: Button
var _body: VBoxContainer
var _error: Label

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	var background := TextureRect.new()
	background.texture = ArtMap.texture(ArtMap.BACKGROUNDS["guild_hall"])
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe := SafeArea.new()
	safe.padding = 7
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe)
	var column := VBoxContainer.new()
	safe.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_back = _button(header, "OrderBack", "", handle_back)
	UiIcons.apply(_back, "back", "Назад")
	var heading := PanelContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var title: Label = _label(heading, "Доска заданий", 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var panel := PanelContainer.new()
	column.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 5)
	panel.add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	margin.add_child(_body)
	_selected_id = initial_order_id
	_render()

func handle_back() -> bool:
	if not _selected_id.is_empty():
		_last_selected_id = _selected_id
		_selected_id = ""
		_render()
	else:
		navigate_requested.emit("guild_from_orders")
	return true

func command_committed(command: String) -> void:
	if command == "report":
		_last_selected_id = _selected_id
		_selected_id = ""
	_render()

func command_rejected() -> void:
	_error.text = "Действие не сохранено. Попробуйте ещё раз."
	_error.show()

func _render() -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if _selected_id.is_empty():
		_render_list()
		return
	var order: Dictionary = GuildOrders.definition(_selected_id)
	var rank: String = order["rank"]
	var rule: Dictionary = GuildOrders.rank_rules(rank)
	var active: bool = session.guild_order.get("id") == _selected_id
	_label(_body, "%s · %s" % [rank, order["title"]], 11)
	if active:
		var cleared: int = int(session.guild_order["cleared"])
		var total: int = int(session.guild_order["total"])
		_label(_body, "Бои %d/%d" % [cleared, total], 9)
		var progress := ProgressBar.new()
		progress.show_percentage = false
		progress.custom_minimum_size.y = 4
		progress.max_value = total
		progress.value = cleared
		_body.add_child(progress)
	else:
		var bounds: String = "%d–%d боёв" % [int(rule["min"]), int(rule["max"])]
		_label(_body, "%s · %s" % [GuildOrders.TYPE_LABELS[order["type"]], bounds], 9)
	var stage: Dictionary = session.guild_order_stage() if active else {}
	var focus: Button = _back
	var gear: ItemDefinition = session.get_item_definition(GuildOrders.order_type(order)["reward"])
	_label(_body, "Награда ранга %s\n%s, ур. %d\n%s · %d опыта" % [rank, gear.display_name, int(rule["level"]), UiText.astra(int(rule["copper"])), int(rule["xp"])], 9)
	if session.guild_order_is_completed(_selected_id):
		_label(_body, "Сдано", 9)
	elif active and stage.is_empty():
		focus = _button(_body, "OrderReport", "Сдать задание", _request.bind("report"))
	elif active and session.traces < 3:
		var caption: String = "Выйти на задание" if int(session.guild_order["cleared"]) == 0 else "Продолжить вылазку"
		focus = _button(_body, "OrderDepart", caption, _request.bind("depart"))
	elif active:
		_label(_body, "Снимите Следы отдыхом в Лиорене.", 9)
	elif not session.guild_order_is_unlocked(_selected_id):
		var previous: String = GuildOrders.RANKS[GuildOrders.RANKS.find(rank) - 1]
		_label(_body, "Сначала сдайте задание ранга %s." % previous, 9)
	elif not session.guild_order.is_empty():
		_label(_body, "Сначала сдайте принятое задание.", 9)
	else:
		focus = _button(_body, "OrderAccept", "Принять задание", _request.bind("accept"))
	if focus != _back:
		focus.theme_type_variation = &"PrimaryButton"
	_error = _label(_body, "", 9)
	_error.add_theme_color_override("font_color", AppTheme.COLOR_DANGER)
	_error.hide()
	focus.grab_focus()

func _render_list() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 204
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_body.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var focus: Button = _back
	for order_id: String in GuildOrders.data()["orders"]:
		var order: Dictionary = GuildOrders.definition(order_id)
		var suffix: String = " · Сдано" if session.guild_order_is_completed(order_id) else ""
		if session.guild_order.get("id") == order_id:
			suffix = " · %d/%d" % [int(session.guild_order["cleared"]), int(session.guild_order["total"])]
		var row: Button = _button(rows, order_id, "%s · %s%s" % [order["rank"], order["title"], suffix], _open_order.bind(order_id))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size.y = 30
		if order_id == _last_selected_id or (_last_selected_id.is_empty() and session.guild_order.get("id", "herbalist_escort") == order_id):
			focus = row
	focus.grab_focus()

func _open_order(order_id: String) -> void:
	_selected_id = order_id
	_render()

func _request(command: String) -> void:
	guild_order_requested.emit(command, _selected_id)

func _button(parent: Control, node_name: String, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 9)
	button.custom_minimum_size = Vector2(24, 24)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(parent: Control, caption: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
