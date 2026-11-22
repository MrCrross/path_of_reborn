class_name DialogueOverlay
extends Control

signal command_requested(command: Dictionary)
signal finished(destination: String)

var session: GameSession
var runner: DialogueRunner
var speaker_label: Label
var story_text: Label
var next_button: Button
var _accent: ColorRect
var _continuation: Label
var _caption_at_last: String = ""
var _measured_width: float = 0.0
var _focus_guard := ModalFocus.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe := SafeArea.new()
	safe.padding = 7
	add_child(safe)
	var dock := VBoxContainer.new()
	dock.alignment = BoxContainer.ALIGNMENT_END
	safe.add_child(dock)
	var panel := PanelContainer.new()
	panel.name = "DialoguePanel"
	panel.add_theme_stylebox_override("panel", AppTheme.flat(AppTheme.COLOR_DIALOGUE_BG, AppTheme.COLOR_DIALOGUE_BORDER, 1, 0))
	dock.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 2)
	margin.add_theme_constant_override("margin_right", 2)
	margin.add_theme_constant_override("margin_top", 1)
	margin.add_theme_constant_override("margin_bottom", 2)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	var speaker_row := HBoxContainer.new()
	speaker_row.add_theme_constant_override("separation", 4)
	column.add_child(speaker_row)
	_accent = ColorRect.new()
	_accent.custom_minimum_size = Vector2(3, 11)
	_accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speaker_row.add_child(_accent)
	speaker_label = Label.new()
	speaker_label.add_theme_font_size_override("font_size", 11)
	speaker_row.add_child(speaker_label)
	story_text = Label.new()
	story_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_text.add_theme_font_size_override("font_size", 9)
	story_text.add_theme_constant_override("line_spacing", 0)
	story_text.add_theme_color_override("font_color", AppTheme.COLOR_DIALOGUE_TEXT)
	column.add_child(story_text)
	_continuation = Label.new()
	_continuation.add_theme_font_size_override("font_size", 9)
	_continuation.add_theme_color_override("font_color", AppTheme.COLOR_ACCENT)
	column.add_child(_continuation)
	var font := story_text.get_theme_font("font")
	story_text.custom_minimum_size.y = ceilf(font.get_height(9) * AppTheme.DIALOGUE_TEXT_LINES)
	story_text.resized.connect(_measure_page_policy)
	var hit_area := Control.new()
	hit_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hit_area)
	next_button = Button.new()
	next_button.name = "ContinueDialogue"
	hit_area.add_child(next_button)
	next_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		next_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	next_button.pressed.connect(_on_next_pressed)
	hide()

func configure(game_session: GameSession) -> void:
	session = game_session

## Timeline scenes can replay their completion cue if Checkpoint rolled back its flag.
func play(narrative_path: String, last_caption: String = "", timeline_scene: bool = false, substitutions: Dictionary = {}) -> bool:
	stop()
	if session == null:
		return false
	runner = DialogueRunner.new()
	runner.configure(session)
	runner.replay_seen_commands = timeline_scene
	if not runner.load_file(narrative_path):
		runner = null
		return false
	for entry: Dictionary in runner.entries:
		for token: String in substitutions:
			entry["text"] = String(entry.get("text", "")).replace(token, String(substitutions[token]))
	_measured_width = 0.0
	_caption_at_last = last_caption
	runner.start()
	if runner.is_finished:
		runner = null
		return false
	runner.command_requested.connect(func(command: Dictionary) -> void: command_requested.emit(command))
	runner.cue_completed.connect(func(_cue_id: String) -> void: session.profile_changed.emit())
	runner.changed.connect(_refresh)
	runner.finished.connect(_on_runner_finished)
	show()
	_focus_guard.capture(self)
	_refresh()
	_measure_page_policy.call_deferred()
	next_button.grab_focus()
	return true

func is_active() -> bool:
	return visible

func stop() -> void:
	if not visible:
		return
	hide()
	_focus_guard.restore()
	runner = null

func _measure_page_policy() -> void:
	if runner == null or runner.is_finished:
		return
	var width := story_text.size.x
	if width < 32.0 or is_equal_approx(width, _measured_width):
		return
	_measured_width = width
	var font := story_text.get_theme_font("font")
	var font_size := story_text.get_theme_font_size("font_size")
	runner.page_policy = func(line: String) -> Array[String]:
		return DialoguePaginator.paginate(line, font, font_size, width, AppTheme.DIALOGUE_TEXT_LINES)
	runner.repaginate_current()

func _refresh() -> void:
	if runner == null or runner.is_finished:
		return
	var speaker: String = runner.current_speaker().get_slice(" / ", 0)
	speaker_label.get_parent().visible = not speaker.is_empty()
	speaker_label.text = speaker
	var accent := AppTheme.dialogue_speaker_color(speaker)
	speaker_label.add_theme_color_override("font_color", accent)
	_accent.color = accent
	story_text.text = runner.current_text()
	var cue := runner.current_cue()
	var more: bool = runner.page_index + 1 < runner.page_count() or runner.part_index + 1 < cue.get("parts", []).size()
	var last: bool = runner.index == runner.entries.size() - 1
	var action: String = _caption_at_last if last and not more else ""
	_continuation.text = "▼" if more else ("◆" if action.is_empty() else "◆  " + action)
	next_button.accessibility_name = "Продолжить диалог" if action.is_empty() else action

func _on_next_pressed() -> void:
	if runner != null:
		runner.tap()

func _on_runner_finished(destination: String) -> void:
	stop()
	finished.emit(destination)
