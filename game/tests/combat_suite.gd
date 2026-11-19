extends RefCounted

const DomainSuite = preload("res://tests/domain_suite.gd")
const TestContext = DomainSuite.TestContext
const SLIME_PATH: String = "res://data/actors/moss_slime.tres"
const GOBLIN_PATH: String = "res://data/actors/goblin_scout.tres"

class FinishCounter:
	extends RefCounted

	var count: int = 0

	func record(_won: bool) -> void:
		count += 1

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_run_case("slime_telegraph_startup_active_boundaries", _test_slime_boundaries))
	results.append(_run_case("goblin_double_slash_and_vulnerability", _test_goblin_cycle))
	results.append(_run_case("dodge_success_failure_and_early_expiry", _test_dodge))
	results.append(_run_case("hero_attack_cooldown_and_vulnerability", _test_attack_windows))
	results.append(_run_case("active_phase_deals_damage_once", _test_damage_once))
	results.append(_run_case("both_enemies_have_reachable_victory", _test_reachable_victory))
	results.append(_run_case("both_enemies_have_defeat_and_terminal_lock", _test_defeat_and_terminal))
	results.append(_run_case("retry_is_clean_and_victory_xp_is_once", _test_retry_and_session))
	results.append(_run_case("tick_batching_preserves_deterministic_outcome", _test_tick_batching))
	return results

func _run_case(case_name: String, test: Callable) -> Dictionary:
	var context := TestContext.new()
	test.call(context)
	return {"name": case_name, "checks": context.checks}

func _combat(enemy_path: String = SLIME_PATH) -> CombatResolver:
	var hero_definition: ActorDefinition = load("res://data/actors/haruto.tres")
	var enemy_definition: ActorDefinition = load(enemy_path)
	return CombatResolver.new(CharacterState.new(hero_definition), enemy_definition)

func _test_slime_boundaries(context: TestContext) -> void:
	var combat := _combat()
	context.check(combat.enemy_phase == CombatResolver.Phase.TELEGRAPH, "Slime starts with a readable telegraph")
	combat.advance_ticks(combat.enemy.definition.telegraph_ticks - 1)
	context.check(combat.enemy_phase == CombatResolver.Phase.TELEGRAPH, "Telegraph does not end one tick early")
	combat.advance_ticks(1)
	context.check(combat.enemy_phase == CombatResolver.Phase.STARTUP, "Telegraph enters startup on its exact boundary")
	combat.advance_ticks(combat.enemy.definition.startup_ticks - 1)
	context.check(combat.hero.current_hp == 12, "Startup cannot deal early damage")
	combat.advance_ticks(1)
	context.check(combat.enemy_phase == CombatResolver.Phase.ACTIVE, "Startup enters active on its exact boundary")
	context.check(combat.hero.current_hp == 11, "Slime active entry applies its damage")

func _test_goblin_cycle(context: TestContext) -> void:
	var combat := _combat(GOBLIN_PATH)
	combat.advance_ticks(combat.enemy.definition.telegraph_ticks + combat.enemy.definition.startup_ticks)
	context.check(combat.enemy_phase == CombatResolver.Phase.ACTIVE and combat.strike_index == 0, "Goblin starts the first slash")
	context.check(combat.hero.current_hp == 10, "First slash deals its configured damage")
	combat.advance_ticks(combat.enemy.definition.active_ticks)
	context.check(combat.enemy_phase == CombatResolver.Phase.STARTUP and combat.strike_index == 1, "First slash leads into the second startup")
	combat.advance_ticks(combat.enemy.definition.startup_ticks)
	context.check(combat.enemy_phase == CombatResolver.Phase.ACTIVE and combat.hero.current_hp == 8, "Second slash deals damage once on entry")
	combat.advance_ticks(combat.enemy.definition.active_ticks + combat.enemy.definition.recovery_ticks)
	context.check(combat.enemy_phase == CombatResolver.Phase.VULNERABILITY, "Retreat ends in a vulnerability window")

func _test_dodge(context: TestContext) -> void:
	var success := _combat()
	success.advance_ticks(success.enemy.definition.telegraph_ticks + success.enemy.definition.startup_ticks - 1)
	context.check(success.request_dodge(), "Dodge can be requested before active")
	success.advance_ticks(1)
	context.check(success.hero.current_hp == 12, "Timed dodge prevents active damage")
	var failure := _combat()
	failure.advance_ticks(failure.enemy.definition.telegraph_ticks + failure.enemy.definition.startup_ticks)
	context.check(failure.hero.current_hp == 11, "No dodge means the hit lands")
	var early := _combat()
	early.request_dodge()
	early.advance_ticks(early.enemy.definition.telegraph_ticks + early.enemy.definition.startup_ticks)
	context.check(early.hero.current_hp == 11, "An early dodge expires before the hit")

func _test_attack_windows(context: TestContext) -> void:
	var cooldown := _combat(GOBLIN_PATH)
	context.check(cooldown.request_attack(), "First hero attack is accepted")
	context.check(cooldown.enemy.current_hp == 8, "Normal hero attack uses base damage")
	context.check(not cooldown.request_attack() and cooldown.enemy.current_hp == 8, "Immediate repeated attack is blocked by cooldown")
	cooldown.advance_ticks(cooldown.hero.definition.attack_cooldown_ticks)
	context.check(cooldown.request_attack() and cooldown.enemy.current_hp == 6, "Attack becomes available after its cooldown")
	var vulnerable := _combat()
	vulnerable.advance_ticks(
		vulnerable.enemy.definition.telegraph_ticks
		+ vulnerable.enemy.definition.startup_ticks
		+ vulnerable.enemy.definition.active_ticks
		+ vulnerable.enemy.definition.recovery_ticks
	)
	context.check(vulnerable.is_vulnerable(), "Slime core opens after recovery")
	context.check(vulnerable.request_attack() and vulnerable.enemy.current_hp == 0, "Vulnerability applies the configured multiplier")
	context.check(vulnerable.is_finished and vulnerable.won, "Lethal vulnerability attack wins immediately")

