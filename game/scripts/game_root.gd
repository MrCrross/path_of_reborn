class_name GameRoot
extends Control

enum CommitResult { SUCCESS, UNAVAILABLE, REJECTED, WRITE_FAILED }

var session: GameSession
var router: SceneRouter
var save_service: SaveService
var preferences: PreferencesService
var preferences_path: String = ""
var save_path: String = SaveService.DEFAULT_PATH

var _applying_profile: bool = false
var _observed_inventory: InventoryService
var _observed_checkpoints: CheckpointService
var _screen_commands: Dictionary[StringName, Callable] = {
	&"new_game_requested": _on_new_game_requested,
	&"continue_requested": _on_continue_requested,
	&"claim_requested": _on_claim_requested,
	&"checkpoint_commit_requested": _on_checkpoint_commit_requested,
	&"story_claim_requested": _on_story_claim_requested,
	&"sound_change_requested": set_sound_enabled,
	&"voice_change_requested": set_voice_id,
	&"shop_deal_requested": _on_shop_deal_requested,
	&"guild_registration_requested": _on_guild_registration_requested,
	&"guild_order_requested": _on_guild_order_requested,
	&"equipment_upgrade_requested": _on_equipment_upgrade_requested,
	&"grove_command_requested": _on_grove_command_requested,
	&"hollow_command_requested": _on_hollow_command_requested,
	&"outpost_command_requested": _on_outpost_command_requested,
	&"travel_requested": _on_travel_requested,
	&"open_bag_requested": _on_open_bag_requested,
}

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
	_apply_preferences()
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
	if event.is_action_pressed("ui_cancel") and _handle_back():
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()

func _handle_back() -> bool:
	if router == null:
		return false
	var screen: Control = router.current_screen
	return screen != null and (
		ConfirmDialog.dismiss_from(screen)
		or (screen.has_method("handle_back") and screen.call("handle_back"))
	)

## Куда ведёт «Продолжить»: незавершённый пролог доигрывается с первой
## непрочитанной cue (повтор незавершённой реплики с начала — осознанная политика).
## Ожидающий результат боя важнее World: экран боя восстановит pending без
## нового resolver'а и даст его спокойно прочесть и получить.
static func route_for_continue(target: GameSession) -> String:
	if target.awaiting_return or target.checkpoints.has_pending_completion():
		return "checkpoint"
	if target.has_pending_battle_result():
		return "combat"
	if not target.pending_story_reward.is_empty():
		return "merchant"
	if target.world_flags.get("daijiro_scout_defeated", false) and not target.story_rewards.has(GameSession.DAIJIRO_SWORD_REWARD_ID):
		return "merchant"
	if not target.world_flags.get("prologue_completed", false):
		return "prologue"
	if target.location_id == GameSession.LOCATION_GUILD_ORDER:
		return "world"
	match target.next_route_approach():
		"daijiro_lookout":
			return "trail_dialogue"
		"daijiro_cart":
			return "merchant"
	if target.guild_visit_active():
		return "guild"
	if target.can_trade():
		if target.seen_cue_ids.has("DIA_SHOP_001") and not target.world_flags.get(GameSession.WORLD_FLAG_SHOP_INTRO_DONE, false):
			return "shop"
		if target.world_flags.get(GameSession.WORLD_FLAG_SHOP_FIRST_PURCHASE_DONE, false) and not target.world_flags.get(GameSession.WORLD_FLAG_SHOP_PURCHASE_BRIEFING_DONE, false):
			return "shop"
	return "world"

func _on_screen_added(screen: Control) -> void:
	for command: StringName in _screen_commands:
		if screen.has_signal(command):
			screen.connect(command, _screen_commands[command])
	if screen.has_method("set_profile_status"):
		var available := save_service.has_profile(save_path)
		screen.call("set_profile_status", available, save_service.last_error)

