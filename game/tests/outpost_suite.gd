extends RefCounted

const DomainSuite = preload("res://tests/domain_suite.gd")
const HollowSuite = preload("res://tests/hollow_suite.gd")
const TestContext = DomainSuite.TestContext

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for entry: Array in [
		["outpost_access_and_checkpoint", _test_access],
		["outpost_battle_patterns_auto_and_active", _test_battles],
		["outpost_reward_resume_and_completion", _test_reward],
	]:
		var context := TestContext.new()
		entry[1].call(context)
		results.append({"name": entry[0], "checks": context.checks})
	return results

static func at_outpost_order(session: GameSession, optional_elite: bool = false) -> void:
	HollowSuite.at_hollow_order(session)
	for flag: String in [GameSession.HOLLOW_STARTED, GameSession.HOLLOW_SHIELDBACK_WON, GameSession.HOLLOW_WATER_MARKER,
		GameSession.HOLLOW_SHELF_WON, GameSession.HOLLOW_UPPER_MARKER, GameSession.HOLLOW_TEMPO, GameSession.HOLLOW_CLOTH]:
		session.quest_flags[flag] = true
	session.claimed_echo_enemy_ids["ash_raven"] = true
	var route: Dictionary = GameSession.hollow_definition()
	var xp: int = int(route["nodes"]["river"]["xp"]) + int(route["nodes"]["shelf"]["xp"])
	if optional_elite:
		session.quest_flags[GameSession.HOLLOW_ELITE_WON] = true
		xp += int(route["nodes"]["elite"]["xp"])
	session.hero.gain_xp(xp)
	HollowSuite.see(session, 18)
	session.apply_hollow_command("report")

static func see_cues(session: GameSession, cues: Array) -> void:
	for cue: String in cues:
		session.seen_cue_ids[cue] = true

func _open_ravens(session: GameSession) -> void:
	see_cues(session, [GameSession.OUTPOST_ORDER_CUE])
	session.apply_outpost_command("enter")
	session.apply_outpost_command("bowl")
	session.apply_outpost_command("seal")
	see_cues(session, GameSession.outpost_node("ravens")["cues"])

func _test_access(context: TestContext) -> void:
	var session := GameSession.new()
	var dialogue := DialogueRunner.new()
	context.check(dialogue.load_file(GameSession.OUTPOST_NARRATIVE_PATH) and dialogue.entries.size() == 32, "The post and epilogue dialogue load as a valid timeline")
	HollowSuite.at_hollow_order(session)
	context.check(not session.can_enter_outpost(), "The Grove report cannot unlock the outpost")
	at_outpost_order(session)
	var saves := SaveService.new()
	context.check(saves.validate(saves.capture(session)) and session.hero.level == 4, "A v7 profile with the Hollow report opens the new route at level 4")
	context.check(not session.apply_outpost_command("enter"), "Midori must issue the outpost order")
	see_cues(session, [GameSession.OUTPOST_ORDER_CUE])
	session.traces = 3
	context.check(not session.apply_outpost_command("enter"), "Three traces require rest before departure")
	session.traces = 0
	context.check(session.apply_outpost_command("enter") and not session.apply_outpost_command("seal"), "The bowl is the first objective")
	context.check(session.checkpoints.begin(), "The approach has a safe point")
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	context.check(session.checkpoints.apply_completion(), "The safe point records the outpost location")
	var checkpoint_id: String = session.checkpoints.manual_snapshots[0]["checkpoint_id"]
	context.check(session.apply_outpost_command("bowl") and session.apply_outpost_command("seal"), "The world commands advance the route")
	context.check(not session.select_encounter("ash_raven"), "First contact must be read before the ravens")
	see_cues(session, GameSession.outpost_node("ravens")["cues"])
	session.start_combat("ash_raven")
	session.abandon_combat()
	context.check(session.awaiting_return and session.checkpoints.restore(checkpoint_id), "Defeat uses the normal Seal flow")
	context.check(session.location_id == GameSession.LOCATION_OUTPOST and session.outpost_stage() == "bowl" and session.traces == 1, "The Seal restores physical objectives and adds one trace")
	var legacy: Dictionary = {GameSession.OUTPOST_BOWL: true, GameSession.OUTPOST_SEAL: true, GameSession.OUTPOST_RAVENS_WON: true}
	context.check(GameSession.outpost_stage_for(legacy) == "warden", "Pre-update signal progress keeps the original route")

