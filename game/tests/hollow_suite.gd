extends RefCounted

const DomainSuite = preload("res://tests/domain_suite.gd")
const GroveSuite = preload("res://tests/grove_suite.gd")
const TestContext = DomainSuite.TestContext
const SAVE_PATH := "user://path_of_reborn_tests/hollow/profile.json"

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for entry: Array in [
		["hollow_access_armor_and_marker", _test_river],
		["hollow_shelf_targets_pending_and_tempo", _test_shelf],
		["hollow_elite_checkpoint_and_report", _test_elite],
		["hollow_balance_auto_and_active", _test_balance],
	]:
		var context := TestContext.new()
		entry[1].call(context)
		results.append({"name": entry[0], "checks": context.checks})
	return results

static func at_hollow_order(session: GameSession) -> void:
	GroveSuite.at_guild(session, true, 38)
	for flag: String in [GameSession.GROVE_HOUNDS_WON, GameSession.GROVE_POLLEN_WON, GameSession.GROVE_FLAX, GameSession.GROVE_MARKER, GameSession.GROVE_REPORTED]:
		session.quest_flags[flag] = true
	session.quest_flags["grove_approached"] = true
	session.npc_flags["grove_kenta_safe"] = true
	session.wallet[GameSession.SILVER] = 35
	var jacket: ItemInstance = session.inventory.add(session.get_item_definition("wanderer_jacket"), 1)[0]
	session.equip_item(jacket.instance_id)

static func see(session: GameSession, number: int) -> void:
	session.seen_cue_ids["DIA_HOLLOW_%03d" % number] = true

func at_river() -> GameSession:
	var session := GameSession.new()
	at_hollow_order(session)
	see(session, 4)
	session.apply_hollow_command("enter")
	see(session, 5)
	return session

func at_shelf() -> GameSession:
	var session: GameSession = at_river()
	session.start_combat("river_shieldback").advance_ticks(1800)
	DomainSuite.claim_pending(session)
	session.apply_hollow_command("water_marker")
	see(session, 6)
	return session

func _test_river(context: TestContext) -> void:
	var session := GameSession.new()
	var dialogue := DialogueRunner.new()
	context.check(dialogue.load_file(GameSession.HOLLOW_NARRATIVE_PATH) and dialogue.entries.size() == 23, "All Hollow cues load through the normal timeline")
	GroveSuite.at_guild(session)
	context.check(not session.can_enter_hollow(), "Registration alone cannot open Blue Hollow")
	at_hollow_order(session)
	var save := SaveService.new()
	context.check(save.validate(save.capture(session)), "Existing v7 profile with no Hollow flags validates")
	context.check(not session.apply_hollow_command("enter"), "Departure dialogue gates the first visit")
	see(session, 4)
	session.traces = 3
	context.check(not session.apply_hollow_command("enter"), "Rest is required at three traces")
	session.traces = 0
	context.check(session.apply_hollow_command("enter") and not session.select_encounter("goblin_scout", true), "Entry selects the new route without mixing repeat encounters")
	context.check(not session.apply_hollow_command("water_marker") and not session.checkpoints.can_begin(), "River fight gates the lower marker and safe point")
	see(session, 5)
	session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
	var combat: CombatResolver = session.start_combat("river_shieldback")
	var full_hp: int = combat.enemy.max_hp
	combat.request_attack()
	combat.advance_ticks(combat.hero.definition.attack_startup_ticks)
	var armor_damage: int = full_hp - combat.enemy.current_hp
	var definition: ActorDefinition = combat.enemy.definition
	combat.advance_ticks(definition.telegraph_ticks + definition.startup_ticks + definition.active_ticks + definition.recovery_ticks - combat.tick_count)
	context.check(combat.is_vulnerable() and combat.request_attack(), "Recovery exposes the joints")
	var hp_before: int = combat.enemy.current_hp
	combat.advance_ticks(combat.hero.definition.attack_startup_ticks)
	context.check(hp_before - combat.enemy.current_hp > armor_damage, "The same attack deals more damage on exposed joints")
	combat.enemy.take_damage(combat.enemy.current_hp - 1)
	combat.advance_ticks(combat.hero_attack_cooldown)
	combat.request_attack()
	combat.advance_ticks(combat.hero.definition.attack_startup_ticks)
	context.check(DomainSuite.claim_pending(session) and session.hollow_stage() == "water_marker", "Only the claimed battle unlocks the marker")
	context.check(session.apply_hollow_command("water_marker") and not session.apply_hollow_command("water_marker"), "Marker and its crystal are idempotent")
	var crystals: Array[ItemInstance] = session.inventory.filter("echo")
	context.check(crystals.size() == 1 and crystals[0].aspect_id == "water" and crystals[0].quantity == 1, "Exactly one water crystal was delivered")

