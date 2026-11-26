class_name CombatResolver
extends RefCounted

signal phase_changed(phase: int, ticks_remaining: int)
signal enemy_phase_changed(instance_id: String)
signal target_changed(instance_id: String)
signal pollen_resolved(avoided: bool)
signal damage_dealt(target_id: String, amount: int)
signal dodge_resolved(success: bool)
## Один источник индикации защиты для любого режима: "auto" (полный автобой)
## или "active" (ручной режим). Эмитится в момент успешного начала защиты.
signal dodge_begun(source: String)
signal hero_attack_begun(run_id: String)
signal hero_attack_landed(run_id: String, target_id: String, amount: int)
signal ability_used(ability_id: String)
signal ally_action(action: String)
signal finished(won: bool)

enum Phase {
	TELEGRAPH,
	STARTUP,
	ACTIVE,
	RECOVERY,
	VULNERABILITY,
}

class EnemySlot:
	var instance_id: String
	var actor: CharacterState
	var attack_id: String
	var phase: int = Phase.TELEGRAPH
	var remaining: int = 0
	var strike_index: int = 0
	var pollen_slow_ticks: int = 0
	var stunned: bool = false
	var dormant: bool = false

	func _init(definition: ActorDefinition, options: Dictionary) -> void:
		instance_id = String(options.get("id", definition.id))
		actor = CharacterState.new(definition)
		attack_id = String(options.get("attack", "attack"))
		pollen_slow_ticks = int(options.get("pollen_slow_ticks", 0))
		dormant = bool(options.get("dormant", false))

## Политика автозащиты полного автобоя (гипотеза для сравнения, не готовый
## баланс): попытка на входе в первую STARTUP-фазу цикла, если защита готова.
## Длительный cooldown не даёт защите покрыть все циклы — автобой не становится
## неуязвимостью. Обычный dodge cooldown героя (0,7 с) при этом не используется:
## политика честно покрывает лишь часть ударов.
const AUTO_DODGE_COOLDOWN_TICKS: int = 150

## Стабильный ID попытки боя; назначается GameSession. enemy_id — тип врага,
## run_id — конкретная встреча: награда положена за новый выигранный run.
var run_id: String = ""
var run_token: String = ""
var combat_format: String = "auto"
var is_active: bool = true
var hero: CharacterState
var enemy_slots: Array[EnemySlot] = []
# Каким бы ни был текущий выбор, ссылки старых одиночных встреч стабильны.
var enemy: CharacterState:
	get: return enemy_slots[0].actor
var enemy_phase: int:
	get: return enemy_slots[0].phase
var phase_ticks_remaining: int:
	get: return enemy_slots[0].remaining
var strike_index: int:
	get: return enemy_slots[0].strike_index
var target: EnemySlot
var vulnerable_ability_bonus: float = 1.0
var tempo_window_ticks: int = 0
var tempo_startup_reduction: int = 0
var _tempo_ticks: int = 0
var slowed_ticks: int = 0
var hero_attack_cooldown: int = 0
var hero_ability_cooldown: int = 0
var dodge_ticks_remaining: int = 0
var dodge_cooldown: int = 0
var tick_count: int = 0
var is_finished: bool = false
var won: bool = false
var ally_warnings: PackedInt32Array = PackedInt32Array()
var warden_pattern: Dictionary = {}
var warden_phase: int = 1
var warden_move: String = "attack"
var _warden_swept: bool = false
var _warden_summoned: bool = false
var _warden_void_struck: bool = false
var _warden_opened: bool = false

## Замах героя в полёте: контакт наступит через столько тиков. Урон наносится
## только на контакте, не в момент начала замаха.
var _hero_strike_ticks_remaining: int = 0
var _hero_strike_started: bool = false
var _hero_strike_multiplier: float = 1.0
var _hero_strike_target: EnemySlot
var _hero_strike_is_ability: bool = false
## Автоматические базовые атаки (подтверждённый режим по умолчанию). Ручной
## запрос через request_attack() использует тот же путь и общий cooldown.
var auto_attack_enabled: bool = true
## Полный автобой: попытки уклонения принадлежат resolver'у; в активном режиме
## источником dodge является игрок через request_dodge() (общий путь защиты).
var auto_dodge_enabled: bool = false
var auto_dodge_cooldown: int = 0