func _on_claim_requested(result_id: String) -> void:
	if not claim_battle_result(result_id):
		return
	var settlement: Dictionary = session.last_settlement
	if settlement.get("enemy_id", "") == "goblin_scout" and settlement.get("encounter_mode", "") == GameSession.ENCOUNTER_ROUTE:
		router.go_to("merchant")
	elif settlement.get("route_node_id", "") == "forest_edge_cart_slime" and session.next_route_approach() == "daijiro_lookout":
		router.go_to("trail_dialogue")
	else:
		router.go_to("world")

func _on_story_claim_requested(reward_id: String) -> void:
	if claim_story_reward(reward_id):
		router.go_to("world")
	elif router.current_screen != null and router.current_screen.has_method("retry_gift"):
		router.current_screen.call("retry_gift")

func claim_story_reward(reward_id: String) -> bool:
	var result := _commit_profile_change(func(candidate: GameSession) -> bool: return candidate.claim_story_reward(reward_id))
	if result != CommitResult.SUCCESS:
		if result == CommitResult.WRITE_FAILED:
			_show_notice("Не удалось сохранить подарок. Повторите получение.")
		return false
	session.story_reward_claimed.emit(session.last_settlement)
	return true

## --- Граница commit сделок лавки ---
## Покупка, продажа и обмен применяются к кандидату, записываются атомарно и только после
## успеха публикуется в текущий экран (без re-navigation: вкладка и позиция
## списка живут на экране). При ошибке записи live-экран получает deal_rejected
## и перечитывает карточку из неизменённой сессии — повтор применяет сделку
## ровно один раз.

func _on_shop_deal_requested(deal: Dictionary) -> void:
	commit_shop_deal(deal)

func commit_shop_deal(deal: Dictionary) -> bool:
	if not session.can_trade():
		return false
	var result := _commit_profile_change(_apply_shop_deal.bind(deal))
	var screen := router.current_screen
	if result == CommitResult.SUCCESS:
		if screen != null and screen.has_method("deal_committed"):
			screen.call("deal_committed", session.last_deal)
		return true
	if screen != null and screen.has_method("deal_rejected"):
		var reason := "Не удалось сохранить сделку. Попробуйте ещё раз." if result == CommitResult.WRITE_FAILED else "Условия изменились. Проверьте сумму и количество."
		screen.call("deal_rejected", reason)
	return false

func _apply_shop_deal(candidate: GameSession, deal: Dictionary) -> bool:
	var price: int = int(deal.get("unit_price_copper", -1))
	var quantity: int = int(deal.get("quantity", 1))
	match deal.get("kind", ""):
		"buy":
			return candidate.buy_item(String(deal.get("offer_id", "")), quantity, price)
		"sell":
			return candidate.sell_item(String(deal.get("instance_id", "")), quantity, price, int(deal.get("stock", -1)))
		"exchange":
			return candidate.exchange_coins(String(deal.get("from_coin", "")), String(deal.get("to_coin", "")), quantity, deal.get("quote", {}))
	return false

func _on_guild_registration_requested() -> void:
	var screen: Control = router.current_screen
	var result := _commit_profile_change(func(candidate: GameSession) -> bool: return candidate.register_with_guild())
	screen.call("registration_committed" if result == CommitResult.SUCCESS else "registration_rejected")

func _on_grove_command_requested(command: String) -> void:
	var screen: Control = router.current_screen
	if commit_grove_command(command):
		screen.call("grove_command_committed", command)
	else:
		screen.call("grove_command_rejected", command)

func commit_grove_command(command: String) -> bool:
	return _commit_expedition_command(command, GameSession.LOCATION_GROVE)

func _on_hollow_command_requested(command: String) -> void:
	var screen: Control = router.current_screen
	if commit_hollow_command(command):
		screen.call("hollow_command_committed", command)
	else:
		screen.call("hollow_command_rejected", command)

func commit_hollow_command(command: String) -> bool:
	return _commit_expedition_command(command, GameSession.LOCATION_HOLLOW)

func _on_outpost_command_requested(command: String) -> void:
	var screen: Control = router.current_screen
	if _commit_expedition_command(command, GameSession.LOCATION_OUTPOST):
		screen.call("outpost_command_committed", command)
	else:
		screen.call("outpost_command_rejected", command)

