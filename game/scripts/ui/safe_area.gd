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
	if not get_viewport().size_changed.is_connected(_apply_safe_area):
		get_viewport().size_changed.connect(_apply_safe_area)


func _apply_safe_area() -> void:
	var margins := Vector4.ZERO
	if OS.get_name() in ["Android", "iOS"]:
		var screen_rect: Rect2i = DisplayServer.get_display_safe_area()
		if screen_rect.has_area():
			# The real transform includes integer scale AND letterbox offset.
			margins = margins_for(get_viewport_rect(), get_viewport().get_screen_transform(), Rect2(screen_rect))
	add_theme_constant_override("margin_left", ceili(margins.x) + padding)
	add_theme_constant_override("margin_top", ceili(margins.y) + padding)
	add_theme_constant_override("margin_right", ceili(margins.z) + padding)
	add_theme_constant_override("margin_bottom", ceili(margins.w) + padding)

static func margins_for(viewport_rect: Rect2, viewport_to_screen: Transform2D, safe_screen: Rect2) -> Vector4:
	var safe: Rect2 = viewport_to_screen.affine_inverse() * safe_screen
	var bounds: Rect2 = safe.intersection(viewport_rect)
	if not bounds.has_area():
		return Vector4.ZERO
	return Vector4(maxf(0, bounds.position.x - viewport_rect.position.x), maxf(0, bounds.position.y - viewport_rect.position.y), maxf(0, viewport_rect.end.x - bounds.end.x), maxf(0, viewport_rect.end.y - bounds.end.y))