func _test_shelf(context: TestContext) -> void:
	var session: GameSession = at_shelf()
	context.check(session.apply_hollow_command("collapse") and not session.apply_hollow_command("collapse"), "Shelf collapse can be recorded once")
	session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
	var combat: CombatResolver = session.start_combat("stone_rodent")
	context.check(combat.enemy_slots.size() == 3 and combat.enemy_slots[0].stunned and not combat.enemy_slots[1].stunned and not combat.enemy_slots[2].stunned, "Only the front rodent is stunned")
	context.check(combat.request_attack() and combat.select_target("ash_raven"), "Third enemy is selectable during a swing")
	combat.advance_ticks(combat.hero.definition.attack_startup_ticks)
	context.check(combat.enemy.current_hp < combat.enemy.max_hp and combat.target.actor.current_hp == combat.target.actor.max_hp, "A swing remains bound to its original target")
	_simulate(combat, true)
	context.check(combat.won and session.battle_echo_reward(session.pending_battle_result) == 2, "Two rodents and raven settle together and yield Echo once per species")
	var save := SaveService.new()
	context.check(save.save(session, SAVE_PATH), "The three-enemy pending result is durable")
	var wrong_stage: Dictionary = save.capture(session)
	wrong_stage["profile"]["quest_flags"][GameSession.HOLLOW_SHELF_WON] = true
	context.check(not save.validate(wrong_stage), "A pending result from another stage is rejected")
	var restored := GameSession.new()
	context.check(save.load_into(restored, SAVE_PATH) and GameRoot.route_for_continue(restored) == "combat", "Continue restores the same pending fight")
	context.check(DomainSuite.claim_pending(restored) and restored.quest_flags.get(GameSession.HOLLOW_TEMPO, false), "Claim commits the learned technique")
	var shield: ActorDefinition = load(GameSession.ACTOR_PATHS["river_shieldback"])
	var next := CombatResolver.new(restored.hero, shield)
	next.auto_attack_enabled = false
	next.tempo_window_ticks = 55
	next.tempo_startup_reduction = 8
	next.advance_ticks(shield.telegraph_ticks + shield.startup_ticks - 1)
	next.request_dodge()
	next.advance_ticks(1)
	next.request_attack()
	next.advance_ticks(restored.hero.definition.attack_startup_ticks - 8)
	context.check(next.enemy.current_hp < next.enemy.max_hp, "A clean dodge advances the next contact")
	var health: int = next.enemy.current_hp
	next.advance_ticks(next.hero_attack_cooldown)
	next.request_attack()
	next.advance_ticks(restored.hero.definition.attack_startup_ticks - 8)
	context.check(next.enemy.current_hp == health, "The accelerated strike is consumed once")

