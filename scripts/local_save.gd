class_name LocalSave
extends RefCounted


enum LoadStatus {
	OK,
	NOT_FOUND,
	INVALID,
	UNSUPPORTED,
}

class LoadResult:
	var status: LoadStatus = LoadStatus.NOT_FOUND
	var state: GameState
	var recovered_from_backup: bool = false
	var message: String = ""


const DEFAULT_SAVE_PATH: String = "user://jar_garden_save.json"
const BACKUP_SUFFIX: String = ".bak"
const TEMP_SUFFIX: String = ".tmp"


static func load_state_result(
	now_unix_seconds: int,
	save_path: String = DEFAULT_SAVE_PATH,
	tuning: MvpTuning = null,
) -> LoadResult:
	var primary := _read_single_save(save_path, now_unix_seconds, tuning)
	if primary.status == LoadStatus.OK or primary.status == LoadStatus.UNSUPPORTED:
		return primary

	var backup_path := save_path + BACKUP_SUFFIX
	var backup := _read_single_save(backup_path, now_unix_seconds, tuning)
	if backup.status == LoadStatus.OK:
		backup.recovered_from_backup = true
		backup.message = "Recovered the last valid local backup."
		return backup
	if primary.status == LoadStatus.NOT_FOUND and backup.status == LoadStatus.NOT_FOUND:
		return primary
	if backup.status == LoadStatus.UNSUPPORTED:
		return backup

	primary.status = LoadStatus.INVALID
	primary.message = "The local save and its backup could not be read safely."
	return primary


static func load_state(
	now_unix_seconds: int,
	save_path: String = DEFAULT_SAVE_PATH,
	tuning: MvpTuning = null,
) -> GameState:
	var result := load_state_result(now_unix_seconds, save_path, tuning)
	return result.state if result.status == LoadStatus.OK else null


static func save_state(
	state: GameState,
	save_path: String = DEFAULT_SAVE_PATH,
	tuning: MvpTuning = null,
) -> Error:
	var temp_path := save_path + TEMP_SUFFIX
	var backup_path := save_path + BACKUP_SUFFIX
	_remove_if_exists(temp_path)

	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	file.flush()
	file.close()

	var verification := _read_single_save(temp_path, state.last_simulated_unix_seconds, tuning)
	if verification.status != LoadStatus.OK:
		_remove_if_exists(temp_path)
		return ERR_FILE_CORRUPT

	var current := _read_single_save(save_path, state.last_simulated_unix_seconds, tuning)
	if current.status == LoadStatus.UNSUPPORTED:
		_remove_if_exists(temp_path)
		return ERR_UNAVAILABLE

	if current.status == LoadStatus.OK:
		_remove_if_exists(backup_path)
		var backup_error := _rename(save_path, backup_path)
		if backup_error != OK:
			_remove_if_exists(temp_path)
			return backup_error
	elif current.status == LoadStatus.INVALID:
		var quarantine_path := "%s.invalid-%d" % [
			save_path,
			int(Time.get_unix_time_from_system()),
		]
		var quarantine_error := _rename(save_path, quarantine_path)
		if quarantine_error != OK:
			_remove_if_exists(temp_path)
			return quarantine_error

	var replace_error := _rename(temp_path, save_path)
	if replace_error != OK:
		return replace_error
	return OK


static func _read_single_save(
	save_path: String,
	now_unix_seconds: int,
	tuning: MvpTuning,
) -> LoadResult:
	var result := LoadResult.new()
	if not FileAccess.file_exists(save_path):
		result.status = LoadStatus.NOT_FOUND
		return result

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		result.status = LoadStatus.INVALID
		result.message = "The local save could not be opened."
		return result

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or typeof(json.data) != TYPE_DICTIONARY:
		result.status = LoadStatus.INVALID
		result.message = "The local save contains invalid JSON."
		return result

	var data: Dictionary = json.data
	var raw_schema: Variant = data.get("schema_version", 0)
	if typeof(raw_schema) != TYPE_INT and typeof(raw_schema) != TYPE_FLOAT:
		result.status = LoadStatus.INVALID
		return result
	var schema_version := int(raw_schema)
	if schema_version > GameState.SCHEMA_VERSION:
		result.status = LoadStatus.UNSUPPORTED
		result.message = "The local save was created by a newer Jar Garden version."
		return result

	result.state = GameState.from_dict(data, now_unix_seconds, tuning)
	if result.state == null:
		result.status = LoadStatus.INVALID
		result.message = "The local save has invalid or unsupported data."
		return result

	result.status = LoadStatus.OK
	return result


static func _rename(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path),
		ProjectSettings.globalize_path(to_path),
	)


static func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
