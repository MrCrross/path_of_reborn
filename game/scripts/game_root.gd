extends Control

var session: GameSession
var router: SceneRouter
var save_service: SaveService
var save_path: String = SaveService.DEFAULT_PATH

var _restoring: bool = false
var _observed_inventory: InventoryService

@onready var screen_host: Control = %ScreenHost
@onready var save_status: Label = %SaveStatus

func _ready() -> void:
	_read_save_path()
	session = GameSession.new()
	save_service = SaveService.new()
	router = SceneRouter.new()
	router.configure(screen_host, session)
	router.screen_added.connect(_on_screen_added)
	_connect_session_signals()
	router.go_to("title")

func _physics_process(_delta: float) -> void:
	if session != null:
		session.play_tick += 1

func _on_screen_added(screen: Control) -> void:
	if screen.has_signal("new_game_requested"):
		screen.connect("new_game_requested", _on_new_game_requested)
		screen.connect("continue_requested", _on_continue_requested)
		screen.call("set_profile_status", save_service.has_profile(save_path), save_service.last_error)

func _on_new_game_requested() -> void:
	_restoring = true
	session.new_game()
	_connect_session_signals()
	_restoring = false
	if not save_service.save(session, save_path):
		_show_save_error(save_service.last_error)
		return
	save_status.hide()
	router.go_to("prologue")

func _on_continue_requested() -> void:
	_restoring = true
	var loaded: bool = save_service.load_into(session, save_path)
	_restoring = false
	if not loaded:
		_show_save_error("Не удалось загрузить профиль. " + save_service.last_error)
		return
	_connect_session_signals()
	if save_service.loaded_from_backup:
		save_status.text = "Основной файл повреждён. Загружена резервная копия."
		save_status.show()
	else:
		save_status.hide()
	router.go_to("checkpoint" if session.awaiting_return else "world")

func _connect_session_signals() -> void:
	if not session.profile_changed.is_connected(_on_profile_changed):
		session.profile_changed.connect(_on_profile_changed)
	if not session.checkpoints.changed.is_connected(_autosave):
		session.checkpoints.changed.connect(_autosave)
	_observe_inventory()

func _on_profile_changed() -> void:
	_observe_inventory()
	_autosave()

func _observe_inventory() -> void:
	if _observed_inventory == session.inventory:
		return
	if _observed_inventory != null:
		_observed_inventory.changed.disconnect(_autosave)
	_observed_inventory = session.inventory
	_observed_inventory.changed.connect(_autosave)

func _autosave() -> void:
	if _restoring or session.in_combat or session.checkpoints.channel_active:
		return
	if save_service.save(session, save_path):
		save_status.hide()
	else:
		_show_save_error(save_service.last_error)

func _show_save_error(message: String) -> void:
	save_status.text = message
	save_status.show()

func _read_save_path() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-path="):
			var candidate: String = argument.trim_prefix("--save-path=")
			if candidate.begins_with("user://"):
				save_path = candidate