func _test_battles(context: TestContext) -> void:
	for format: String in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE]:
		var session := GameSession.new()
		at_outpost_order(session, format == GameSession.COMBAT_FORMAT_ACTIVE)
		_open_ravens(session)
		session.set_combat_format(format)
		var ravens: CombatResolver = session.start_combat("ash_raven")
		if ravens == null:
			context.check(false, "Ravens did not initialize")
			continue
		var actions: Array[String] = []
		ravens.ally_action.connect(func(action: String) -> void: actions.append(action))
		context.check(not ravens.enemy_slots[0].stunned and ravens.enemy_slots[1].stunned, "Akari holds just one raven")
		_simulate(ravens)
		context.check(ravens.won and DomainSuite.claim_pending(session), "The first battle completes in %s" % format)
		context.check(actions == ["hold", "dive_warning"], "Akari gives both warnings in %s" % format)
		context.check(session.hero.level == 4 and not session.select_encounter("bone_warden"), "Ravens preserve level 4 and the next dialogue gates the boss")
		_clear_patrols(session, context)
		see_cues(session, GameSession.outpost_node("warden")["cues"])
		var boss: CombatResolver = session.start_combat("bone_warden")
		if boss == null:
			context.check(false, "Boss did not initialize")
			continue
		actions.clear()
		var strikes: Array[String] = []
		boss.ally_action.connect(func(action: String) -> void: actions.append(action))
		boss.enemy_phase_changed.connect(func(instance_id: String) -> void:
			if instance_id == "bone_warden" and boss.enemy_phase == CombatResolver.Phase.ACTIVE:
				strikes.append(boss.warden_move))
		context.check(boss.enemy_slots[1].dormant and not boss.select_target("warden_raven"), "Hidden raven cannot be targeted")
		_simulate(boss)
		print("OUTPOST_SIM %s ticks=%d HP=%d moves=%s" % [format, boss.tick_count, session.hero.current_hp, str(strikes)])
		context.check(boss.won and not boss.enemy_slots[1].dormant and boss.enemy_slots[1].actor.is_dead(), "Victory includes the reinforcement in %s" % format)
		context.check(strikes.slice(0, 3) == ["attack", "summon", "void"] and actions == ["summon_warning", "joint_break"], "Sweep, summoning, void contact and the joint opening occur in order")
		var expected_level: int = 5 if format == GameSession.COMBAT_FORMAT_ACTIVE else 4
		context.check(DomainSuite.claim_pending(session) and session.outpost_stage() == "alliance" and session.hero.level == expected_level, "Level 5 requires XP beyond the core route")
		# The signal closure observes the boss; disconnect to release the reference cycle.
		for connection: Dictionary in boss.enemy_phase_changed.get_connections():
			boss.enemy_phase_changed.disconnect(connection["callable"])

func _test_reward(context: TestContext) -> void:
	var session := GameSession.new()
	at_outpost_order(session)
	_open_ravens(session)
	session.start_combat("ash_raven").advance_ticks(1800)
	DomainSuite.claim_pending(session)
	_clear_patrols(session, context)
	see_cues(session, GameSession.outpost_node("warden")["cues"])
	session.start_combat("bone_warden").advance_ticks(1800)
	var saves := SaveService.new()
	var dto: Dictionary = saves.capture(session)
	if not saves.validate(dto) or dto["pending_battle_result"].is_empty():
		context.check(false, "Save contains a valid pending boss result")
		return
	var wrong_location: Dictionary = dto.duplicate(true)
	wrong_location["location_id"] = GameSession.LOCATION_HOLLOW
	context.check(not saves.validate(wrong_location), "A boss result never loads into the Hollow")
	var restored := GameSession.new()
	restored.apply_state_dto(dto)
	context.check(GameRoot.route_for_continue(restored) == "combat" and not restored.apply_outpost_command("leave"), "Continue prioritizes the unclaimed boss result")
	context.check(DomainSuite.claim_pending(restored) and not DomainSuite.claim_pending(restored), "Both quest rewards claim once")
	var items: Array[ItemInstance] = restored.inventory.filter("quest")
	context.check(items.size() == 2 and not items[0].sellable and not items[1].sellable, "Badge and fragment are protected quest items")
	context.check(not restored.apply_outpost_command("alliance"), "The alliance requires the fixed dialogue")
	see_cues(restored, GameSession.outpost_node("alliance")["cues"])
	context.check(restored.apply_outpost_command("alliance") and restored.apply_outpost_command("leave"), "Temporary alliance leads back to Lioren")
	restored.set_guild_visit_active(true)
	see_cues(restored, GameSession.outpost_definition()["report_cues"])
	var silver: int = restored.wallet[GameSession.SILVER]
	var echoes: int = restored.echoes
	context.check(restored.apply_outpost_command("report") and not restored.apply_outpost_command("report"), "The report rewards once")
	context.check(restored.wallet[GameSession.SILVER] == silver + 60 and restored.echoes == echoes + 3, "The report pays the configured reward")
	context.check(not restored.apply_outpost_command("finish"), "The letter and map are required to finish")
	see_cues(restored, GameSession.outpost_definition()["epilogue_cues"])
	context.check(restored.apply_outpost_command("finish") and not restored.apply_outpost_command("finish"), "The epilogue completes the chapter once")

func _clear_patrols(session: GameSession, context: TestContext) -> void:
	for expected: String in ["gate_patrol", "stairs_patrol", "tower_patrol"]:
		context.check(session.outpost_stage() == expected, "Patrol stage %s is next" % expected)
		var patrol: CombatResolver = session.start_combat(GameSession.outpost_node(expected)["enemy_id"])
		if patrol == null:
			return
		_simulate(patrol)
		context.check(patrol.won and DomainSuite.claim_pending(session), "Patrol loot advances the route")

func _simulate(combat: CombatResolver) -> void:
	while not combat.is_finished and combat.tick_count < 1800:
		if combat.combat_format == GameSession.COMBAT_FORMAT_ACTIVE:
			for slot: CombatResolver.EnemySlot in combat.enemy_slots:
				if not slot.dormant and not slot.actor.is_dead() and slot.phase == CombatResolver.Phase.STARTUP and slot.remaining <= 2:
					combat.request_dodge()
			if not combat.request_ability():
				combat.request_attack()
		combat.advance_ticks(1)
