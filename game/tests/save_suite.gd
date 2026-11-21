extends RefCounted

const DomainSuite = preload("res://tests/domain_suite.gd")
const TestContext = DomainSuite.TestContext
const TEST_ROOT: String = "user://path_of_reborn_tests/save_suite"

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_run_case("save_round_trip_preserves_full_state", _test_round_trip))
	results.append(_run_case("save_load_save_is_semantically_stable", _test_stable_round_trip))
	results.append(_run_case("corrupt_primary_restores_previous_backup", _test_backup))
	results.append(_run_case("missing_malformed_and_incomplete_saves_do_not_apply", _test_rejection))
	results.append(_run_case("newer_schema_is_rejected", _test_newer_version))
	results.append(_run_case("version_zero_migration_is_pure_and_loadable", _test_migration))
	results.append(_run_case("legacy_v1_pending_reward_is_delivered_exactly_once", _test_v1_pending_reward_delivery))
	results.append(_run_case("write_failure_preserves_previous_primary", _test_write_failure))
	results.append(_run_case("save_respects_safe_boundaries_and_checkpoint_state", _test_safe_boundaries))
	results.append(_run_case("invalid_route_state_is_rejected", _test_invalid_route))
	results.append(_run_case("real_v0_v1_v2_nested_snapshots_migrate_without_errors", _test_legacy_nested_snapshots))
	results.append(_run_case("v3_pending_migration_has_one_explicit_source_policy", _test_v3_pending_source_policy))
	results.append(_run_case("pending_and_return_contradictions_are_rejected", _test_pending_contradictions))
	results.append(_run_case("preferences_restart_backup_and_profile_independence", _test_preferences))
	results.append(_run_case("pending_choices_and_historical_equipment_survive_continue", _test_pending_continue))
	results.append(_run_case("crystal_sale_round_trip_backup_and_rollback", _test_sale_persistence))
	_cleanup_root()
	return results

func _run_case(case_name: String, test: Callable) -> Dictionary:
	var context := TestContext.new()
	test.call(context)
	return {"name": case_name, "checks": context.checks}

func _test_round_trip(context: TestContext) -> void:
	var path: String = _path("round_trip")
	var service := SaveService.new()
	var session := GameSession.new()
	session.hero.gain_xp(4)
	session.choose_upgrade("max_hp")
	var charms: Array[ItemInstance] = session.inventory.add(session.get_item_definition("moss_charm"), 1)
	session.inventory.equip(charms[0].instance_id)
	var echoes: Array[ItemInstance] = session.inventory.add(session.get_item_definition("echo_crystal"), 2, "goblin")
	echoes[0].secured = true
	session.currency = 42
	session.quest_flags["quest"] = "started"
	session.npc_flags["npc"] = true
	session.world_flags["tree"] = "fallen"
	session._beaten_encounter_ids["moss_slime"] = true
	session.seen_cue_ids["DIA_TEST"] = true
	session.memory_flags["memory"] = true
	session.adaptation_nodes["node"] = true
	session.techniques["technique"] = true
	session.enemy_journal["moss_slime"] = true
	session.echoes = 3
	session.claimed_echo_enemy_ids["moss_slime"] = true
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.checkpoints.apply_completion()
	session.currency = 77
	session.traces = 1
	session.hero.set_void_traces(1)
	session.location_id = "forest_edge"
	session.pending_reward = [{"item_id": "slime_residue", "quantity": 2, "aspect_id": ""}]
	context.check(service.save(session, path), "Full state saves successfully: %s" % service.last_error)
	var restored := GameSession.new()
	context.check(service.load_into(restored, path), "Full state loads successfully: %s" % service.last_error)
	context.check(restored.hero.level == 2 and restored.hero.pending_upgrade_choices == 0 and restored.hero.max_hp == 18, "Hero level, upgrade and trace-adjusted HP survive")
	context.check(restored.inventory.items.size() == 4 and restored.inventory.is_equipped(charms[0].instance_id), "Item instances, delivery and equipment survive")
	context.check(restored.inventory.get_item(echoes[0].instance_id).secured and restored.inventory.get_item(echoes[0].instance_id).aspect_id == "goblin", "Crystal security and aspect survive")
	context.check(restored.currency == 77 and restored.quest_flags["quest"] == "started" and restored.world_flags["tree"] == "fallen", "Currency and narrative/world flags survive")
	context.check(restored.checkpoints.manual_snapshots.size() == 1 and restored.checkpoints.manual_snapshots[0]["profile"]["currency"] == 42, "Checkpoint snapshot remains distinct from current state")
	context.check(restored.echoes == 3 and restored.memory_flags.has("memory") and restored.adaptation_nodes.has("node") and restored.techniques.has("technique") and restored.enemy_journal.has("moss_slime"), "Meta progression survives")
	context.check(restored.traces == 1, "Traces survive")
	context.check(restored.pending_reward.is_empty(), "Legacy pending reward is consumed by the one-time delivery")
	context.check(restored.inventory.items.size() == 4, "Delivered residue joins the restored inventory")
	var delivered: ItemInstance = null
	for item: ItemInstance in restored.inventory.items:
		if item.definition_id == "slime_residue":
			delivered = item
	context.check(delivered != null and delivered.quantity == 2, "Delivered residue keeps its quantity")
	context.check(restored.loot_seed == session.loot_seed and str(restored.loot_rng.state) == str(session.loot_rng.state), "Loot seed and state survive as exact strings")
	_cleanup(path)

