extends SceneTree

const DomainSuite = preload("res://tests/domain_suite.gd")

## Read-only audit of shipped rules. Does not open or write a player profile.
## Run with --fixed-fps 60; JSON output is an audit artifact, not game data.
##
## Обновлён под семантику итерации 2026-11-20 (pending-result + claim):
## - победа создаёт durable pending, inventory/XP не меняются до claim;
## - ни auto-dismiss, ни auto-выдачи нет: ожидание на экране результата
##   ничего не собирает и никуда не уводит;
## - выборы карточек находок завершаются одним атомарным claim;
## - один активный run: второй start_combat отклонён доменом;
## - невалидный route_state отклоняется валидацией сохранения;
## - hero_attack_begun подписан на клип замаха (F-01).
## Оригинальный снапшот аудита: probe_results.json (не перезаписывается).
var report: Dictionary = {"balance": [], "save_observations": [], "presentation": {}}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for build: String in ["base", "strength_level_5", "health_level_5", "sword"]:
		for enemy_id: String in ["moss_slime", "goblin_scout"]:
			for policy: String in ["idle_v1", "spam_v1", "react_6_ticks_v1"]:
				for seed_value: int in [11, 22, 33]:
					report["balance"].append(_trial(build, enemy_id, policy, seed_value))
	_observe_settlement()
	_observe_domain_guards()
	await _observe_presentation()
	var path: String = "res://../docs/reviews/followup_audit_2026_11_20/probe_results_refactor_2026_11_20.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("AUDIT_PROBE trials=", report["balance"].size(), " report=", path)
	print("SAVE_OBSERVATIONS ", JSON.stringify(report["save_observations"]))
	print("GUARDS ", JSON.stringify(report.get("guards", {})))
	print("PRESENTATION ", JSON.stringify(report["presentation"]))
	quit()

func _trial(build: String, enemy_id: String, policy: String, seed_value: int) -> Dictionary:
	var session := GameSession.new()
	session.set_loot_seed(str(seed_value))
	if build in ["strength_level_5", "health_level_5"]:
		session.hero.gain_xp(42)
		while session.hero.pending_upgrade_choices > 0:
			session.choose_upgrade("strength" if build == "strength_level_5" else "max_hp")
	elif build == "sword":
		var items: Array[ItemInstance] = session.inventory.add(session.get_item_definition("training_sword"), 1)
		session.equip_item(items[0].instance_id)
	var combat: CombatResolver = session.start_combat(enemy_id)
	var counters: Dictionary = {"damage": 0, "dodged": 0, "dodge_requests": 0, "enemy_strikes": 0}
	combat.damage_dealt.connect(func(target: String, amount: int) -> void:
		if target == "hero": counters["damage"] += amount)
	combat.dodge_resolved.connect(func(success: bool) -> void:
		counters["enemy_strikes"] += 1
		if success: counters["dodged"] += 1)
	var items_before: int = session.inventory.items.size()
	var level_before: int = session.hero.level
	while not combat.is_finished and combat.tick_count < 6000:
		var should_dodge: bool = policy == "spam_v1" or (policy == "react_6_ticks_v1" and combat.enemy_phase == CombatResolver.Phase.STARTUP and combat.phase_ticks_remaining <= 6)
		if should_dodge and combat.request_dodge(): counters["dodge_requests"] += 1
		combat.advance_ticks(1)
	# Новая семантика: win фиксирует pending, награды ждут отдельного claim.
	var pending: Dictionary = session.pending_battle_result.duplicate(true)
	var unclaimed: Dictionary = {
		"pending_created": not pending.is_empty(),
		"inventory_unchanged": session.inventory.items.size() == items_before,
		"level_unchanged": session.hero.level == level_before,
	}
	var claimed: bool = false
	if not pending.is_empty():
		claimed = DomainSuite.claim_pending(session)
	return {
		"build": build,
		"enemy": enemy_id,
		"policy": policy,
		"seed": seed_value,
		"ticks": combat.tick_count,
		"seconds": combat.tick_count / 60.0,
		"won": combat.won,
		"hp": session.hero.current_hp,
		"max_hp": session.hero.max_hp,
		"strength": session.hero.strength,
		"counts": counters,
		"unclaimed_after_win": unclaimed,
		"claim_ok": claimed,
		"route": session.route_state.duplicate(true),
	}

func _observe_settlement() -> void:
	var session := GameSession.new()
	var saves := SaveService.new()
	var observations: Array = report["save_observations"]
	var capture_event := func(kind: String) -> void:
		if session.in_combat or session.is_transaction_active(): return
		var dto: Dictionary = saves.capture(session)
		observations.append({"event": kind, "valid": saves.validate(dto), "level": session.hero.level, "items": session.inventory.items.size(), "echoes": session.echoes, "route": session.route_state.duplicate(true), "beaten": session.completed_encounter_ids().duplicate(true), "settlement_run": session.last_settlement.get("run_id", ""), "pending": not session.pending_battle_result.is_empty()})
	session.inventory.changed.connect(func() -> void: capture_event.call("inventory.changed"))
	session.profile_changed.connect(func() -> void: capture_event.call("profile_changed"))
	var combat: CombatResolver = session.start_combat("moss_slime")
	combat.advance_ticks(6000)
	report["after_settlement"] = {
		"beaten": session.completed_encounter_ids().duplicate(true),
		"route": session.route_state.duplicate(true),
		"pending_exists": not session.pending_battle_result.is_empty(),
		"inventory_still_empty": session.inventory.items.is_empty(),
	}
	# Claim внутри транзакции: ни одно наблюдаемое сохранение не должно быть
	# «половиной награды», beaten попадает в dto до итогового profile_changed.
	DomainSuite.claim_pending(session)
	report["after_claim"] = {
		"beaten": session.completed_encounter_ids().duplicate(true),
		"route": session.route_state.duplicate(true),
		"items": session.inventory.items.size(),
		"level": session.hero.level,
	}
	# Audit observers capture the session. Disconnect to avoid a probe-owned cycle.
	for connection: Dictionary in session.inventory.get_signal_connection_list("changed"):
		session.inventory.changed.disconnect(connection["callable"])
	for connection: Dictionary in session.get_signal_connection_list("profile_changed"):
		session.profile_changed.disconnect(connection["callable"])

