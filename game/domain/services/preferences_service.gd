class_name PreferencesService
extends RefCounted

const CURRENT_VERSION: int = 1
const AUTO_SPEEDS: Array[int] = [1, 2]

var sound_enabled: bool = true
var voice_id: String = ""
var combat_format: String = GameSession.COMBAT_FORMAT_AUTO
var auto_speed: int = 1
var last_error: String = ""

static func path_for_profile(profile_path: String) -> String:
	return profile_path + ".preferences.json"

func load_preferences(path: String, fallback_format: String = GameSession.COMBAT_FORMAT_AUTO) -> bool:
	last_error = ""
	sound_enabled = true
	voice_id = ""
	auto_speed = 1
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
	var make_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if make_error != OK:
		last_error = "Не удалось создать каталог настроек: %s" % error_string(make_error)
		return false
	var temp_path: String = path + ".tmp"
	var backup_path: String = path + ".bak"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = "Не удалось открыть временный файл настроек: %s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(dto, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove(temp_path)
		last_error = "Не удалось записать настройки: %s" % error_string(write_error)
		return false
	if FileAccess.file_exists(path) and not _read(path).is_empty():
		var copy_error: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path))
		if copy_error != OK:
			_remove(temp_path)
			last_error = "Не удалось обновить резервную копию настроек: %s" % error_string(copy_error)
			return false
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if rename_error != OK:
		_remove(temp_path)
		last_error = "Не удалось заменить файл настроек: %s" % error_string(rename_error)
		return false
	return true

func capture_dto() -> Dictionary:
	return {
		"schema_version": CURRENT_VERSION,
		"sound_enabled": sound_enabled,
		"voice_id": voice_id,
		"combat_format": combat_format,
		"auto_speed": auto_speed,
	}

func _apply(dto: Dictionary) -> void:
	sound_enabled = bool(dto["sound_enabled"])
	voice_id = String(dto["voice_id"])
	combat_format = String(dto["combat_format"])
	auto_speed = int(dto["auto_speed"])

func _read(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var dto: Dictionary = parser.data
	return dto if _valid(dto) else {}

func _valid(dto: Dictionary) -> bool:
	if typeof(dto.get("schema_version")) not in [TYPE_INT, TYPE_FLOAT] or int(dto.get("schema_version", -1)) != CURRENT_VERSION:
		return false
	if typeof(dto.get("sound_enabled")) != TYPE_BOOL or typeof(dto.get("voice_id")) != TYPE_STRING:
		return false
	if typeof(dto.get("combat_format")) != TYPE_STRING or dto["combat_format"] not in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE]:
		return false
	return typeof(dto.get("auto_speed")) in [TYPE_INT, TYPE_FLOAT] and int(dto.get("auto_speed", 0)) in AUTO_SPEEDS

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
