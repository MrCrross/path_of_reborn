class_name SaveService
extends RefCounted

const ProfileSchema = preload("res://domain/services/profile_schema.gd")
const AtomicJsonFile = preload("res://domain/services/atomic_json_file.gd")
const CURRENT_VERSION: int = ProfileSchema.CURRENT_VERSION
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
			"trial_echo_claimed": session.trial_echo_claimed,
		},
		"checkpoints": session.checkpoints.capture_dto(),
		"location_id": session.location_id,
		"current_enemy_id": session.current_enemy_id,
		"pending_reward": session.pending_reward.duplicate(true),
		"pending_battle_result": session.pending_battle_result.duplicate(true),
		"pending_story_reward": session.pending_story_reward.duplicate(true),
		"combat_format": session.combat_format,
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
	if session.in_combat or session.checkpoints.channel_active or session.is_transaction_active():
		return _fail("Сохранение возможно только вне боя, фиксации и транзакции награды")
	var dto: Dictionary = capture(session)
	if not validate(dto):
		return _fail("Состояние не прошло проверку сохранения")
	return _write_dto(dto, path)

func save_combat_format(format: String, path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	if not path.begins_with("user://"):
		return _fail("Путь сохранения должен находиться в user://")
	if format not in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE]:
		return _fail("Неизвестный формат боя")
	var result: Dictionary = _read_profile(path)
	if not result["ok"]:
		return _fail("Нет сохранённого профиля для настройки боя")
	var dto: Dictionary = result["data"]
	dto["combat_format"] = format
	if not validate(dto):
		return _fail("Профиль не прошёл проверку настройки боя")
	return _write_dto(dto, path)

func _write_dto(dto: Dictionary, path: String) -> bool:
	last_error = AtomicJsonFile.write(path, dto, func(current: String) -> bool: return _read_dto(current)["ok"])
	return last_error.is_empty()

func load_into(session: GameSession, path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	var result: Dictionary = _read_profile(path)
	loaded_from_backup = result["from_backup"]
	if not result["ok"]:
		if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
			last_error = ""
		else:
			last_error = "Профиль повреждён или имеет неподдерживаемую версию"
		return false
	session.apply_state_dto(result["data"])
	return true

func peek_combat_format(path: String = DEFAULT_PATH) -> String:
	var result: Dictionary = _read_profile(path)
	return String(result["data"].get("combat_format", GameSession.COMBAT_FORMAT_AUTO)) if result["ok"] else GameSession.COMBAT_FORMAT_AUTO

func has_profile(path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	if _read_profile(path)["ok"]:
		return true
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
		last_error = "Профиль повреждён или имеет неподдерживаемую версию"
	return false

func migrate(source: Dictionary) -> Dictionary:
	return ProfileSchema.migrate(source)

func validate(dto: Dictionary) -> bool:
	return ProfileSchema.validate(dto)

func _read_profile(path: String) -> Dictionary:
	var result: Dictionary = _read_dto(path)
	result["from_backup"] = false
	if not result["ok"]:
		result = _read_dto(path + ".bak")
		result["from_backup"] = result["ok"]
	return result

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
	return {"ok": true, "data": ProfileSchema.normalize_numbers(dto)}

func _fail(message: String) -> bool:
	last_error = message
	return false