func _test_damage_once(context: TestContext) -> void:
	var combat := _combat()
	combat.advance_ticks(combat.enemy.definition.telegraph_ticks + combat.enemy.definition.startup_ticks)
	context.check(combat.hero.current_hp == 11, "Active entry deals one hit")
	combat.advance_ticks(combat.enemy.definition.active_ticks - 1)
	context.check(combat.hero.current_hp == 11 and combat.enemy_phase == CombatResolver.Phase.ACTIVE, "Remaining active ticks do not repeat damage")
	combat.advance_ticks(1)
	context.check(combat.enemy_phase == CombatResolver.Phase.RECOVERY and combat.hero.current_hp == 11, "Recovery starts without another hit")

func _test_reachable_victory(context: TestContext) -> void:
	for path: String in [SLIME_PATH, GOBLIN_PATH]:
		var combat := _combat(path)
		while not combat.is_finished and combat.tick_count < 3000:
			if combat.enemy_phase == CombatResolver.Phase.STARTUP and combat.phase_ticks_remaining <= 2:
				combat.request_dodge()
			combat.request_attack()
			combat.advance_ticks(1)
		context.check(combat.is_finished and combat.won, "A bounded input policy can win: %s" % path)
		context.check(combat.hero.current_hp > 0 and combat.enemy.current_hp == 0, "Victory leaves hero alive and enemy at zero: %s" % path)

func _test_defeat_and_terminal(context: TestContext) -> void:
	for path: String in [SLIME_PATH, GOBLIN_PATH]:
		var combat := _combat(path)
		var counter := FinishCounter.new()
		combat.finished.connect(counter.record)
		while not combat.is_finished and combat.tick_count < 5000:
			combat.advance_ticks(1)
		context.check(combat.is_finished and not combat.won and combat.hero.is_dead(), "No-input policy reaches defeat: %s" % path)
		var terminal_tick: int = combat.tick_count
		context.check(not combat.request_attack() and not combat.request_dodge(), "Terminal state rejects both actions: %s" % path)
		combat.advance_ticks(30)
		context.check(combat.tick_count == terminal_tick and counter.count == 1, "Terminal state stops time and emits once: %s" % path)

func _test_retry_and_session(context: TestContext) -> void:
	var session := GameSession.new()
	session.select_encounter("moss_slime")
	var first := session.start_combat(session.current_enemy_id)
	first.request_attack()
	first.advance_ticks(10)
	first.hero.take_damage(4)
	var second := session.retry_combat()
	context.check(first != second, "Retry creates a new resolver")
	context.check(second.tick_count == 0 and second.enemy_phase == CombatResolver.Phase.TELEGRAPH, "Retry starts at the initial phase and tick")
	context.check(second.hero.current_hp == second.hero.max_hp and second.enemy.current_hp == second.enemy.max_hp, "Retry restores both health pools")
	context.check(second.hero_attack_cooldown == 0 and second.dodge_cooldown == 0 and second.dodge_ticks_remaining == 0, "Retry clears action timers")
	second.enemy.current_hp = 1
	second.request_attack()
	context.check(session.apply_victory("moss_slime"), "First victory transaction is accepted")
	context.check(session.hero.level == 2 and session.hero.experience == 0, "Slime reward reaches narrative level two")
	context.check(not session.apply_victory("moss_slime") and session.hero.level == 2, "Repeated victory cannot duplicate XP")
	session.select_encounter("goblin_scout")
	var goblin := session.start_combat(session.current_enemy_id)
	context.check(goblin.enemy.definition.id == "goblin_scout" and goblin.hero == session.hero, "The same runtime and session support the next encounter")

func _test_tick_batching(context: TestContext) -> void:
	for path: String in [SLIME_PATH, GOBLIN_PATH]:
		var baseline: Dictionary = _run_schedule(path, 1)
		for batch_size: int in [3, 6]:
			var actual: Dictionary = _run_schedule(path, batch_size)
			context.check(actual == baseline, "Batch size %d matches single ticks: %s" % [batch_size, path])

func _run_schedule(enemy_path: String, batch_size: int) -> Dictionary:
	var combat := _combat(enemy_path)
	var commands: Dictionary = {
		0: "attack",
		42: "dodge",
		66: "attack",
		90: "attack",
		114: "attack",
	}
	for tick: int in range(0, 180, batch_size):
		if combat.is_finished:
			break
		match commands.get(tick, ""):
			"attack":
				combat.request_attack()
			"dodge":
				combat.request_dodge()
		combat.advance_ticks(batch_size)
	return {
		"tick": combat.tick_count,
		"phase": combat.enemy_phase,
		"phase_remaining": combat.phase_ticks_remaining,
		"hero_hp": combat.hero.current_hp,
		"enemy_hp": combat.enemy.current_hp,
		"attack_cooldown": combat.hero_attack_cooldown,
		"dodge_cooldown": combat.dodge_cooldown,
		"finished": combat.is_finished,
		"won": combat.won,
	}