func _init(hero_state: CharacterState, enemy_definition: ActorDefinition, combat_run_id: String = "", first_options: Dictionary = {}, second_definition: ActorDefinition = null, second_options: Dictionary = {}) -> void:
	run_id = combat_run_id
	hero = hero_state
	_add_enemy(enemy_definition, first_options)
	if second_definition != null:
		_add_enemy(second_definition, second_options)
	target = enemy_slots[0]

func _add_enemy(definition: ActorDefinition, options: Dictionary) -> void:
	var slot := EnemySlot.new(definition, options)
	enemy_slots.append(slot)
	if slot.dormant:
		return
	_enter_phase(slot, Phase.TELEGRAPH)
	slot.remaining = maxi(1, slot.remaining + int(options.get("telegraph_offset", 0)))
	var stun_ticks: int = int(options.get("initial_stun_ticks", 0))
	if stun_ticks > 0:
		_enter_phase(slot, Phase.VULNERABILITY)
		slot.stunned = true
		slot.remaining = stun_ticks

func add_encounter_enemy(definition: ActorDefinition, options: Dictionary) -> void:
	assert(tick_count == 0 and not _hero_strike_started)
	_add_enemy(definition, options)

func select_target(instance_id: String) -> bool:
	if not is_active or is_finished or combat_format != "active":
		return false
	for slot: EnemySlot in enemy_slots:
		if slot.instance_id == instance_id and not slot.dormant and not slot.actor.is_dead():
			_set_target(slot)
			return true
	return false

func _set_target(slot: EnemySlot) -> void:
	if target != slot:
		target = slot
		target_changed.emit(slot.instance_id)

## Ручной запрос атаки (тесты/режимы без автоатаки). Доменный путь тот же, что
## у автоатаки: двойной удар в один тик невозможен, cooldown общий.
func request_attack() -> bool:
	if not is_active or is_finished or hero_attack_cooldown > 0 or _hero_strike_started:
		return false
	_hero_strike_multiplier = 1.0
	_begin_hero_strike()
	return true

func request_ability() -> bool:
	var ability: AbilityDefinition = hero.first_ability()
	if ability == null or hero.level < ability.unlock_level or not is_active or is_finished or hero_attack_cooldown > 0 or _hero_strike_started or hero_ability_cooldown > 0:
		return false
	_hero_strike_multiplier = ability.damage_multiplier
	hero_ability_cooldown = ability.cooldown_ticks
	_begin_hero_strike(true)
	ability_used.emit(ability.id)
	return true

func request_dodge() -> bool:
	if not is_active or is_finished or dodge_cooldown > 0 or dodge_ticks_remaining > 0:
		return false
	_begin_dodge("manual")
	dodge_cooldown = hero.definition.dodge_cooldown_ticks
	return true

func invalidate() -> void:
	if not is_active:
		return
	is_active = false
	_hero_strike_started = false
	_hero_strike_ticks_remaining = 0
	dodge_ticks_remaining = 0

## Детерминированный порядок одного тика: сначала контакт героя, затем фазы
## врага (в ACTIVE — его удар), затем cooldown'ы, затем авто-начало нового
## замаха. Batching (advance_ticks(n)) повторяет этот порядок n раз.
func advance_ticks(count: int) -> void:
	for _tick: int in range(maxi(0, count)):
		if not is_active or is_finished:
			return
		tick_count += 1
		if tick_count in ally_warnings:
			ally_action.emit("hold" if tick_count == ally_warnings[0] else "dive_warning")
		_tick_hero_strike()
		if not is_active or is_finished:
			return
		for slot: EnemySlot in enemy_slots:
			if slot.dormant or slot.actor.is_dead():
				continue
			slot.remaining -= 1
			if slot.remaining <= 0:
				_advance_phase(slot)
			if not is_active or is_finished:
				return
		slowed_ticks = maxi(0, slowed_ticks - 1)
		_tempo_ticks = maxi(0, _tempo_ticks - 1)
		hero_attack_cooldown = maxi(0, hero_attack_cooldown - 1)
		hero_ability_cooldown = maxi(0, hero_ability_cooldown - 1)
		dodge_ticks_remaining = maxi(0, dodge_ticks_remaining - 1)
		dodge_cooldown = maxi(0, dodge_cooldown - 1)
		auto_dodge_cooldown = maxi(0, auto_dodge_cooldown - 1)
		if auto_attack_enabled and hero_attack_cooldown == 0 and not _hero_strike_started:
			if hero_ability_cooldown == 0 and request_ability():
				continue
			_begin_hero_strike()

