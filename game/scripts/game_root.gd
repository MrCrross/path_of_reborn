class_name GameRoot
extends Control

var session: GameSession
var router: SceneRouter
var save_service: SaveService
var preferences: PreferencesService
var preferences_path: String = ""
var save_path: String = SaveService.DEFAULT_PATH

var _restoring: bool = false
var _claim_commit_active: bool = false
var _checkpoint_commit_active: bool = false
var _observed_inventory: InventoryService

@onready var screen_host: Control = %ScreenHost
@onready var notice_bar: PanelContainer = %NoticeBar
@onready var notice_text: Label = %NoticeText
@onready var void_return_fx: TextureRect = %VoidReturn

var _was_awaiting_return: bool = false
var _return_fx_tween: Tween

func _ready() -> void:
	theme = AppTheme.build()
	_read_save_path()
	_read_debug_flags()
	session = GameSession.new()
	save_service = SaveService.new()
	preferences = PreferencesService.new()
	preferences_path = PreferencesService.path_for_profile(save_path)
	preferences.load_preferences(preferences_path, save_service.peek_combat_format(save_path))
	session.combat_format = preferences.combat_format
	session.auto_speed = preferences.auto_speed
	AudioServer.set_bus_mute(0, not preferences.sound_enabled)
	router = SceneRouter.new()
	router.configure(screen_host, session)
	router.screen_added.connect(_on_screen_added)
	_connect_session_signals()
	_was_awaiting_return = session.awaiting_return
	router.go_to("title")

func _physics_process(_delta: float) -> void:
	if session != null:
		session.play_tick += 1

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Android Back / Esc закрывает только верхний разрешённый слой текущего экрана.
	var screen: Control = router.current_screen
	if screen != null and screen.has_method("handle_back") and screen.call("handle_back"):
		get_viewport().set_input_as_handled()

## Куда ведёт «Продолжить»: незавершённый пролог доигрывается с первой
## непрочитанной cue (повтор незавершённой реплики с начала — осознанная политика).
## Ожидающий результат боя важнее World: экран боя восстановит pending без
## нового resolver'а и даст его спокойно прочесть и получить.
static func route_for_continue(target: GameSession) -> String:
	if target.awaiting_return:
		return "checkpoint"
	if target.has_pending_battle_result():
		return "combat"
	if not target.pending_story_reward.is_empty():
		return "merchant"
	if target.world_flags.get("daijiro_scout_defeated", false) and not target.world_flags.get("daijiro_introduction_completed", false):
		return "merchant"
	if not target.world_flags.get("prologue_completed", false):
		return "prologue"
	return "world"

func _on_screen_added(screen: Control) -> void:
	if screen.has_signal("new_game_requested"):
		screen.connect("new_game_requested", _on_new_game_requested)
		screen.connect("continue_requested", _on_continue_requested)
		screen.call("set_profile_status", save_service.has_profile(save_path), save_service.last_error)
	if screen.has_signal("claim_requested"):
		screen.connect("claim_requested", _on_claim_requested)
	if screen.has_signal("checkpoint_commit_requested"):
		screen.connect("checkpoint_commit_requested", _on_checkpoint_commit_requested)
	if screen.has_signal("story_claim_requested"):
		screen.connect("story_claim_requested", _on_story_claim_requested)
	if screen.has_signal("sound_change_requested"):
		screen.connect("sound_change_requested", set_sound_enabled)
		screen.connect("voice_change_requested", set_voice_id)
	if screen.has_signal("sale_requested"):
		screen.connect("sale_requested", _on_sale_requested)

func _on_claim_requested(result_id: String) -> void:
	if not claim_battle_result(result_id):
		return
	var settlement: Dictionary = session.last_settlement
	if settlement.get("enemy_id", "") == "goblin_scout" and settlement.get("encounter_mode", "") == GameSession.ENCOUNTER_ROUTE:
		router.go_to("merchant")
	else:
		router.go_to("world")

func _on_story_claim_requested(reward_id: String) -> void:
	if claim_story_reward(reward_id):
		router.go_to("world")

func claim_story_reward(reward_id: String) -> bool:
	if _claim_commit_active or _restoring:
		return false
	_claim_commit_active = true
	var candidate := GameSession.new()
	candidate.apply_state_dto(save_service.capture(session))
	var claimed: bool = candidate.claim_story_reward(reward_id)
	if not claimed or not save_service.save(candidate, save_path):
		_claim_commit_active = false
		_show_claim_failure()
		return false
	_restoring = true
	session.apply_state_dto(save_service.capture(candidate))
	_restoring = false
	_claim_commit_active = false
	_connect_session_signals()
	notice_bar.hide()
	return true

func _on_sale_requested(instance_id: String, quantity: int) -> void:
	if sell_item(instance_id, quantity):
		router.go_to("merchant")

