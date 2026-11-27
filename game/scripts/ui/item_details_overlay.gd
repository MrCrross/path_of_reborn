class_name ItemDetailsOverlay
extends Control

signal dismissed

@onready var view: ItemDetailsView = %ItemDetails
var _focus := ModalFocus.new()

func _ready() -> void:
	view.close_requested.connect(dismiss)
	$Dim.gui_input.connect(_on_backdrop_input)

func open_instance(instance_id: String) -> bool:
	if not view.present_instance(instance_id):
		return false
	_show_details()
	return true

func open_reward(reward: Dictionary) -> bool:
	if not view.present_reward(reward["item_id"], reward.get("aspect_id", ""), reward.get("quantity", 1), reward):
		return false
	_show_details()
	return true

func _show_details() -> void:
	show()
	isolate_focus()
	view.close_button.grab_focus()

## The backpack can replace its buttons while the item remains open.
func isolate_focus() -> void:
	if visible:
		_focus.capture(self)

func dismiss() -> void:
	if visible:
		hide()
		_focus.restore()
		dismissed.emit()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed or event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		dismiss()
