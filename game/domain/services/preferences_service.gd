class_name PreferencesService
extends RefCounted

const AtomicJsonFile = preload("res://domain/services/atomic_json_file.gd")
const CURRENT_VERSION: int = 1
const AUTO_SPEEDS: Array[int] = [1, 2]

var sound_enabled: bool = true
var voice_id: String = ""
var combat_format: String = GameSession.COMBAT_FORMAT_AUTO
var auto_speed: int = 1
var auto_ability: bool = true
var last_error: String = ""

static func path_for_profile(profile_path: String) -> String:
	return profile_path + ".preferences.json"

func load_preferences(path: String, fallback_format: String = GameSession.COMBAT_FORMAT_AUTO) -> bool:
	last_error = ""
	sound_enabled = true
	voice_id = ""
	auto_speed = 1
	auto_ability = true
	combat_format = fallback_format if fallback_format in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE] else GameSession.COMBAT_FORMAT_AUTO
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		return false
	var dto: Dictionary = _read(path)
	if dto.is_empty():
		dto = _read(path + ".bak")
	if dto.is_empty():
		last_error = "Настройки повреждены; использованы значения по умолчанию"
		return false
	_apply(dto)
	return true

func save_preferences(path: String) -> bool:
	last_error = ""
	if not path.begins_with("user://"):
		last_error = "Путь настроек должен находиться в user://"
		return false
	var dto: Dictionary = capture_dto()
	if not _valid(dto):
		last_error = "Настройки не прошли проверку"
		return false
	last_error = AtomicJsonFile.write(path, dto, func(current: String) -> bool: return not _read(current).is_empty())
	return last_error.is_empty()

func capture_dto() -> Dictionary:
	return {
		"schema_version": CURRENT_VERSION,
		"sound_enabled": sound_enabled,
		"voice_id": voice_id,
		"combat_format": combat_format,
		"auto_speed": auto_speed,
		"auto_ability": auto_ability,
	}

func _apply(dto: Dictionary) -> void:
	sound_enabled = bool(dto["sound_enabled"])
	voice_id = String(dto["voice_id"])
	combat_format = String(dto["combat_format"])
	auto_speed = int(dto["auto_speed"])
	auto_ability = bool(dto.get("auto_ability", true))

func _read(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var dto: Dictionary = parser.data
	return dto if _valid(dto) else {}

func _valid(dto: Dictionary) -> bool:
	if typeof(dto.get("schema_version")) not in [TYPE_INT, TYPE_FLOAT] or dto["schema_version"] != CURRENT_VERSION:
		return false
	if typeof(dto.get("sound_enabled")) != TYPE_BOOL or typeof(dto.get("voice_id")) != TYPE_STRING:
		return false
	if typeof(dto.get("combat_format")) != TYPE_STRING or dto["combat_format"] not in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE]:
		return false
	if typeof(dto.get("auto_ability", true)) != TYPE_BOOL:
		return false
	var speed: Variant = dto.get("auto_speed")
	return typeof(speed) in [TYPE_INT, TYPE_FLOAT] and speed == int(speed) and int(speed) in AUTO_SPEEDS
