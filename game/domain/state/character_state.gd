class_name CharacterState
extends RefCounted

signal health_changed(current_hp: int, max_hp: int)
signal died
signal level_changed(level: int)
signal stats_changed

var definition: ActorDefinition
var level: int = 1
var experience: int = 0
var pending_upgrade_choices: int = 0
var current_hp: int = 0
var max_hp: int = 0
var strength: int = 0
var defense: int = 0
var mana: int = 0

var _base_max_hp: int = 0
var _base_strength: int = 0
var _base_defense: int = 0
var _base_mana: int = 0
var _strength_upgrades: int = 0
var _max_hp_upgrades: int = 0
var _xp_thresholds: Array[int] = []
var _death_emitted: bool = false
var _modifiers: Dictionary = {}
var _void_traces: int = 0

func _init(actor_definition: ActorDefinition) -> void:
	definition = actor_definition
	_base_max_hp = maxi(1, actor_definition.max_hp)
	_base_strength = actor_definition.strength
	_base_defense = actor_definition.defense
	_base_mana = actor_definition.mana
	_xp_thresholds = actor_definition.xp_thresholds.duplicate()
	recompute_stats()
	current_hp = max_hp

static func calculate_damage(attack: int, target_defense: int, window_multiplier: float = 1.0) -> int:
	return maxi(1, roundi((attack - target_defense) * window_multiplier))

func take_damage(amount: int) -> int:
	if is_dead():
		return 0
	var previous_hp: int = current_hp
	current_hp = clampi(current_hp - maxi(0, amount), 0, max_hp)
	var damage_taken: int = previous_hp - current_hp
	if damage_taken > 0:
		health_changed.emit(current_hp, max_hp)
	if current_hp == 0 and not _death_emitted:
		_death_emitted = true
		died.emit()
	return damage_taken

func heal(amount: int) -> int:
	if is_dead():
		return 0
	var previous_hp: int = current_hp
	current_hp = clampi(current_hp + maxi(0, amount), 0, max_hp)
	var healing_received: int = current_hp - previous_hp
	if healing_received > 0:
		health_changed.emit(current_hp, max_hp)
	return healing_received

func gain_xp(amount: int) -> void:
	var allocation: Dictionary = calculate_level_gain(level, experience, _xp_thresholds, amount)
	experience = int(allocation["experience"])
	var gained: int = int(allocation["levels_gained"])
	level = int(allocation["level"])
	pending_upgrade_choices += gained
	for gained_level: int in allocation["levels"]:
		level_changed.emit(gained_level)

func xp_to_next_level() -> int:
	if level > _xp_thresholds.size():
		return 0
	return maxi(1, _xp_thresholds[level - 1])

## Честный прогноз начисления опыта для экрана результата: до claim игрок
## видит, какой уровень и остаток опыта даст получение награды.
func preview_level_gain(amount: int) -> Dictionary:
	var preview: Dictionary = calculate_level_gain(level, experience, _xp_thresholds, amount)
	var next_level: int = int(preview["level"])
	preview["xp_remaining"] = 0
	if next_level <= _xp_thresholds.size():
		preview["xp_remaining"] = maxi(1, _xp_thresholds[next_level - 1]) - int(preview["experience"])
	return preview

static func calculate_level_gain(start_level: int, start_experience: int, thresholds: Array[int], amount: int) -> Dictionary:
	var next_level: int = start_level
	var next_experience: int = start_experience + maxi(0, amount)
	var levels: Array[int] = []
	while next_level <= thresholds.size():
		var required_xp: int = maxi(1, thresholds[next_level - 1])
		if next_experience < required_xp:
			break
		next_experience -= required_xp
		next_level += 1
		levels.append(next_level)
	return {
		"levels_gained": levels.size(),
		"levels": levels,
		"level": next_level,
		"experience": next_experience,
		"upgrade_choices": levels.size(),
	}

## Cap: дальше роста по данным нет; UI показывает понятное состояние, а не 0/0.
func has_reached_level_cap() -> bool:
	return _xp_thresholds.is_empty() or level > _xp_thresholds.size()

## Отображаемая оценка комплекта, не участвующая в расчёте боя.
func power_rating() -> int:
	return max_hp + strength * 4 + defense * 4 + mana * 2