func _test_stable_round_trip(context: TestContext) -> void:
	var path: String = _path("stable")
	var service := SaveService.new()
	var session := GameSession.new()
	session.currency = 19
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.checkpoints.apply_completion()
	service.save(session, path)
	var restored := GameSession.new()
	service.load_into(restored, path)
	var first_save: String = FileAccess.get_file_as_string(path)
	context.check(service.save(restored, path), "Second save succeeds")
	context.check(FileAccess.get_file_as_string(path) == first_save, "Save-load-save produces identical readable JSON")
	_cleanup(path)

func _test_backup(context: TestContext) -> void:
	var path: String = _path("backup")
	var service := SaveService.new()
	var session := GameSession.new()
	session.currency = 10
	service.save(session, path)
	session.currency = 20
	service.save(session, path)
	_write_text(path, "{broken")
	var restored := GameSession.new()
	context.check(service.load_into(restored, path), "Backup is used when primary is malformed")
	context.check(service.loaded_from_backup and restored.currency == 10, "Previous valid state, not the latest corrupt write, is restored")
	_cleanup(path)

func _test_rejection(context: TestContext) -> void:
	var service := SaveService.new()
	var session := GameSession.new()
	session.currency = 55
	var missing: String = _path("missing")
	context.check(not service.load_into(session, missing) and service.last_error.is_empty(), "Missing profile is an empty state, not a crash or error")
	context.check(session.currency == 55, "Missing profile does not mutate the session")
	var malformed: String = _path("malformed")
	_write_text(malformed, "not json")
	context.check(not service.load_into(session, malformed) and session.currency == 55, "Malformed JSON is rejected without partial apply")
	var incomplete: String = _path("incomplete")
	_write_text(incomplete, JSON.stringify({"schema_version": 1, "profile": {}}))
	context.check(not service.load_into(session, incomplete) and session.currency == 55, "Incomplete DTO is rejected without partial apply")
	_cleanup(malformed)
	_cleanup(incomplete)

func _test_newer_version(context: TestContext) -> void:
	var path: String = _path("newer")
	var service := SaveService.new()
	var dto: Dictionary = service.capture(GameSession.new())
	dto["schema_version"] = SaveService.CURRENT_VERSION + 1
	_write_text(path, JSON.stringify(dto))
	var session := GameSession.new()
	context.check(not service.load_into(session, path), "Newer schema is refused")
	context.check(not service.last_error.is_empty(), "Refusal has a user-facing error")
	_cleanup(path)

func _test_migration(context: TestContext) -> void:
	var path: String = _path("migration")
	var service := SaveService.new()
	var old: Dictionary = service.capture(GameSession.new())
	var loot: Dictionary = old["loot"]
	old.erase("loot")
	old["loot_seed"] = loot["seed"]
	old["loot_state"] = loot["state"]
	old["schema_version"] = 0
	var migrated: Dictionary = service.migrate(old)
	context.check(old["schema_version"] == 0 and not old.has("loot"), "Migration does not mutate its source")
	context.check(migrated.get("schema_version") == SaveService.CURRENT_VERSION and service.validate(migrated), "Sequential migration produces a valid current DTO")
	_write_text(path, JSON.stringify(old))
	var restored := GameSession.new()
	context.check(service.load_into(restored, path), "Old fixture can be loaded after migration")
	_cleanup(path)