func _commit_expedition_command(command: String, route_id: String) -> bool:
	return _commit_route_change(func(candidate: GameSession) -> bool: return candidate.apply_expedition_command(command, route_id))

func _on_travel_requested(destination: String) -> void:
	var map: Control = router.current_screen
	if not session.map_travel_blocker(destination).is_empty():
		map.call("travel_rejected")
	elif destination == GameSession.MAP_SHOP and session.has_visited_map_location(destination):
		router.go_to("shop")
	elif _commit_route_change(func(candidate: GameSession) -> bool: return candidate.apply_map_travel(destination)):
		match destination:
			GameSession.LOCATION_LIOREN:
				router.go_to("world" if session.should_show_lioren_gates() else "lioren_map")
			GameSession.MAP_SHOP:
				router.go_to("shop")
			GameSession.MAP_GUILD:
				router.go_to("guild")
			_:
				router.go_to("world")
	else:
		map.call("travel_rejected")

func _on_guild_order_requested(command: String, order_id: String) -> void:
	var screen: Control = router.current_screen
	if not commit_guild_order(command, order_id):
		screen.call("command_rejected")
		return
	match command:
		"depart":
			router.go_to("world")
		"leave":
			router.go_to("guild_order_detail")
		"shop":
			router.go_to("shop_from_order")
		_:
			screen.call("command_committed", command)

func commit_guild_order(command: String, order_id: String) -> bool:
	var action: String = "leave" if command == "shop" else command
	return _commit_route_change(func(candidate: GameSession) -> bool: return candidate.apply_guild_order_command(action, order_id))

func _on_equipment_upgrade_requested(quote: Dictionary) -> void:
	var upgraded: bool = _commit_route_change(func(candidate: GameSession) -> bool: return candidate.upgrade_equipment(quote))
	router.current_screen.call("equipment_upgrade_finished", upgraded, quote)

func _commit_route_change(apply: Callable) -> bool:
	return _commit_profile_change(apply) == CommitResult.SUCCESS

## Check live-only guards before taking the snapshot. Callbacks during publication
## cannot write an intermediate state or start a nested command.
func _commit_profile_change(apply: Callable, completing_checkpoint: bool = false) -> CommitResult:
	if _applying_profile or session.is_transaction_active() or session.in_combat or session.checkpoints.channel_active:
		return CommitResult.UNAVAILABLE
	if session.checkpoints.has_pending_completion() != completing_checkpoint:
		return CommitResult.UNAVAILABLE
	_applying_profile = true
	var candidate := GameSession.new()
	candidate.apply_state_dto(save_service.capture(session))
	candidate.pending_receive_fx = session.pending_receive_fx
	var result := CommitResult.REJECTED
	if apply.call(candidate):
		result = _save_candidate(candidate)
	_applying_profile = false
	return result

func _save_candidate(candidate: GameSession) -> CommitResult:
	if not save_service.save(candidate, save_path):
		return CommitResult.WRITE_FAILED
	session.apply_state_dto(save_service.capture(candidate), candidate)
	notice_bar.hide()
	return CommitResult.SUCCESS

func _on_open_bag_requested(instance_id: String) -> void:
	router.go_to("inventory")
	if router.current_screen != null and router.current_screen.has_method("open_item"):
		router.current_screen.call("open_item", instance_id)

func claim_battle_result(result_id: String) -> bool:
	if result_id.is_empty() or session.pending_battle_result.get("result_id", "") != result_id:
		return false
	var result := _commit_profile_change(func(candidate: GameSession) -> bool: return candidate.claim_battle_result(result_id))
	if result != CommitResult.SUCCESS:
		if result == CommitResult.WRITE_FAILED:
			_show_claim_failure()
		return false
	session.publish_battle_result_claimed()
	return true

func _show_claim_failure() -> void:
	_show_notice("Не удалось сохранить результат боя. Нажмите «Повторить запись».")
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
	var result := _commit_profile_change(func(candidate: GameSession) -> bool: return candidate.checkpoints.apply_completion(), true)
	if result == CommitResult.SUCCESS and session.has_pending_reward() and not session.awaiting_return:
		router.go_to(route_for_continue(session))
		return true
	return _finish_checkpoint_commit(result, "completion")

