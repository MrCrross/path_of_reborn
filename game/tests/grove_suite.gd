extends RefCounted

const DomainSuite = preload("res://tests/domain_suite.gd")
const TestContext = DomainSuite.TestContext
const SAVE_PATH := "user://path_of_reborn_tests/grove/profile.json"

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_case("grove_v7_admission_and_departure", _test_admission))
	results.append(_case("grove_target_lock_noise_and_retry", _test_targets))
	results.append(_case("grove_kenta_choices_continue_and_bandage", _test_kenta))
	results.append(_case("grove_pollen_contact_dodge_and_slow", _test_pollen))
	results.append(_case("grove_pending_restore_objectives_and_submission", _test_progress))
	results.append(_case("grove_technique_bonus_at_vulnerable_contact", _test_technique))
	results.append(_case("grove_combat_simulation_on_route_and_repeat_builds", _test_balance))
	return results

func _case(case_name: String, test: Callable) -> Dictionary:
	var context := TestContext.new()
	test.call(context)
	return {"name": case_name, "checks": context.checks}

static func at_guild(session: GameSession, register: bool = true, xp: int = 16) -> void:
	# The shop and guild already have end-to-end coverage in the first session.
	session.new_game()
	session.world_flags["prologue_completed"] = true
	session.world_flags[GameSession.WORLD_FLAG_LIOREN_SHOP_UNLOCKED] = true
	session.world_flags[GameSession.WORLD_FLAG_SHOP_INTRO_DONE] = true
	session.world_flags[GameSession.WORLD_FLAG_SHOP_PURCHASE_BRIEFING_DONE] = true
	session.route_state["next_index"] = session.route_nodes().size()
	session.route_state["completed"] = true
	session.story_rewards[GameSession.DAIJIRO_SWORD_REWARD_ID] = true
	session.hero.gain_xp(xp)
	var sword: ItemInstance = session.inventory.add(session.get_item_definition("training_sword"), 1)[0]
	session.equip_item(sword.instance_id)
	session.travel_to(GameSession.LOCATION_LIOREN)
	session.set_guild_visit_active(true)
	session.seen_cue_ids[GameSession.GUILD_LAST_CUE_ID] = true
	if register:
		session.register_with_guild()

static func see(session: GameSession, number: int) -> void:
	session.seen_cue_ids["DIA_GROVE_%03d" % number] = true

func _at_hounds(noise: bool = false, xp: int = 16) -> GameSession:
	var session := GameSession.new()
	at_guild(session, true, xp)
	session.apply_grove_command("enter")
	see(session, 4)
	session.apply_grove_command("noise" if noise else "approach")
	return session

func _at_clearing(xp: int = 16) -> GameSession:
	var session: GameSession = _at_hounds(true, xp)
	_win(session.start_combat("needle_hound"))
	DomainSuite.claim_pending(session)
	see(session, 7)
	session.apply_grove_command("grove_kenta_safe")
	see(session, 11)
	_win(session.start_combat("dust_moth"))
	DomainSuite.claim_pending(session)
	return session

func _win(combat: CombatResolver) -> void:
	combat.advance_ticks(1200)

func _test_admission(context: TestContext) -> void:
	var session := GameSession.new()
	at_guild(session, false)
	var save := SaveService.new()
	var old_v7: Dictionary = save.capture(session)
	context.check(save.validate(old_v7), "Unregistered v7 shape requires no Grove keys")
	var restored := GameSession.new()
	restored.apply_state_dto(old_v7)
	context.check(not restored.apply_grove_command("enter"), "Unregistered character cannot enter")
	context.check(restored.register_with_guild(), "Existing registration still issues the first order")
	restored.traces = 3
	context.check(not restored.apply_grove_command("enter"), "Three traces block entry")
	restored.traces = 0
	context.check(restored.apply_grove_command("enter") and restored.grove_stage() == "approach", "Registered profile enters at approach")
	context.check(not restored.select_encounter("needle_hound") and not restored.select_encounter("moss_slime", true), "Approach gates both encounter routes")
	context.check(restored.apply_grove_command("leave"), "Grove may be left before any encounter")
	restored.set_guild_visit_active(true)
	context.check(restored.apply_grove_command("enter") and restored.grove_stage() == "approach", "Re-entry resumes the Grove separately")
	context.check(restored.route_completed() and restored.trial_available(), "Trail route and trial survive travel")

