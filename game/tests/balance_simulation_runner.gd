extends SceneTree

const DomainSuite = preload("res://tests/domain_suite.gd")

## Shipped resolver и команды GameSession; формулы урона, RNG и награды здесь
## не копируются. Политики описывают только правило бота, не человеческий skill
## и не доказанную верхнюю границу.
const SEEDS: Array[int] = [11, 22, 33]
const POLICIES: Array[String] = ["no_defense_v2", "auto_v1", "manual_competent_v2", "manual_early_8_v2", "first_available_window_v2"]
const ISOLATED_BUILDS: Array[String] = ["base", "strength_2", "health_2", "sword_only", "guild_sword", "guild_equipped"]
const ROUTE_BUILDS: Array[String] = ["unspent_store", "strength_store", "health_store", "unspent_equip", "strength_equip", "health_equip"]
const MAX_TICKS: int = 6000
var invalid_encounters: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var route: Array[String] = []
	for node: Dictionary in GameSession.route_definition()["nodes"]:
		route.append(node["enemy_id"])
	route.append(GameSession.TRIAL_ENEMY_ID)
	var enemies: Array[String] = []
	enemies.assign(GameSession.route_definition()["repeat_enemies"].keys())
	enemies.append(GameSession.TRIAL_ENEMY_ID)
	var isolated_count: int = 0
	for build: String in ISOLATED_BUILDS:
		for policy: String in POLICIES:
			for enemy_id: String in enemies:
				for seed_value: int in SEEDS:
					print("SIM_JSON %s" % JSON.stringify(_simulate_isolated(build, policy, enemy_id, seed_value)))
					isolated_count += 1
	var route_count: int = 0
	for build: String in ROUTE_BUILDS:
		for policy: String in POLICIES:
			for seed_value: int in SEEDS:
				print("SIM_JSON %s" % JSON.stringify(_simulate_route(build, policy, seed_value, route)))
				route_count += 1
	print("SIMULATION DONE isolated=%d route=%d seeds=%s invalid=%d" % [isolated_count, route_count, str(SEEDS), invalid_encounters])
	quit(1 if invalid_encounters else 0)

func _make_isolated_build(build: String) -> GameSession:
	var session := GameSession.new()
	if build in ["strength_2", "health_2"]:
		var stat: String = "strength" if build == "strength_2" else "max_hp"
		for index: int in range(2):
			session.hero.gain_xp(session.hero.xp_to_next_level())
			session.choose_upgrade(stat)
	if build in ["sword_only", "guild_sword", "guild_equipped"]:
		var swords: Array[ItemInstance] = session.inventory.add(session.get_item_definition("training_sword"), 1)
		session.equip_item(swords[0].instance_id)
	if build in ["guild_sword", "guild_equipped"]:
		session.hero.gain_xp(session.hero.xp_to_next_level())
		session.choose_upgrade("strength")
	if build == "guild_equipped":
		var jacket: ItemInstance = session.inventory.add(session.get_item_definition("wanderer_jacket"), 1)[0]
		session.equip_item(jacket.instance_id)
	return session

func _simulate_isolated(build: String, policy: String, enemy_id: String, seed_value: int) -> Dictionary:
	var session := _make_isolated_build(build)
	session.set_loot_seed("sim_%d" % seed_value)
	# Start isolated story encounters at their actual node. Later species use
	# the Trail's scaled repeat encounter after discovery in the journal.
	var repeat: bool = true
	for index: int in session.route_nodes().size():
		if session.route_nodes()[index]["enemy_id"] == enemy_id:
			session.route_state["next_index"] = index
			repeat = false
			break
	if enemy_id == GameSession.TRIAL_ENEMY_ID:
		session.route_state["next_index"] = session.route_nodes().size()
		session.route_state["completed"] = true
		repeat = false
	elif repeat:
		session.enemy_journal[enemy_id] = true
	var encounter: Dictionary = _run_encounter(session, policy, enemy_id, repeat)
	encounter.merge({"scope": "isolated", "build": build, "policy": policy, "seed": seed_value})
	return encounter

func _simulate_route(build: String, policy: String, seed_value: int, route: Array[String]) -> Dictionary:
	var session := GameSession.new()
	session.set_loot_seed("sim_%d" % seed_value)
	var encounters: Array[Dictionary] = []
	var total_ticks: int = 0
	for enemy_id: String in route:
		if session.hero.pending_upgrade_choices > 0:
			if build.begins_with("strength_"):
				session.choose_upgrade("strength")
			elif build.begins_with("health_"):
				session.choose_upgrade("max_hp")
		var helping_daijiro: bool = session.next_route_node().get("approach", "") == "daijiro"
		if helping_daijiro:
			# merchant_intro.json finishes before the scout encounter.
			session.world_flags["daijiro_intervened"] = true
		var encounter: Dictionary = _run_encounter(session, policy, enemy_id)
		encounters.append(encounter)
		total_ticks += int(encounter["ticks"])
		if not bool(encounter["won"]) or not bool(encounter["claim_ok"]):
			break
		if helping_daijiro:
			var gift_choice: String = "equip" if build.ends_with("_equip") else "store"
			if not _claim_daijiro_gift(session, gift_choice):
				invalid_encounters += 1
				push_error("Failed to claim Daijiro's story gift for %s" % build)
				break
	return {
		"scope": "route",
		"route": ">".join(route),
		"build": build,
		"policy": policy,
		"seed": seed_value,
		"story_completed": session.route_completed(),
		"completed": session.route_completed() and encounters.size() == route.size() and bool(encounters[-1]["claim_ok"]),
		"encounters": encounters,
		"ticks": total_ticks,
		"seconds": snappedf(total_ticks / 60.0, 0.1),
		"hp_left": session.hero.current_hp,
		"level": session.hero.level,
		"experience": session.hero.experience,
		"echoes": session.echoes,
		"equipment": session.inventory.equipment.duplicate(),
		"inventory": session.inventory.capture_dto()["items"],
	}

