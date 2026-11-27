extends Control

signal navigate_requested(destination: String)
signal claim_requested(result_id: String)

const VICTORY_FONT_SIZE := 24
const VICTORY_REACTION_SECONDS := 0.65
const DEFEAT_TO_CHECKPOINT_SECONDS := 0.8
const FOCUSED_STRIKE_TUTORIAL := "tutorial_focused_strike"

var session: GameSession
var resolver: CombatResolver

@onready var arena: Control = %Arena
@onready var telegraph: Sprite2D = %Telegraph
@onready var phase_cue: Label = %PhaseCue
@onready var hero_sprite: AnimatedSprite2D = %HeroSprite
@onready var enemy_sprite: AnimatedSprite2D = %EnemySprite
@onready var hint_label: Label = %HintLabel
@onready var victory_label: Label = %VictoryLabel
@onready var actions: HBoxContainer = %Actions
@onready var attack_button: Button = %AttackButton
@onready var attack_cooldown: ProgressBar = %AttackCooldown
@onready var ability_button: Button = %AbilityButton
@onready var ability_cooldown: ProgressBar = %AbilityCooldown
@onready var dodge_button: Button = %DodgeButton
@onready var dodge_cooldown: ProgressBar = %DodgeCooldown
@onready var pause_button: Button = %PauseButton
@onready var pause_layer: Control = %PauseLayer
@onready var resume_button: Button = %ResumeButton
@onready var forfeit_button: Button = %ForfeitButton
@onready var format_switch: Button = %FormatSwitch
@onready var speed_switch: Button = %SpeedSwitch
@onready var format_label: Label = %FormatLabel
@onready var result_panel: CombatResultView = %ResultPanel
@onready var details_layer: Control = %DetailsLayer
@onready var details_view: ItemDetailsView = %DetailsView
@onready var detail_close: Button = details_view.close_button
@onready var equipment_strip: EquipmentStrip = %EquipmentStrip

var hero_health: ActorHealthDisplay
var enemy_health: ActorHealthDisplay
var arena_presenter: CombatArenaPresenter

var _intro_active: bool = false
var _ability_lesson: bool = false
var _feedback_ticks: int = 0
var _pause_open: bool = false
var _navigating: bool = false
## Результат ждёт игрока: ни auto-dismiss, ни auto-world. Каждая находка
## получает выбор «В рюкзак»/«Надеть», затем выполняется один атомарный claim.
var _result_visible: bool = false
var _pointer_candidate: Dictionary = {}
var _pointer_down: bool = false
var _pointer_down_began_at_result: bool = false
var _details_open: bool = false
var _loot_tutorial: ConfirmDialog
var _focus_guard := ModalFocus.new()

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	if _details_open:
		_close_details()
		return true
	if _result_visible:
		# Из несобранного результата Back не уводит: состояние не теряется.
		return true
	# Android Back в бою управляет только паузой: открыть или закрыть.
	if resolver == null or resolver.is_finished:
		return false
	_set_pause(not _pause_open)
	return true