func sell_item(instance_id: String, quantity: int = 1) -> bool:
	if _claim_commit_active or _restoring:
		return false
	_claim_commit_active = true
	var candidate := GameSession.new()
	candidate.apply_state_dto(save_service.capture(session))
	if not candidate.sell_item(instance_id, quantity) or not save_service.save(candidate, save_path):
		_claim_commit_active = false
		_show_notice("Не удалось сохранить обмен. Предмет и кошелёк не изменены.")
		return false
	_restoring = true
	session.apply_state_dto(save_service.capture(candidate))
	_restoring = false
	_claim_commit_active = false
	_connect_session_signals()
	notice_bar.hide()
	return true

func claim_battle_result(result_id: String) -> bool:
	if _claim_commit_active or _restoring:
		return false
	_claim_commit_active = true
	var candidate := GameSession.new()
	candidate.apply_state_dto(save_service.capture(session))
	var claimed: bool = candidate.claim_battle_result(result_id)
	if not claimed or not save_service.save(candidate, save_path):
		_claim_commit_active = false
		_show_claim_failure()
		return false
	var settlement: Dictionary = candidate.last_settlement.duplicate(true)
	var receive_fx: bool = candidate.pending_receive_fx
	_restoring = true
	session.apply_state_dto(save_service.capture(candidate))
	session.last_settlement = settlement
	session.pending_receive_fx = receive_fx
	_restoring = false
	_claim_commit_active = false
	_connect_session_signals()
	session.publish_battle_result_claimed()
	notice_bar.hide()
	return true

func _show_claim_failure() -> void:
	_show_notice("Не удалось сохранить добычу. Результат сохранён на экране — повторите касание.")
	if router.current_screen != null and router.current_screen.has_method("show_claim_error"):
		router.current_screen.call("show_claim_error")

## --- Граница commit Checkpoint ---
## Домен (CheckpointService) вычисляет итог чисто: завершение канала staged в
## pending_completion, возврат/удаление — через планы. Здесь итог применяется к
## кандидату, атомарно записывается и только после успеха публикуется в live.
## При ошибке живое состояние совпадает с последним подтверждённым, игрок
## остаётся на экране, повтор применяет действие ровно один раз.

func _on_checkpoint_commit_requested(kind: String, payload: Dictionary) -> void:
	match kind:
		"completion":
			_commit_checkpoint_completion()
		"restore":
			_commit_checkpoint_restore(String(payload.get("checkpoint_id", "")))
		"delete":
			_commit_checkpoint_delete(String(payload.get("checkpoint_id", "")))

func _commit_checkpoint_completion() -> bool:
	if _checkpoint_commit_active or _restoring:
		return false
	if not session.checkpoints.has_pending_completion():
		return false
	_checkpoint_commit_active = true
	var candidate := GameSession.new()
	candidate.apply_state_dto(save_service.capture(session))
	candidate.checkpoints.apply_completion()
	var committed: bool = save_service.save(candidate, save_path)
	if committed:
		_restoring = true
		session.apply_state_dto(save_service.capture(candidate))
		_restoring = false
		_connect_session_signals()
		notice_bar.hide()
	_checkpoint_commit_active = false
	if committed:
		_notify_checkpoint_screen("checkpoint_committed", "completion")
	else:
		_notify_checkpoint_screen("show_checkpoint_error", "completion")
	return committed

func _commit_checkpoint_restore(checkpoint_id: String) -> bool:
	if _checkpoint_commit_active or _restoring or not session.awaiting_return:
		return false
	_checkpoint_commit_active = true
	var candidate := GameSession.new()
	candidate.apply_state_dto(save_service.capture(session))
	var plan: Dictionary = candidate.checkpoints.restore_plan(checkpoint_id)
	if plan.is_empty():
		_checkpoint_commit_active = false
		_notify_checkpoint_screen("show_checkpoint_error", "restore")
		return false
	candidate.checkpoints.apply_restore_plan(plan)
	var committed: bool = save_service.save(candidate, save_path)
	if committed:
		_restoring = true
		session.apply_state_dto(save_service.capture(candidate))
		_restoring = false
		_connect_session_signals()
		notice_bar.hide()
	_checkpoint_commit_active = false
	if committed:
		# Возврат применён и записан: FX профиля уже сыграл по profile_changed.
		router.go_to("world")
	else:
		_notify_checkpoint_screen("show_checkpoint_error", "restore")
	return committed

func _commit_checkpoint_delete(checkpoint_id: String) -> bool:
	if _checkpoint_commit_active or _restoring:
		return false
	_checkpoint_commit_active = true
	var candidate := GameSession.new()
	candidate.apply_state_dto(save_service.capture(session))
	var plan: Dictionary = candidate.checkpoints.delete_plan(checkpoint_id)
	if plan.is_empty():
		_checkpoint_commit_active = false
		_notify_checkpoint_screen("show_checkpoint_error", "delete")
		return false
	candidate.checkpoints.apply_delete_plan(plan)
	var committed: bool = save_service.save(candidate, save_path)
	if committed:
		_restoring = true
		session.apply_state_dto(save_service.capture(candidate))
		_restoring = false
		_connect_session_signals()
		notice_bar.hide()
	_checkpoint_commit_active = false
	if committed:
		_notify_checkpoint_screen("checkpoint_committed", "delete")
	else:
		_notify_checkpoint_screen("show_checkpoint_error", "delete")
	return committed

