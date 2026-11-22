extends Control

signal navigate_requested(destination: String)
signal sound_change_requested(enabled: bool)
signal voice_change_requested(voice_id: String)

var session: GameSession
var sound_toggle: CheckButton
var voice_option: OptionButton
var format_option: OptionButton
var speed_option: OptionButton
var balance_label: Label

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	navigate_requested.emit("world")
	return true

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	var safe := SafeArea.new()
	add_child(safe)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	safe.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
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
	sound_toggle = CheckButton.new()
	sound_toggle.text = "Звук"
	sound_toggle.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	sound_toggle.button_pressed = not AudioServer.is_bus_mute(0)
	sound_toggle.toggled.connect(func(value: bool) -> void: sound_change_requested.emit(value))
	column.add_child(sound_toggle)
	voice_option = OptionButton.new()
	voice_option.fit_to_longest_item = false
	voice_option.clip_text = true
	voice_option.add_theme_font_size_override("font_size", 9)
	voice_option.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	voice_option.add_item("Без озвучки · дорожек нет")
	voice_option.disabled = true
	voice_option.tooltip_text = "Голосовые дорожки ещё не подключены"
	column.add_child(voice_option)
	format_option = OptionButton.new()
	format_option.fit_to_longest_item = false
	format_option.clip_text = true
	format_option.add_theme_font_size_override("font_size", 9)
	format_option.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	format_option.add_item("Автобой")
	format_option.add_item("Ручной бой")
	format_option.selected = 1 if session.combat_format == GameSession.COMBAT_FORMAT_ACTIVE else 0
	format_option.item_selected.connect(_on_format_selected)
	column.add_child(format_option)
	speed_option = OptionButton.new()
	speed_option.fit_to_longest_item = false
	speed_option.clip_text = true
	speed_option.add_theme_font_size_override("font_size", 9)
	speed_option.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	speed_option.add_item("Скорость автобоя ×1")
	speed_option.add_item("Скорость автобоя ×2")
	speed_option.selected = session.auto_speed - 1
	speed_option.item_selected.connect(_on_speed_selected)
	column.add_child(speed_option)
	var note := Label.new()
	note.text = "Режим и скорость применяются со следующего боя.\nНастройки не откатываются Печатью Пути."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 8)
	column.add_child(note)
	balance_label = Label.new()
	balance_label.text = "Точный баланс\n" + UiText.wallet(session.wallet)
	balance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	balance_label.add_theme_font_size_override("font_size", 9)
	column.add_child(balance_label)
	back.grab_focus()

func _on_format_selected(index: int) -> void:
	session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE if index == 1 else GameSession.COMBAT_FORMAT_AUTO)

func _on_speed_selected(index: int) -> void:
	session.set_auto_speed(2 if index == 1 else 1)