func _test_v1_pending_reward_delivery(context: TestContext) -> void:
	var path: String = _path("v1_pending")
	var service := SaveService.new()
	# Регрессия UX-07: сейв v1 с незабранной добычей. v1 начислял XP сразу,
	# поэтому доставка приносит только предметы и ровно один раз.
	var dto: Dictionary = service.capture(GameSession.new())
	dto["schema_version"] = 1
	dto["profile"].erase("route_state")
	dto["profile"].erase("run_sequence")
	dto["pending_reward"] = [{"item_id": "slime_residue", "quantity": 2, "aspect_id": ""}]
	dto["profile"]["completed_encounter_ids"] = {"moss_slime": true}
	_write_text(path, JSON.stringify(dto))
	var restored := GameSession.new()
	context.check(service.load_into(restored, path), "Legacy v1 profile loads through migration")
	context.check(restored.pending_reward.is_empty(), "Pending reward is delivered on load")
	var residue: int = 0
	for item: ItemInstance in restored.inventory.items:
		if item.definition_id == "slime_residue":
			residue += item.quantity
	context.check(residue == 2, "Delivered quantity matches the legacy reward")
	context.check(restored.hero.level == 1 and restored.hero.experience == 0, "Legacy XP is not granted a second time")
	context.check(restored.route_state.get("next_index", 0) == 1, "Route state is derived honestly from beaten encounters")
	context.check(service.save(restored, path), "Delivered profile saves at the current schema")
	var reloaded := GameSession.new()
	context.check(service.load_into(reloaded, path), "Reload after delivery succeeds")
	residue = 0
	for item: ItemInstance in reloaded.inventory.items:
		if item.definition_id == "slime_residue":
			residue += item.quantity
	context.check(residue == 2, "Reload does not duplicate or lose the delivered reward")
	_cleanup(path)