func _ready() -> void:
	if session == null:
		session = GameSession.new()
		session.select_encounter("moss_slime")
	if session.location_id in GameSession.EXPEDITION_LOCATIONS:
		$Arena/ArenaBackground.texture = ArtMap.world_background(session.location_id)
		if session.location_id == GameSession.LOCATION_HOLLOW and session.hollow_stage() == "elite":
			$Arena/ArenaBackground.texture = ArtMap.texture(ArtMap.BACKGROUNDS["hollow_basin"])
	arena_presenter = CombatArenaPresenter.new()
	arena_presenter.name = "ArenaPresenter"
	add_child(arena_presenter)
	arena_presenter.configure(session, arena, hero_sprite, enemy_sprite, telegraph, phase_cue)
	arena_presenter.intro_finished.connect(_finish_intro)
	hero_health = arena_presenter.hero_health
	enemy_health = arena_presenter.enemy_health
	details_view.configure(session)
	details_view.close_requested.connect(_close_details)
	result_panel.claim_requested.connect(_claim_result)
	result_panel.summary_acknowledged.connect(_show_next_reward)
	result_panel.choice_requested.connect(_on_reward_choice)
	result_panel.item_requested.connect(_open_details)
	equipment_strip.configure(session, "combat")
	UiIcons.apply(attack_button, "attack", "Атака")
	var ability: AbilityDefinition = session.hero.first_ability()
	if ability != null:
		var mastered: bool = session.quest_flags.get(GameSession.GROVE_REPORTED, false) and not ability.mastered_display_name.is_empty()
		ability_button.tooltip_text = ability.mastered_display_name if mastered else ability.display_name
		ability_button.accessibility_name = ability_button.tooltip_text
		ability_button.text = ability_button.tooltip_text
	ability_button.custom_minimum_size = Vector2(72, UiIcons.TOUCH_SIZE)
	ability_button.theme_type_variation = &"PrimaryButton"
	ability_button.add_theme_font_size_override("font_size", 8)
	ability_button.add_theme_color_override("font_disabled_color", AppTheme.COLOR_TEXT_DIM)
	UiIcons.apply(dodge_button, "dodge", "Уклонение")
	# Короткая подпись режима поверх яркого фона арены: тёмная компактная
	# подложка, чтобы текст не сливался со светлой листвой.
	var format_box := AppTheme.flat(Color("0e1811e8"), Color("2f4433"), 1, 2)
	format_box.content_margin_left = 3
	format_box.content_margin_right = 3
	format_label.add_theme_stylebox_override("normal", format_box)
	_refresh_format_ui()
	if session.has_pending_battle_result():
		# Восстановление после relaunch: тот же pending-result, без нового
		# resolver'а, вступления и боя; RNG не перебрасывается.
		_show_restored_result()
		return
	var next_resolver: CombatResolver = session.start_selected_combat()
	if next_resolver == null:
		_show_start_failure()
		return
	_set_resolver(next_resolver)
	arena_presenter.layout()
	_start_intro()

func _physics_process(_delta: float) -> void:
	_update_marker_positions()
	if resolver != null and not resolver.is_finished and not _intro_active and not _pause_open and not _ability_lesson:
		resolver.advance_ticks(_combat_speed())
		_refresh_cooldowns()
		if _feedback_ticks > 0:
			_feedback_ticks -= 1
			if _feedback_ticks == 0:
				hint_label.hide()

func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree() or event.is_action_pressed("ui_cancel"):
		return
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch and event.canceled:
		if _matches_pointer(event, "touch"):
			get_viewport().set_input_as_handled()
		_cancel_pointer()
		return
	if event is InputEventScreenDrag:
		if _matches_pointer(event, "touch"):
			_cancel_pointer()
			get_viewport().set_input_as_handled()
		return
	if not _result_visible and _current_combat_format() == GameSession.COMBAT_FORMAT_ACTIVE:
		if event.is_action_pressed("primary"):
			get_viewport().set_input_as_handled()
			_on_attack_pressed()
			return
		if event.is_action_pressed("secondary"):
			get_viewport().set_input_as_handled()
			_on_dodge_pressed()
			return
	if ability_button.is_visible_in_tree() and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q:
		get_viewport().set_input_as_handled()
		_on_ability_pressed()
		return
	if _is_press(event):
		if resolver != null and not _intro_active and not _pause_open and not _result_visible and not _details_open and _current_combat_format() == GameSession.COMBAT_FORMAT_ACTIVE:
			if event is InputEventScreenTouch or event is InputEventMouseButton:
				var relative: Vector2 = arena.get_global_transform_with_canvas().affine_inverse() * event.position
				if resolver.select_target(arena_presenter.target_at(relative)):
					get_viewport().set_input_as_handled()
					return
		get_viewport().set_input_as_handled()
		_on_press_began(event)
	elif _is_release(event):
		var canceled: bool = event is InputEventScreenTouch and event.canceled
		var matches: bool = _matches_event_pointer(event)
		if matches or canceled:
			get_viewport().set_input_as_handled()
		_on_press_ended(event, canceled)

func _is_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return event.is_action_pressed("primary") or event.is_action_pressed("secondary")

func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not event.pressed
	if event is InputEventMouseButton:
		return not event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return event.is_action_released("primary") or event.is_action_released("secondary")