func _claim_daijiro_gift(session: GameSession, choice: String) -> bool:
	# merchant_after.json completes the introduction. The victory flag comes
	# from claiming the actual scout encounter, and the gift equips via its card.
	session.world_flags["daijiro_introduction_completed"] = true
	if not session.prepare_daijiro_sword_reward():
		return false
	var entry: Dictionary = session.pending_story_reward["items"][0]
	return session.choose_story_reward(entry["entry_id"], choice) and session.claim_story_reward(GameSession.DAIJIRO_SWORD_REWARD_ID)

func _run_encounter(session: GameSession, policy: String, enemy_id: String, repeat: bool = false) -> Dictionary:
	session.set_combat_format(GameSession.COMBAT_FORMAT_AUTO if policy == "auto_v1" else GameSession.COMBAT_FORMAT_ACTIVE)
	if not session.select_encounter(enemy_id, repeat):
		invalid_encounters += 1
		return {"enemy": enemy_id, "error": "selection_refused", "won": false, "claim_ok": false, "ticks": 0}
	var resolver: CombatResolver = session.start_selected_combat()
	if resolver == null:
		invalid_encounters += 1
		return {"enemy": enemy_id, "error": "start_refused", "won": false, "claim_ok": false, "ticks": 0}
	var mode: String = session.active_encounter_context["encounter_mode"]
	var level: int = session.hero.level
	var strength: int = session.hero.strength
	var defense: int = session.hero.defense
	var enemy_strikes: Array[bool] = []
	var strike_ticks: Array[int] = []
	var hp_lost: Array[int] = []
	var defense_uses: Array[String] = []
	var hero_strikes: Array[int] = []
	var record_strike: Callable = func(success: bool) -> void:
		enemy_strikes.append(success)
		strike_ticks.append(resolver.tick_count)
	resolver.dodge_resolved.connect(record_strike)
	resolver.damage_dealt.connect(func(target_id: String, amount: int) -> void:
		if target_id == "hero":
			hp_lost.append(amount))
	resolver.dodge_begun.connect(func(source: String) -> void: defense_uses.append(source))
	resolver.hero_attack_landed.connect(func(_run_id: String, _target_id: String, amount: int) -> void: hero_strikes.append(amount))
	var max_hp: int = session.hero.max_hp
	while not resolver.is_finished and resolver.tick_count < MAX_TICKS:
		_apply_policy(resolver, policy)
		resolver.advance_ticks(1)
	resolver.dodge_resolved.disconnect(record_strike)
	var pending: Dictionary = session.pending_battle_result.duplicate(true)
	var result_id: String = String(pending.get("result_id", ""))
	var hp_left: int = session.hero.current_hp
	var claimed: bool = not result_id.is_empty() and DomainSuite.claim_pending(session)
	if not resolver.is_finished or (resolver.won and not claimed):
		invalid_encounters += 1
	return {
		"enemy": enemy_id,
		"encounter_mode": mode,
		"starting_level": level,
		"strength": strength,
		"defense": defense,
		"won": resolver.won,
		"finished": resolver.is_finished,
		"ticks": resolver.tick_count,
		"seconds": snappedf(resolver.tick_count / 60.0, 0.1),
		"hp_left": hp_left,
		"max_hp": max_hp,
		"damage_taken": max_hp - hp_left,
		"incoming_damage": hp_lost,
		"enemy_strike_ticks": strike_ticks,
		"hero_strikes": hero_strikes.size(),
		"hero_damage": hero_strikes,
		"enemy_strikes": enemy_strikes.size(),
		"defense_uses": defense_uses.size(),
		"dodged": enemy_strikes.count(true),
		"drops": pending.get("items", []),
		"xp": int(pending.get("xp", 0)),
		"echo_gained": bool(pending.get("echo_gained", false)),
		"trial_echo_gained": bool(pending.get("trial_echo_gained", false)),
		"claim_ok": claimed,
	}

func _apply_policy(resolver: CombatResolver, policy: String) -> void:
	if policy == "auto_v1":
		return
	# Manual policies press an available attack/skill through the active mode.
	if resolver.hero_attack_cooldown == 0:
		if not resolver.request_ability():
			resolver.request_attack()
	match policy:
		"manual_competent_v2":
			if resolver.enemy_phase == CombatResolver.Phase.STARTUP and resolver.phase_ticks_remaining <= 2:
				resolver.request_dodge()
		"manual_early_8_v2":
			if resolver.enemy_phase == CombatResolver.Phase.STARTUP and resolver.phase_ticks_remaining <= 8:
				resolver.request_dodge()
		"first_available_window_v2":
			if resolver.dodge_cooldown == 0 and resolver.dodge_ticks_remaining == 0 and resolver.enemy_phase in [CombatResolver.Phase.STARTUP, CombatResolver.Phase.ACTIVE]:
				resolver.request_dodge()