func _notify_checkpoint_screen(method: String, kind: String) -> void:
	if router.current_screen != null and router.current_screen.has_method(method):
		router.current_screen.call(method, kind)

func _on_new_game_requested() -> void:
	_restoring = true
	session.new_game()
	_connect_session_signals()
	_restoring = false
	if not save_service.save(session, save_path):
		_show_notice(save_service.last_error)
		return
	notice_bar.hide()
	router.go_to("prologue")

func _on_continue_requested() -> void:
	_restoring = true
	var loaded: bool = save_service.load_into(session, save_path)
	_restoring = false
	if not loaded:
		_show_notice("Не удалось загрузить профиль. " + save_service.last_error)
		return
	session.combat_format = preferences.combat_format
	session.auto_speed = preferences.auto_speed
	AudioServer.set_bus_mute(0, not preferences.sound_enabled)
	_connect_session_signals()
	_was_awaiting_return = session.awaiting_return
	if save_service.loaded_from_backup:
		_show_notice("Основной файл повреждён. Загружена резервная копия.")
	else:
		notice_bar.hide()
	router.go_to(route_for_continue(session))

func _connect_session_signals() -> void:
	if not session.profile_changed.is_connected(_on_profile_changed):
		session.profile_changed.connect(_on_profile_changed)
	if not session.combat_format_changed.is_connected(_on_combat_format_changed):
		session.combat_format_changed.connect(_on_combat_format_changed)
	if not session.auto_speed_changed.is_connected(_on_auto_speed_changed):
		session.auto_speed_changed.connect(_on_auto_speed_changed)
	if not session.checkpoints.changed.is_connected(_autosave):
		session.checkpoints.changed.connect(_autosave)
	_observe_inventory()

func _on_profile_changed() -> void:
	if _was_awaiting_return and not session.awaiting_return:
		_show_return_fx()
	_was_awaiting_return = session.awaiting_return
	_observe_inventory()
	_autosave()

func _on_combat_format_changed(format: String) -> void:
	if _restoring:
		return
	preferences.combat_format = format
	_save_preferences()

func _on_auto_speed_changed(speed: int) -> void:
	if _restoring:
		return
	preferences.auto_speed = speed
	_save_preferences()

func set_sound_enabled(enabled: bool) -> bool:
	preferences.sound_enabled = enabled
	AudioServer.set_bus_mute(0, not enabled)
	return _save_preferences()

func set_voice_id(value: String) -> bool:
	preferences.voice_id = value
	return _save_preferences()

func _save_preferences() -> bool:
	if preferences.save_preferences(preferences_path):
		notice_bar.hide()
		return true
	_show_notice("Не удалось сохранить настройки. Повторите выбор.")
	return false

func _observe_inventory() -> void:
	if _observed_inventory == session.inventory:
		return
	if _observed_inventory != null:
		_observed_inventory.changed.disconnect(_autosave)
	_observed_inventory = session.inventory
	_observed_inventory.changed.connect(_autosave)

func _autosave() -> bool:
	if _restoring or session.in_combat or session.checkpoints.channel_active or session.is_transaction_active():
		return true
	if save_service.save(session, save_path):
		notice_bar.hide()
		return true
	if session.has_pending_battle_result():
		_show_claim_failure()
	else:
		_show_notice(save_service.last_error)
	return false

func _show_return_fx() -> void:
	if void_return_fx == null:
		return
	if _return_fx_tween != null and _return_fx_tween.is_valid():
		_return_fx_tween.kill()
	void_return_fx.modulate.a = 0.0
	void_return_fx.show()
	_return_fx_tween = create_tween()
	_return_fx_tween.tween_property(void_return_fx, "modulate:a", 1.0, 0.25)
	_return_fx_tween.tween_property(void_return_fx, "modulate:a", 0.0, 1.1).set_delay(0.4)
	_return_fx_tween.tween_callback(void_return_fx.hide)

## Выделенная зона ошибок сохранения/загрузки; не перекрывает нижние кнопки экранов.
func _show_notice(message: String) -> void:
	notice_text.text = message
	notice_bar.show()

func _read_save_path() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-path="):
			var candidate: String = argument.trim_prefix("--save-path=")
			if candidate.begins_with("user://"):
				save_path = candidate

func _read_debug_flags() -> void:
	DebugFlags.ui_enabled = "--debug-ui" in OS.get_cmdline_user_args()