func _test_elite(context: TestContext) -> void:
	var session: GameSession = at_shelf()
	session.apply_hollow_command("collapse")
	session.start_combat("stone_rodent").advance_ticks(1800)
	DomainSuite.claim_pending(session)
	see(session, 21)
	context.check(not session.apply_hollow_command("upper_marker"), "Upper marker is gated by the third battle")
	context.check(session.apply_map_travel(GameSession.LOCATION_LIOREN) and session.apply_map_travel(GameSession.MAP_SHOP), "The shop is reachable between story battles")
	context.check(session.apply_map_travel(GameSession.LOCATION_HOLLOW) and session.hollow_stage() == "upper_guard", "The story stage survives a shop visit")
	session.start_combat("river_shieldback").advance_ticks(1800)
	context.check(DomainSuite.claim_pending(session) and session.apply_hollow_command("upper_marker"), "Upper marker is restored after the guard")
	see(session, 7)
	context.check(session.apply_hollow_command("cloth") and session.checkpoints.begin(), "Cloth and safe ledge are available before elite")
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	context.check(session.checkpoints.apply_completion(), "Safe ledge can be recorded as a checkpoint")
	var checkpoint_id: String = session.checkpoints.manual_snapshots[0]["checkpoint_id"]
	context.check(session.apply_hollow_command("descend") and session.apply_hollow_command("retreat"), "Player can back out without losing progress")
	context.check(not session.quest_flags.has(GameSession.HOLLOW_ELITE_WON) and session.hollow_stage() == "ledge", "Retreat leaves elite available")
	session.apply_hollow_command("descend")
	see(session, 9)
	session.start_combat("crystal_toad")
	session.abandon_combat()
	context.check(GameRoot.route_for_continue(session) == "checkpoint" and session.checkpoints.restore(checkpoint_id), "Elite loss uses the normal checkpoint flow")
	context.check(session.hollow_stage() == "ledge" and session.quest_flags.has(GameSession.HOLLOW_CLOTH), "Return preserves the main objectives from the ledge")
	session.apply_hollow_command("leave")
	session.set_guild_visit_active(true)
	see(session, 18)
	var echoes: int = session.echoes
	context.check(session.apply_hollow_command("report") and not session.apply_hollow_command("report"), "Elite victory is optional and report cannot pay twice")
	context.check(session.wallet[GameSession.SILVER] == 80 and session.echoes == echoes + 2, "Report grants the configured currencies once")

func _test_balance(context: TestContext) -> void:
	for format: String in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE]:
		var session: GameSession = at_river()
		session.set_combat_format(format)
		see(session, 6)
		see(session, 7)
		see(session, 9)
		see(session, 21)
		for enemy_id: String in ["river_shieldback", "stone_rodent", "river_shieldback", "crystal_toad"]:
			var stage: String = session.hollow_stage()
			var combat: CombatResolver = session.start_combat(enemy_id)
			if combat == null:
				context.check(false, "Missing encounter %s in %s" % [enemy_id, format])
				break
			_simulate(combat, format == GameSession.COMBAT_FORMAT_ACTIVE)
			var label: String = "%s %s ticks=%d HP=%d" % [enemy_id, format, combat.tick_count, session.hero.current_hp]
			print("HOLLOW_SIM ", label)
			if not combat.won or not DomainSuite.claim_pending(session):
				context.check(false, label)
				break
			context.check(true, label)
			if stage == "river":
				session.apply_hollow_command("water_marker")
			elif stage == "upper_guard":
				session.apply_hollow_command("upper_marker")
				session.apply_hollow_command("cloth")
				session.choose_upgrade("strength")
				session.choose_upgrade("max_hp")
				session.apply_hollow_command("descend")
			elif stage == "elite":
				var radiant: bool = false
				for item: ItemInstance in session.inventory.filter("echo"):
					radiant = radiant or item.aspect_id == "stone_radiant"
				context.check(radiant and session.quest_flags.get(GameSession.HOLLOW_ELITE_WON, false), "Elite reward has the radiant aspect")

func _simulate(combat: CombatResolver, active: bool) -> void:
	while not combat.is_finished and combat.tick_count < 1800:
		if active:
			for slot: CombatResolver.EnemySlot in combat.enemy_slots:
				if not slot.actor.is_dead() and slot.phase == CombatResolver.Phase.STARTUP and slot.remaining <= 2:
					combat.request_dodge()
			if combat.enemy.definition.id == "crystal_toad":
				if combat.is_vulnerable():
					combat.request_ability()
			elif not combat.request_ability():
				combat.request_attack()
		combat.advance_ticks(1)
