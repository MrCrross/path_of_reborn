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
	"water": "Вода",
	"stone_radiant": "Камень · лучистый",
	"unspecified": "",
	"": "",
}
const TYPE_LABELS: Dictionary = {
	"weapon": "Оружие",
	"armor": "Доспех",
	"charm": "Амулет",
	"material": "Материал",
	"quest": "Сюжетный предмет",
	"echo": "Кристалл Эха",
	"consumable": "Расходник",
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
	"whispering_grass_grove": "Роща Шелестящих Трав",
	"blue_hollow": "Синий Овраг",
	"winds_edge": "Край Ветров",
	"forest_edge": "Граница леса",
}
const ENEMY_LABELS: Dictionary = {
	"moss_slime": "Слизь-тина",
	"goblin_scout": "Гоблин-разведчик",
	"goblin_trial": "Гоблин-испытание",
	"needle_hound": "Иглопёс",
	"dust_moth": "Пыльный мотылёк",
	"root_weaver": "Корневой плетун",
	"river_shieldback": "Речной щитень",
	"stone_rodent": "Каменный грызун",
	"ash_raven": "Пепельный ворон",
	"crystal_toad": "Кристальная жаба",
}
const COIN_SUFFIXES: Dictionary = {GameSession.COPPER: "мед.", GameSession.SILVER: "сер.", GameSession.GOLD: "зол."}


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

static func astra(amount: int, coin: String = GameSession.COPPER) -> String:
	return _grouped(amount) + " " + COIN_SUFFIXES[coin]

static func astra_compact(amount: int, coin: String = GameSession.COPPER) -> String:
	return coin_count(amount) + " " + COIN_SUFFIXES[coin]

static func coin_count(amount: int) -> String:
	var value: int = maxi(0, amount)
	var scale: int = 1000
	if value < 10000:
		return _grouped(value)
	var units: Array[String] = ["K", "M", "B", "T", "Q", "E"]
	var unit_index: int = 0
	@warning_ignore_start("integer_division")
	while value / scale >= 1000:
		scale *= 1000
		unit_index += 1
	var compact: String = str(value / scale)
	var tenths: int = (value % scale) / (scale / 10)
	@warning_ignore_restore("integer_division")
	if tenths > 0:
		compact += ",%d" % tenths
	return compact + units[unit_index]

static func wallet(wallet_balances: Dictionary[String, int], separator: String = " · ") -> String:
	var amounts: PackedStringArray = []
	for coin: String in GameSession.COIN_TYPES:
		amounts.append(astra(wallet_balances[coin], coin))
	return separator.join(amounts)

static func _grouped(value: int) -> String:
	var digits: String = str(maxi(0, value))
	var result: String = ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += " "
		result += digits[index]
	return result
