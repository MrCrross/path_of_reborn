class_name AppTheme
extends RefCounted

## Единая Theme проекта: типографика, палитра и состояния кнопок.
## Тёмные подложки, тёплый текст, золотые действия и отдельный магический акцент.

const COLOR_BG := Color("22332b")
const COLOR_TEXT := Color("f2e6ce")
const COLOR_TEXT_DIM := Color("a9b6a2")
const COLOR_ACCENT := Color("e4bd6c")
const COLOR_ACCENT_PRESSED := Color("bd9851")
const COLOR_ACCENT_TEXT := Color("202016")
const COLOR_MAGIC := Color("90c4ad")
const COLOR_PANEL := Color("1c2b24")
const COLOR_PANEL_LIGHT := Color("2b4034")
const COLOR_PANEL_BORDER := Color("49634f")
const COLOR_HUD := Color("14241be8")
const COLOR_DANGER := Color("e68c78")
const COLOR_DANGER_PRESSED := Color("b86e5c")
const COLOR_DANGER_TEXT := Color("202016")
const COLOR_HERO_HP := Color("b9d99a")
const COLOR_ENEMY_HP := Color("e68c78")
const COLOR_PROGRESS := Color("e4bd6c")
const COLOR_DIALOGUE_BG := Color("111a24e8")
const COLOR_DIALOGUE_BORDER := Color("8fa3c0")
const COLOR_DIALOGUE_TEXT := Color("e9e4d8")
const DIALOGUE_TEXT_LINES := 3

