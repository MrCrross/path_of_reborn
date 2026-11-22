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

class SignalCounter:
	extends RefCounted

	var begun: int = 0
	var landed: int = 0

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_run_case("slime_telegraph_startup_active_boundaries", _test_slime_boundaries))
	results.append(_run_case("goblin_double_slash_and_vulnerability", _test_goblin_cycle))
	results.append(_run_case("dodge_success_failure_and_early_expiry", _test_dodge))
	results.append(_run_case("hero_attack_startup_contact_and_cooldown", _test_attack_windows))
	results.append(_run_case("active_phase_deals_damage_once", _test_damage_once))
	results.append(_run_case("manual_policy_still_wins_when_auto_is_off", _test_reachable_victory))
	results.append(_run_case("auto_attack_wins_without_any_input", _test_auto_attack))
	results.append(_run_case("manual_and_auto_share_one_strike_path", _test_no_double_strike))
	results.append(_run_case("hero_death_cancels_pending_strike", _test_death_cancels_strike))
	results.append(_run_case("both_enemies_have_defeat_and_terminal_lock", _test_defeat_and_terminal))
	results.append(_run_case("retry_is_clean_and_settlement_is_once_per_run", _test_retry_and_session))
	results.append(_run_case("single_active_run_guards_and_pending_gate", _test_single_active_run_guards))
	results.append(_run_case("combat_format_policies_share_one_damage_path", _test_combat_format_policies))
	results.append(_run_case("auto_dodge_policy_is_bounded_and_readable", _test_auto_dodge_policy))
	results.append(_run_case("trial_is_voluntary_gated_and_rewards_once", _test_trial))
	results.append(_run_case("tick_batching_preserves_deterministic_outcome", _test_tick_batching))
	results.append(_run_case("replaced_resolver_is_invalidated_before_damage_or_finish", _test_stale_resolver_invalidation))
	results.append(_run_case("reentrant_claim_is_refused_before_internal_signals", _test_reentrant_claim_guard))
	results.append(_run_case("commands_and_checkpoint_respect_pending_and_return", _test_incompatible_command_guards))
	results.append(_run_case("route_advance_uses_only_saved_winning_route_context", _test_pending_route_context))
	results.append(_run_case("trial_echo_flag_survives_checkpoint_rollback", _test_trial_echo_rollback))
	results.append(_run_case("starting_branch_wins_slime_and_story_goblin_in_both_modes", _test_branch_reachable_both_modes))
	results.append(_run_case("auto_speed_preserves_events_seed_and_single_loot_roll", _test_auto_speed_determinism))
	results.append(_run_case("ability_unlock_applies_after_load_and_checkpoint_return", _test_ability_unlock_and_return))
	return results

func _run_case(case_name: String, test: Callable) -> Dictionary:
	var context := TestContext.new()
	test.call(context)
	return {"name": case_name, "checks": context.checks}