func is_vulnerable() -> bool:
	return target.phase == Phase.VULNERABILITY

func _begin_hero_strike(ability: bool = false) -> void:
	_hero_strike_started = true
	_hero_strike_target = target
	_hero_strike_is_ability = ability
	_hero_strike_ticks_remaining = maxi(0, hero.definition.attack_startup_ticks)
	hero_attack_cooldown = hero.definition.attack_cooldown_ticks
	if slowed_ticks > 0:
		_hero_strike_ticks_remaining += ceili(hero.definition.attack_startup_ticks * 0.5)
		hero_attack_cooldown += ceili(hero.definition.attack_cooldown_ticks * 0.5)
	if _tempo_ticks > 0:
		_hero_strike_ticks_remaining = maxi(1, _hero_strike_ticks_remaining - tempo_startup_reduction)
		_tempo_ticks = 0
	hero_attack_begun.emit(run_id)

func _tick_hero_strike() -> void:
	if not _hero_strike_started:
		return
	_hero_strike_ticks_remaining -= 1
	if _hero_strike_ticks_remaining > 0:
		return
	_hero_strike_started = false
	var slot: EnemySlot = _hero_strike_target
	var strike_multiplier: float = _hero_strike_multiplier
	_hero_strike_multiplier = 1.0
	if is_finished or slot.actor.is_dead():
		return
	# Умение и уязвимость оцениваются на контакте с целью замаха.
	if slot.phase == Phase.VULNERABILITY:
		strike_multiplier *= slot.actor.definition.vulnerability_multiplier
		if _hero_strike_is_ability:
			strike_multiplier *= vulnerable_ability_bonus
	else:
		strike_multiplier *= slot.actor.definition.guarded_damage_multiplier
	var damage: int = CharacterState.calculate_damage(hero.strength, slot.actor.defense, strike_multiplier)
	var warden: bool = _is_warden(slot)
	if warden and not _warden_opened:
		var gate: String = "phase_two_hp" if warden_phase == 1 else "joint_break_hp"
		damage = clampi(damage, 0, slot.actor.current_hp - int(warden_pattern[gate]))
	var applied_damage: int = slot.actor.take_damage(damage)
	if warden:
		_update_warden_after_hit(slot)
	if applied_damage > 0:
		damage_dealt.emit(slot.instance_id, applied_damage)
	hero_attack_landed.emit(run_id, slot.instance_id, applied_damage)
	if not slot.actor.is_dead():
		return
	for survivor: EnemySlot in enemy_slots:
		if not survivor.dormant and not survivor.actor.is_dead():
			if target == slot:
				_set_target(survivor)
			return
	_finish(true)

func _advance_phase(slot: EnemySlot) -> void:
	var warden: bool = _is_warden(slot)
	match slot.phase:
		Phase.TELEGRAPH:
			_enter_phase(slot, Phase.STARTUP)
		Phase.STARTUP:
			_enter_phase(slot, Phase.ACTIVE)
		Phase.ACTIVE:
			var strikes: int = warden_phase if warden else slot.actor.definition.attacks_per_cycle
			if slot.strike_index + 1 < strikes:
				slot.strike_index += 1
				_enter_phase(slot, Phase.STARTUP)
			else:
				_enter_phase(slot, Phase.RECOVERY)
		Phase.RECOVERY:
			if warden and _try_begin_warden_phase_two(slot):
				return
			if not warden or not _try_open_warden(slot):
				_enter_phase(slot, Phase.VULNERABILITY)
		Phase.VULNERABILITY:
			slot.strike_index = 0
			_enter_phase(slot, Phase.TELEGRAPH)

