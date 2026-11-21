class_name PrologueStaging
extends RefCounted

## Постановочные данные пролога (presentation-слой): человеческие названия планов,
## look-hotspot на дороге, компоновка актёров. Канонический текст и 44 cue ID
## живут в data/narrative/prologue.json и здесь не дублируются.

## План -> заголовок, понятный игроку. Технические shot ID не выводятся.
const SHOT_HEADINGS: Dictionary = {
	"routine": "Вечер. Токио",
	"crosswalk": "Переход",
	"alarm": "Тревога",
	"rescue": "Бросок",
	"dark": "Темнота",
	"threshold": "Порог",
	"seal": "Печать",
	"title": "Путь",
}

## Look-hotspot прямо на дороге (логические координаты 180x320), по фону перехода.
const HOTSPOTS: Dictionary = {
	"crosswalk": Rect2(24, 172, 56, 32),
}

## Актёрский оверлей: для планов, где story frame уже показывает героя в действии,
## дополнительный спрайт не добавляется (иначе дубль персонажа на кадре).
## {"shot": {"hold": true}} — hold-взаимодействие идёт через панель, спрайт не нужен.
const ACTOR_OVERLAY_SUPPRESSED: Dictionary = {
	"alarm": true,
	"rescue": true,
}

## Полноэкранные клипы по enter-команде (свой фон уже внутри клипа).
const FULL_CLIPS: Dictionary = {
	"wing_glitch": "wing_glitch",
	"offer_gift": "offer",
}

## Единая панель для всех планов; смена фона не меняет контраст UI.
const DIALOGUE_PANEL := {"bg": "111a24e8", "border": "8fa3c0", "accent": "d9b45c", "frame": ""}

static func heading(shot: String) -> String:
	return String(SHOT_HEADINGS.get(shot, ""))


static func dialogue_panel(_shot: String) -> Dictionary:
	return DIALOGUE_PANEL


static func hotspot(shot: String) -> Rect2:
	return HOTSPOTS.get(shot, Rect2())


static func is_actor_overlay_suppressed(shot: String) -> bool:
	return ACTOR_OVERLAY_SUPPRESSED.has(shot)


static func full_clip(enter: String) -> String:
	return String(FULL_CLIPS.get(enter, ""))