func _combat(enemy_path: String = SLIME_PATH, auto: bool = false) -> CombatResolver:
	var hero_definition: ActorDefinition = load("res://data/actors/haruto.tres")
	var enemy_definition: ActorDefinition = load(enemy_path)
	var resolver := CombatResolver.new(CharacterState.new(hero_definition), enemy_definition)
	resolver.auto_attack_enabled = auto
	return resolver

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
	context.check(combat.hero.current_hp == 11, "First slash deals its configured damage")
	combat.advance_ticks(combat.enemy.definition.active_ticks)
	context.check(combat.enemy_phase == CombatResolver.Phase.STARTUP and combat.strike_index == 1, "First slash leads into the second startup")
	combat.advance_ticks(combat.enemy.definition.startup_ticks)
	context.check(combat.enemy_phase == CombatResolver.Phase.ACTIVE and combat.hero.current_hp == 10, "Second slash deals damage once on entry")
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
	context.check(cooldown.enemy.current_hp == 16, "Damage waits for the strike contact, not the button press")
	context.check(not cooldown.request_attack(), "Repeated request during the swing is refused")
	cooldown.advance_ticks(cooldown.hero.definition.attack_startup_ticks)
	context.check(cooldown.enemy.current_hp == 14, "Contact applies base damage after startup ticks")
	context.check(not cooldown.request_attack() and cooldown.enemy.current_hp == 14, "Immediate repeated attack is blocked by cooldown")
	cooldown.advance_ticks(cooldown.hero.definition.attack_cooldown_ticks)
	context.check(cooldown.request_attack(), "Attack becomes available after its cooldown")
	var vulnerable := _combat()
	vulnerable.advance_ticks(
		vulnerable.enemy.definition.telegraph_ticks
		+ vulnerable.enemy.definition.startup_ticks
		+ vulnerable.enemy.definition.active_ticks
		+ vulnerable.enemy.definition.recovery_ticks
	)
	context.check(vulnerable.is_vulnerable(), "Slime core opens after recovery")
	context.check(vulnerable.request_attack(), "Attack into the open window is accepted")
	vulnerable.advance_ticks(vulnerable.hero.definition.attack_startup_ticks)
	context.check(vulnerable.enemy.current_hp == 14, "Vulnerability applies the configured multiplier at contact (20 - 6)")
	context.check(not vulnerable.is_finished, "A single window hit does not finish a full-HP enemy")

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
		context.check(combat.is_finished and combat.won, "A bounded manual policy can win with auto off: %s" % path)
		context.check(combat.hero.current_hp > 0 and combat.enemy.current_hp == 0, "Victory leaves hero alive and enemy at zero: %s" % path)

func _test_auto_attack(context: TestContext) -> void:
	for path: String in [SLIME_PATH, GOBLIN_PATH]:
		var combat := _combat(path, true)
		var signals := SignalCounter.new()
		combat.hero_attack_begun.connect(func(_run_id: String) -> void: signals.begun += 1)
		combat.hero_attack_landed.connect(func(_run_id: String, _target: String, _amount: int) -> void: signals.landed += 1)
		while not combat.is_finished and combat.tick_count < 3000:
			combat.advance_ticks(1)
		context.check(combat.is_finished and combat.won, "Auto attacks win without any input: %s" % path)
		context.check(signals.begun > 0 and signals.begun == signals.landed, "Every begun strike lands exactly once: %s" % path)

func _test_no_double_strike(context: TestContext) -> void:
	var combat := _combat(SLIME_PATH, true)
	var signals := SignalCounter.new()
	combat.hero_attack_landed.connect(func(_run_id: String, _target: String, _amount: int) -> void: signals.landed += 1)
	# Первый замах начинается автоматически на первом тике; ручной запрос в тот
	# же момент не должен дать второй удар.
	combat.request_attack()
	combat.advance_ticks(combat.hero.definition.attack_startup_ticks)
	context.check(signals.landed == 1, "Manual request on top of auto start does not double the strike")