func _commit_checkpoint_restore(checkpoint_id: String) -> bool:
	var result := _commit_profile_change(func(candidate: GameSession) -> bool: return candidate.checkpoints.restore(checkpoint_id))
	if result == CommitResult.SUCCESS:
		router.go_to("world")
		return true
	return _finish_checkpoint_commit(result, "restore")

func _commit_checkpoint_delete(checkpoint_id: String) -> bool:
	var result := _commit_profile_change(func(candidate: GameSession) -> bool: return candidate.checkpoints.delete_checkpoint(checkpoint_id))
	return _finish_checkpoint_commit(result, "delete")

func _finish_checkpoint_commit(result: CommitResult, kind: String) -> bool:
	var committed := result == CommitResult.SUCCESS
	_notify_checkpoint_screen("checkpoint_committed" if committed else "show_checkpoint_error", kind)
	return committed

func _notify_checkpoint_screen(method: String, kind: String) -> void:
	if router.current_screen != null and router.current_screen.has_method(method):
		router.current_screen.call(method, kind)

func _on_new_game_requested() -> void:
	if _applying_profile:
		return
	_applying_profile = true
	var candidate := GameSession.new()
	candidate.combat_format = preferences.combat_format
	var result := _save_candidate(candidate)
	_applying_profile = false
	if result != CommitResult.SUCCESS:
		_show_notice(save_service.last_error)
		return
	router.go_to("prologue")

func _on_continue_requested() -> void:
	if _applying_profile:
		return
	_applying_profile = true
	var loaded: bool = save_service.load_into(session, save_path)
	_applying_profile = false
	if not loaded:
		_show_notice("Не удалось загрузить профиль. " + save_service.last_error)
		return
	_apply_preferences()
	_was_awaiting_return = session.awaiting_return
	if save_service.loaded_from_backup:
		_show_notice("Основной файл повреждён. Загружена резервная копия.")
	else:
		notice_bar.hide()
	router.go_to(route_for_continue(session))

func _apply_preferences() -> void:
	session.combat_format = preferences.combat_format
	session.auto_speed = preferences.auto_speed
	session.auto_ability = preferences.auto_ability
	AudioServer.set_bus_mute(0, not preferences.sound_enabled)

func _connect_session_signals() -> void:
	session.profile_changed.connect(_on_profile_changed)
	session.combat_format_changed.connect(_on_combat_format_changed)
	session.auto_speed_changed.connect(_on_auto_speed_changed)
	session.auto_ability_changed.connect(_on_auto_ability_changed)
	_observe_profile_services()

func _on_profile_changed() -> void:
	if _was_awaiting_return and not session.awaiting_return:
		_show_return_fx()
	_was_awaiting_return = session.awaiting_return
	_observe_profile_services()
	_autosave()

func _on_combat_format_changed(format: String) -> void:
	if _applying_profile:
		return
	preferences.combat_format = format
	_save_preferences()

func _on_auto_speed_changed(speed: int) -> void:
	if _applying_profile:
		return
	preferences.auto_speed = speed
	_save_preferences()

func _on_auto_ability_changed(enabled: bool) -> void:
	if _applying_profile:
		return
	preferences.auto_ability = enabled
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

func _observe_profile_services() -> void:
	if _observed_inventory != session.inventory:
		if _observed_inventory != null:
			_observed_inventory.changed.disconnect(_autosave)
		_observed_inventory = session.inventory
		_observed_inventory.changed.connect(_autosave)
	if _observed_checkpoints != session.checkpoints:
		if _observed_checkpoints != null:
			_observed_checkpoints.changed.disconnect(_autosave)
		_observed_checkpoints = session.checkpoints
		_observed_checkpoints.changed.connect(_autosave)

func _autosave() -> bool:
	if _applying_profile or session.in_combat or session.checkpoints.channel_active or session.is_transaction_active():
		return true
	if save_service.save(session, save_path):
		notice_bar.hide()
		return true
	if session.has_pending_battle_result():
		_show_notice("Не удалось сохранить результат боя. Запись повторится при подтверждении.")
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