func _enter_phase(slot: EnemySlot, next_phase: int) -> void:
	slot.phase = next_phase
	slot.stunned = false
	var definition: ActorDefinition = slot.actor.definition
	if _is_warden(slot) and slot.phase in [Phase.TELEGRAPH, Phase.STARTUP]:
		warden_move = "void" if slot.strike_index == 1 else ("summon" if warden_phase == 2 and not _warden_summoned else "attack")
	match slot.phase:
		Phase.TELEGRAPH:
			slot.remaining = definition.telegraph_ticks
		Phase.STARTUP:
			slot.remaining = definition.startup_ticks
		Phase.ACTIVE:
			slot.remaining = definition.active_ticks
		Phase.RECOVERY:
			slot.remaining = definition.recovery_ticks
		Phase.VULNERABILITY:
			slot.remaining = definition.vulnerability_ticks
	if slot.phase == Phase.STARTUP and auto_dodge_enabled and (slot.strike_index == 0 or (_is_warden(slot) and warden_move == "void")) and not (_is_warden(slot) and warden_move == "summon"):
		_try_auto_dodge()
	if slot == enemy_slots[0]:
		phase_changed.emit(slot.phase, slot.remaining)
	enemy_phase_changed.emit(slot.instance_id)
	if slot.phase == Phase.ACTIVE:
		_resolve_enemy_strike(slot)

func _try_auto_dodge() -> void:
	if not is_active or is_finished or auto_dodge_cooldown > 0 or dodge_cooldown > 0 or dodge_ticks_remaining > 0:
		return
	_begin_dodge("auto")
	auto_dodge_cooldown = AUTO_DODGE_COOLDOWN_TICKS

func _begin_dodge(source: String) -> void:
	dodge_ticks_remaining = hero.definition.dodge_duration_ticks
	dodge_begun.emit(source)

func _resolve_enemy_strike(slot: EnemySlot) -> void:
	var attack_multiplier: float = slot.actor.definition.attack_multiplier
	if _is_warden(slot):
		if warden_move == "summon":
			_summon_warden_raven()
			return
		if warden_move == "void":
			_warden_void_struck = true
			attack_multiplier = float(warden_pattern["void_multiplier"])
		else:
			_warden_swept = true
	if slot.pollen_slow_ticks > 0:
		var avoided: bool = dodge_ticks_remaining > 0
		if avoided:
			_tempo_ticks = tempo_window_ticks
		else:
			slowed_ticks = maxi(slowed_ticks, slot.pollen_slow_ticks)
		dodge_resolved.emit(avoided)
		pollen_resolved.emit(avoided)
		return
	if dodge_ticks_remaining > 0:
		_tempo_ticks = tempo_window_ticks
		dodge_resolved.emit(true)
		return
	dodge_resolved.emit(false)
	var damage: int = CharacterState.calculate_damage(
		slot.actor.strength,
		hero.defense,
		attack_multiplier
	)
	var applied_damage: int = hero.take_damage(damage)
	damage_dealt.emit("hero", applied_damage)
	if hero.is_dead():
		_finish(false)

func _is_warden(slot: EnemySlot) -> bool:
	return not warden_pattern.is_empty() and slot == enemy_slots[0]

func _update_warden_after_hit(slot: EnemySlot) -> void:
	if _try_begin_warden_phase_two(slot):
		return
	if _warden_void_struck:
		_try_open_warden(slot)

func _try_begin_warden_phase_two(slot: EnemySlot) -> bool:
	if warden_phase != 1 or not _warden_swept or slot.actor.current_hp > int(warden_pattern["phase_two_hp"]):
		return false
	if slot.phase == Phase.ACTIVE:
		return false
	warden_phase = 2
	slot.strike_index = 0
	_enter_phase(slot, Phase.TELEGRAPH)
	ally_action.emit("summon_warning")
	return true

func _summon_warden_raven() -> void:
	_warden_summoned = true
	for slot: EnemySlot in enemy_slots:
		if slot.dormant:
			slot.dormant = false
			_enter_phase(slot, Phase.TELEGRAPH)
			slot.remaining += int(warden_pattern["raven_offset_ticks"])
			if combat_format == "auto":
				_set_target(slot)

func _try_open_warden(slot: EnemySlot) -> bool:
	if _warden_opened or not _warden_void_struck or slot.actor.current_hp > int(warden_pattern["joint_break_hp"]):
		return false
	_warden_opened = true
	_enter_phase(slot, Phase.VULNERABILITY)
	slot.stunned = true
	slot.remaining = int(warden_pattern["joint_break_ticks"])
	enemy_phase_changed.emit(slot.instance_id)
	ally_action.emit("joint_break")
	return true

func _finish(player_won: bool) -> void:
	if not is_active or is_finished:
		return
	is_finished = true
	_hero_strike_started = false
	won = player_won
	finished.emit(won)