func _test_death_cancels_strike(context: TestContext) -> void:
	var combat := _combat(GOBLIN_PATH, true)
	var signals := SignalCounter.new()
	combat.hero_attack_landed.connect(func(_run_id: String, _target: String, _amount: int) -> void: signals.landed += 1)
	combat.hero.current_hp = 1
	while not combat.is_finished and combat.tick_count < 3000:
		combat.advance_ticks(1)
	context.check(combat.is_finished and not combat.won, "Low-HP hero dies to the enemy offense")
	var landed_at_death: int = signals.landed
	combat.advance_ticks(60)
	context.check(signals.landed == landed_at_death, "A pending strike cannot land after the terminal event")
	context.check(combat.tick_count > 0 and combat.hero.current_hp == 0, "Terminal state keeps hero at zero")

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
	first.advance_ticks(10)
	first.hero.take_damage(4)
	var second := session.retry_combat()
	context.check(first != second, "Retry creates a new resolver")
	context.check(second.tick_count == 0 and second.enemy_phase == CombatResolver.Phase.TELEGRAPH, "Retry starts at the initial phase and tick")
	context.check(second.hero.current_hp == second.hero.max_hp and second.enemy.current_hp == second.enemy.max_hp, "Retry restores both health pools")
	context.check(second.hero_attack_cooldown == 0 and second.dodge_cooldown == 0 and second.dodge_ticks_remaining == 0, "Retry clears action timers")
	context.check(not session.equip_item("anything"), "Equipment changes are refused while a combat is active")
	var run_id: String = second.run_id
	context.check(not session.settle_combat(run_id, "moss_slime"), "Settlement before the terminal event is refused")
	second.enemy.current_hp = 1
	second.advance_ticks(second.hero.definition.attack_startup_ticks + 1)
	context.check(second.is_finished and second.won, "Forced low HP enemy dies to the auto strike")
	# Win создаёт pending; награды приходят только через claim ровно один раз.
	context.check(session.hero.level == 1 and session.inventory.items.size() == 1, "Win alone grants nothing yet")
	context.check(not session.pending_battle_result.is_empty(), "A durable pending result is created by the terminal win")
	context.check(session.pending_reward.is_empty(), "No legacy pending reward remains")
	var result_id: String = String(session.pending_battle_result.get("result_id", ""))
	context.check(not session.settle_combat(run_id, "moss_slime"), "Repeated settlement of the same run is refused")
	context.check(DomainSuite.claim_pending(session), "The pending result is claimed")
	context.check(session.hero.level == 2 and session.hero.experience == 0, "Slime reward reaches narrative level two on claim")
	context.check(not session.inventory.items.is_empty(), "Claim delivers loot into the inventory")
	context.check(session.last_settlement.get("run_id", "") == run_id, "Last settlement carries the winning run id")
	context.check(session.echoes == 1, "First victory claims one echo")
	context.check(not session.claim_battle_result(result_id), "Repeated claim is refused")
	context.check(session.hero.level == 2 and session.echoes == 1, "Repeated claim duplicates neither XP nor echo")
	session.select_encounter("moss_slime")
	var repeat := session.start_combat(session.current_enemy_id)
	context.check(repeat.run_id != run_id, "A new encounter creates a new run id")
	repeat.enemy.current_hp = 1
	repeat.advance_ticks(repeat.hero.definition.attack_startup_ticks + 1)
	DomainSuite.claim_pending(session)
	context.check(session.hero.experience == 4, "A separate won run grants the ordinary reward again on claim")
	context.check(session.echoes == 1, "The meta echo stays once per enemy type")
	context.check(session.last_settlement.get("route_node_id") == "forest_edge_cart_slime", "The second slime advances its own route node")
	session.select_encounter("goblin_scout")
	var goblin := session.start_combat(session.current_enemy_id)
	context.check(goblin.enemy.definition.id == "goblin_scout" and goblin.hero == session.hero, "The same runtime and session support the next encounter")

func _test_single_active_run_guards(context: TestContext) -> void:
	var session := GameSession.new()
	var first := session.start_combat("moss_slime")
	context.check(first != null, "First combat starts")
	context.check(session.start_combat("goblin_scout") == null, "Second combat over an active run is refused")
	context.check(not session.select_encounter("goblin_scout"), "Encounter selection is refused mid-combat")
	first.enemy.current_hp = 1
	first.advance_ticks(first.hero.definition.attack_startup_ticks + 1)
	context.check(first.is_finished and first.won, "Finishing the first run wins")
	context.check(session.start_combat("goblin_scout") == null, "Pending result blocks the next combat before claim")
	context.check(DomainSuite.claim_pending(session), "Claim clears the pending result")
	context.check(session.start_combat("moss_slime") != null, "Next combat is legal after claim")
	context.check(not session.select_encounter("moss_slime"), "Selection stays locked during the next combat")
	session.abandon_combat()
	context.check(session.awaiting_return and not session.in_combat, "Surrender closes the run and awaits return")
	context.check(session.start_combat("moss_slime") == null, "Awaiting return blocks new combat")

