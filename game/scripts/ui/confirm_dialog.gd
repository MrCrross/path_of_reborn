class_name ConfirmDialog
extends Control

## Модальное подтверждение: блокирует фон и фокус, Esc/касание снаружи = отмена.
## Открытие только через ConfirmDialog.open(...); действие под диалогом не выполняется.

signal confirmed
signal cancelled

const MODAL_GROUP: StringName = &"confirm_dialogs"

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
	dialog.add_to_group(MODAL_GROUP)
	dialog._setup(title, message, confirm_text, cancel_text, danger)
	return dialog


static func dismiss_from(screen: Control) -> bool:
	var dialog := _top_from(screen)
	if dialog == null:
		return false
	dialog._on_cancel_pressed()
	return true


static func has_open(screen: Control) -> bool:
	return _top_from(screen) != null


static func _top_from(screen: Control) -> ConfirmDialog:
	var dialogs := screen.get_tree().get_nodes_in_group(MODAL_GROUP)
	for index: int in range(dialogs.size() - 1, -1, -1):
		var dialog := dialogs[index] as ConfirmDialog
		if screen.is_ancestor_of(dialog) and dialog.is_visible_in_tree():
			return dialog
	return null


static func tutorial(parent: Node, session: GameSession, id: String, title: String, message: String) -> ConfirmDialog:
	if session.seen_cue_ids.has(id):
		return null
	var dialog := open(parent, title, message, "Закрыть", "")
	var remember := func() -> void:
		session.seen_cue_ids[id] = true
		session.profile_changed.emit()
	dialog.confirmed.connect(remember)
	dialog.cancelled.connect(remember)
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
	_cancel.visible = not cancel_text.is_empty()
	if _cancel.visible:
		_confirm.focus_neighbor_top = _confirm.get_path_to(_cancel)
		_confirm.focus_neighbor_bottom = _confirm.get_path_to(_cancel)
		_cancel.focus_neighbor_top = _cancel.get_path_to(_confirm)
		_cancel.focus_neighbor_bottom = _cancel.get_path_to(_confirm)
	if danger and _cancel.visible:
		_cancel.grab_focus()
	else:
		_confirm.grab_focus()


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
	close()
	cancelled.emit()


func _on_outside_pressed(event: InputEvent = null) -> void:
	# Касание/клик по dim-слою снаружи панели — безопасная отмена.
	if event != null:
		var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		pressed = pressed or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		if not pressed:
			return
		get_viewport().set_input_as_handled()
	_on_cancel_pressed()


func close() -> void:
	_focus_guard.restore()
	hide()
	queue_free()
