class_name SafeArea
extends MarginContainer

@export var padding: int = 0

## Применяет реальную safe area дисплея (DisplayServer) к полям контейнера.
## Экранные пиксели пересчитываются в логические viewport-координаты с учётом
## stretch scale/offset; на desktop и при полном совпадении safe area с окном
## поля равны нулю (fallback).

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_apply_safe_area()
	if OS.get_name() in ["Android", "iOS"]:
		item_rect_changed.connect(_apply_safe_area)
		get_viewport().size_changed.connect(_apply_safe_area)


func _apply_safe_area() -> void:
	var margins := Vector4.ZERO
	if OS.get_name() in ["Android", "iOS"]:
		var screen_rect: Rect2i = DisplayServer.get_display_safe_area()
		if screen_rect.has_area():
			# A screen can already be inside GameRoot's safe rectangle.
			margins = margins_for(Rect2(Vector2.ZERO, size), get_screen_transform(), Rect2(screen_rect))
	_set_margin(&"margin_left", margins.x)
	_set_margin(&"margin_top", margins.y)
	_set_margin(&"margin_right", margins.z)
	_set_margin(&"margin_bottom", margins.w)

func _set_margin(side: StringName, inset: float) -> void:
	var pixels := ceili(snappedf(inset, 0.0001)) + padding
	if not has_theme_constant_override(side) or get_theme_constant(side) != pixels:
		add_theme_constant_override(side, pixels)

static func margins_for(rect: Rect2, local_to_screen: Transform2D, safe_screen: Rect2) -> Vector4:
	var safe: Rect2 = local_to_screen.affine_inverse() * safe_screen
	var bounds: Rect2 = safe.intersection(rect)
	if not bounds.has_area():
		return Vector4.ZERO
	return Vector4(bounds.position.x - rect.position.x, bounds.position.y - rect.position.y,
		rect.end.x - bounds.end.x, rect.end.y - bounds.end.y)