func _test_combat_format_policies(context: TestContext) -> void:
	# Оба режима используют одни характеристики и одну формулу; отличается только
	# источник dodge. Награды за режим не различаются (проверяется в session).
	var session := GameSession.new()
	context.check(session.combat_format == GameSession.COMBAT_FORMAT_AUTO, "Default format is full auto")
	var auto_resolver := session.start_combat("moss_slime")
	context.check(auto_resolver.auto_dodge_enabled, "Full auto resolver owns its defense attempts")
	session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
	context.check(auto_resolver.auto_dodge_enabled, "Mid-combat switch does not mutate the active run")
	context.check(not auto_resolver.auto_dodge_cooldown == -1, "Active run keeps its own defense timers")
	auto_resolver.enemy.current_hp = 1
	auto_resolver.advance_ticks(auto_resolver.hero.definition.attack_startup_ticks + 1)
	DomainSuite.claim_pending(session)
	context.check(session.combat_format == GameSession.COMBAT_FORMAT_ACTIVE, "Format preference survives the encounter")
	var active_resolver := session.start_combat("moss_slime")
	context.check(not active_resolver.auto_dodge_enabled, "The next combat uses the switched format")
	context.check(active_resolver.request_dodge(), "Active format accepts a manual dodge")
	var auto_again := GameSession.new()
	auto_again.set_combat_format("invalid_format")
	context.check(auto_again.combat_format == GameSession.COMBAT_FORMAT_AUTO, "Unknown format values are refused")
	# Rollback не откатывает формат: он вне профиля Checkpoint.
	var profile: Dictionary = session.capture_profile_dto()
	context.check(not profile.has("combat_format"), "Format preference lives outside the rollback profile")

func _test_auto_dodge_policy(context: TestContext) -> void:
	# Политика автозащиты: попытка на первой STARTUP цикла, cooldown 150 тиков
	# не покрывает все циклы; повторный удар гоблина бесплатной попытки не даёт.
	var slime := _combat(SLIME_PATH, true)
	slime.auto_dodge_enabled = true
	var attempts: Array[String] = []
	slime.dodge_begun.connect(func(source: String) -> void: attempts.append(source))
	while not slime.is_finished and slime.tick_count < 3000:
		slime.advance_ticks(1)
	context.check(slime.won, "Auto defense still wins the ordinary fight")
	context.check(attempts.size() >= 2, "Auto defense attempts at least twice over the fight")
	context.check(attempts.size() < slime.enemy.definition.attacks_per_cycle * 3 + 3, "Auto defense does not cover every cycle")
	var goblin := _combat(GOBLIN_PATH, true)
	goblin.auto_dodge_enabled = true
	# Лямбды над локальными int в раннере ненадёжны — считаем через массивы.
	var resolutions: Array = []
	goblin.dodge_resolved.connect(func(success: bool) -> void: resolutions.append(success))
	while not goblin.is_finished and goblin.tick_count < 3000:
		goblin.advance_ticks(1)
	var dodged: int = resolutions.count(true)
	var strikes: int = resolutions.size()
	context.check(goblin.won, "Auto defense wins against the double slash")
	context.check(dodged > 0 and dodged < strikes, "Auto defense dodges a readable share, not everything")
	var manual := _combat(SLIME_PATH, true)
	manual.auto_dodge_enabled = false
	var manual_attempts: Array = []
	manual.dodge_begun.connect(func(source: String) -> void: manual_attempts.append(source))
	while not manual.is_finished and manual.tick_count < 3000:
		manual.advance_ticks(1)
	context.check(manual.won and manual_attempts.is_empty(), "Active format without input performs no auto defense")