func _observe_domain_guards() -> void:
	var session := GameSession.new()
	var first: CombatResolver = session.start_combat("moss_slime")
	var second: CombatResolver = session.start_combat("goblin_scout")
	# Новая семантика: второй бой поверх активного run отклоняется доменом.
	var guards: Dictionary = {"second_combat_accepted": second != null, "shared_hero": second != null and first.hero == second.hero}
	var saves := SaveService.new()
	var dto: Dictionary = saves.capture(GameSession.new())
	dto["profile"]["route_state"] = {"route_id": "unknown_route", "next_index": 99, "completed": false}
	guards["invalid_route_save_accepted"] = saves.validate(dto)
	var restored := GameSession.new()
	var path: String = "user://_audit_probe_invalid_route.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(dto))
	file.close()
	guards["invalid_route_load_accepted"] = saves.load_into(restored, path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	guards["invalid_route_next"] = restored.next_route_node()
	guards["invalid_route_completed"] = restored.route_completed()
	guards["invalid_route_state"] = restored.route_state.duplicate(true)
	report["guards"] = guards

func _observe_presentation() -> void:
	root.size = Vector2i(180, 320)
	var host := Control.new()
	host.size = Vector2(180, 320)
	host.theme = AppTheme.build()
	root.add_child(host)
	current_scene = host
	var session := GameSession.new()
	session.select_encounter("moss_slime")
	var screen: Control = load("res://scenes/combat.tscn").instantiate()
	screen.configure(session)
	host.add_child(screen)
	for frame: int in range(4): await process_frame
	screen.set_physics_process(false)
	if screen.arena_presenter._intro_tween != null and screen.arena_presenter._intro_tween.is_valid(): screen.arena_presenter._intro_tween.kill()
	screen._finish_intro()
	var presentation: Dictionary = report["presentation"]
	presentation["hero_begin_connections"] = screen.resolver.get_signal_connection_list("hero_attack_begun").size()
	screen.resolver.advance_ticks(1)
	# F-01: начало удара показывает замах с первого тика замаха.
	presentation["hero_clip_at_strike_begin"] = "attack" if screen.hero_sprite.sprite_frames == screen.arena_presenter._hero_frames["attack"]["frames"] else "other"
	screen.resolver.advance_ticks(47)
	presentation["first_enemy_contact_tick"] = screen.resolver.tick_count
	presentation["enemy_clip_at_first_contact"] = "attack" if screen.enemy_sprite.sprite_frames == screen.arena_presenter._enemy_frames["attack"]["frames"] else "other"
	presentation["enemy_frame_at_first_contact"] = screen.enemy_sprite.frame
	var before_frame: int = screen.enemy_sprite.frame
	var before_progress: float = screen.enemy_sprite.frame_progress
	var before_tick: int = screen.resolver.tick_count
	screen._set_pause(true)
	await create_timer(0.35).timeout
	presentation["pause_tick_unchanged"] = screen.resolver.tick_count == before_tick
	presentation["pause_animation_unchanged"] = before_frame == screen.enemy_sprite.frame and is_equal_approx(before_progress, screen.enemy_sprite.frame_progress)
	screen._set_pause(false)
	var navigations: Array = []
	screen.navigate_requested.connect(func(destination: String) -> void: navigations.append(destination))
	# «Старый» палец: нажатие началось до terminal event.
	screen._on_press_began()
	screen.resolver.advance_ticks(6000)
	# Новая семантика: результат висит без таймера, награда только по новому
	# намеренному press→release.
	presentation["result_visible_at_victory"] = screen.result_panel.visible
	presentation["pending_exists_at_victory"] = not session.pending_battle_result.is_empty()
	presentation["inventory_empty_at_victory"] = session.inventory.items.is_empty()
	screen._on_press_ended()
	# Ввод, начавшийся до terminal event, не собирает награду.
	presentation["navigations_from_stale_press"] = navigations.duplicate()
	presentation["pending_after_stale_press"] = not session.pending_battle_result.is_empty()
	await create_timer(1.2).timeout
	presentation["navigations_after_1_2s"] = navigations.duplicate()
	presentation["result_still_visible_without_claim"] = screen.result_panel.visible and screen.result_panel.modulate.a > 0.9
	presentation["pending_after_1_2s"] = not session.pending_battle_result.is_empty()
	# Один новый press→release собирает ровно один раз.
	screen._on_press_began()
	screen._on_press_ended()
	presentation["navigations_after_claim_press"] = navigations.duplicate()
	presentation["pending_after_claim"] = not session.pending_battle_result.is_empty()
	presentation["inventory_after_claim"] = session.inventory.items.size()
	screen.free()
	host.free()
