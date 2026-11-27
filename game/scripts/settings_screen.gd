extends Control

signal navigate_requested(destination: String)
signal sound_change_requested(enabled: bool)
signal voice_change_requested(voice_id: String)

var session: GameSession

@onready var sound_toggle: CheckButton = %Sound
@onready var voice_option: OptionButton = %Voice
@onready var format_option: OptionButton = %Format
@onready var speed_option: OptionButton = %Speed
@onready var ability_option: OptionButton = %Ability
@onready var balance_label: Label = %Balance

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	navigate_requested.emit("world")
	return true

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	$Background.color = AppTheme.COLOR_BG
	%Column.add_theme_constant_override("separation", AppTheme.SPACE_SECTION)
	%Rows.add_theme_constant_override("separation", AppTheme.SPACE_INSET)
	%Note.add_theme_color_override("font_color", AppTheme.COLOR_TEXT_DIM)
	var balance_box := AppTheme.card_box(AppTheme.COLOR_PANEL)
	balance_box.set_content_margin_all(AppTheme.SPACE_INSET)
	%WalletCard.add_theme_stylebox_override("panel", balance_box)
	balance_label.text = "Точный баланс\n" + UiText.wallet(session.wallet)
	UiIcons.apply(%Back, "back", "К миру")
	%Back.pressed.connect(handle_back)
	sound_toggle.set_pressed_no_signal(not AudioServer.is_bus_mute(0))
	sound_toggle.toggled.connect(sound_change_requested.emit)
	_setup_option(voice_option, ["Без озвучки · дорожек нет"], 0)
	_setup_option(format_option, ["Автобой", "Ручной бой"], int(session.combat_format == GameSession.COMBAT_FORMAT_ACTIVE))
	_setup_option(speed_option, ["Скорость автобоя ×1", "Скорость автобоя ×2"], session.auto_speed - 1)
	_setup_option(ability_option, ["Навык в автобое: авто", "Навык в автобое: вручную"], int(not session.auto_ability))
	format_option.item_selected.connect(_on_format_selected)
	speed_option.item_selected.connect(func(index: int) -> void: session.set_auto_speed(index + 1))
	ability_option.item_selected.connect(func(index: int) -> void: session.set_auto_ability(index == 0))
	%Back.grab_focus()

func _setup_option(option: OptionButton, labels: Array[String], selection: int) -> void:
	option.theme_type_variation = &"SettingsOptionButton"
	option.fit_to_longest_item = false
	option.clip_text = true
	option.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	option.get_popup().theme_type_variation = &"SettingsPopupMenu"
	for label: String in labels:
		option.add_item(label)
	option.select(selection)

func _on_format_selected(index: int) -> void:
	session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE if index == 1 else GameSession.COMBAT_FORMAT_AUTO)