func _test_trial(context: TestContext) -> void:
	# Испытание — добровольный вариант после учебного участка: не маскируется
	# под сюжет, закрыто до завершения маршрута, эхо разово, добыча обычная.
	var session := GameSession.new()
	context.check(not session.trial_encounter_available(), "Trial is locked before the slice is completed")
	context.check(session.start_combat(GameSession.TRIAL_ENEMY_ID) == null, "Trial cannot start before the slice is completed")
	context.check(ArtMap.ENEMY_SHEETS.has(GameSession.TRIAL_ENEMY_ID), "Trial enemy has an art/presentation mapping")
	session.route_state["next_index"] = session.route_nodes().size()
	session.route_state["completed"] = true
	context.check(session.trial_encounter_available(), "Trial opens after the slice is completed")
	context.check(session.select_encounter(GameSession.TRIAL_ENEMY_ID), "Trial is a legal voluntary selection")
	var first := session.start_combat(GameSession.TRIAL_ENEMY_ID)
	context.check(first != null and first.enemy.definition.id == GameSession.TRIAL_ENEMY_ID, "Trial starts as its own encounter variant")
	first.enemy.current_hp = 1
	first.advance_ticks(first.hero.definition.attack_startup_ticks + 1)
	context.check(first.is_finished and first.won, "Trial run is winnable")
	var first_id: String = String(session.pending_battle_result.get("result_id", ""))
	context.check(bool(session.pending_battle_result.get("trial_echo_gained", false)), "Trial win flags its one-time echo")
	context.check(DomainSuite.claim_pending(session), "Trial result is claimed")
	# Первый зачёт гоблина-испытания приносит и обычное эхо нового типа, и эхо испытания.
	context.check(session.echoes == 2, "Trial echo lands on top of the ordinary first-type echo")
	var loot_size: int = session.inventory.items.size()
	context.check(loot_size > 0, "Trial claim delivers the ordinary loot table")
	# Повторное испытание: обычная добыча снова, второго эха нет.
	context.check(session.select_encounter(GameSession.TRIAL_ENEMY_ID), "Trial stays voluntary after completion")
	var second := session.start_combat(GameSession.TRIAL_ENEMY_ID)
	second.enemy.current_hp = 1
	second.advance_ticks(second.hero.definition.attack_startup_ticks + 1)
	context.check(not bool(session.pending_battle_result.get("trial_echo_gained", false)), "A repeat trial run grants no second echo flag")
	context.check(DomainSuite.claim_pending(session), "Repeat trial result is claimed")
	context.check(session.echoes == 2, "The trial echo never duplicates")
	var units: int = 0
	for item: ItemInstance in session.inventory.items:
		units += item.quantity
	context.check(units > loot_size + 1, "Repeat trial keeps paying crystal loot, including into an existing stack")

func _test_tick_batching(context: TestContext) -> void:
	for path: String in [SLIME_PATH, GOBLIN_PATH]:
		var baseline: Dictionary = _run_schedule(path, 1)
		for batch_size: int in [3, 6]:
			var actual: Dictionary = _run_schedule(path, batch_size)
			context.check(actual == baseline, "Batch size %d matches single ticks: %s" % [batch_size, path])

