extends Control

signal navigate_requested(destination: String)

var session: GameSession
var runner: DialogueRunner

@onready var background: ColorRect = %Background
@onready var heading: Label = %Heading
@onready var speaker_text: Label = %SpeakerText
@onready var story_text: Label = %StoryText
@onready var page_text: Label = %PageText
@onready var continue_button: Button = %ContinueButton
@onready var look_button: Button = %LookButton
@onready var hold_button: Button = %HoldButton
@onready var hold_progress: ProgressBar = %HoldProgress
@onready var hint_text: Label = %HintText

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	runner = DialogueRunner.new()
	runner.configure(session)
	runner.changed.connect(_refresh)
	runner.transition_started.connect(_on_transition_started)
	runner.command_requested.connect(_on_command_requested)
	runner.finished.connect(_on_finished)
	if not runner.load_file("res://data/narrative/prologue.json") or not runner.start():
		story_text.text = "Не удалось загрузить данные пролога."
		continue_button.disabled = true
		return
	_refresh()
	continue_button.grab_focus()

func _physics_process(_delta: float) -> void:
	if runner != null:
		runner.advance_ticks(1)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("primary"):
		get_viewport().set_input_as_handled()
		if runner.current_kind() == "hold":
			runner.begin_hold()
		else:
			runner.tap()
	elif event.is_action_released("primary"):
		get_viewport().set_input_as_handled()
		runner.release_hold()

func _on_continue_pressed() -> void:
	runner.tap()

func _on_look_pressed() -> void:
	runner.look()

func _on_look_gui_input(event: InputEvent) -> void:
	var swiped: bool = event is InputEventScreenDrag and event.relative.length() >= 12.0
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		swiped = event.relative.length() >= 12.0
	if swiped:
		look_button.accept_event()
		runner.look()

func _on_hold_down() -> void:
	runner.begin_hold()

func _on_hold_up() -> void:
	runner.release_hold()

func _on_transition_started(cue: Dictionary) -> void:
	var colors: Dictionary = {
		"routine": Color("172131"),
		"crosswalk": Color("1c2931"),
		"alarm": Color("351d24"),
		"rescue": Color("3b3030"),
		"dark": Color("08090e"),
		"threshold": Color("211b35"),
		"seal": Color("153333"),
		"title": Color("10182a"),
	}
	background.color = colors.get(String(cue.get("shot", "")), Color("151522"))

func _on_command_requested(command: Dictionary) -> void:
	match String(command["type"]):
		"set_world_flag":
			session.world_flags[command["key"]] = command["value"]
		"set_npc_flag":
			session.npc_flags[command["key"]] = command["value"]
		_:
			return
	session.profile_changed.emit()

func _on_finished(destination: String) -> void:
	navigate_requested.emit(destination)

func _refresh() -> void:
	if runner == null or runner.is_finished:
		return
	var kind: String = runner.current_kind()
	heading.text = "PATH OF REBORN" if kind == "title" else runner.current_shot().to_upper()
	speaker_text.text = runner.current_speaker()
	story_text.text = runner.current_text()
	page_text.text = "%d/%d · cue %d/%d" % [runner.page_index + 1, runner.page_count(), runner.index + 1, runner.entries.size()]
	continue_button.visible = kind == "line" or kind == "title"
	look_button.visible = kind == "look"
	hold_button.visible = kind == "hold"
	hold_progress.visible = kind == "hold"
	continue_button.disabled = runner.transition_ticks > 0
	look_button.disabled = runner.transition_ticks > 0
	hold_button.disabled = runner.transition_ticks > 0
	hold_progress.value = runner.hold_progress() * 100.0
	match kind:
		"look":
			hint_text.text = "Коснитесь области или проведите по ней"
		"hold":
			hint_text.text = "Держите кнопку или Space · отпускание отменяет"
		"title":
			hint_text.text = "Далее — первый игровой план"
		_:
			hint_text.text = "Space / касание — далее"
	if runner.transition_ticks > 0:
		hint_text.text = "Переход… ввод временно заблокирован"