func _test_targets(context: TestContext) -> void:
	var plain: GameSession = _at_hounds()
	var noisy: GameSession = _at_hounds(true)
	plain.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
	noisy.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
	var normal: CombatResolver = plain.start_combat("needle_hound")
	var pair: CombatResolver = noisy.start_combat("needle_hound")
	context.check(normal.enemy_slots.size() == 2 and pair.enemy_slots.size() == 2, "Two slots exist")
	var first: CombatResolver.EnemySlot = pair.enemy_slots[0]
	var second: CombatResolver.EnemySlot = pair.enemy_slots[1]
	context.check(first.instance_id != second.instance_id and first.actor != second.actor, "Same species gets independent IDs and state")
	context.check(first.remaining > normal.enemy_slots[0].remaining and second.remaining == normal.enemy_slots[1].remaining, "Noise delays only the first threat")
	context.check(pair.request_attack() and pair.select_target(second.instance_id), "Target can change during a swing")
	pair.advance_ticks(pair.hero.definition.attack_startup_ticks)
	context.check(first.actor.current_hp < first.actor.max_hp and second.actor.current_hp == second.actor.max_hp, "Contact stays locked to the original slot")
	var next_pair: CombatResolver = noisy.retry_combat()
	context.check(not pair.is_active and next_pair != null and next_pair.enemy_slots[0].remaining == first.actor.definition.telegraph_ticks + 12, "Retry restores both slots and one application of noise")
	next_pair.enemy_slots[1].actor.take_damage(next_pair.enemy_slots[1].actor.max_hp - 1)
	next_pair.select_target(next_pair.enemy_slots[1].instance_id)
	next_pair.request_attack()
	next_pair.advance_ticks(next_pair.hero.definition.attack_startup_ticks)
	context.check(not next_pair.is_finished and not noisy.has_pending_battle_result(), "Defeating one enemy cannot settle the pair")
	next_pair.enemy_slots[0].actor.take_damage(next_pair.enemy_slots[0].actor.max_hp - 1)
	next_pair.advance_ticks(next_pair.hero_attack_cooldown)
	next_pair.request_attack()
	next_pair.advance_ticks(next_pair.hero.definition.attack_startup_ticks)
	context.check(next_pair.won and noisy.has_pending_battle_result(), "Second death yields one pending result")
	var id: String = noisy.pending_battle_result["result_id"]
	context.check(DomainSuite.claim_pending(noisy) and noisy.echoes == 1 and not noisy.claim_battle_result(id), "Repeated claim is rejected and identical hounds yield one Echo")
	context.check(noisy.inventory.filter("material")[0].definition_id == "needle_hound_quills", "Quills are materials")

func _test_kenta(context: TestContext) -> void:
	var save := SaveService.new()
	for choice: String in GameSession.GROVE_KENTA_CHOICES:
		var session: GameSession = _at_hounds(true)
		_win(session.start_combat("needle_hound"))
		DomainSuite.claim_pending(session)
		context.check(not session.apply_grove_command(choice), "Choice is gated by the opening dialogue")
		see(session, 7)
		if choice == "grove_kenta_bandage":
			var bandage: ItemInstance = session.grove_bandage()
			session.inventory.remove(bandage.instance_id, 1)
			context.check(not session.apply_grove_command(choice), "Bandage branch is rejected without an item")
			session.inventory.add(session.get_item_definition(GameSession.GROVE_BANDAGE), 1)
		context.check(session.apply_grove_command(choice), "Choice commits %s" % choice)
		context.check(not session.apply_grove_command(choice), "Choice cannot run twice")
		var restored := GameSession.new()
		restored.apply_state_dto(save.capture(session))
		context.check(restored.grove_kenta_outcome() == choice and restored.grove_stage() == "pollen_pair", "Choice and next stage survive Continue")
		context.check(restored.npc_flags.get("grove_kenta_trust", false) == (choice != "grove_kenta_hint"), "Only helped Kenta grants warning and trust")
		context.check((restored.grove_bandage() == null) == (choice == "grove_kenta_bandage"), "Only bandage choice consumes the item")