func _test_stale_resolver_invalidation(context: TestContext) -> void:
	for boundary: String in ["retry", "surrender", "rollback", "load", "new_game"]:
		var session := GameSession.new()
		var old := session.start_combat("moss_slime")
		old.advance_ticks(5)
		var hp_before: int = session.hero.current_hp
		var tick_before: int = old.tick_count
		var replacement: CombatResolver = null
		match boundary:
			"retry":
				replacement = session.retry_combat()
			"surrender":
				session.abandon_combat()
			"rollback":
				session.abandon_combat()
				session.checkpoints.restore("first_trace")
			"load":
				var dto: Dictionary = SaveService.new().capture(GameSession.new())
				session.apply_state_dto(dto)
			"new_game":
				session.new_game()
		old.advance_ticks(600)
		context.check(old.tick_count == tick_before and not old.is_finished, "%s freezes the old resolver without a terminal event" % boundary)
		context.check(session.pending_battle_result.is_empty(), "%s prevents the old resolver from creating pending" % boundary)
		context.check(session.hero.current_hp == hp_before or boundary in ["rollback", "load", "new_game"], "%s prevents old damage to the shared hero" % boundary)
		if replacement != null:
			context.check(session.in_combat and replacement.tick_count == 0, "Retry replacement remains the sole active run")
			context.check(not replacement.request_dodge() or replacement.tick_count == 0, "Replacement still accepts its own legal actions")

func _test_reentrant_claim_guard(context: TestContext) -> void:
	var session := GameSession.new()
	var resolver := session.start_combat("moss_slime")
	resolver.advance_ticks(600)
	var result_id: String = session.pending_battle_result["result_id"]
	var expected_units: int = 0
	for item: Dictionary in session.pending_battle_result["items"]:
		expected_units += int(item["quantity"])
	var inner := {"accepted": false}
	DomainSuite.prepare_pending_choices(session)
	session.inventory.changed.connect(func() -> void: inner["accepted"] = session.claim_battle_result(result_id), CONNECT_ONE_SHOT)
	var outer: bool = session.claim_battle_result(result_id)
	var units: int = 0
	for item: ItemInstance in session.inventory.items:
		units += item.quantity
	context.check(outer and not inner["accepted"], "Only the outer claim is accepted")
	context.check(units == expected_units + 1 and session.echoes == 1, "Internal inventory.changed cannot duplicate items, the starting branch or echo")
	context.check(session.last_settlement.get("result_id", "") == result_id, "The single settlement keeps its result identity")

func _test_incompatible_command_guards(context: TestContext) -> void:
	var session := GameSession.new()
	var resolver := session.start_combat("moss_slime")
	resolver.advance_ticks(600)
	context.check(not session.checkpoints.can_begin() and not session.checkpoints.begin(), "Pending result blocks checkpoint channel")
	var unequip_refused: bool = not session.has_method("unequip_item") or not bool(session.call("unequip_item", "weapon"))
	context.check(not session.equip_item("anything") and unequip_refused, "Pending result blocks equipment commands")
	context.check(not session.choose_upgrade("strength") or session.hero.pending_upgrade_choices == 0, "Upgrade guard is explicit and state-preserving")
	DomainSuite.claim_pending(session)
	session.awaiting_return = true
	context.check(not session.checkpoints.can_begin() and not session.select_encounter("moss_slime"), "Awaiting return blocks checkpoint and selection")
	context.check(session.start_combat("moss_slime") == null and not session.equip_item("anything"), "Awaiting return blocks combat and equipment")

func _test_pending_route_context(context: TestContext) -> void:
	var session := GameSession.new()
	var resolver := session.start_combat("moss_slime")
	resolver.advance_ticks(600)
	context.check(session.pending_battle_result.get("route_node_id", "") == "forest_edge_slime", "Winning route node is captured in pending")
	session.pending_battle_result["enemy_id"] = "goblin_scout"
	context.check(not DomainSuite.claim_pending(session), "Tampered actor identity cannot claim route progress")
	context.check(session.route_state.get("next_index", 0) == 0, "Rejected context does not advance route")
	var repeat_session := GameSession.new()
	repeat_session.route_state["next_index"] = 1
	context.check(repeat_session.select_encounter("moss_slime", true), "Repeat can be explicitly selected while the next route node uses the same enemy")
	var repeat := repeat_session.start_selected_combat()
	repeat = repeat_session.retry_combat()
	repeat.advance_ticks(600)
	context.check(repeat_session.pending_battle_result.get("encounter_mode", "") == GameSession.ENCOUNTER_REPEAT, "A beaten earlier enemy is a repeat")
	DomainSuite.claim_pending(repeat_session)
	context.check(repeat_session.route_state.get("next_index", 0) == 1, "Repeat claim cannot advance the canonical route")

