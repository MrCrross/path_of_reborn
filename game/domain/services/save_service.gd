class_name SaveService
extends RefCounted

const CURRENT_VERSION: int = 1
const DEFAULT_PATH: String = "user://profile.json"

var last_error: String = ""
var loaded_from_backup: bool = false

func capture(session: GameSession) -> Dictionary:
	return {
		"schema_version": CURRENT_VERSION,
		"profile": session.capture_profile_dto(),
		"meta": {
			"echoes": session.echoes,
			"claimed_echo_enemy_ids": session.claimed_echo_enemy_ids.duplicate(true),
			"seen_cue_ids": session.seen_cue_ids.duplicate(true),
			"memory_flags": session.memory_flags.duplicate(true),
			"adaptation_nodes": session.adaptation_nodes.duplicate(true),
			"techniques": session.techniques.duplicate(true),
			"enemy_journal": session.enemy_journal.duplicate(true),
			"traces": session.traces,
		},
		"checkpoints": session.checkpoints.capture_dto(),
		"location_id": session.location_id,
		"current_enemy_id": session.current_enemy_id,
		"pending_reward": session.pending_reward.duplicate(true),
		"loot": {
			"seed": session.loot_seed,
			"state": str(session.loot_rng.state),
		},
		"awaiting_return": session.awaiting_return,
	}

