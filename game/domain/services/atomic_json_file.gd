extends RefCounted

## Returns an empty string on success. Each service checks its own file format
## before an existing primary is allowed to replace a good backup.
static func write(path: String, dto: Dictionary, valid_primary: Callable) -> String:
	var primary: String = ProjectSettings.globalize_path(path)
	var temp_path: String = primary + ".tmp"
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(primary.get_base_dir())
	if directory_error != OK:
		return "Не удалось создать каталог сохранения (%s)" % error_string(directory_error)
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return "Не удалось открыть временный файл (%s)" % error_string(FileAccess.get_open_error())
	var stored: bool = file.store_string(JSON.stringify(dto, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not stored or write_error != OK:
		DirAccess.remove_absolute(temp_path)
		return "Не удалось записать файл (%s)" % error_string(write_error if write_error != OK else ERR_FILE_CANT_WRITE)
	if FileAccess.file_exists(primary) and valid_primary.call(path):
		var backup_error: Error = _replace_backup(primary)
		if backup_error != OK:
			DirAccess.remove_absolute(temp_path)
			return "Не удалось обновить резервную копию (%s)" % error_string(backup_error)
	var rename_error: Error = DirAccess.rename_absolute(temp_path, primary)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_path)
		return "Не удалось заменить файл сохранения (%s)" % error_string(rename_error)
	return ""

static func _replace_backup(primary: String) -> Error:
	var backup: String = primary + ".bak"
	var staged: String = backup + ".tmp"
	var error: Error = DirAccess.copy_absolute(primary, staged)
	if error == OK:
		error = DirAccess.rename_absolute(staged, backup)
	if error != OK and FileAccess.file_exists(staged):
		DirAccess.remove_absolute(staged)
	return error