func _test_pollen(context: TestContext) -> void:
	for dodge: bool in [false, true]:
		var session: GameSession = _at_hounds(true)
		_win(session.start_combat("needle_hound"))
		DomainSuite.claim_pending(session)
		see(session, 7)
		session.apply_grove_command("grove_kenta_hint")
		context.check(not session.select_encounter("dust_moth"), "Approach line gates second fight")
		see(session, 11)
		session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
		var pair: CombatResolver = session.start_combat("dust_moth")
		var moth: CombatResolver.EnemySlot = pair.enemy_slots[0]
		var weaver: CombatResolver.EnemySlot = pair.enemy_slots[1]
		context.check(pair.target == moth and moth.remaining != weaver.remaining, "Moth has priority and the warnings are staggered")
		pair.advance_ticks(moth.remaining + moth.actor.definition.startup_ticks - 1)
		if dodge:
			pair.request_dodge()
		pair.advance_ticks(1)
		context.check((pair.slowed_ticks > 0) != dodge, "Pollen slow depends on dodge at contact")
		context.check(pair.hero.current_hp == pair.hero.max_hp, "Pollen is a status without direct damage")
		context.check(pair.request_attack(), "Attack remains available with pollen")
		context.check((pair.hero_attack_cooldown > pair.hero.definition.attack_cooldown_ticks) != dodge, "Only pollen exposure slows the swing")
		pair.advance_ticks(weaver.remaining + weaver.actor.definition.startup_ticks)
		context.check((pair.hero.current_hp < pair.hero.max_hp) != dodge, "Weaver resolves its own threat within the shared dodge window")
		if dodge:
			session.abandon_combat()
		else:
			pair.advance_ticks(3000)
			context.check(pair.is_finished and not pair.won, "A living weaver can defeat Haruto independently")
		context.check(session.awaiting_return and not session.has_pending_battle_result() and GameRoot.route_for_continue(session) == "checkpoint", "Forfeit and defeat follow the existing return path")

func _test_progress(context: TestContext) -> void:
	var save := SaveService.new()
	var session: GameSession = _at_hounds(true)
	_win(session.start_combat("needle_hound"))
	context.check(save.save(session, SAVE_PATH), "Pending Grove result saves as v7")
	var restored := GameSession.new()
	context.check(save.load_into(restored, SAVE_PATH) and GameRoot.route_for_continue(restored) == "combat", "Continue opens durable pending result")
	context.check(restored.grove_stage() == "hound_pair" and DomainSuite.claim_pending(restored), "Claim alone advances Grove")
	for marker_first: bool in [false, true]:
		session = _at_clearing(4)
		var first: String = "marker" if marker_first else "flax"
		var second: String = "flax" if marker_first else "marker"
		context.check(session.checkpoints.begin(), "Seal can start before either objective")
		session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
		context.check(session.checkpoints.apply_completion(), "First seal commits")
		context.check(session.apply_grove_command(first) and not session.apply_grove_command(first), "First objective is independent and idempotent")
		context.check(session.apply_grove_command("leave"), "May return to Lioren with one objective")
		session.set_guild_visit_active(true)
		context.check(not session.can_report_grove() and session.apply_grove_command("enter"), "Incomplete report is gated and re-entry is possible")
		context.check(session.apply_grove_command(second), "Either order of objectives works")
		context.check(session.checkpoints.begin(), "Seal is available after gathering")
		session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
		context.check(session.checkpoints.apply_completion(), "Second seal commits")
		var snapshot_one: Dictionary = session.checkpoints.manual_snapshots[0]["profile"]["quest_flags"]
		var snapshot_two: Dictionary = session.checkpoints.manual_snapshots[1]["profile"]["quest_flags"]
		context.check(not snapshot_one.has(GameSession.GROVE_FLAX) and snapshot_two.has(GameSession.GROVE_FLAX) and snapshot_two.has(GameSession.GROVE_MARKER), "Snapshots record exact objective progress")
		session.apply_grove_command("leave")
		session.set_guild_visit_active(true)
		see(session, 21)
		var echoes: int = session.echoes
		context.check(session.apply_grove_command("report") and not session.apply_grove_command("report"), "Report rewards commit once")
		context.check(session.wallet[GameSession.SILVER] == 35 and session.echoes == echoes + 2, "Report awards silver and two Echoes")
		context.check(not session.quest_flags.get(GameSession.GROVE_LEVEL_THREE, false), "Level 3 line is gated by actual advancement")
		session.awaiting_return = true
		var point: String = session.checkpoints.manual_snapshots[0]["checkpoint_id"]
		context.check(session.checkpoints.restore(point) and not session.quest_flags.has(GameSession.GROVE_REPORTED), "Rollback restores pre-report quest and technique state")
		context.check(not session.quest_flags.has(GameSession.GROVE_FLAX) and not session.quest_flags.has(GameSession.GROVE_MARKER) and session.seen_cue_ids.has("DIA_GROVE_021"), "Rollback clears objectives while preserving dialogue memory")
		context.check(session.echoes == echoes + 2, "One-time Echoes are preserved after rollback")

