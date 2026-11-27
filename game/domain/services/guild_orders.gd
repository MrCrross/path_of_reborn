class_name GuildOrders
extends RefCounted

const DATA_PATH := "res://data/route/guild_orders.json"
const RANKS: Array[String] = ["E", "D", "C", "B", "A", "S"]
const TYPE_LABELS := {"escort": "Сопровождение", "hunt": "Охота", "rescue": "Спасение"}

static var _data: Dictionary

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data

static func definition(order_id: String) -> Dictionary:
	return data().get("orders", {}).get(order_id, {})

static func rank_rules(rank: String) -> Dictionary:
	return data().get("ranks", {}).get(rank, {})

static func order_type(order: Dictionary) -> Dictionary:
	return data().get("types", {}).get(order.get("type", ""), {})

static func stage(order_id: String, index: int, total: int) -> Dictionary:
	var order: Dictionary = definition(order_id)
	if order.is_empty() or index < 0 or index >= total:
		return {}
	var kind: Dictionary = order_type(order)
	var enemies: Array = kind["enemies"]
	var objectives: Array = kind["objectives"]
	var final: bool = index == total - 1
	var enemy_id: String = kind["final_enemy"] if final else enemies[index % enemies.size()]
	var rules: Dictionary = rank_rules(order["rank"])
	var battle: Dictionary = data()["battle"]
	var slots: Array[Dictionary] = [{"actor_id": enemy_id}]
	if order["type"] == "rescue" and (final or index % 3 == 2):
		slots.append({"id": "bandit_reinforcement", "actor_id": enemy_id, "telegraph_offset": 32})
	return {
		"enemy_id": enemy_id,
		"enemies": slots,
		"objective": kind["final_objective"] if final else objectives[index % objectives.size()],
		"hp": int(rules["enemy_hp"]) + mini(index, int(battle["stage_hp_cap"])) + (int(battle["final_hp_bonus"]) if final else 0),
		"strength": int(rules["enemy_strength"]) + (int(battle["final_strength_bonus"]) if final else 0),
		"xp": int(battle["xp"]),
		"rewards": [{"item_id": kind["material"], "quantity": 1}],
	}

static func bonus_loot(rank: String, index: int, total: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var loot: Dictionary = data()["stage_loot"]
	var progress: float = float(index) / maxi(1, total - 1)
	var chance: float = lerpf(float(loot["first_chance"]), float(loot["last_chance"]), progress)
	if rng.randf() >= chance:
		return []
	var rank_level: int = int(rank_rules(rank)["level"])
	var gear: Array = loot["gear"]
	return [{
		"item_id": gear[rng.randi_range(0, gear.size() - 1)],
		"quantity": 1,
		"level": clampi(rank_level - 1, 1, 5),
		"sellable": true,
		"sale_price_copper": 4 + rank_level * 3,
	}]

static func valid_progress(progress: Variant) -> bool:
	if not progress is Dictionary:
		return false
	if progress.is_empty():
		return true
	if not progress.get("id") is String:
		return false
	var order: Dictionary = definition(progress["id"])
	if order.is_empty() or not _whole_number(progress.get("total")) or not _whole_number(progress.get("cleared")):
		return false
	var rules: Dictionary = rank_rules(order["rank"])
	var total: int = int(progress["total"])
	return total >= int(rules["min"]) and total <= int(rules["max"]) and int(progress["cleared"]) >= 0 and int(progress["cleared"]) <= total

static func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