func _test_write_failure(context: TestContext) -> void:
	var path: String = _path("write_failure")
	var service := SaveService.new()
	var session := GameSession.new()
	session.currency = 77
	service.save(session, path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	session.currency = 99
	context.check(not service.save(session, path) and not service.last_error.is_empty(), "A temporary-file failure is reported")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	var restored := GameSession.new()
	context.check(service.load_into(restored, path) and restored.currency == 77, "Failed write leaves previous primary intact")
	_cleanup(path)

func _test_safe_boundaries(context: TestContext) -> void:
	var path: String = _path("boundaries")
	var service := SaveService.new()
	var session := GameSession.new()
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.checkpoints.apply_completion()
	var before: String = JSON.stringify(session.checkpoints.capture_dto())
	context.check(service.save(session, path), "Safe state can be saved")
	context.check(JSON.stringify(session.checkpoints.capture_dto()) == before, "Saving neither creates nor consumes checkpoints")
	session.in_combat = true
	context.check(not service.save(session, path), "Active combat blocks autosave")
	session.in_combat = false
	session.checkpoints.begin()
	context.check(not service.save(session, path), "Active channel blocks autosave")
	session.checkpoints.cancel()
	_cleanup(path)

func _test_invalid_route(context: TestContext) -> void:
	var service := SaveService.new()
	var path: String = _path("invalid_route")
	# Регрессия аудита: сломанный маршрут не должен превращаться в успешную
	# загрузку с «маршрутом по умолчанию», как это было раньше.
	var dto: Dictionary = service.capture(GameSession.new())
	dto["profile"]["route_state"] = {"route_id": "unknown_route", "next_index": 99, "completed": false}
	context.check(not service.validate(dto), "An unknown route with an out-of-range index is rejected")
	var restored := GameSession.new()
	_write_text(path, JSON.stringify(dto))
	context.check(not service.load_into(restored, path), "A save with a broken route does not load")
	context.check(restored.route_state.get("route_id", "") == "forest_edge_slice" and int(restored.route_state.get("next_index", -1)) == 0, "A rejected load leaves the initial route state untouched")
	# Пустой route_state — легаси-случай, который выводится из журнала при apply.
	var legacy: Dictionary = service.capture(GameSession.new())
	legacy["profile"]["route_state"] = {}
	context.check(service.validate(legacy), "An empty legacy route state stays acceptable")
	# Те же правила внутри Checkpoint-снимков.
	var snapshot: Dictionary = service.capture(GameSession.new())
	snapshot["profile"]["route_state"] = {"route_id": "unknown_route", "next_index": 99, "completed": false}
	snapshot["checkpoints"]["first_trace_snapshot"] = {
		"checkpoint_id": "trace_000001",
		"sequence": 1,
		"location_id": "forest_edge",
		"profile": snapshot["profile"],
	}
	context.check(not service.validate(snapshot), "A checkpoint snapshot with a broken route is rejected too")
	_cleanup(path)

func _test_legacy_nested_snapshots(context: TestContext) -> void:
	for version: int in [0, 1, 2]:
		var service := SaveService.new()
		var dto: Dictionary = _legacy_dto(version)
		var path: String = _path("legacy_v%d_nested" % version)
		_write_text(path, JSON.stringify(dto))
		var restored := GameSession.new()
		context.check(service.load_into(restored, path), "Real v%d shape with First Trace and manual snapshot loads" % version)
		context.check(not restored.has_pending_battle_result(), "Already granted v%d loot does not become a new pending result" % version)
		context.check(restored.checkpoints.first_trace_available and restored.checkpoints.manual_snapshots.size() == 1, "Both rollback snapshots survive v%d migration" % version)
		context.check(service.validate(service.migrate(dto)), "Migrated v%d nested profiles validate" % version)
		_cleanup(path)
	var service := SaveService.new()
	var v2: Dictionary = _legacy_dto(2)
	v2["profile"]["completed_encounter_ids"] = {"moss_slime": true, "goblin_scout": true}
	v2["profile"]["route_state"] = {}
	context.check(service.validate(service.migrate(v2)), "Legacy empty route remains valid")
	var restored := GameSession.new()
	_write_text(_path("legacy_route"), JSON.stringify(v2))
	context.check(service.load_into(restored, _path("legacy_route")) and restored.route_completed(), "Consecutive victories derive the completed legacy route")
	_cleanup(_path("legacy_route"))

func _test_v3_pending_source_policy(context: TestContext) -> void:
	var service := SaveService.new()
	var session := GameSession.new()
	var resolver: CombatResolver = session.start_combat("moss_slime")
	resolver.advance_ticks(600)
	var dto: Dictionary = service.capture(session)
	dto["schema_version"] = 3
	dto["profile"]["pending_battle_result"] = dto["pending_battle_result"].duplicate(true)
	dto["profile"]["trial_echo_claimed"] = false
	dto["meta"].erase("trial_echo_claimed")
	var profile_pending: Dictionary = dto["profile"]["pending_battle_result"].duplicate(true)
	var root_pending: Dictionary = dto["pending_battle_result"].duplicate(true)
	profile_pending["result_id"] = "profile_result"
	profile_pending["run_id"] = "profile_run"
	root_pending["result_id"] = "root_result"
	root_pending["run_id"] = "root_run"
	dto["profile"]["pending_battle_result"] = profile_pending
	dto["pending_battle_result"] = root_pending
	var migrated: Dictionary = service.migrate(dto)
	context.check(service.validate(migrated), "Conflicting valid v3 copies have a controlled migration result")
	context.check(migrated["pending_battle_result"].get("result_id", "") == "profile_result", "The copy applied by the old runtime wins")
	context.check(not migrated["profile"].has("pending_battle_result"), "Current profile no longer duplicates pending")
	dto["profile"]["pending_battle_result"] = {}
	migrated = service.migrate(dto)
	context.check(migrated["pending_battle_result"].get("result_id", "") == "root_result", "A valid root is retained when the old profile copy is empty")
	dto["profile"]["pending_battle_result"] = {"broken": true}
	context.check(not service.validate(service.migrate(dto)), "An invalid old-runtime copy rejects the DTO instead of silently substituting root")

func _test_pending_contradictions(context: TestContext) -> void:
	var service := SaveService.new()
	var session := GameSession.new()
	var resolver: CombatResolver = session.start_combat("moss_slime")
	resolver.advance_ticks(600)
	var dto: Dictionary = service.capture(session)
	dto["awaiting_return"] = true
	context.check(not service.validate(dto), "awaiting_return and pending cannot coexist")
	dto["awaiting_return"] = false
	dto["pending_battle_result"]["enemy_id"] = "unknown_enemy"
	context.check(not service.validate(dto), "Unknown pending encounter is rejected")
	dto = service.capture(session)
	dto["pending_battle_result"]["items"] = [{"item_id": "unknown_item", "quantity": 1, "aspect_id": "", "slot_id": ""}]
	context.check(not service.validate(dto), "Unknown pending loot entry is rejected")
	dto = service.capture(session)
	dto["pending_battle_result"].erase("loot_state")
	context.check(not service.validate(dto), "Incomplete pending DTO is rejected")
	dto = service.capture(session)
	dto["checkpoints"]["first_trace_snapshot"]["profile"]["pending_battle_result"] = session.pending_battle_result.duplicate(true)
	context.check(not service.validate(dto), "A rollback snapshot cannot own a non-empty pending result")

func _legacy_dto(version: int) -> Dictionary:
	var service := SaveService.new()
	var session := GameSession.new()
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.checkpoints.apply_completion()
	var dto: Dictionary = service.capture(session)
	dto["schema_version"] = version
	var profiles: Array[Dictionary] = [dto["profile"], dto["checkpoints"]["first_trace_snapshot"]["profile"]]
	for snapshot: Dictionary in dto["checkpoints"]["manual_snapshots"]:
		profiles.append(snapshot["profile"])
	for profile: Dictionary in profiles:
		for key: String in ["pending_battle_result", "last_claimed_result_id", "trial_echo_claimed"]:
			profile.erase(key)
		if version < 2:
			profile.erase("route_state")
			profile.erase("run_sequence")
	dto.erase("pending_battle_result")
	dto.erase("combat_format")
	if version == 0:
		dto["loot_seed"] = dto["loot"]["seed"]
		dto["loot_state"] = dto["loot"]["state"]
		dto.erase("loot")
	return dto

func _path(case_name: String) -> String:
	return "%s/%s.json" % [TEST_ROOT, case_name]

func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _cleanup(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var target: String = path + suffix
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target))

