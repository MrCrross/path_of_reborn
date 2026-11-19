class_name DialogueRunner
extends RefCounted

signal changed
signal transition_started(cue: Dictionary)
signal command_requested(command: Dictionary)
signal finished(destination: String)

const TRANSITION_TICKS: int = 12
const HOLD_TICKS: int = 45
const PAGE_CHARACTERS: int = 88
const ALLOWED_KINDS: Array[String] = ["line", "look", "hold", "title"]
const ALLOWED_DESTINATIONS: Array[String] = ["world"]
const ALLOWED_ENTERS: Array[String] = ["", "approach", "signal", "rescue_motion", "flash", "night_pause", "threshold", "wing_glitch", "offer_gift", "title"]
const ALLOWED_COMMANDS: Array[String] = ["set_world_flag", "set_npc_flag"]

var entries: Array[Dictionary] = []
var session: GameSession
var index: int = 0
var part_index: int = 0
var page_index: int = 0
var pages: Array[String] = []
var transition_ticks: int = 0
var hold_ticks: int = 0
var holding: bool = false
var is_finished: bool = false
var destination: String = ""

func configure(game_session: GameSession) -> void:
	session = game_session

func load_file(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return false
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_ARRAY:
		return false
	var loaded: Array[Dictionary] = []
	loaded.assign(parser.data)
	if not validate_entries(loaded):
		return false
	entries = loaded
	return true

func start() -> bool:
	if entries.is_empty() or session == null:
		return false
	is_finished = false
	destination = ""
	index = 0
	_skip_seen()
	if is_finished:
		return true
	_enter_current()
	return true

func advance_ticks(count: int = 1) -> void:
	for _tick: int in range(maxi(0, count)):
		if is_finished:
			return
		if transition_ticks > 0:
			transition_ticks -= 1
			changed.emit()
			continue
		if holding:
			hold_ticks += 1
			if hold_ticks >= HOLD_TICKS:
				holding = false
				hold_ticks = 0
				_complete_current()
			else:
				changed.emit()

func tap() -> bool:
	if not _can_interact() or current_kind() == "hold" or current_kind() == "look":
		return false
	if page_index + 1 < pages.size():
		page_index += 1
		changed.emit()
		return true
	var cue: Dictionary = current_cue()
	var parts: Array = cue.get("parts", [])
	if part_index + 1 < parts.size():
		part_index += 1
		_set_pages()
		transition_started.emit(_presentation_cue())
		changed.emit()
		return true
	_complete_current()
	return true

func look() -> bool:
	if not _can_interact() or current_kind() != "look":
		return false
	_complete_current()
	return true

func begin_hold() -> bool:
	if not _can_interact() or current_kind() != "hold" or holding:
		return false
	holding = true
	hold_ticks = 0
	changed.emit()
	return true

func release_hold() -> void:
	if not holding:
		return
	holding = false
	hold_ticks = 0
	changed.emit()

func current_cue() -> Dictionary:
	return entries[index] if index >= 0 and index < entries.size() else {}

func current_kind() -> String:
	return String(current_cue().get("kind", "line"))

func current_text() -> String:
	return pages[page_index] if page_index >= 0 and page_index < pages.size() else ""

func current_speaker() -> String:
	return String(current_cue().get("speaker", ""))

func current_shot() -> String:
	var parts: Array = current_cue().get("parts", [])
	if part_index < parts.size():
		return String(parts[part_index].get("shot", current_cue().get("shot", "")))
	return String(current_cue().get("shot", ""))

func page_count() -> int:
	return pages.size()

func hold_progress() -> float:
	return float(hold_ticks) / HOLD_TICKS

static func paginate(text: String, limit: int = PAGE_CHARACTERS) -> Array[String]:
	var result: Array[String] = []
	var remaining: String = text.strip_edges()
	while remaining.length() > limit:
		var cut: int = remaining.rfind(" ", limit)
		if cut <= 0:
			cut = limit
		result.append(remaining.left(cut).strip_edges())
		remaining = remaining.substr(cut).strip_edges()
	if not remaining.is_empty():
		result.append(remaining)
	return result

static func validate_entries(cues: Array[Dictionary]) -> bool:
	if cues.is_empty():
		return false
	var ids: Dictionary = {}
	for cue: Dictionary in cues:
		var cue_id: Variant = cue.get("id")
		if typeof(cue_id) != TYPE_STRING or cue_id.is_empty() or ids.has(cue_id):
			return false
		if String(cue.get("kind", "line")) not in ALLOWED_KINDS:
			return false
		if typeof(cue.get("text", "")) != TYPE_STRING or typeof(cue.get("speaker", "")) != TYPE_STRING or typeof(cue.get("shot", "")) != TYPE_STRING:
			return false
		if String(cue.get("enter", "")) not in ALLOWED_ENTERS:
			return false
		if typeof(cue.get("once", false)) != TYPE_BOOL:
			return false
		if cue.has("destination") and String(cue["destination"]) not in ALLOWED_DESTINATIONS:
			return false
		if typeof(cue.get("parts", [])) != TYPE_ARRAY:
			return false
		for part: Variant in cue.get("parts", []):
			if typeof(part) != TYPE_DICTIONARY or typeof(part.get("text", "")) != TYPE_STRING or String(part.get("text", "")).is_empty() or typeof(part.get("shot", "")) != TYPE_STRING:
				return false
		for command: Variant in cue.get("commands", []):
			if typeof(command) != TYPE_DICTIONARY or String(command.get("type", "")) not in ALLOWED_COMMANDS:
				return false
			if typeof(command.get("key", "")) != TYPE_STRING or String(command.get("key", "")).is_empty() or typeof(command.get("value")) not in [TYPE_BOOL, TYPE_STRING, TYPE_INT, TYPE_FLOAT]:
				return false
		ids[cue_id] = true
	for cue: Dictionary in cues:
		if cue.has("next") and (typeof(cue["next"]) != TYPE_STRING or not ids.has(cue["next"])):
			return false
	var visited: Dictionary = {}
	var cursor: int = 0
	while cursor >= 0 and cursor < cues.size():
		if visited.has(cursor):
			return false
		visited[cursor] = true
		var cue: Dictionary = cues[cursor]
		if cue.has("next"):
			cursor = cues.find_custom(func(candidate: Dictionary) -> bool: return candidate["id"] == cue["next"])
		elif cue.has("destination"):
			cursor = -1
		else:
			cursor += 1
	if visited.size() != cues.size() or not cues.back().has("destination"):
		return false
	return true

func _enter_current() -> void:
	part_index = 0
	page_index = 0
	holding = false
	hold_ticks = 0
	_set_pages()
	transition_ticks = TRANSITION_TICKS if not String(current_cue().get("enter", "")).is_empty() else 0
	transition_started.emit(_presentation_cue())
	changed.emit()

func _set_pages() -> void:
	var text: String = String(current_cue().get("text", ""))
	var parts: Array = current_cue().get("parts", [])
	if part_index < parts.size():
		text = String(parts[part_index].get("text", ""))
	pages = paginate(text)
	if pages.is_empty():
		pages.append("")
	page_index = 0

func _can_interact() -> bool:
	return not is_finished and transition_ticks == 0 and not current_cue().is_empty()

func _complete_current() -> void:
	var cue: Dictionary = current_cue()
	if bool(cue.get("once", false)):
		session.seen_cue_ids[cue["id"]] = true
	for command: Dictionary in cue.get("commands", []):
		command_requested.emit(command.duplicate(true))
	if cue.has("destination"):
		_finish(String(cue["destination"]))
		return
	if cue.has("next"):
		var next_id: String = cue["next"]
		index = entries.find_custom(func(candidate: Dictionary) -> bool: return candidate["id"] == next_id)
	else:
		index += 1
	_skip_seen()
	if not is_finished:
		_enter_current()

func _skip_seen() -> void:
	while index < entries.size() and bool(entries[index].get("once", false)) and session.seen_cue_ids.has(entries[index]["id"]):
		index += 1
	if index >= entries.size():
		_finish("world")

func _finish(next_destination: String) -> void:
	if is_finished:
		return
	is_finished = true
	destination = next_destination
	holding = false
	hold_ticks = 0
	changed.emit()
	finished.emit(destination)

func _presentation_cue() -> Dictionary:
	var cue: Dictionary = current_cue().duplicate(true)
	cue["part_index"] = part_index
	cue["shot"] = current_shot()
	return cue