static func dialogue_speaker_color(speaker: String) -> Color:
	return COLOR_ACCENT if speaker == "Харуто" else COLOR_MAGIC


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = ThemeDB.fallback_font
	theme.default_font_size = 10
	theme.set_color("font_color", "Label", COLOR_TEXT)
	theme.set_color("font_color", "Button", COLOR_TEXT)

	theme.set_stylebox("panel", "PanelContainer", flat(COLOR_PANEL, COLOR_PANEL_BORDER))
	theme.set_stylebox("panel", "Panel", flat(COLOR_PANEL, COLOR_PANEL_BORDER))

	# Обычная (вторичная) кнопка.
	theme.set_stylebox("normal", "Button", flat(COLOR_PANEL_LIGHT, COLOR_PANEL_BORDER))
	theme.set_stylebox("hover", "Button", flat(Color("24382a"), Color("3a5a42")))
	theme.set_stylebox("pressed", "Button", flat(Color("121f16"), COLOR_PANEL_BORDER))
	theme.set_stylebox("disabled", "Button", flat(Color("141d17"), Color("1d2b20")))
	theme.set_stylebox("focus", "Button", focus_box())
	theme.set_color("font_disabled_color", "Button", COLOR_TEXT_DIM.darkened(0.25))
	theme.set_type_variation("CompactMultilineButton", "Button")
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		box.content_margin_top = 0
		box.content_margin_bottom = 0
		theme.set_stylebox(state, "CompactMultilineButton", box)
	# Small visible icons sit inside independent, generous touch targets.
	theme.set_type_variation("IconButton", "Button")
	theme.set_type_variation("ActionIconButton", "IconButton")
	for role: String in ["IconButton", "ActionIconButton"]:
		var primary: bool = role == "ActionIconButton"
		theme.set_stylebox("normal", role, flat(Color("d9b45c") if primary else Color("101c15e6"), COLOR_ACCENT if primary else Color("3a4d3d"), 1, 0))
		theme.set_stylebox("hover", role, flat(Color("e8c97a") if primary else Color("1d3325e6"), COLOR_ACCENT, 1, 0))
		theme.set_stylebox("pressed", role, flat(Color("a48b4a") if primary else Color("121f18"), COLOR_ACCENT, 1, 0))
		theme.set_stylebox("disabled", role, flat(Color("141d18cc"), Color("2a352c"), 1, 0))
		theme.set_stylebox("focus", role, focus_box())
		theme.set_color("icon_normal_color", role, COLOR_ACCENT_TEXT if primary else COLOR_TEXT)
		theme.set_color("icon_hover_color", role, COLOR_ACCENT_TEXT if primary else COLOR_ACCENT)
		theme.set_color("icon_pressed_color", role, COLOR_ACCENT_TEXT if primary else COLOR_TEXT)
		theme.set_color("icon_disabled_color", role, Color("6e756c"))
	theme.set_type_variation("HudIconButton", "IconButton")
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "HudIconButton", StyleBoxEmpty.new())
	theme.set_type_variation("ArenaPanel", "PanelContainer")
	theme.set_stylebox("panel", "ArenaPanel", StyleBoxEmpty.new())
	theme.set_type_variation("HudPanel", "PanelContainer")
	theme.set_stylebox("panel", "HudPanel", flat(COLOR_HUD, COLOR_PANEL_BORDER, 1, 0))
	theme.set_type_variation("EquipmentPanel", "PanelContainer")
	theme.set_stylebox("panel", "EquipmentPanel", flat(Color("d4ddc8"), COLOR_MAGIC, 1, 2))

	# Основное действие (вариация типа).
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", flat(COLOR_ACCENT, COLOR_ACCENT.lightened(0.15)))
	theme.set_stylebox("hover", "PrimaryButton", flat(COLOR_ACCENT.lightened(0.1), COLOR_ACCENT.lightened(0.25)))
	theme.set_stylebox("pressed", "PrimaryButton", flat(COLOR_ACCENT_PRESSED, COLOR_ACCENT_PRESSED))
	theme.set_stylebox("disabled", "PrimaryButton", flat(Color("3d3a2e"), Color("4a4636")))
	theme.set_stylebox("focus", "PrimaryButton", focus_box())
	theme.set_color("font_color", "PrimaryButton", COLOR_ACCENT_TEXT)
	theme.set_color("font_disabled_color", "PrimaryButton", Color("8a8570"))
	for state: String in ["font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, "PrimaryButton", COLOR_ACCENT_TEXT)
	for state: String in ["icon_normal_color", "icon_focus_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		theme.set_color(state, "ActionIconButton", COLOR_ACCENT_TEXT)
		theme.set_color(state, "PrimaryButton", COLOR_ACCENT_TEXT)

	# Печать — отдельное магическое действие, а не обычное продвижение по маршруту.
	theme.set_type_variation("MagicButton", "Button")
	theme.set_stylebox("normal", "MagicButton", flat(COLOR_MAGIC, COLOR_MAGIC.lightened(0.15)))
	theme.set_stylebox("hover", "MagicButton", flat(COLOR_MAGIC.lightened(0.1), COLOR_MAGIC.lightened(0.25)))
	theme.set_stylebox("pressed", "MagicButton", flat(COLOR_MAGIC.darkened(0.18), COLOR_MAGIC.darkened(0.18)))
	theme.set_stylebox("disabled", "MagicButton", flat(Color("34483e"), COLOR_PANEL_BORDER))
	theme.set_stylebox("focus", "MagicButton", focus_box())
	for state: String in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "icon_normal_color", "icon_focus_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		theme.set_color(state, "MagicButton", COLOR_ACCENT_TEXT)
	theme.set_color("font_disabled_color", "MagicButton", COLOR_TEXT_DIM)

	# Опасное действие (вариация типа).
	theme.set_type_variation("DangerButton", "Button")
	theme.set_stylebox("normal", "DangerButton", flat(Color("5c2f26"), Color("8a4636")))
	theme.set_stylebox("hover", "DangerButton", flat(Color("6d3a2e"), Color("9c5140")))
	theme.set_stylebox("pressed", "DangerButton", flat(Color("47231c"), Color("6d382c")))
	theme.set_stylebox("disabled", "DangerButton", flat(Color("33201c"), Color("412a24")))
	theme.set_stylebox("focus", "DangerButton", focus_box())
	theme.set_color("font_color", "DangerButton", COLOR_DANGER_TEXT)
	theme.set_color("font_disabled_color", "DangerButton", Color("7d6a63"))

	# ProgressBar.
	theme.set_stylebox("background", "ProgressBar", flat(Color("101a13"), Color("1a2820")))
	theme.set_stylebox("fill", "ProgressBar", flat(COLOR_PROGRESS, COLOR_PROGRESS.lightened(0.1)))

	theme.set_constant("separation", "HBoxContainer", 4)
	theme.set_constant("separation", "VBoxContainer", 4)
	return theme


static func flat(bg: Color, border: Color, border_width: int = 1, corner: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(border_width)
	box.border_color = border
	box.set_corner_radius_all(corner)
	return box


static func focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_border_width_all(1)
	box.border_color = COLOR_ACCENT
	box.set_corner_radius_all(2)
	box.draw_center = false
	return box


## Панель с заданным фоном/рамкой (для карточек поверх сцены).
static func card_box(bg: Color = Color("1c2436cc")) -> StyleBoxFlat:
	var box := flat(bg, COLOR_PANEL_BORDER)
	return box