func save(session: GameSession, path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	if not path.begins_with("user://"):
		return _fail("Путь сохранения должен находиться в user://")
	if session.in_combat or session.checkpoints.channel_active:
		return _fail("Сохранение возможно только вне боя и фиксации")
	var dto: Dictionary = capture(session)
	if not validate(dto):
		return _fail("Состояние не прошло проверку сохранения")
	var base_dir: String = path.get_base_dir()
	var make_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	if make_error != OK:
		return _fail("Не удалось создать каталог профиля: %s" % error_string(make_error))
	var temp_path: String = path + ".tmp"
	var backup_path: String = path + ".bak"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("Не удалось открыть временный файл: %s" % error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(dto, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_file(temp_path)
		return _fail("Не удалось записать профиль: %s" % error_string(write_error))
	if FileAccess.file_exists(path) and _read_dto(path)["ok"]:
		var copy_error: Error = DirAccess.copy_absolute(
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(backup_path)
		)
		if copy_error != OK:
			_remove_file(temp_path)
			return _fail("Не удалось обновить резервную копию: %s" % error_string(copy_error))
	var rename_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(path)
	)
	if rename_error != OK:
		_remove_file(temp_path)
		return _fail("Не удалось заменить профиль: %s" % error_string(rename_error))
	return true

func load_into(session: GameSession, path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	loaded_from_backup = false
	var result: Dictionary = _read_dto(path)
	if not result["ok"]:
		result = _read_dto(path + ".bak")
		loaded_from_backup = result["ok"]
	if not result["ok"]:
		if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
			last_error = ""
		else:
			last_error = "Профиль повреждён или имеет неподдерживаемую версию"
		return false
	session.apply_state_dto(result["data"])
	return true

func has_profile(path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	if _read_dto(path)["ok"] or _read_dto(path + ".bak")["ok"]:
		return true
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
		last_error = "Профиль повреждён или имеет неподдерживаемую версию"
	return false

func migrate(source: Dictionary) -> Dictionary:
	var dto: Dictionary = source.duplicate(true)
	if not _is_intlike(dto.get("schema_version")):
		return {}
	var version: int = int(dto["schema_version"])
	if version > CURRENT_VERSION or version < 0:
		return {}
	while version < CURRENT_VERSION:
		match version:
			0:
				if not dto.has("loot_seed") or not dto.has("loot_state"):
					return {}
				dto["loot"] = {"seed": dto["loot_seed"], "state": dto["loot_state"]}
				dto.erase("loot_seed")
				dto.erase("loot_state")
			_:
				return {}
		version += 1
		dto["schema_version"] = version
	return dto

func validate(dto: Dictionary) -> bool:
	if not _has_keys(dto, ["schema_version", "profile", "meta", "checkpoints", "location_id", "current_enemy_id", "pending_reward", "loot", "awaiting_return"]):
		return false
	if int(dto["schema_version"]) != CURRENT_VERSION or typeof(dto["awaiting_return"]) != TYPE_BOOL:
		return false
	if typeof(dto["location_id"]) != TYPE_STRING or dto["location_id"].is_empty():
		return false
	if typeof(dto["current_enemy_id"]) != TYPE_STRING:
		return false
	if not dto["current_enemy_id"].is_empty() and not GameSession.ACTOR_PATHS.has(dto["current_enemy_id"]):
		return false
	if not _valid_profile(dto["profile"]) or not _valid_meta(dto["meta"]) or not _valid_checkpoints(dto["checkpoints"]):
		return false
	if typeof(dto["loot"]) != TYPE_DICTIONARY or not _has_keys(dto["loot"], ["seed", "state"]):
		return false
	if typeof(dto["loot"]["seed"]) != TYPE_STRING or typeof(dto["loot"]["state"]) != TYPE_STRING or not dto["loot"]["state"].is_valid_int():
		return false
	return _valid_rewards(dto["pending_reward"])

func _read_dto(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}}
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return {"ok": false, "data": {}}
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}}
	var dto: Dictionary = migrate(parser.data)
	if dto.is_empty() or not validate(dto):
		return {"ok": false, "data": {}}
	return {"ok": true, "data": _normalize_numbers(dto)}

func _valid_profile(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["hero", "inventory", "currency", "quest_flags", "npc_flags", "world_flags", "completed_encounter_ids", "play_tick"]):
		return false
	if not _nonnegative(dto["currency"]) or not _nonnegative(dto["play_tick"]):
		return false
	for key: String in ["quest_flags", "npc_flags", "world_flags", "completed_encounter_ids"]:
		if not _valid_flag_map(dto[key]):
			return false
	return _valid_hero(dto["hero"]) and _valid_inventory(dto["inventory"])

func _valid_hero(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["level", "experience", "pending_upgrade_choices", "current_hp", "strength_upgrades", "max_hp_upgrades"]):
		return false
	for key: String in ["level", "experience", "pending_upgrade_choices", "current_hp", "strength_upgrades", "max_hp_upgrades"]:
		if not _nonnegative(dto[key]):
			return false
	return int(dto["level"]) >= 1

func _valid_inventory(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["items", "equipment", "next_serial"]):
		return false
	if typeof(dto["items"]) != TYPE_ARRAY or typeof(dto["equipment"]) != TYPE_DICTIONARY or not _nonnegative(dto["next_serial"]) or int(dto["next_serial"]) < 1:
		return false
	var ids: Dictionary = {}
	for entry: Variant in dto["items"]:
		if typeof(entry) != TYPE_DICTIONARY or not _has_keys(entry, ["instance_id", "definition_id", "quantity", "aspect_id", "secured"]):
			return false
		if typeof(entry["instance_id"]) != TYPE_STRING or entry["instance_id"].is_empty() or ids.has(entry["instance_id"]):
			return false
		if typeof(entry["definition_id"]) != TYPE_STRING or not GameSession.ITEM_PATHS.has(entry["definition_id"]):
			return false
		var definition: ItemDefinition = load(GameSession.ITEM_PATHS[entry["definition_id"]])
		if not _nonnegative(entry["quantity"]) or int(entry["quantity"]) < 1 or int(entry["quantity"]) > definition.stack_limit:
			return false
		if typeof(entry["aspect_id"]) != TYPE_STRING or typeof(entry["secured"]) != TYPE_BOOL:
			return false
		ids[entry["instance_id"]] = entry
	for slot_id: Variant in dto["equipment"]:
		if typeof(slot_id) != TYPE_STRING or typeof(dto["equipment"][slot_id]) != TYPE_STRING:
			return false
		var instance_id: String = dto["equipment"][slot_id]
		if not ids.has(instance_id):
			return false
		var definition: ItemDefinition = load(GameSession.ITEM_PATHS[ids[instance_id]["definition_id"]])
		if definition.slot_id != slot_id:
			return false
	return true

func _valid_meta(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["echoes", "claimed_echo_enemy_ids", "seen_cue_ids", "memory_flags", "adaptation_nodes", "techniques", "enemy_journal", "traces"]):
		return false
	if not _nonnegative(dto["echoes"]) or not _nonnegative(dto["traces"]) or int(dto["traces"]) > 3:
		return false
	for key: String in ["claimed_echo_enemy_ids", "seen_cue_ids", "memory_flags", "adaptation_nodes", "techniques", "enemy_journal"]:
		if not _valid_flag_map(dto[key]):
			return false
	return true

func _valid_checkpoints(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["manual_snapshots", "first_trace_snapshot", "first_trace_available", "sequence"]):
		return false
	if typeof(dto["manual_snapshots"]) != TYPE_ARRAY or dto["manual_snapshots"].size() > CheckpointService.MANUAL_LIMIT:
		return false
	if typeof(dto["first_trace_available"]) != TYPE_BOOL or not _nonnegative(dto["sequence"]):
		return false
	if not _valid_snapshot(dto["first_trace_snapshot"]):
		return false
	var ids: Dictionary = {}
	for snapshot: Variant in dto["manual_snapshots"]:
		if not _valid_snapshot(snapshot) or ids.has(snapshot["checkpoint_id"]):
			return false
		ids[snapshot["checkpoint_id"]] = true
	return true

func _valid_snapshot(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["checkpoint_id", "sequence", "location_id", "profile"]):
		return false
	return (
		typeof(dto["checkpoint_id"]) == TYPE_STRING
		and not dto["checkpoint_id"].is_empty()
		and _nonnegative(dto["sequence"])
		and typeof(dto["location_id"]) == TYPE_STRING
		and not dto["location_id"].is_empty()
		and _valid_profile(dto["profile"])
	)

func _valid_rewards(rewards: Variant) -> bool:
	if typeof(rewards) != TYPE_ARRAY:
		return false
	for reward: Variant in rewards:
		if typeof(reward) != TYPE_DICTIONARY or not _has_keys(reward, ["item_id", "quantity", "aspect_id"]):
			return false
		if typeof(reward["item_id"]) != TYPE_STRING or not GameSession.ITEM_PATHS.has(reward["item_id"]):
			return false
		if not _nonnegative(reward["quantity"]) or int(reward["quantity"]) < 1 or typeof(reward["aspect_id"]) != TYPE_STRING:
			return false
	return true

func _valid_flag_map(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or typeof(value[key]) not in [TYPE_BOOL, TYPE_STRING, TYPE_INT, TYPE_FLOAT]:
			return false
	return true

func _has_keys(dto: Variant, keys: Array) -> bool:
	if typeof(dto) != TYPE_DICTIONARY:
		return false
	for key: String in keys:
		if not dto.has(key):
			return false
	return true

func _is_intlike(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value))

func _nonnegative(value: Variant) -> bool:
	return _is_intlike(value) and float(value) >= 0.0

func _normalize_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
		return int(value)
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for entry: Variant in value:
			result.append(_normalize_numbers(entry))
		return result
	if typeof(value) == TYPE_DICTIONARY:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _normalize_numbers(value[key])
		return result
	return value

func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _fail(message: String) -> bool:
	last_error = message
	return false
