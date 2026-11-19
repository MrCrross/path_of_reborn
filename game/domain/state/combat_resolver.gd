class_name CombatResolver
extends RefCounted

signal phase_changed(phase: int, ticks_remaining: int)
signal damage_dealt(target_id: String, amount: int)
signal dodge_resolved(success: bool)
signal finished(won: bool)

enum Phase {
	TELEGRAPH,
	STARTUP,
	ACTIVE,
	RECOVERY,
	VULNERABILITY,
}

var hero: CharacterState
var enemy: CharacterState
var enemy_phase: int = Phase.TELEGRAPH
var phase_ticks_remaining: int = 0
var hero_attack_cooldown: int = 0
var dodge_ticks_remaining: int = 0
var dodge_cooldown: int = 0
var strike_index: int = 0
var tick_count: int = 0
var is_finished: bool = false
var won: bool = false

func _init(hero_state: CharacterState, enemy_definition: ActorDefinition) -> void:
	hero = hero_state
	enemy = CharacterState.new(enemy_definition)
	_enter_phase(Phase.TELEGRAPH)

func request_attack() -> bool:
	if is_finished or hero_attack_cooldown > 0:
		return false
	hero_attack_cooldown = hero.definition.attack_cooldown_ticks
	var multiplier: float = 1.0
	if enemy_phase == Phase.VULNERABILITY:
		multiplier = enemy.definition.vulnerability_multiplier
	var damage: int = CharacterState.calculate_damage(hero.strength, enemy.defense, multiplier)
	var applied_damage: int = enemy.take_damage(damage)
	damage_dealt.emit(enemy.definition.id, applied_damage)
	if enemy.is_dead():
		_finish(true)
	return true

func request_dodge() -> bool:
	if is_finished or dodge_cooldown > 0:
		return false
	dodge_ticks_remaining = hero.definition.dodge_duration_ticks
	dodge_cooldown = hero.definition.dodge_cooldown_ticks
	return true

func advance_ticks(count: int) -> void:
	for _tick: int in range(maxi(0, count)):
		if is_finished:
			return
		tick_count += 1
		phase_ticks_remaining -= 1
		if phase_ticks_remaining <= 0:
			_advance_phase()
		hero_attack_cooldown = maxi(0, hero_attack_cooldown - 1)
		dodge_ticks_remaining = maxi(0, dodge_ticks_remaining - 1)
		dodge_cooldown = maxi(0, dodge_cooldown - 1)

func is_vulnerable() -> bool:
	return enemy_phase == Phase.VULNERABILITY

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
	phase_changed.emit(enemy_phase, phase_ticks_remaining)
	if enemy_phase == Phase.ACTIVE:
		_resolve_enemy_strike()

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
	if is_finished:
		return
	is_finished = true
	won = player_won
	finished.emit(won)
