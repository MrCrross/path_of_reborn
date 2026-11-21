extends SceneTree

const DomainSuite = preload("res://tests/domain_suite.gd")

## Shipped resolver и команды GameSession; формулы урона, RNG и награды здесь
## не копируются. Политики описывают только правило бота, не человеческий skill
## и не доказанную верхнюю границу.
const SEEDS: Array[int] = [11, 22, 33]
const ENEMIES: Array[String] = ["moss_slime", "goblin_scout", "goblin_trial"]
const POLICIES: Array[String] = ["no_defense", "auto_v1", "manual_competent_v1", "manual_slow_8_v1", "first_available_window_v1"]
const ISOLATED_BUILDS: Array[String] = ["base", "strength_2", "health_2", "sword_only"]
const ROUTE_BUILDS: Array[String] = ["no_progress", "strength_2", "health_2", "drop_equipment", "strength_2_drops", "health_2_drops"]
const MAX_TICKS: int = 6000

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var isolated_count: int = 0
	for build: String in ISOLATED_BUILDS:
		for policy: String in POLICIES:
			for enemy_id: String in ENEMIES:
				for seed_value: int in SEEDS:
					print("SIM_JSON %s" % JSON.stringify(_simulate_isolated(build, policy, enemy_id, seed_value)))
					isolated_count += 1
	var route_count: int = 0
	for build: String in ROUTE_BUILDS:
		for policy: String in POLICIES:
			for seed_value: int in SEEDS:
				print("SIM_JSON %s" % JSON.stringify(_simulate_route(build, policy, seed_value)))
				route_count += 1
	print("SIMULATION DONE isolated=%d route=%d seeds=%s" % [isolated_count, route_count, str(SEEDS)])
	quit()

func _make_isolated_build(build: String) -> GameSession:
	var session := GameSession.new()
	if build in ["strength_2", "health_2"]:
		session.hero.gain_xp(24)
		var stat: String = "strength" if build == "strength_2" else "max_hp"
		for index: int in range(2):
			session.choose_upgrade(stat)
	if build == "sword_only":
		var swords: Array[ItemInstance] = session.inventory.add(session.get_item_definition("training_sword"), 1)
		session.equip_item(swords[0].instance_id)
	return session

func _simulate_isolated(build: String, policy: String, enemy_id: String, seed_value: int) -> Dictionary:
	var session := _make_isolated_build(build)
	session.set_loot_seed("sim_%d" % seed_value)
	if enemy_id == GameSession.TRIAL_ENEMY_ID:
		session.route_state["next_index"] = session.route_nodes().size()
		session.route_state["completed"] = true
	var encounter: Dictionary = _run_encounter(session, policy, enemy_id)
	encounter.merge({"scope": "isolated", "build": build, "policy": policy, "seed": seed_value})
	return encounter

func _simulate_route(build: String, policy: String, seed_value: int) -> Dictionary:
	var session := GameSession.new()
	session.set_loot_seed("sim_%d" % seed_value)
	var encounters: Array[Dictionary] = []
	var total_ticks: int = 0
	for enemy_id: String in ENEMIES:
		_apply_route_build(session, build)
		var encounter: Dictionary = _run_encounter(session, policy, enemy_id)
		encounters.append(encounter)
		total_ticks += int(encounter["ticks"])
		if not bool(encounter["won"]) or not bool(encounter["claim_ok"]):
			break
	return {
		"scope": "route",
		"route": "moss_slime>goblin_scout>goblin_trial",
		"build": build,
		"policy": policy,
		"seed": seed_value,
		"completed": session.route_completed() and encounters.size() == ENEMIES.size() and bool(encounters[-1]["won"]),
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

func _apply_route_build(session: GameSession, build: String) -> void:
	if build.begins_with("strength_2"):
		while session.hero.pending_upgrade_choices > 0 and int(session.hero.capture_dto()["strength_upgrades"]) < 2:
			session.choose_upgrade("strength")
	elif build.begins_with("health_2"):
		while session.hero.pending_upgrade_choices > 0 and int(session.hero.capture_dto()["max_hp_upgrades"]) < 2:
			session.choose_upgrade("max_hp")
	if build == "drop_equipment" or build.ends_with("_drops"):
		for type_id: String in ["weapon", "charm"]:
			var items: Array[ItemInstance] = session.inventory.filter(type_id)
			if not items.is_empty():
				session.equip_item(items[-1].instance_id)

func _run_encounter(session: GameSession, policy: String, enemy_id: String) -> Dictionary:
	if not session.select_encounter(enemy_id):
		return {"enemy": enemy_id, "error": "selection_refused", "won": false, "claim_ok": false, "ticks": 0}
	var resolver: CombatResolver = session.start_combat(enemy_id)
	if resolver == null:
		return {"enemy": enemy_id, "error": "start_refused", "won": false, "claim_ok": false, "ticks": 0}
	resolver.auto_dodge_enabled = policy == "auto_v1"
	var enemy_strikes: Array[bool] = []
	var defense_uses: Array[String] = []
	var hero_strikes: Array[int] = []
	resolver.dodge_resolved.connect(func(success: bool) -> void: enemy_strikes.append(success))
	resolver.dodge_begun.connect(func(source: String) -> void: defense_uses.append(source))
	resolver.hero_attack_landed.connect(func(_run_id: String, _target_id: String, amount: int) -> void: hero_strikes.append(amount))
	var max_hp: int = session.hero.max_hp
	while not resolver.is_finished and resolver.tick_count < MAX_TICKS:
		_apply_policy(resolver, policy)
		resolver.advance_ticks(1)
	var pending: Dictionary = session.pending_battle_result.duplicate(true)
	var result_id: String = String(pending.get("result_id", ""))
	var claimed: bool = not result_id.is_empty() and DomainSuite.claim_pending(session)
	return {
		"enemy": enemy_id,
		"won": resolver.won,
		"finished": resolver.is_finished,
		"ticks": resolver.tick_count,
		"seconds": snappedf(resolver.tick_count / 60.0, 0.1),
		"hp_left": session.hero.current_hp,
		"max_hp": max_hp,
		"damage_taken": max_hp - session.hero.current_hp,
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
	match policy:
		"manual_competent_v1":
			if resolver.enemy_phase == CombatResolver.Phase.STARTUP and resolver.phase_ticks_remaining <= 2:
				resolver.request_dodge()
		"manual_slow_8_v1":
			if resolver.enemy_phase == CombatResolver.Phase.STARTUP and resolver.phase_ticks_remaining <= 8:
				resolver.request_dodge()
		"first_available_window_v1":
			if resolver.dodge_cooldown == 0 and resolver.dodge_ticks_remaining == 0 and resolver.enemy_phase in [CombatResolver.Phase.STARTUP, CombatResolver.Phase.ACTIVE]:
				resolver.request_dodge()
