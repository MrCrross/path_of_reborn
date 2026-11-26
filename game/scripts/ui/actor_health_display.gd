class_name ActorHealthDisplay
extends Control

## Компактная полоса HP над персонажем. Одна для героя и врага, в World и Combat.
## Тонкая тёмная подложка без рамки и свечения; якорь головы задаётся данными
## листа (ArtMap.*["head"]), позиция округляется в логических пикселях.

const BAR_SIZE := Vector2(36, 4)
const HEAD_GAP := 2.0

var _underlay: ColorRect
var _fill: ColorRect
var _label: Label
var _show_numbers := false
var _max_hp := 1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BAR_SIZE
	size = BAR_SIZE
	# Трек и заполнение — один видимый прямоугольник 36x4 от одного начала:
	# приглушённая тёмная подложка без внешней кромки, fill растёт слева направо.
	_underlay = ColorRect.new()
	_underlay.name = "Underlay"
	_underlay.color = Color(0.06, 0.1, 0.08, 0.92)
	_underlay.position = Vector2.ZERO
	_underlay.size = BAR_SIZE
	_underlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_underlay)
	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.position = Vector2.ZERO
	_fill.size = BAR_SIZE
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	_label = Label.new()
	_label.name = "Numbers"
	_label.add_theme_font_size_override("font_size", 7)
	_label.add_theme_color_override("font_color", AppTheme.COLOR_TEXT)
	_label.add_theme_color_override("font_outline_color", Color(0.03, 0.045, 0.04, 0.9))
	_label.add_theme_constant_override("outline_size", 2)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)


## role: "hero" | "enemy"; числа — опциональная микро-подпись под полосой.
func setup(role: String, show_numbers: bool = false) -> void:
	_show_numbers = show_numbers
	_fill.color = AppTheme.COLOR_HERO_HP if role == "hero" else AppTheme.COLOR_ENEMY_HP
	_label.visible = show_numbers


func set_targeted(targeted: bool) -> void:
	_fill.color = AppTheme.COLOR_ACCENT if targeted else AppTheme.COLOR_ENEMY_HP
	_underlay.color = Color("83623de8") if targeted else Color(0.06, 0.1, 0.08, 0.92)

func set_hp(current: int, max_hp: int) -> void:
	# max_hp <= 0 — только защита от некорректных данных: показываем пустую полосу.
	_max_hp = maxi(1, max_hp)
	var ratio := clampf(float(current) / float(_max_hp), 0.0, 1.0)
	# HP=0 — нулевая ширина без «пикселя мёртвого»; 1 px остаётся лишь
	# для текущего HP > 0 (минимально видимый остаток).
	var width := 0
	if current > 0:
		width = maxi(1, roundi(BAR_SIZE.x * ratio))
	_fill.size = Vector2(width, BAR_SIZE.y)
	if _show_numbers:
		_label.text = "%d/%d" % [current, max_hp]
		_label.reset_size()
		_label.position = Vector2(
			roundi((BAR_SIZE.x - _label.size.x) * 0.5), BAR_SIZE.y + 1
		)
		size = Vector2(BAR_SIZE.x, BAR_SIZE.y + 9)
	else:
		size = BAR_SIZE


## Центр полосы — над якорем головы; результат не выходит за bounds.
func follow(anchor: Vector2, bounds: Rect2) -> void:
	var top_left := Vector2(
		anchor.x - size.x * 0.5,
		anchor.y - size.y - HEAD_GAP
	).round()
	top_left.x = clampf(top_left.x, bounds.position.x, bounds.end.x - size.x)
	top_left.y = clampf(top_left.y, bounds.position.y, bounds.end.y - size.y)
	position = top_left
