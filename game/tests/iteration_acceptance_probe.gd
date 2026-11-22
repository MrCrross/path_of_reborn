extends SceneTree

const DomainSuite = preload("res://tests/domain_suite.gd")

## Диагностика аудита. Exit 0 означает, что наблюдения собраны.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var report := {
		"stale_run": _stale_run(),
		"reentrant_claim": _reentrant_claim(),
		"trial_echo_after_rollback": _trial_echo_after_rollback(),
		"route_balance": _route_balance(),
	}
	report["failed_claim_save"] = await _failed_claim_save()
	report["goblin_contacts"] = await _goblin_contacts()
	report["legacy_snapshot"] = _legacy_snapshot()
	print("AUDIT_PROBE_JSON %s" % JSON.stringify(report))
	quit()

func _stale_run() -> Dictionary:
	var session := GameSession.new()
	var old := session.start_combat("moss_slime")
	var replacement := session.retry_combat()
	old.advance_ticks(600)
	return {
		"old_run": old.run_id,
		"new_run": replacement.run_id,
		"new_run_finished": replacement.is_finished,
		"session_in_combat_after_old_finish": session.in_combat,
		"pending_run": session.pending_battle_result.get("run_id", ""),
	}

func _reentrant_claim() -> Dictionary:
	var session := GameSession.new()
	var resolver := session.start_combat("moss_slime")
	resolver.advance_ticks(600)
	var id: String = session.pending_battle_result["result_id"]
	var expected_units: int = 0
	for item: Dictionary in session.pending_battle_result["items"]:
		expected_units += int(item["quantity"])
	var inner := {"accepted": false}
	DomainSuite.prepare_pending_choices(session)
	var observer := func() -> void:
		inner["accepted"] = session.claim_battle_result(id)
	session.inventory.changed.connect(observer, CONNECT_ONE_SHOT)
	var outer := session.claim_battle_result(id)
	var units: int = 0
	for item: ItemInstance in session.inventory.items:
		units += item.quantity
	return {"inner_accepted": inner["accepted"], "outer_accepted": outer, "expected_units": expected_units, "units": units, "level": session.hero.level, "xp": session.hero.experience}

func _failed_claim_save() -> Dictionary:
	var game: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	var suffix := str(Time.get_ticks_usec())
	game.save_path = "user://por_acceptance_probe_%s.json" % suffix
	root.add_child(game)
	current_scene = game
	game.session.world_flags["prologue_completed"] = true
	game.save_service.save(game.session, game.save_path)
	game.session.select_encounter("moss_slime")
	game.router.go_to("combat")
	await process_frame
	var screen: Control = game.router.current_screen
	screen.resolver.advance_ticks(600)
	for step: int in range(90):
		if screen._result_visible:
			break
		await process_frame
	var blocked_tmp := ProjectSettings.globalize_path(game.save_path + ".tmp")
	var blocker := DirAccess.make_dir_absolute(blocked_tmp)
	screen.result_panel.summary_button.pressed.emit()
	ConfirmDialog.dismiss_from(screen)
	for _item: Dictionary in game.session.pending_battle_result["items"]:
		screen.result_panel._choose("store")
	screen.result_panel.claim_button.pressed.emit()
	await process_frame
	var restored := GameSession.new()
	var loaded := SaveService.new().load_into(restored, game.save_path)
	var observation := {
		"blocker_created": blocker == OK,
		"notice": game.notice_text.text,
		"result_visible": screen._result_visible,
		"screen_after_claim": game.router.current_screen.name,
		"memory_items": game.session.inventory.items.size(),
		"memory_pending": game.session.has_pending_battle_result(),
		"disk_loaded": loaded,
		"disk_items": restored.inventory.items.size(),
		"disk_pending": restored.has_pending_battle_result(),
	}
	if blocker == OK:
		DirAccess.remove_absolute(blocked_tmp)
	_remove_files(game.save_path)
	_remove_files(PreferencesService.path_for_profile(game.save_path))
	game.queue_free()
	await process_frame
	return observation