func _test_trial_echo_rollback(context: TestContext) -> void:
	var session := GameSession.new()
	for enemy_id: String in ["moss_slime", "moss_slime", "goblin_scout"]:
		var ordinary := session.start_combat(enemy_id)
		ordinary.advance_ticks(6000)
		DomainSuite.claim_pending(session)
		session.choose_upgrade("strength")
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.checkpoints.apply_completion()
	var before: int = session.echoes
	var first := session.start_combat(GameSession.TRIAL_ENEMY_ID)
	first.advance_ticks(6000)
	DomainSuite.claim_pending(session)
	context.check(session.echoes - before == 2, "First trial pays first-ID plus trial echo, totaling +2")
	session.start_combat("moss_slime")
	session.abandon_combat()
	context.check(session.checkpoints.restore(), "Rollback returns to the pre-trial snapshot")
	context.check(session.echoes == before + 2 and session.trial_echo_claimed, "Echo balance and one-time flag share non-rollback meta ownership")
	var second := session.start_combat(GameSession.TRIAL_ENEMY_ID)
	second.advance_ticks(6000)
	DomainSuite.claim_pending(session)
	context.check(session.echoes == before + 2, "A repeated post-rollback victory pays no second trial bonus")
	context.check(session.claimed_echo_enemy_ids.has(GameSession.TRIAL_ENEMY_ID), "The first-ID marker also survives rollback")

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


func _test_branch_reachable_both_modes(context: TestContext) -> void:
	for enemy_id: String in ["moss_slime", "goblin_scout"]:
		for format: String in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE]:
			var session := GameSession.new()
			session.set_combat_format(format)
			if enemy_id == "goblin_scout":
				session.route_state["next_index"] = 2
			var equipped: Dictionary = EquipmentModel.slot(session, "weapon")
			context.check(equipped["definition"] != null and equipped["definition"].id == "broken_wanderer_branch", "%s starts with the branch: %s" % [enemy_id, format])
			var resolver: CombatResolver = session.start_combat(enemy_id)
			while resolver != null and not resolver.is_finished and resolver.tick_count < 4000:
				if format == GameSession.COMBAT_FORMAT_ACTIVE:
					if resolver.enemy_phase == CombatResolver.Phase.STARTUP and resolver.phase_ticks_remaining <= 2:
						resolver.request_dodge()
					resolver.request_attack()
				resolver.advance_ticks(1)
			context.check(resolver != null and resolver.won, "%s is winnable with the branch: %s" % [enemy_id, format])
			var crystal_only: bool = not session.pending_battle_result.is_empty()
			for entry: Dictionary in session.pending_battle_result.get("items", []):
				crystal_only = crystal_only and entry.get("item_id") == "echo_crystal"
			context.check(crystal_only and DomainSuite.claim_pending(session), "%s pays only crystals and claims once: %s" % [enemy_id, format])
			context.check(session.inventory.filter("weapon").size() == 1 and session.inventory.filter("weapon")[0].definition_id == "broken_wanderer_branch", "%s grants no hidden sword: %s" % [enemy_id, format])


