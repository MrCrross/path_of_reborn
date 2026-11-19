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
	results.append(_run_case("write_failure_preserves_previous_primary", _test_write_failure))
	results.append(_run_case("save_respects_safe_boundaries_and_checkpoint_state", _test_safe_boundaries))
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
	session.completed_encounter_ids["moss_slime"] = true
	session.seen_cue_ids["DIA_TEST"] = true
	session.memory_flags["memory"] = true
	session.adaptation_nodes["node"] = true
	session.techniques["technique"] = true
	session.enemy_journal["moss_slime"] = true
	session.echoes = 3
	session.claimed_echo_enemy_ids["moss_slime"] = true
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.currency = 77
	session.traces = 1
	session.hero.set_void_traces(1)
	session.location_id = "forest_edge"
	session.pending_reward = [{"item_id": "slime_residue", "quantity": 2, "aspect_id": ""}]
	context.check(service.save(session, path), "Full state saves successfully: %s" % service.last_error)
	var restored := GameSession.new()
	context.check(service.load_into(restored, path), "Full state loads successfully: %s" % service.last_error)
	context.check(restored.hero.level == 2 and restored.hero.pending_upgrade_choices == 0 and restored.hero.max_hp == 18, "Hero level, upgrade and trace-adjusted HP survive")
	context.check(restored.inventory.items.size() == 2 and restored.inventory.is_equipped(charms[0].instance_id), "Item instances and equipment survive")
	context.check(restored.inventory.get_item(echoes[0].instance_id).secured and restored.inventory.get_item(echoes[0].instance_id).aspect_id == "goblin", "Crystal security and aspect survive")
	context.check(restored.currency == 77 and restored.quest_flags["quest"] == "started" and restored.world_flags["tree"] == "fallen", "Currency and narrative/world flags survive")
	context.check(restored.checkpoints.manual_snapshots.size() == 1 and restored.checkpoints.manual_snapshots[0]["profile"]["currency"] == 42, "Checkpoint snapshot remains distinct from current state")
	context.check(restored.echoes == 3 and restored.memory_flags.has("memory") and restored.adaptation_nodes.has("node") and restored.techniques.has("technique") and restored.enemy_journal.has("moss_slime"), "Meta progression survives")
	context.check(restored.traces == 1 and restored.pending_reward == session.pending_reward, "Traces and pending reward survive")
	context.check(restored.loot_seed == session.loot_seed and str(restored.loot_rng.state) == str(session.loot_rng.state), "Loot seed and state survive as exact strings")
	_cleanup(path)

func _test_stable_round_trip(context: TestContext) -> void:
	var path: String = _path("stable")
	var service := SaveService.new()
	var session := GameSession.new()
	session.currency = 19
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
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
	context.check(migrated.get("schema_version") == 1 and service.validate(migrated), "Sequential 0-to-1 migration produces a valid DTO")
	_write_text(path, JSON.stringify(old))
	var restored := GameSession.new()
	context.check(service.load_into(restored, path), "Old fixture can be loaded after migration")
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
