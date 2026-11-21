class_name ConfirmDialog
extends Control

## Модальное подтверждение: блокирует фон и фокус, Esc/касание снаружи = отмена.
## Открытие только через ConfirmDialog.open(...); действие под диалогом не выполняется.

signal confirmed
signal cancelled

static func open(
	parent: Node,
	title: String,
	message: String,
	confirm_text: String = "Подтвердить",
	cancel_text: String = "Отмена",
	danger: bool = false
) -> ConfirmDialog:
	var dialog: ConfirmDialog = preload("res://scenes/ui/confirm_dialog.tscn").instantiate()
	parent.add_child(dialog)
	dialog._setup(title, message, confirm_text, cancel_text, danger)
	return dialog


var _focus_guard := ModalFocus.new()
var _closed: bool = false

@onready var _title: Label = %Title
@onready var _message: Label = %Message
@onready var _confirm: Button = %Confirm
@onready var _cancel: Button = %Cancel


func _setup(
	title: String,
	message: String,
	confirm_text: String,
	cancel_text: String,
	danger: bool
) -> void:
	_title.text = title
	_message.text = message
	_confirm.text = confirm_text
	_cancel.text = cancel_text
	_confirm.theme_type_variation = "DangerButton" if danger else "PrimaryButton"
	_focus_guard.capture(self)
	_confirm.focus_neighbor_left = _confirm.get_path_to(_cancel)
	_confirm.focus_neighbor_right = _confirm.get_path_to(_cancel)
	_cancel.focus_neighbor_left = _cancel.get_path_to(_confirm)
	_cancel.focus_neighbor_right = _cancel.get_path_to(_confirm)
	_confirm.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()


func _on_confirm_pressed() -> void:
	if _closed:
		return
	_closed = true
	close()
	confirmed.emit()


func _on_cancel_pressed() -> void:
	if _closed:
		return
	_closed = true
	cancelled.emit()
	close()


func _on_outside_pressed(event: InputEvent = null) -> void:
	# Касание/клик по dim-слою снаружи панели — безопасная отмена.
	if event != null:
		var pressed: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed
		pressed = pressed or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		if not pressed:
			return
	_on_cancel_pressed()


func close() -> void:
	_focus_guard.restore()
	hide()
	queue_free()