func _test_auto_speed_determinism(context: TestContext) -> void:
	var traces: Array[Dictionary] = []
	for speed: int in [1, 2]:
		var session := GameSession.new()
		session.set_loot_seed("speed_contract")
		session.set_auto_speed(speed)
		var resolver: CombatResolver = session.start_combat("moss_slime")
		var events: Array = []
		resolver.phase_changed.connect(func(phase: int, _remaining: int) -> void: events.append(["phase", resolver.tick_count, phase]))
		resolver.damage_dealt.connect(func(target: String, amount: int) -> void: events.append(["damage", resolver.tick_count, target, amount]))
		resolver.dodge_resolved.connect(func(success: bool) -> void: events.append(["dodge", resolver.tick_count, success]))
		resolver.hero_attack_begun.connect(func(run_id: String) -> void: events.append(["attack", resolver.tick_count, run_id]))
		resolver.finished.connect(func(won: bool) -> void: events.append(["finished", resolver.tick_count, won]))
		var observed_speed: int = int(session.active_encounter_context.get("auto_speed", 1))
		var frames: int = 0
		while not resolver.is_finished and frames < 3000:
			resolver.advance_ticks(int(session.active_encounter_context.get("auto_speed", 1)))
			frames += 1
		context.check(resolver.won and observed_speed == speed, "Auto ×%d finishes with its fixed encounter timing" % speed)
		var pending: Dictionary = session.pending_battle_result.duplicate(true)
		context.check(session._settled_run_ids.size() == 1 and not pending.is_empty(), "Auto ×%d performs exactly one terminal loot roll" % speed)
		context.check(DomainSuite.claim_pending(session), "Auto ×%d claims its fixed result" % speed)
		for signal_name: String in ["phase_changed", "damage_dealt", "dodge_resolved", "hero_attack_begun", "finished"]:
			for connection: Dictionary in resolver.get_signal_connection_list(signal_name):
				resolver.disconnect(signal_name, connection["callable"])
		traces.append({"events": events, "items": pending.get("items", []), "loot_state": pending.get("loot_state", ""), "rng": str(session.loot_rng.state), "settlement": session.last_settlement})
	context.check(traces[0]["events"] == traces[1]["events"], "×1 and ×2 produce the same ordered combat events at the same simulation ticks")
	context.check(traces[0]["items"] == traces[1]["items"] and traces[0]["loot_state"] == traces[1]["loot_state"] and traces[0]["rng"] == traces[1]["rng"], "×1 and ×2 share one seeded loot outcome and RNG state")
	context.check(traces[0]["settlement"] == traces[1]["settlement"], "×1 and ×2 have identical settlements")


func _test_ability_unlock_and_return(context: TestContext) -> void:
	var locked := GameSession.new()
	locked.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
	var locked_combat: CombatResolver = locked.start_combat("moss_slime")
	context.check(not locked_combat.request_ability(), "Focused Strike is locked at level one")
	var session := GameSession.new()
	session.hero.gain_xp(4)
	session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
	var resolver: CombatResolver = session.start_combat("moss_slime")
	var used: Array[String] = []
	resolver.ability_used.connect(func(ability_id: String) -> void: used.append(ability_id))
	context.check(session.hero.level == 2 and resolver.request_ability(), "Focused Strike unlocks and can be requested at level two")
	resolver.advance_ticks(resolver.hero.definition.attack_startup_ticks)
	var expected_hp: int = resolver.enemy.definition.max_hp - CharacterState.calculate_damage(resolver.hero.strength, resolver.enemy.defense, 1.5)
	context.check(used == ["focused_strike"] and resolver.enemy.current_hp == expected_hp and resolver.hero_ability_cooldown > 0, "The unlocked ability uses its real damage and cooldown in combat")
	session.abandon_combat()
	var restored := GameSession.new()
	restored.apply_state_dto(SaveService.new().capture(session))
	restored.awaiting_return = false
	restored.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
	restored.checkpoints.begin()
	restored.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	restored.checkpoints.apply_completion()
	var loaded_combat: CombatResolver = restored.start_combat("moss_slime")
	context.check(restored.hero.level == 2 and loaded_combat.request_ability(), "The unlocked ability remains usable after save/load")
	restored.abandon_combat()
	restored.checkpoints.restore()
	restored.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
	var returned_combat: CombatResolver = restored.start_combat("moss_slime")
	context.check(not restored.awaiting_return and returned_combat != null and returned_combat.request_ability(), "The unlocked ability remains usable after Checkpoint return")