func _goblin_contacts() -> Array[Dictionary]:
	var session := GameSession.new()
	session.route_state["next_index"] = 2
	session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
	session.select_encounter("goblin_scout")
	var screen: Control = load("res://scenes/combat.tscn").instantiate()
	screen.configure(session)
	root.add_child(screen)
	var resolver: CombatResolver = screen.resolver
	var events: Array[Dictionary] = []
	var record := func(target_id: String, _amount: int) -> void:
		var actor: AnimatedSprite2D = screen.hero_sprite if target_id != "hero" else screen.enemy_sprite
		var attack: Dictionary = screen.arena_presenter._hero_frames["attack"] if target_id != "hero" else screen.arena_presenter._enemy_frames["attack"]
		events.append({"tick": resolver.tick_count, "target": target_id, "strike_index": resolver.strike_index, "attacker_in_attack_clip": actor.sprite_frames == attack["frames"], "frame": actor.frame, "frame_progress": snappedf(actor.frame_progress, 0.01)})
	resolver.damage_dealt.connect(record)
	for frame: int in range(150):
		resolver.request_attack()
		await process_frame
	resolver.damage_dealt.disconnect(record)
	screen.queue_free()
	await process_frame
	return events

func _legacy_snapshot() -> Dictionary:
	var service := SaveService.new()
	var dto := service.capture(GameSession.new())
	dto["schema_version"] = 2
	var legacy_profile: Dictionary = dto["checkpoints"]["first_trace_snapshot"]["profile"]
	for profile: Dictionary in [dto["profile"], legacy_profile]:
		profile["currency"] = 0
		profile.erase("wallet")
	for key: String in ["pending_battle_result", "last_claimed_result_id", "trial_echo_claimed"]:
		legacy_profile.erase(key)
		dto["profile"].erase(key)
	dto.erase("pending_battle_result")
	dto.erase("combat_format")
	var migrated := service.migrate(dto)
	return {
		"migrated_version": migrated.get("schema_version", 0),
		"snapshot_has_pending_field": migrated["checkpoints"]["first_trace_snapshot"]["profile"].has("pending_battle_result"),
		"validates": service.validate(migrated),
	}

func _trial_echo_after_rollback() -> Dictionary:
	var session := GameSession.new()
	for enemy: String in ["moss_slime", "moss_slime", "goblin_scout"]:
		_win_and_claim(session, enemy)
		session.choose_upgrade("strength")
	var began := session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	var before := session.echoes
	var first_claim := _win_and_claim(session, "goblin_trial")
	var after := session.echoes
	session.start_combat("moss_slime")
	session.abandon_combat()
	var restored := session.checkpoints.restore()
	var after_restore := session.echoes
	var second_claim := _win_and_claim(session, "goblin_trial")
	return {"checkpoint_began": began, "restored": restored, "first_claim": first_claim, "first_delta": after - before, "echoes_preserved": after_restore == after, "second_claim": second_claim, "second_delta": session.echoes - after_restore}

func _remove_files(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var absolute_path: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)


func _win_and_claim(session: GameSession, enemy: String) -> bool:
	var resolver := session.start_combat(enemy)
	if resolver == null:
		return false
	resolver.advance_ticks(6000)
	return resolver.won and DomainSuite.claim_pending(session)

func _route_balance() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for seed: String in ["path_of_reborn_blockout", "11", "22", "33"]:
		for build: String in ["no_growth", "strength", "max_hp", "equip_drops"]:
			var session := GameSession.new()
			session.set_loot_seed(seed)
			var stages: Array[Dictionary] = []
			for enemy: String in ["moss_slime", "moss_slime", "goblin_scout", "goblin_trial"]:
				var combat := session.start_combat(enemy)
				combat.advance_ticks(6000)
				var stage := {"enemy": enemy, "won": combat.won, "ticks": combat.tick_count, "hp": session.hero.current_hp, "hp_max": session.hero.max_hp, "strength": session.hero.strength}
				stages.append(stage)
				if not combat.won:
					break
				stage["loot"] = session.pending_battle_result.get("items", [])
				stage["echo_delta"] = session.echoes
				DomainSuite.claim_pending(session)
				stage["echo_delta"] = session.echoes - int(stage["echo_delta"])
				if build in ["strength", "max_hp"]:
					while session.hero.pending_upgrade_choices > 0:
						session.choose_upgrade(build)
				if build == "equip_drops":
					for item: ItemInstance in session.inventory.items:
						if item.definition_id in ["training_sword", "moss_charm"]:
							session.equip_item(item.instance_id)
			result.append({"seed": seed, "build": build, "stages": stages})
	return result