func upgrade_gains() -> Dictionary[String, int]:
	var upgraded_hp: int = _calculate_stats(_modifiers.values(), 1)["max_hp"]
	return {"strength": definition.strength_upgrade_amount, "max_hp": upgraded_hp - max_hp}

func choose_upgrade(upgrade_id: String) -> bool:
	if pending_upgrade_choices == 0:
		return false
	match upgrade_id:
		"strength":
			_strength_upgrades += 1
		"max_hp":
			_max_hp_upgrades += 1
		_:
			return false
	pending_upgrade_choices -= 1
	recompute_stats()
	return true

func set_modifiers(source_id: String, modifiers: Array[StatModifierDefinition]) -> bool:
	if source_id.is_empty():
		return false
	_modifiers[source_id] = modifiers.duplicate()
	recompute_stats()
	return true

func remove_modifiers(source_id: String) -> bool:
	if not _modifiers.has(source_id):
		return false
	_modifiers.erase(source_id)
	recompute_stats()
	return true

func recompute_stats() -> void:
	var stats: Dictionary[String, int] = _calculate_stats(_modifiers.values())
	max_hp = stats["max_hp"]
	strength = stats["strength"]
	defense = stats["defense"]
	mana = stats["mana"]
	current_hp = clampi(current_hp, 0, max_hp)
	stats_changed.emit()

func preview_stats(replaced_sources: Array[String], added_modifiers: Array[StatModifierDefinition]) -> Dictionary[String, int]:
	var kept: Dictionary = _modifiers.duplicate()
	for source_id: String in replaced_sources:
		kept.erase(source_id)
	var modifier_groups: Array = kept.values()
	modifier_groups.append(added_modifiers)
	return _calculate_stats(modifier_groups)

func _calculate_stats(modifier_groups: Array, extra_hp_upgrades: int = 0) -> Dictionary[String, int]:
	var stats: Dictionary[String, int] = {
		"max_hp": _base_max_hp + (_max_hp_upgrades + extra_hp_upgrades) * definition.max_hp_upgrade_amount,
		"strength": _base_strength + _strength_upgrades * definition.strength_upgrade_amount,
		"defense": _base_defense,
		"mana": _base_mana,
	}
	for modifiers: Array in modifier_groups:
		for modifier: StatModifierDefinition in modifiers:
			if stats.has(modifier.stat_id):
				stats[modifier.stat_id] += modifier.amount
	stats["max_hp"] = maxi(1, floori(stats["max_hp"] * (10 - _void_traces) / 10.0))
	return stats

func clear_modifiers() -> void:
	_modifiers.clear()
	recompute_stats()

func set_void_traces(traces: int) -> void:
	_void_traces = clampi(traces, 0, 3)
	recompute_stats()

func capture_dto() -> Dictionary:
	return {
		"level": level,
		"experience": experience,
		"pending_upgrade_choices": pending_upgrade_choices,
		"current_hp": current_hp,
		"strength_upgrades": _strength_upgrades,
		"max_hp_upgrades": _max_hp_upgrades,
	}

func apply_dto(dto: Dictionary) -> void:
	level = maxi(1, int(dto.get("level", 1)))
	experience = maxi(0, int(dto.get("experience", 0)))
	pending_upgrade_choices = maxi(0, int(dto.get("pending_upgrade_choices", 0)))
	_strength_upgrades = maxi(0, int(dto.get("strength_upgrades", 0)))
	_max_hp_upgrades = maxi(0, int(dto.get("max_hp_upgrades", 0)))
	recompute_stats()
	current_hp = clampi(int(dto.get("current_hp", max_hp)), 0, max_hp)
	_death_emitted = is_dead()

func unlocked_abilities() -> Array[AbilityDefinition]:
	var result: Array[AbilityDefinition] = []
	for ability: AbilityDefinition in definition.abilities:
		if level >= ability.unlock_level:
			result.append(ability)
	return result

func first_ability() -> AbilityDefinition:
	return null if definition.abilities.is_empty() else definition.abilities[0]

func restore_full_health() -> void:
	current_hp = max_hp
	_death_emitted = false
	health_changed.emit(current_hp, max_hp)

func is_dead() -> bool:
	return current_hp == 0
