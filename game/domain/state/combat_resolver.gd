class_name CombatResolver
extends RefCounted

signal phase_changed(phase: int, ticks_remaining: int)
signal damage_dealt(target_id: String, amount: int)
signal dodge_resolved(success: bool)
## Один источник индикации защиты для любого режима: "auto" (полный автобой)
## или "active" (ручной режим). Эмитится в момент успешного начала защиты.
signal dodge_begun(source: String)
signal hero_attack_begun(run_id: String)
signal hero_attack_landed(run_id: String, target_id: String, amount: int)
signal ability_used(ability_id: String)
signal finished(won: bool)

enum Phase {
	TELEGRAPH,
	STARTUP,
	ACTIVE,
	RECOVERY,
	VULNERABILITY,
}

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
var enemy: CharacterState
var enemy_phase: int = Phase.TELEGRAPH
var phase_ticks_remaining: int = 0
var hero_attack_cooldown: int = 0
var hero_ability_cooldown: int = 0
var dodge_ticks_remaining: int = 0
var dodge_cooldown: int = 0
var strike_index: int = 0
var tick_count: int = 0
var is_finished: bool = false
var won: bool = false

## Замах героя в полёте: контакт наступит через столько тиков. Урон наносится
## только на контакте, не в момент начала замаха.
var _hero_strike_ticks_remaining: int = 0
var _hero_strike_started: bool = false
var _hero_strike_multiplier: float = 1.0
## Автоматические базовые атаки (подтверждённый режим по умолчанию). Ручной
## запрос через request_attack() использует тот же путь и общий cooldown.
var auto_attack_enabled: bool = true
## Полный автобой: попытки уклонения принадлежат resolver'у; в активном режиме
## источником dodge является игрок через request_dodge() (общий путь защиты).
var auto_dodge_enabled: bool = false
var auto_dodge_cooldown: int = 0

func _init(hero_state: CharacterState, enemy_definition: ActorDefinition, combat_run_id: String = "") -> void:
	run_id = combat_run_id
	hero = hero_state
	enemy = CharacterState.new(enemy_definition)
	_enter_phase(Phase.TELEGRAPH)

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
	_begin_hero_strike()
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
		_tick_hero_strike()
		if not is_active or is_finished:
			return
		phase_ticks_remaining -= 1
		if phase_ticks_remaining <= 0:
			_advance_phase()
		if not is_active or is_finished:
			return
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
	return enemy_phase == Phase.VULNERABILITY

func _begin_hero_strike() -> void:
	_hero_strike_started = true
	_hero_strike_ticks_remaining = maxi(0, hero.definition.attack_startup_ticks)
	hero_attack_cooldown = hero.definition.attack_cooldown_ticks
	hero_attack_begun.emit(run_id)

func _tick_hero_strike() -> void:
	if not _hero_strike_started:
		return
	_hero_strike_ticks_remaining -= 1
	if _hero_strike_ticks_remaining > 0:
		return
	_hero_strike_started = false
	if is_finished or enemy.is_dead():
		return
	# Множитель уязвимости считается в момент контакта.
	var multiplier: float = 1.0
	if enemy_phase == Phase.VULNERABILITY:
		multiplier = enemy.definition.vulnerability_multiplier
	multiplier *= _hero_strike_multiplier
	_hero_strike_multiplier = 1.0
	var damage: int = CharacterState.calculate_damage(hero.strength, enemy.defense, multiplier)
	var applied_damage: int = enemy.take_damage(damage)
	damage_dealt.emit(enemy.definition.id, applied_damage)
	hero_attack_landed.emit(run_id, enemy.definition.id, applied_damage)
	if enemy.is_dead():
		_finish(true)

func _advance_phase() -> void:
	match enemy_phase:
		Phase.TELEGRAPH:
			_enter_phase(Phase.STARTUP)
		Phase.STARTUP:
			_enter_phase(Phase.ACTIVE)
		Phase.ACTIVE:
			if strike_index + 1 < enemy.definition.attacks_per_cycle:
				strike_index += 1
				_enter_phase(Phase.STARTUP)
			else:
				_enter_phase(Phase.RECOVERY)
		Phase.RECOVERY:
			_enter_phase(Phase.VULNERABILITY)
		Phase.VULNERABILITY:
			strike_index = 0
			_enter_phase(Phase.TELEGRAPH)

func _enter_phase(next_phase: int) -> void:
	enemy_phase = next_phase
	match enemy_phase:
		Phase.TELEGRAPH:
			phase_ticks_remaining = enemy.definition.telegraph_ticks
		Phase.STARTUP:
			phase_ticks_remaining = enemy.definition.startup_ticks
		Phase.ACTIVE:
			phase_ticks_remaining = enemy.definition.active_ticks
		Phase.RECOVERY:
			phase_ticks_remaining = enemy.definition.recovery_ticks
		Phase.VULNERABILITY:
			phase_ticks_remaining = enemy.definition.vulnerability_ticks
	# Автозащита полного автобоя: одна попытка на цикл (первая STARTUP),
	# только при готовности; повторный удар гоблина бесплатной попытки не даёт.
	if enemy_phase == Phase.STARTUP and strike_index == 0 and auto_dodge_enabled:
		_try_auto_dodge()
	phase_changed.emit(enemy_phase, phase_ticks_remaining)
	if enemy_phase == Phase.ACTIVE:
		_resolve_enemy_strike()

func _try_auto_dodge() -> void:
	if not is_active or is_finished or auto_dodge_cooldown > 0 or dodge_cooldown > 0 or dodge_ticks_remaining > 0:
		return
	_begin_dodge("auto")
	auto_dodge_cooldown = AUTO_DODGE_COOLDOWN_TICKS

func _begin_dodge(source: String) -> void:
	dodge_ticks_remaining = hero.definition.dodge_duration_ticks
	dodge_begun.emit(source)

func _resolve_enemy_strike() -> void:
	if dodge_ticks_remaining > 0:
		dodge_resolved.emit(true)
		return
	dodge_resolved.emit(false)
	var damage: int = CharacterState.calculate_damage(
		enemy.strength,
		hero.defense,
		enemy.definition.attack_multiplier
	)
	var applied_damage: int = hero.take_damage(damage)
	damage_dealt.emit("hero", applied_damage)
	if hero.is_dead():
		_finish(false)

func _finish(player_won: bool) -> void:
	if not is_active or is_finished:
		return
	is_finished = true
	_hero_strike_started = false
	won = player_won
	finished.emit(won)