func _cleanup_root() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ROOT))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://path_of_reborn_tests"))


func _test_preferences(context: TestContext) -> void:
	var profile_path: String = _path("preferences")
	var path: String = PreferencesService.path_for_profile(profile_path)
	var preferences := PreferencesService.new()
	preferences.sound_enabled = false
	preferences.combat_format = GameSession.COMBAT_FORMAT_ACTIVE
	preferences.auto_speed = 2
	context.check(preferences.save_preferences(path), "Preferences save independently: %s" % preferences.last_error)
	var restored := PreferencesService.new()
	context.check(restored.load_preferences(path) and not restored.sound_enabled and restored.combat_format == GameSession.COMBAT_FORMAT_ACTIVE and restored.auto_speed == 2, "Restart restores sound, manual combat and auto speed")
	var session := GameSession.new()
	session.combat_format = restored.combat_format
	session.auto_speed = restored.auto_speed
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.checkpoints.apply_completion()
	context.check(not session.capture_profile_dto().has("combat_format") and not session.checkpoints.manual_snapshots[0]["profile"].has("combat_format"), "Neither the profile nor Checkpoint owns combat preferences")
	session.new_game()
	context.check(session.combat_format == GameSession.COMBAT_FORMAT_ACTIVE and session.auto_speed == 2, "New game keeps the loaded control preferences")
	preferences.sound_enabled = true
	preferences.combat_format = GameSession.COMBAT_FORMAT_AUTO
	preferences.auto_speed = 1
	context.check(preferences.save_preferences(path), "A second preferences commit creates a backup")
	_write_text(path, "{broken")
	var backup := PreferencesService.new()
	context.check(backup.load_preferences(path) and not backup.sound_enabled and backup.combat_format == GameSession.COMBAT_FORMAT_ACTIVE and backup.auto_speed == 2, "Corrupt primary preferences fall back to the previous .bak")
	_cleanup(profile_path)
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _test_pending_continue(context: TestContext) -> void:
	var path: String = _path("pending_continue")
	var service := SaveService.new()
	var session := GameSession.new()
	var resolver: CombatResolver = session.start_combat("moss_slime")
	resolver.advance_ticks(600)
	session.pending_battle_result["items"].append({"entry_id": "story_like_sword", "item_id": "training_sword", "quantity": 1, "aspect_id": "", "slot_id": "weapon", "level": 1, "sale_price_copper": 0, "sellable": false})
	var crystal_id: String = String(session.pending_battle_result["items"][0]["entry_id"])
	context.check(session.choose_battle_reward(crystal_id, "store") and service.save(session, path), "A partial durable choice saves with stable result and entry IDs")
	var restored := GameSession.new()
	context.check(service.load_into(restored, path) and restored.pending_battle_result.get("result_id") == session.pending_battle_result["result_id"] and restored.pending_battle_result["choices"].has(crystal_id), "Continue restores the same pending cards and confirmed choice")
	context.check(restored.inventory.items.size() == 1 and restored.inventory.equipment.get("weapon") != "story_like_sword", "Pending choices do not mutate the confirmed inventory before commit")
	context.check(restored.choose_battle_reward("story_like_sword", "equip") and restored.claim_battle_result(String(restored.pending_battle_result["result_id"])), "The remaining equipment choice completes one claim after Continue")
	context.check(EquipmentModel.slot(restored, "weapon")["definition"].id == "training_sword" and restored.inventory.filter("weapon").size() == 2, "Equip-on-claim keeps the replaced branch in the backpack")
	context.check(service.save(restored, path), "The completed multi-card claim saves")
	var reloaded := GameSession.new()
	context.check(service.load_into(reloaded, path) and not reloaded.has_pending_battle_result() and reloaded.inventory.filter("weapon").size() == 2, "A second restart neither reopens nor duplicates the result")

	var historical := GameSession.new()
	var old_resolver: CombatResolver = historical.start_combat("moss_slime")
	old_resolver.advance_ticks(600)
	var dto: Dictionary = service.capture(historical)
	dto["schema_version"] = 4
	dto["pending_battle_result"]["items"].append({"item_id": "training_sword", "quantity": 1, "aspect_id": "", "slot_id": "weapon"})
	var historical_path: String = _path("v4_pending_equipment")
	_write_text(historical_path, JSON.stringify(dto))
	var legacy := GameSession.new()
	context.check(service.load_into(legacy, historical_path) and legacy.pending_battle_result.get("items", []).size() == 2 and legacy.pending_battle_result.get("choices", {}).is_empty(), "Historical pending equipment migrates to an explicit repeatable choice")
	context.check(legacy.pending_battle_result["items"][1].get("entry_id", "") != legacy.pending_battle_result["items"][0].get("entry_id", "") and legacy.inventory.items.size() == 1, "Migration assigns distinct stable entry IDs without granting items")
	context.check(DomainSuite.claim_pending(legacy) and legacy.inventory.filter("weapon").size() == 2, "The historical equipment reward can still be collected")
	_cleanup(path)
	_cleanup(historical_path)


