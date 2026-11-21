class_name UiText
extends RefCounted

## Локализованные подписи внутренних ID для UI.
## Технические ID (common, moss, checkpoint_000123) не выводятся игроку как основной текст.

const RARITY_LABELS: Dictionary = {
	"common": "Обычный",
	"uncommon": "Необычный",
	"rare": "Редкий",
	"epic": "Эпический",
}
const ASPECT_LABELS: Dictionary = {
	"moss": "Рост",
	"goblin": "Сумрак",
	"unspecified": "",
	"": "",
}
const TYPE_LABELS: Dictionary = {
	"weapon": "Оружие",
	"charm": "Амулет",
	"material": "Материал",
	"echo": "Кристалл Эха",
}
const SLOT_LABELS: Dictionary = {
	"helmet": "Шлем",
	"armor": "Доспех",
	"weapon": "Оружие",
	"boots": "Обувь",
	"shoulders": "Наплечники",
	"familiar": "Фамильяр",
	"charm": "Амулет",
	"ring": "Кольцо",
}
const STAT_LABELS: Dictionary = {
	"max_hp": "Макс. HP",
	"strength": "Сила",
	"defense": "Защита",
	"mana": "Мана",
}
const LOCATION_LABELS: Dictionary = {
	"lioren": "Лиорен",
	"forest_edge": "Граница леса",
}
const ENEMY_LABELS: Dictionary = {
	"moss_slime": "Слизь-тина",
	"goblin_scout": "Гоблин-разведчик",
	"goblin_trial": "Гоблин-испытание",
}


static func rarity(rarity_id: String) -> String:
	return String(RARITY_LABELS.get(rarity_id, "")) if RARITY_LABELS.has(rarity_id) else rarity_id


static func aspect(aspect_id: String) -> String:
	return String(ASPECT_LABELS.get(aspect_id, ""))


static func item_type(type_id: String) -> String:
	return String(TYPE_LABELS.get(type_id, type_id))


static func slot(slot_id: String) -> String:
	return String(SLOT_LABELS.get(slot_id, slot_id))


static func stat(stat_id: String) -> String:
	return String(STAT_LABELS.get(stat_id, stat_id))


static func location(location_id: String) -> String:
	return String(LOCATION_LABELS.get(location_id, location_id))


static func enemy_name(enemy_id: String) -> String:
	return String(ENEMY_LABELS.get(enemy_id, enemy_id))

static func astra(copper: int) -> String:
	var value: int = maxi(0, copper)
	if value >= 100 and value % 100 == 0:
		return "%s сер." % _grouped(value / 100)
	return "%s мед." % _grouped(value)

static func currency_compact(copper: int) -> String:
	var value: int = maxi(0, copper)
	if value < 1000:
		return str(value)
	var units: Array[String] = ["K", "M", "B", "T", "Q"]
	var scaled: float = float(value)
	var unit: String = ""
	for next_unit: String in units:
		scaled /= 1000.0
		unit = next_unit
		if scaled < 1000.0:
			break
	var shortened: float = floorf(scaled * 10.0) / 10.0
	return ("%d" % int(shortened)) + unit if is_equal_approx(shortened, floorf(shortened)) else ("%.1f%s" % [shortened, unit])

static func currency_exact(copper: int) -> String:
	return "%s мед. астры" % _grouped(maxi(0, copper))

static func _grouped(value: int) -> String:
	var digits: String = str(maxi(0, value))
	var result: String = ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += " "
		result += digits[index]
	return result
