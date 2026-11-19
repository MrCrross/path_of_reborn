extends Control

signal new_game_requested
signal continue_requested

var profile_available: bool = false

@onready var begin_button: Button = %BeginButton
@onready var continue_button: Button = %ContinueButton
@onready var confirm_row: HBoxContainer = %ConfirmRow
@onready var status_text: Label = %StatusText

func _ready() -> void:
	begin_button.grab_focus()

func set_profile_status(available: bool, message: String = "") -> void:
	profile_available = available
	continue_button.visible = available
	begin_button.text = "Новая игра" if available else "Начать путь"
	status_text.text = message
	confirm_row.hide()
	if available:
		continue_button.grab_focus()
	else:
		begin_button.grab_focus()

func _on_begin_pressed() -> void:
	if not profile_available:
		new_game_requested.emit()
		return
	confirm_row.show()
	status_text.text = "Новая игра заменит текущий профиль. Продолжить?"
	%ConfirmButton.grab_focus()

func _on_continue_pressed() -> void:
	continue_requested.emit()

func _on_confirm_pressed() -> void:
	new_game_requested.emit()

func _on_cancel_pressed() -> void:
	confirm_row.hide()
	status_text.text = ""
	begin_button.grab_focus()