func _on_press_began(event: InputEvent = null) -> void:
	if _intro_active or _pause_open or _navigating or _details_open:
		return
	if event is InputEventScreenTouch and not _pointer_candidate.is_empty():
		_cancel_pointer()
		return
	if not _pointer_candidate.is_empty():
		return
	_pointer_candidate = _pointer_identity(event)
	_pointer_down = true
	_pointer_down_began_at_result = _result_visible
	if _result_visible:
		return

func _on_press_ended(_event: InputEvent = null, _canceled: bool = false) -> void:
	_cancel_pointer()

func _pointer_identity(event: InputEvent) -> Dictionary:
	var kind: String = "key"
	var index: int = 0
	var device: int = 0
	var pointer_position: Vector2 = Vector2.ZERO
	if event is InputEventScreenTouch:
		kind = "touch"
		index = event.index
		device = event.device
		pointer_position = event.position
	elif event is InputEventMouseButton:
		kind = "mouse"
		index = event.button_index
		device = event.device
		pointer_position = event.position
	return {"kind": kind, "index": index, "device": device, "position": pointer_position}

func _matches_event_pointer(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return _matches_pointer(event, "touch")
	if event is InputEventMouseButton:
		return _matches_pointer(event, "mouse")
	return not _pointer_candidate.is_empty() and _pointer_candidate.get("kind", "") == "key" and (event == null or not (event is InputEventScreenTouch or event is InputEventMouseButton))

func _matches_pointer(event: InputEvent, kind: String) -> bool:
	if _pointer_candidate.is_empty() or _pointer_candidate.get("kind", "") != kind:
		return false
	var event_index: Variant = event.get("index") if kind == "touch" else event.get("button_index")
	return _pointer_candidate.get("index", -1) == event_index and _pointer_candidate.get("device", -1) == event.get("device")

func _cancel_pointer() -> void:
	_pointer_candidate = {}
	_pointer_down = false
	_pointer_down_began_at_result = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_pointer()
		if resolver != null and not resolver.is_finished and not _result_visible:
			_set_pause(true)

## Отказ домена (awaiting_return, три Следа, неизвестный враг) — безопасное
## состояние вместо падения на сигналах resolver (UX-12).
func _show_start_failure() -> void:
	actions.visible = false
	pause_button.visible = false
	equipment_strip.set_suppressed(true)
	hint_label.text = "Бой сейчас недоступен."
	hint_label.show()
	_navigating = true
	await get_tree().create_timer(0.9).timeout
	navigate_requested.emit("world")

func _layout_arena() -> void:
	arena_presenter.layout()

func _update_marker_positions() -> void:
	arena_presenter.update_positions()

func _start_intro() -> void:
	_intro_active = true
	actions.visible = false
	arena_presenter.start_intro()

func _finish_intro() -> void:
	if not _intro_active:
		return
	_intro_active = false
	_ability_lesson = (
		session.active_encounter_context.get("route_node_id") == "forest_edge_cart_slime"
		and not session.seen_cue_ids.has(FOCUSED_STRIKE_TUTORIAL)
		and _ability_unlocked()
	)
	arena_presenter.layout()
	_refresh_format_ui()
	_refresh_actions_visibility()
	if _ability_lesson:
		equipment_strip.set_suppressed(true)
		hint_label.text = "Слизь перегородила тропу.\nПримените «%s»." % ability_button.tooltip_text
		hint_label.show()
		ability_button.grab_focus()
		return
	if _current_combat_format() == GameSession.COMBAT_FORMAT_ACTIVE:
		_show_feedback("Коснитесь врага для выбора цели" if resolver.enemy_slots.size() > 1 else "Атакуйте и уклоняйтесь вручную")
		_feedback_ticks = 90
	if attack_button.visible:
		attack_button.grab_focus()
	elif ability_button.visible:
		ability_button.grab_focus()
	else:
		pause_button.grab_focus()

func _set_resolver(next_resolver: CombatResolver) -> void:
	resolver = next_resolver
	resolver.dodge_resolved.connect(_on_dodge_resolved)
	resolver.pollen_resolved.connect(_on_pollen_resolved)
	resolver.ability_used.connect(_on_ability_used)
	resolver.finished.connect(_on_finished)
	arena_presenter.bind_resolver(next_resolver)

func _current_combat_format() -> String:
	return resolver.combat_format if resolver != null else session.current_combat_format()

func _combat_speed() -> int:
	return int(session.active_encounter_context.get("auto_speed", 1)) if _current_combat_format() == GameSession.COMBAT_FORMAT_AUTO else 1

func _on_attack_pressed() -> void:
	if _intro_active or _pause_open or _navigating or _result_visible:
		return
	if _ability_lesson or _current_combat_format() != GameSession.COMBAT_FORMAT_ACTIVE:
		return
	if resolver != null and not resolver.is_finished and resolver.request_attack():
		_refresh()

func _on_ability_pressed() -> void:
	if _intro_active or _pause_open or _navigating or _result_visible or resolver == null:
		return
	var auto: bool = not _ability_lesson and _current_combat_format() == GameSession.COMBAT_FORMAT_AUTO
	if not (resolver.request_auto_ability() if auto else resolver.request_ability()):
		return
	if _ability_lesson:
		_ability_lesson = false
		equipment_strip.set_suppressed(false)
		session.seen_cue_ids[FOCUSED_STRIKE_TUTORIAL] = true
		session.profile_changed.emit()
		_refresh_format_ui()
		(pause_button if _current_combat_format() == GameSession.COMBAT_FORMAT_AUTO else attack_button).grab_focus()
	_refresh()

func _on_ability_used(_ability_id: String) -> void:
	if _ability_lesson or not resolver.auto_ability_enabled:
		_show_feedback(ability_button.tooltip_text)

func _on_dodge_pressed() -> void:
	if _intro_active or _pause_open or _navigating or _result_visible:
		return
	if _ability_lesson or _current_combat_format() != GameSession.COMBAT_FORMAT_ACTIVE:
		return
	if resolver != null and not resolver.is_finished and resolver.request_dodge():
		_refresh()

func _on_pause_pressed() -> void:
	if resolver == null or resolver.is_finished or _result_visible:
		return
	_set_pause(not _pause_open)

func _on_resume_pressed() -> void:
	_set_pause(false)

## Сдача — это поражение без катсцены: далее выбор точки возврата в Печати,
## точку за игрока никто не выбирает.
func _on_forfeit_pressed() -> void:
	if _navigating:
		return
	_navigating = true
	session.abandon_combat()
	navigate_requested.emit("checkpoint")

func _on_speed_switch_pressed() -> void:
	session.set_auto_speed(2 if session.auto_speed == 1 else 1)
	_refresh_format_ui()

## Смена формата — минимальный пункт паузы: применяется со следующего боя,
## текущий бой (cooldown/замах) не трогаем; предпочтение живёт вне Checkpoint.
func _on_format_switch_pressed() -> void:
	var next_format: String = (
		GameSession.COMBAT_FORMAT_ACTIVE
		if session.combat_format == GameSession.COMBAT_FORMAT_AUTO
		else GameSession.COMBAT_FORMAT_AUTO
	)
	session.set_combat_format(next_format)
	_refresh_format_ui()

func _refresh_format_ui() -> void:
	var current_format: String = _current_combat_format()
	var is_auto: bool = current_format == GameSession.COMBAT_FORMAT_AUTO
	if format_label != null:
		format_label.text = "Авто ×%d" % int(session.active_encounter_context.get("auto_speed", session.auto_speed)) if is_auto else "Ручной"
		if _ability_lesson:
			format_label.text = "Обучение"
		format_label.reset_size()
		format_label.visible = not _result_visible
	var has_ability: bool = _ability_unlocked()
	equipment_strip.offset_bottom = -8.0 if is_auto and not has_ability else actions.offset_top - AppTheme.SPACE_COMPACT
	equipment_strip.offset_top = equipment_strip.offset_bottom - equipment_strip.get_combined_minimum_size().y
	actions.alignment = BoxContainer.ALIGNMENT_CENTER if is_auto or _ability_lesson else BoxContainer.ALIGNMENT_END
	if format_switch != null:
		var next_action: String = "ручной бой" if session.combat_format == GameSession.COMBAT_FORMAT_AUTO else "автобой"
		format_switch.text = "Включить %s\nсо следующего боя" % next_action
		format_switch.tooltip_text = "Текущий бой и cooldown не меняются"
	if speed_switch != null:
		speed_switch.text = "Скорость автобоя: ×%d\nсо следующего боя" % session.auto_speed
	if attack_button != null:
		attack_button.visible = not is_auto and not _ability_lesson
	if ability_button != null:
		ability_button.visible = has_ability
	if dodge_button != null:
		dodge_button.visible = not is_auto and not _ability_lesson
	if resolver != null:
		_refresh_cooldowns()

func _ability_unlocked() -> bool:
	var ability: AbilityDefinition = session.hero.first_ability()
	return ability != null and session.hero.level >= ability.unlock_level

## Один владелец паузы gameplay+presentation: resolver стоит, клипы и tweens
## замирают на своём кадре; resume продолжает с того же места без catch-up.
func _set_pause(open: bool) -> void:
	if _pause_open == open:
		return
	_pause_open = open
	pause_layer.visible = open
	pause_button.visible = not open
	equipment_strip.set_suppressed(open or _ability_lesson)
	_refresh_actions_visibility()
	arena_presenter.set_pause(open)
	if open:
		resume_button.grab_focus()
	elif _ability_lesson:
		ability_button.grab_focus()
	elif attack_button.is_visible_in_tree() and not attack_button.disabled:
		attack_button.grab_focus()
	elif dodge_button.is_visible_in_tree() and not dodge_button.disabled:
		dodge_button.grab_focus()
	else:
		pause_button.grab_focus()

func _on_dodge_resolved(success: bool) -> void:
	if success:
		_show_feedback("Уклонение")

func _on_pollen_resolved(avoided: bool) -> void:
	_show_feedback("Пыльца рассеялась" if avoided else "Пыльца · замедление")

func _show_feedback(text: String) -> void:
	hint_label.text = text
	hint_label.show()
	_feedback_ticks = 45

func _on_finished(player_won: bool) -> void:
	format_label.hide()
	hint_label.hide()
	actions.visible = false
	pause_button.visible = false
	equipment_strip.set_suppressed(true)
	if pause_layer.visible:
		pause_layer.hide()
	_pause_open = false
	arena_presenter.finish(player_won)
	if player_won:
		_play_victory_sequence()
	else:
		_play_defeat_sequence()

func _play_victory_sequence() -> void:
	victory_label.text = "Победа"
	victory_label.modulate.a = 0.0
	victory_label.position = Vector2(victory_label.position.x, 48.0)
	victory_label.show()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(victory_label, "modulate:a", 1.0, 0.28)
	tween.tween_property(victory_label, "position:y", 44.0, 0.28)
	# Сначала читаем реакцию победы и исчезновение врага; только затем
	# в нижней части появляется pending-result и ждёт нового нажатия.
	await get_tree().create_timer(VICTORY_REACTION_SECONDS).timeout
	if not _navigating:
		_show_result_panel(session.pending_battle_result)

func _play_defeat_sequence() -> void:
	# Короткая честная реакция, затем сразу выбор возврата без промежуточного шага.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(hero_sprite, "modulate:a", 0.35, DEFEAT_TO_CHECKPOINT_SECONDS)
	await get_tree().create_timer(DEFEAT_TO_CHECKPOINT_SECONDS).timeout
	_navigate_once("checkpoint")

func _navigate_once(destination: String) -> void:
	if _navigating:
		return
	_navigating = true
	navigate_requested.emit(destination)

## --- Результат боя: выбор по каждой находке, затем одна атомарная запись ---

func _show_restored_result() -> void:
	arena_presenter.show_restored()
	victory_label.text = "Победа"
	victory_label.modulate.a = 1.0
	victory_label.show()
	_layout_arena()
	_show_result_panel(session.pending_battle_result)

func _show_result_panel(result: Dictionary) -> void:
	_cancel_pointer()
	format_label.hide()
	pause_button.hide()
	actions.hide()
	equipment_strip.set_suppressed(true)
	result_panel.present(session, result)
	_result_visible = true

func _show_next_reward() -> void:
	if result_panel.present_next(session.pending_battle_result) and not is_instance_valid(_loot_tutorial):
		_loot_tutorial = ConfirmDialog.tutorial(self, session, "tutorial_loot_gestures", "Добыча", "Коснитесь карточки или смахните влево, чтобы забрать. Экипировку можно надеть свайпом вправо. Значок i открывает описание.")

func _open_details(reward: Dictionary) -> void:
	_cancel_pointer()
	if not details_view.present_reward(String(reward["item_id"]), String(reward["aspect_id"]), int(reward["quantity"]), reward):
		return
	details_layer.show()
	_details_open = true
	_focus_guard.capture(details_layer)
	detail_close.grab_focus()

func _close_details() -> void:
	_cancel_pointer()
	details_layer.hide()
	_details_open = false
	_focus_guard.restore()

func _on_detail_close_pressed() -> void:
	_close_details()

func _on_details_dismiss(event: InputEvent) -> void:
	if _is_press(event):
		get_viewport().set_input_as_handled()
		_close_details()

func _on_reward_choice(entry_id: String, action: String) -> void:
	if _navigating:
		return
	session.choose_battle_reward(entry_id, action)
	_show_next_reward()

func _claim_result() -> void:
	if _navigating or not result_panel.can_claim() or not session.reward_choices_complete():
		return
	var result_id: String = String(session.pending_battle_result.get("result_id", ""))
	if result_id.is_empty():
		return
	_navigating = true
	claim_requested.emit(result_id)

func show_claim_error() -> void:
	_navigating = false
	if result_panel.can_claim():
		result_panel.show_write_error()

func _refresh() -> void:
	if resolver == null:
		return
	arena_presenter.refresh()
	_refresh_actions_visibility()
	_refresh_cooldowns()

func _refresh_actions_visibility() -> void:
	actions.visible = (
		resolver != null and not resolver.is_finished and not _intro_active
		and not _pause_open and (ability_button.visible or attack_button.visible or dodge_button.visible)
	)

func _refresh_cooldowns() -> void:
	if resolver == null:
		return
	attack_button.disabled = (
		resolver.is_finished
		or resolver.hero_attack_cooldown > 0
		or _intro_active
		or _pause_open
	)
	attack_cooldown.value = 1.0 - float(resolver.hero_attack_cooldown) / maxi(1, resolver.hero.definition.attack_cooldown_ticks)
	attack_cooldown.visible = resolver.hero_attack_cooldown > 0 and attack_button.visible
	ability_button.disabled = (
		not resolver.can_request_ability()
		or (not resolver.auto_attack_enabled and resolver.hero_attack_cooldown > 0)
		or _intro_active
		or _pause_open
	)
	var ability: AbilityDefinition = resolver.hero.first_ability()
	if ability != null and ability_button.visible:
		var remaining: int = resolver.hero_ability_cooldown
		var caption: String = ability_button.tooltip_text
		if resolver.ability_queued:
			caption += "\nСледующий удар"
		elif remaining > 0:
			var seconds := ceili(float(remaining) / (Engine.physics_ticks_per_second * _combat_speed()))
			caption += "\nАвто · %d с" % seconds if resolver.auto_ability_enabled else "\n%d с" % seconds
		elif resolver.auto_ability_enabled and not _ability_lesson:
			caption += "\nАвто"
		if ability_button.text != caption:
			ability_button.text = caption
		ability_cooldown.value = 1.0 - float(remaining) / maxi(1, ability.cooldown_ticks)
		ability_cooldown.visible = remaining > 0
	dodge_button.disabled = (
		resolver.is_finished
		or resolver.dodge_cooldown > 0
		or _intro_active
		or _pause_open
	)
	dodge_cooldown.value = 1.0 - float(resolver.dodge_cooldown) / maxi(1, resolver.hero.definition.dodge_cooldown_ticks)
	dodge_cooldown.visible = resolver.dodge_cooldown > 0 and dodge_button.visible

## Число урона у туловища цели, сбоку от полосы HP: обратная связь у события,
## а не в общей строке.
func _spawn_damage_number(target_id: String, amount: int) -> void:
	arena_presenter.spawn_damage_number(target_id, amount)
