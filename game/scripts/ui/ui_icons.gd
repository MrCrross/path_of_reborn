class_name UiIcons
extends RefCounted

## Локальные векторные пиктограммы, рассчитанные на дробный масштаб интерфейса.
const ROOT := "res://art/ui/icons/"
const TOUCH_SIZE := 24
const ICON_SIZE := 16
const NAMES := {
	"attack": "sword", "dodge": "human_run", "inventory": "backpack",
	"back": "chevron_left", "close": "close", "info": "info_box",
	"path": "map", "rest": "bed", "delete": "trash", "next": "chevron_right",
	"health": "heart", "defense": "shield", "repeat": "reload",
}
const ASTRA_TEXTURES: Dictionary = {
	GameSession.COPPER: preload("res://art/equipment/astra_copper_icon.png"),
	GameSession.SILVER: preload("res://art/equipment/astra_silver_icon.png"),
	GameSession.GOLD: preload("res://art/equipment/astra_gold_icon.png"),
}

static func texture(action: String) -> Texture2D:
	return load(ROOT + String(NAMES[action]) + "_icon.svg")

static func astra(coin: String) -> Texture2D:
	return ASTRA_TEXTURES[coin]

static func apply(button: Button, action: String, label: String, primary: bool = false) -> void:
	apply_texture(button, texture(action), label, primary)


## Кнопка с произвольной текстурой-знаком (например, утверждённая печать).
static func apply_texture(button: Button, icon: Texture2D, label: String, primary: bool = false) -> void:
	button.text = ""
	button.icon = icon
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", ICON_SIZE)
	button.custom_minimum_size = Vector2(TOUCH_SIZE, TOUCH_SIZE)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = label
	button.accessibility_name = label
	button.theme_type_variation = &"ActionIconButton" if primary else &"IconButton"
	button.add_theme_color_override("icon_normal_color", AppTheme.COLOR_ACCENT_TEXT if primary else AppTheme.COLOR_TEXT)


static func tint(button: Button, color: Color) -> void:
	for state: String in ["normal", "focus", "hover", "pressed", "hover_pressed"]:
		button.add_theme_color_override("icon_%s_color" % state, color)
