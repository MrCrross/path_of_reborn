extends Control

signal new_game_requested
signal continue_requested

var profile_available: bool = false

@onready var begin_button: Button = %BeginButton
@onready var continue_button: Button = %ContinueButton
@onready var status_text: Label = %StatusText

func _ready() -> void:
	begin_button.grab_focus()

func handle_back() -> bool:
	# Модальное подтверждение закрывает себя само; иначе Back на Title ничего не делает.
	return false

func set_profile_status(available: bool, message: String = "") -> void:
	profile_available = available
	continue_button.visible = available
	begin_button.text = "Новая игра" if available else "Начать путь"
	begin_button.theme_type_variation = &"Button" if available else &"PrimaryButton"
	status_text.text = message
	status_text.visible = not message.is_empty()
	if not message.is_empty():
		status_text.add_theme_stylebox_override("normal", AppTheme.flat(AppTheme.COLOR_HUD, AppTheme.COLOR_PANEL_BORDER, 1, 2))
	if available:
		continue_button.grab_focus()
	else:
		begin_button.grab_focus()

func _on_begin_pressed() -> void:
	if not profile_available:
		new_game_requested.emit()
		return
	var dialog: ConfirmDialog = ConfirmDialog.open(
		self,
		"Новая игра",
		"Текущий профиль будет безвозвратно заменён. Продолжить?",
		"Заменить",
		"Отмена",
		true
	)
	dialog.confirmed.connect(_on_replace_confirmed)

func _on_replace_confirmed() -> void:
	new_game_requested.emit()

func _on_continue_pressed() -> void:
	continue_requested.emit()
