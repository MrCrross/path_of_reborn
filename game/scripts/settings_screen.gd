extends Control

signal navigate_requested(destination: String)
signal sound_change_requested(enabled: bool)
signal voice_change_requested(voice_id: String)

var session: GameSession
var sound_toggle: CheckButton
var voice_option: OptionButton
var format_option: OptionButton
var speed_option: OptionButton
var ability_option: OptionButton
var balance_label: Label

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	navigate_requested.emit("world")
	return true

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	var background := ColorRect.new()
	background.color = AppTheme.COLOR_BG
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe := SafeArea.new()
	add_child(safe)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, AppTheme.SPACE_INSET)
	safe.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", AppTheme.SPACE_SECTION)
	margin.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var back := Button.new()
	UiIcons.apply(back, "back", "К миру")
	back.pressed.connect(func() -> void: navigate_requested.emit("world"))
	top.add_child(back)
	var title := Label.new()
	title.text = "Настройки"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	top.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = UiIcons.TOUCH_SIZE
	top.add_child(spacer)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", AppTheme.SPACE_INSET)
	column.add_child(rows)
	sound_toggle = CheckButton.new()
	sound_toggle.theme_type_variation = &"SettingsCheckButton"
	sound_toggle.text = "Звук"
	sound_toggle.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	sound_toggle.button_pressed = not AudioServer.is_bus_mute(0)
	sound_toggle.toggled.connect(func(value: bool) -> void: sound_change_requested.emit(value))
	rows.add_child(sound_toggle)
	voice_option = OptionButton.new()
	voice_option.theme_type_variation = &"SettingsOptionButton"
	voice_option.fit_to_longest_item = false
	voice_option.clip_text = true
	voice_option.add_theme_font_size_override("font_size", 9)
	voice_option.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	voice_option.add_item("Без озвучки · дорожек нет")
	voice_option.disabled = true
	voice_option.tooltip_text = "Голосовые дорожки ещё не подключены"
	rows.add_child(voice_option)
	format_option = OptionButton.new()
	format_option.theme_type_variation = &"SettingsOptionButton"
	format_option.fit_to_longest_item = false
	format_option.clip_text = true
	format_option.add_theme_font_size_override("font_size", 9)
	format_option.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	format_option.add_item("Автобой")
	format_option.add_item("Ручной бой")
	format_option.selected = 1 if session.combat_format == GameSession.COMBAT_FORMAT_ACTIVE else 0
	format_option.item_selected.connect(_on_format_selected)
	rows.add_child(format_option)
	speed_option = OptionButton.new()
	speed_option.theme_type_variation = &"SettingsOptionButton"
	speed_option.fit_to_longest_item = false
	speed_option.clip_text = true
	speed_option.add_theme_font_size_override("font_size", 9)
	speed_option.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	speed_option.add_item("Скорость автобоя ×1")
	speed_option.add_item("Скорость автобоя ×2")
	speed_option.selected = session.auto_speed - 1
	speed_option.item_selected.connect(_on_speed_selected)
	rows.add_child(speed_option)
	ability_option = OptionButton.new()
	ability_option.theme_type_variation = &"SettingsOptionButton"
	ability_option.fit_to_longest_item = false
	ability_option.clip_text = true
	ability_option.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	ability_option.add_item("Навык в автобое: авто")
	ability_option.add_item("Навык в автобое: вручную")
	ability_option.selected = 0 if session.auto_ability else 1
	ability_option.item_selected.connect(func(index: int) -> void: session.set_auto_ability(index == 0))
	rows.add_child(ability_option)
	for option: OptionButton in [voice_option, format_option, speed_option, ability_option]:
		option.get_popup().theme_type_variation = &"SettingsPopupMenu"
	var note := Label.new()
	note.text = "Боевые настройки применяются со следующего боя и сохраняются после возврата Печатью Пути."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 8)
	note.add_theme_constant_override("line_spacing", 1)
	note.add_theme_color_override("font_color", AppTheme.COLOR_TEXT_DIM)
	column.add_child(note)
	var balance_card := PanelContainer.new()
	var balance_box := AppTheme.card_box(AppTheme.COLOR_PANEL)
	balance_box.set_content_margin_all(AppTheme.SPACE_INSET)
	balance_card.add_theme_stylebox_override("panel", balance_box)
	column.add_child(balance_card)
	balance_label = Label.new()
	balance_label.text = "Точный баланс\n" + UiText.wallet(session.wallet)
	balance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	balance_label.add_theme_font_size_override("font_size", 9)
	balance_card.add_child(balance_label)
	back.grab_focus()

func _on_format_selected(index: int) -> void:
	session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE if index == 1 else GameSession.COMBAT_FORMAT_AUTO)

func _on_speed_selected(index: int) -> void:
	session.set_auto_speed(2 if index == 1 else 1)
