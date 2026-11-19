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
	experience += maxi(0, amount)
	while level <= _xp_thresholds.size():
		var required_xp: int = maxi(1, _xp_thresholds[level - 1])
		if experience < required_xp:
			break
		experience -= required_xp
		level += 1
		pending_upgrade_choices += 1
		level_changed.emit(level)

func xp_to_next_level() -> int:
	if level > _xp_thresholds.size():
		return 0
	return maxi(1, _xp_thresholds[level - 1])

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

func _calculate_stats(modifier_groups: Array) -> Dictionary[String, int]:
	var stats: Dictionary[String, int] = {
		"max_hp": _base_max_hp + _max_hp_upgrades * definition.max_hp_upgrade_amount,
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

func restore_full_health() -> void:
	current_hp = max_hp
	_death_emitted = false
	health_changed.emit(current_hp, max_hp)

func is_dead() -> bool:
	return current_hp == 0
