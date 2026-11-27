class_name ModalFocus
extends RefCounted

## Temporarily exclude controls behind an overlay from keyboard focus.
## The overlay remains in its own screen; no duplicate routing/state owner.
var _modes: Dictionary = {}
var _previous: Control

func capture(overlay: Control) -> void:
	if _modes.is_empty():
		_previous = overlay.get_viewport().gui_get_focus_owner()
	var viewport := overlay.get_viewport()
	for node: Node in viewport.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if control.get_viewport() == viewport and control != overlay and not overlay.is_ancestor_of(control):
			if not _modes.has(control):
				_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE

func restore() -> void:
	for saved: Variant in _modes:
		# Item grids may rebuild while the sheet is open. Validate before casting.
		if is_instance_valid(saved):
			var control: Control = saved
			control.focus_mode = _modes[saved]
	_modes.clear()
	if is_instance_valid(_previous) and _previous.is_visible_in_tree():
		_previous.grab_focus()
	_previous = null