func _test_technique(context: TestContext) -> void:
	var damages: Array[int] = []
	for multiplier: float in [1.0, 1.25]:
		var session := GameSession.new()
		at_guild(session)
		var source: ActorDefinition = load("res://data/actors/needle_hound.tres")
		var definition: ActorDefinition = source.duplicate()
		definition.max_hp = 100
		var combat := CombatResolver.new(session.hero, definition)
		combat.auto_attack_enabled = false
		combat.vulnerable_ability_bonus = multiplier
		combat.advance_ticks(definition.telegraph_ticks + definition.startup_ticks + definition.active_ticks + definition.recovery_ticks)
		context.check(combat.is_vulnerable() and combat.request_ability(), "The existing ability can land during vulnerability")
		var hp: int = combat.enemy.current_hp
		combat.advance_ticks(combat.hero.definition.attack_startup_ticks)
		damages.append(hp - combat.enemy.current_hp)
	context.check(damages[1] > damages[0], "The mastered technique increases vulnerability contact damage")

func _test_balance(context: TestContext) -> void:
	var direct: GameSession = _at_hounds()
	direct.choose_upgrade("strength")
	var jacket: ItemInstance = direct.inventory.add(direct.get_item_definition("wanderer_jacket"), 1)[0]
	direct.equip_item(jacket.instance_id)
	var hounds: CombatResolver = direct.start_combat("needle_hound")
	hounds.advance_ticks(1200)
	context.check(hounds.won and direct.hero.current_hp < direct.hero.max_hp, "The equipped level-two hero survives the direct approach and takes damage")
	for xp: int in [16, 48]:
		for format: String in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE]:
			for combat_seed: int in [11, 22, 33]:
				var session: GameSession = _at_hounds(true, xp)
				session.set_loot_seed("grove_%d" % combat_seed)
				session.set_combat_format(format)
				if xp > 16:
					while session.hero.pending_upgrade_choices > 0:
						session.choose_upgrade("strength")
				for enemy_id: String in ["needle_hound", "dust_moth"]:
					var combat: CombatResolver = session.start_combat(enemy_id)
					if combat == null:
						context.check(false, "%s combat starts, xp=%d seed=%d" % [enemy_id, xp, combat_seed])
						break
					while not combat.is_finished and combat.tick_count < 1200:
						if format == GameSession.COMBAT_FORMAT_ACTIVE:
							for slot: CombatResolver.EnemySlot in combat.enemy_slots:
								if not slot.actor.is_dead() and slot.phase == CombatResolver.Phase.STARTUP and slot.remaining == 2:
									combat.request_dodge()
							if not combat.request_ability():
								combat.request_attack()
						combat.advance_ticks(1)
					var label: String = "%s %s xp=%d seed=%d ticks=%d HP=%d" % [enemy_id, format, xp, combat_seed, combat.tick_count, combat.hero.current_hp]
					context.check(combat.won and DomainSuite.claim_pending(session), label)
					if combat_seed == 11:
						print("GROVE_SIM ", label)
					if enemy_id == "needle_hound" and combat.won:
						see(session, 7)
						session.apply_grove_command("grove_kenta_safe")
						see(session, 11)