func _test_sale_persistence(context: TestContext) -> void:
	var path: String = _path("crystal_sale")
	var service := SaveService.new()
	var session := GameSession.new()
	var crystals: Array[ItemInstance] = session.inventory.add(session.get_item_definition("echo_crystal"), 3, "moss")
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.checkpoints.apply_completion()
	context.check(session.sell_item(crystals[0].instance_id, 2) and session.currency == 4000 and crystals[0].quantity == 1, "Sale removes crystals and credits their copper price in one domain transaction")
	context.check(service.save(session, path), "The sale saves")
	var restored := GameSession.new()
	context.check(service.load_into(restored, path) and restored.currency == 4000 and restored.inventory.get_item(crystals[0].instance_id).quantity == 1, "Save/load preserves both sides of the sale")
	context.check(session.sell_item(crystals[0].instance_id, 1) and session.currency == 6000 and session.inventory.get_item(crystals[0].instance_id) == null, "Selling the last crystal removes its stack")
	context.check(service.save(session, path), "The second sale creates a previous-state backup")
	_write_text(path, "{broken")
	var backup := GameSession.new()
	context.check(service.load_into(backup, path) and backup.currency == 4000 and backup.inventory.get_item(crystals[0].instance_id).quantity == 1, "A corrupt primary restores matching wallet and stack from .bak")
	session.start_combat("moss_slime")
	session.abandon_combat()
	context.check(session.checkpoints.restore() and session.currency == 0 and session.inventory.get_item(crystals[0].instance_id).quantity == 3, "Checkpoint rollback restores the wallet and sold crystals together")
	var branch: ItemInstance = EquipmentModel.slot(session, "weapon")["item"]
	context.check(not session.sell_item(branch.instance_id) and session.currency == 0, "Equipment without an explicit sellable rule cannot be exchanged")
	_cleanup(path)
