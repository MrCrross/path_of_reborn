extends Control

signal navigate_requested(destination: String)
signal grove_command_requested(command: String)
signal hollow_command_requested(command: String)
signal outpost_command_requested(command: String)
signal guild_order_requested(command: String, order_id: String)

var session: GameSession

@onready var art_background: TextureRect = %ArtBackground
@onready var hero_label: Label = %HeroLabel
@onready var traces_label: Label = %TracesLabel
@onready var location_label: Label = %LocationLabel
@onready var settings_button: Button = %SettingsButton
@onready var balance_button: Button = %BalanceButton
@onready var _top_left: Control = settings_button.get_parent_control()
@onready var hero_sprite: TextureRect = %HeroSprite
@onready var main_action_button: Button = %MainActionButton
@onready var upgrade_button: Button = %UpgradeButton
@onready var locked_label: Label = %LockedLabel
@onready var repeats_button: Button = %RepeatsButton
@onready var inventory_button: Button = %InventoryButton
@onready var checkpoint_button: Button = %CheckpointButton
@onready var characters_button: Button = %CharactersButton
@onready var rest_button: Button = %RestButton
@onready var map_button: Button = %MapButton

var hero_health: ActorHealthDisplay
var equipment_strip: EquipmentStrip
@onready var details_layer: ItemDetailsOverlay = %ItemDetailsLayer
@onready var details_view: ItemDetailsView = details_layer.view
var gates_dialogue: DialogueOverlay
var grove_route: GroveRouteView
var hollow_route: HollowRouteView
var outpost_route: OutpostRouteView
var focus_map_on_entry: bool = false
var _shown_background: String = ""
var _hero_still_id: String = ""
var _main_enemy_id: String = "moss_slime"
var _navigating: bool = false
var _balance_exact: bool = false
var _order_progress: Label
var _story_frame: bool = false

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	if grove_route != null and grove_route.close_dialogue():
		return true
	if hollow_route != null and hollow_route.close_dialogue():
		return true
	if outpost_route != null and outpost_route.close_dialogue():
		return true
	if gates_dialogue != null and gates_dialogue.is_active():
		return true
	if details_layer != null and details_layer.visible:
		details_layer.dismiss()
		return true
	if session.location_id == GameSession.LOCATION_GUILD_ORDER:
		_on_order_destination("leave")
		return true
	if session.location_id in GameSession.EXPEDITION_LOCATIONS:
		_on_map_pressed()
		return true
	return false

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	UiIcons.apply_texture(settings_button, ArtMap.texture(ArtMap.UI["settings"]), "Настройки")
	settings_button.theme_type_variation = &"HudIconButton"
	UiIcons.tint(settings_button, Color.WHITE)
	balance_button.icon = UiIcons.astra(GameSession.COPPER)
	balance_button.add_theme_constant_override("icon_max_width", 16)
	balance_button.expand_icon = false
	UiIcons.tint(balance_button, Color.WHITE)
	traces_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Одно главное действие продвижения: tap/касание по свободной области экрана.
	# Видимая кнопка не дублирует жест; программный остаток хранит текст,
	# доступное состояние и клавиатурный focus-path.
	main_action_button.text = "Следующая встреча"
	main_action_button.tooltip_text = "Касание по свободной области начинает следующую встречу"
	main_action_button.accessibility_name = main_action_button.tooltip_text
	main_action_button.hide()
	main_action_button.focus_mode = Control.FOCUS_ALL
	main_action_button.icon = UiIcons.texture("next")
	main_action_button.add_theme_constant_override("icon_max_width", 12)
	main_action_button.expand_icon = true
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box: StyleBoxFlat = main_action_button.get_theme_stylebox(state).duplicate()
		box.expand_margin_left = -24.0
		box.expand_margin_right = -24.0
		box.expand_margin_top = -3.0
		box.expand_margin_bottom = -3.0
		main_action_button.add_theme_stylebox_override(state, box)
	UiIcons.apply(inventory_button, "inventory", "Рюкзак")
	UiIcons.apply_texture(characters_button, ArtMap.texture(ArtMap.UI["characters"]), "Персонажи")
	UiIcons.apply_texture(
		checkpoint_button, ArtMap.texture(ArtMap.UI["path_seal_nav"]), "Печать Пути"
	)
	UiIcons.apply(rest_button, "rest", "Отдохнуть · снять Следы")
	UiIcons.apply(map_button, "path", "Карта мира")
	var nav_bar: Control = inventory_button.get_parent()
	UiIcons.apply(repeats_button, "repeat", "Случайный бой")
	upgrade_button.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	upgrade_button.add_theme_font_size_override("font_size", 8)
	var bottom: Control = nav_bar.get_parent()
	if session.location_id in GameSession.EXPEDITION_LOCATIONS or session.location_id == GameSession.LOCATION_GUILD_ORDER:
		_order_progress = Label.new()
		_order_progress.name = "StoryOrderProgress"
		_order_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_order_progress.add_theme_font_size_override("font_size", 8)
		_order_progress.add_theme_color_override("font_outline_color", AppTheme.COLOR_PANEL)
		_order_progress.add_theme_constant_override("outline_size", 4)
		bottom.add_child(_order_progress)
	equipment_strip = EquipmentStrip.new()
	equipment_strip.name = "EquipmentStrip"
	nav_bar.get_parent().add_child(equipment_strip)
	nav_bar.get_parent().move_child(equipment_strip, main_action_button.get_index())
	equipment_strip.configure(session, "world")
	nav_bar.get_parent().move_child(upgrade_button, maxi(0, nav_bar.get_index() - 1))
	equipment_strip.item_requested.connect(details_layer.open_instance)
	equipment_strip.empty_slot_requested.connect(func(_slot_id: String) -> void: navigate_requested.emit("inventory"))
	equipment_strip.familiar_requested.connect(func(_character_id: String) -> void: _on_hero_profile_pressed())
	details_view.configure(session)
	hero_health = ActorHealthDisplay.new()
	hero_health.name = "HeroHealth"
	hero_health.setup("hero")
	add_child(hero_health)
	move_child(hero_health, hero_sprite.get_index() + 1)
	gates_dialogue = DialogueOverlay.new()
	gates_dialogue.name = "GatesDialogue"
	gates_dialogue.configure(session)
	gates_dialogue.command_requested.connect(_on_dialogue_command)
	gates_dialogue.finished.connect(_on_gates_finished)
	add_child(gates_dialogue)
	if session.location_id == GameSession.LOCATION_GROVE:
		grove_route = GroveRouteView.new()
		add_child(grove_route)
		grove_route.configure(session, self, bottom, map_button, art_background)
		grove_route.command_requested.connect(func(command: String) -> void: grove_command_requested.emit(command))
		grove_route.checkpoint_requested.connect(_on_checkpoint_pressed)
		grove_route.encounter_requested.connect(_on_grove_encounter)
		grove_route.dialogue_visibility_changed.connect(_show_grove_dialogue_shot)
		grove_route.refresh.call_deferred()
	elif session.location_id == GameSession.LOCATION_HOLLOW:
		hollow_route = HollowRouteView.new()
		add_child(hollow_route)
		hollow_route.configure(session, self, bottom, map_button, art_background)
		hollow_route.command_requested.connect(func(command: String) -> void: hollow_command_requested.emit(command))
		hollow_route.checkpoint_requested.connect(_on_checkpoint_pressed)
		hollow_route.encounter_requested.connect(_on_grove_encounter)
		hollow_route.shot_changed.connect(_show_grove_dialogue_shot)
		hollow_route.refresh.call_deferred()
	elif session.location_id == GameSession.LOCATION_OUTPOST:
		outpost_route = OutpostRouteView.new()
		add_child(outpost_route)
		outpost_route.configure(session, self, bottom, map_button, art_background)
		outpost_route.command_requested.connect(func(command: String) -> void: outpost_command_requested.emit(command))
		outpost_route.encounter_requested.connect(_on_grove_encounter)
		outpost_route.shot_changed.connect(_show_grove_dialogue_shot)
		outpost_route.refresh.call_deferred()
	elif session.location_id == GameSession.LOCATION_GUILD_ORDER:
		%OrderActions.show()
		%OrderFight.pressed.connect(_on_order_fight)
		%OrderToReport.pressed.connect(_on_order_destination.bind("leave"))
		%OrderGuild.pressed.connect(_on_order_destination.bind("leave"))
		%OrderShop.pressed.connect(_on_order_destination.bind("shop"))
	if _order_progress != null:
		bottom.move_child(_order_progress, -1)
	bottom.move_child(nav_bar, -1)
	_refresh()
	session.profile_changed.connect(_refresh_hero_art)
	_refresh_hero_art()
	if not resized.is_connected(_layout_scene):
		resized.connect(_layout_scene)
	if focus_map_on_entry:
		_focus_map.call_deferred()
	elif %OrderActions.visible:
		var action: Button = %OrderFight if %OrderFight.visible else %OrderToReport
		action.grab_focus()
	else:
		inventory_button.grab_focus()
	_try_start_gates_dialogue()
	_show_trail_tutorial.call_deferred()

func _focus_map() -> void:
	if not _has_modal():
		map_button.grab_focus()


func _refresh_hero_art() -> void:
	var still_id: String = ArtMap.hero_still_id(session.inventory)
	if still_id == _hero_still_id:
		return
	_hero_still_id = still_id
	hero_sprite.texture = ArtMap.texture(ArtMap.SOURCE_STILLS[still_id]["path"])
	_layout_scene()

func _layout_scene() -> void:
	var view := Rect2(Vector2.ZERO, size)
	var anchor: Vector2 = SceneStaging.grove_hero_anchor(size) if session.location_id in GameSession.EXPEDITION_LOCATIONS else SceneStaging.hero_anchor(size)
	var scale: float = ArtMap.still_scale(_hero_still_id)
	var pivot: Vector2 = ArtMap.SOURCE_STILLS[_hero_still_id]["pivot"]
	if hero_sprite.texture != null:
		hero_sprite.size = hero_sprite.texture.get_size() * scale
	# Точка опоры ног (pivot: середина solid по X, низ solid по Y) стоит на anchor.
	hero_sprite.position = Vector2(
		anchor.x - pivot.x * scale,
		anchor.y - pivot.y * scale
	).round()
	# Полоса HP над головой: верх solid силуэта — HERO_SOLID_HEIGHT над опорой.
	hero_health.follow(anchor + Vector2(0, -SceneStaging.HERO_SOLID_HEIGHT), view)

func _on_main_action_pressed() -> void:
	if _navigating or details_layer.visible or gates_dialogue.is_active() or ConfirmDialog.has_open(self):
		return
	# Лиорен — безопасная зона: свободное касание по городу не начинает бой.
	if session.location_id != GameSession.LOCATION_FOREST_EDGE:
		return
	if not session.pending_story_reward.is_empty():
		navigate_requested.emit("merchant")
		return
	var approach: String = session.next_route_approach()
	if not approach.is_empty():
		_navigating = true
		main_action_button.disabled = true
		navigate_requested.emit("merchant" if approach == "daijiro_cart" else "trail_dialogue")
		return
	if _main_enemy_id.is_empty():
		_on_repeats_pressed()
	elif session.select_encounter(_main_enemy_id):
		_enter_combat()

func _enter_combat() -> void:
	_navigating = true
	main_action_button.disabled = true
	repeats_button.disabled = true
	navigate_requested.emit("combat")

func _show_grove_dialogue_shot(active: bool, bridge_shot: bool) -> void:
	$Margin.visible = not active
	_story_frame = bridge_shot
	_refresh_upgrade_button()
	hero_label.get_parent_control().visible = not bridge_shot
	balance_button.get_parent_control().visible = not bridge_shot
	traces_label.visible = not bridge_shot and (_balance_exact or session.traces > 0 or session.echoes > 0)
	hero_sprite.visible = not bridge_shot
	hero_health.visible = not bridge_shot and session.hero.current_hp < session.hero.max_hp

func _on_grove_encounter(enemy_id: String) -> void:
	if not _navigating and session.select_encounter(enemy_id):
		_navigating = true
		navigate_requested.emit("combat")

func grove_command_committed(command: String) -> void:
	if grove_route != null:
		_refresh()
		grove_route.committed(command)

func grove_command_rejected(command: String) -> void:
	if grove_route != null:
		grove_route.rejected(command)

func hollow_command_committed(_command: String) -> void:
	if hollow_route != null:
		_refresh()
		hollow_route.refresh()

func hollow_command_rejected(command: String) -> void:
	if hollow_route != null:
		hollow_route.rejected(command)

func outpost_command_committed(_command: String) -> void:
	if outpost_route != null:
		_refresh()
		outpost_route.refresh()

func outpost_command_rejected(command: String) -> void:
	outpost_route.rejected(command)

func _on_repeats_pressed() -> void:
	if _navigating or details_layer.visible or gates_dialogue.is_active() or ConfirmDialog.has_open(self):
		return
	if session.select_random_repeat_encounter():
		_enter_combat()

func _on_order_destination(command: String) -> void:
	guild_order_requested.emit(command, session.guild_order["id"])

func command_rejected() -> void:
	locked_label.text = "Действие не сохранено. Попробуйте ещё раз."
	locked_label.show()
	locked_label.get_parent().show()

func _on_order_fight() -> void:
	if session.select_encounter(session.guild_order_stage().get("enemy_id", "")):
		_enter_combat()

func _on_map_pressed() -> void:
	if _navigating or _has_modal():
		return
	navigate_requested.emit("world_map")

func _on_dialogue_command(command: Dictionary) -> void:
	var key: String = String(command.get("key", ""))
	if command.get("type", "") == "set_world_flag":
		session.world_flags[key] = command.get("value")
	elif command.get("type", "") == "set_npc_flag":
		session.npc_flags[key] = command.get("value")

## Сцена ворот играет при первом въезде в Лиорен с выданным мечом. Возобновление
## после закрытия приложения — естественное: вход определяется флагом лавки, а
## прочитанные реплики пропускаются runner'ом.
func _try_start_gates_dialogue() -> void:
	if gates_dialogue.is_active() or not session.should_show_lioren_gates():
		return
	if gates_dialogue.play("res://data/narrative/lioren_gates.json", "К карте Лиорена", true):
		$Margin.hide()
		hero_sprite.hide()
		hero_health.hide()

func _on_gates_finished(destination: String) -> void:
	navigate_requested.emit(destination)

func _show_trail_tutorial() -> void:
	if session.location_id != GameSession.LOCATION_FOREST_EDGE or session.awaiting_return or session.traces == 3:
		return
	if session.trial_encounter_available() and not session.trial_echo_claimed:
		ConfirmDialog.tutorial(self, session, "tutorial_trail_trial", "Испытание на Тропе",
			"Разведчик отступил. Перед усиленным гоблином можно выбрать улучшение. Здоровье восстановится перед следующим боем.")

func _on_settings_pressed() -> void:
	navigate_requested.emit("settings")

func _on_balance_pressed() -> void:
	_balance_exact = not _balance_exact
	_refresh()

func _on_inventory_pressed() -> void:
	navigate_requested.emit("inventory")

func _on_characters_pressed() -> void:
	navigate_requested.emit("characters")

func _on_hero_profile_pressed() -> void:
	navigate_requested.emit("hero_profile")

func _on_checkpoint_pressed() -> void:
	if not session.can_place_expedition_checkpoint():
		return
	session.checkpoints.notify_movement()
	navigate_requested.emit("checkpoint")

func _on_rest_pressed() -> void:
	if session.checkpoints.rest():
		_refresh()
		_layout_scene()

func _gui_input(event: InputEvent) -> void:
	# Касание/клик по свободной игровой области начинает следующую встречу.
	# STOP-контролы (навигация, слоты) обрабатывают своё раньше.
	var pressed: bool = event is InputEventScreenTouch and event.pressed
	pressed = pressed or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION)
	if pressed:
		accept_event()
		_on_main_action_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if _has_modal():
		return
	if event.is_action_pressed("primary"):
		get_viewport().set_input_as_handled()
		_on_main_action_pressed()
	elif event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		_on_inventory_pressed()
	elif event.is_action_pressed("checkpoint"):
		get_viewport().set_input_as_handled()
		_on_checkpoint_pressed()

func _has_modal() -> bool:
	return details_layer.visible or gates_dialogue.is_active() or ConfirmDialog.has_open(self) or (
		(grove_route != null and grove_route.dialogue.is_active())
		or (hollow_route != null and hollow_route.dialogue.is_active())
		or (outpost_route != null and outpost_route.dialogue.is_active())
	)

func _refresh() -> void:
	var on_order: bool = session.location_id == GameSession.LOCATION_GUILD_ORDER
	var place: String = session.guild_order_location() if on_order else session.location_id
	if place != _shown_background:
		_shown_background = place
		art_background.texture = ArtMap.world_background(place)
	hero_label.text = "Ур. %d" % session.hero.level
	balance_button.text = UiText.astra_compact(session.wallet[GameSession.COPPER])
	var balance_width: float = ceilf(balance_button.get_combined_minimum_size().x)
	var side_width: float = maxf(48.0, balance_width)
	balance_button.offset_left = -balance_width
	balance_button.get_parent_control().custom_minimum_size.x = side_width
	_top_left.custom_minimum_size.x = side_width
	balance_button.tooltip_text = UiText.wallet(session.wallet)
	balance_button.accessibility_name = "Баланс: " + balance_button.tooltip_text
	traces_label.text = balance_button.tooltip_text if _balance_exact else "Следы %d/3 · Эхо %d" % [session.traces, session.echoes]
	traces_label.visible = _balance_exact or session.traces > 0 or session.echoes > 0
	location_label.text = "Роща" if place == GameSession.LOCATION_GROVE else UiText.location(place)
	location_label.tooltip_text = UiText.location(place)
	var combat_blocked: bool = session.awaiting_return or session.traces == 3

	# HP героя на пути: полоса появляется после урона, при полном здоровье скрыта.
	hero_health.set_hp(session.hero.current_hp, session.hero.max_hp)
	hero_health.visible = session.hero.current_hp < session.hero.max_hp

	var node: Dictionary = session.next_route_node()
	if not node.is_empty():
		_main_enemy_id = String(node.get("enemy_id", ""))
		main_action_button.text = "Следующая встреча"
		main_action_button.tooltip_text = "Касание по свободной области начинает следующую встречу"
	elif session.trial_encounter_available() and not session.trial_echo_claimed:
		_main_enemy_id = GameSession.TRIAL_ENEMY_ID
		main_action_button.text = "К испытанию"
		main_action_button.tooltip_text = "Следующий вызов: усиленный гоблин"
	else:
		_main_enemy_id = ""
		main_action_button.text = "Случайный бой"
		main_action_button.tooltip_text = "Касание по свободной области начинает бой со знакомым врагом"
	main_action_button.disabled = combat_blocked or _navigating
	if combat_blocked:
		locked_label.text = (
			"Вернитесь через Печать Пути."
			if session.awaiting_return
			else "Следы 3/3 — нужен отдых в Лиорене."
		)
	else:
		locked_label.text = ""
	locked_label.visible = not locked_label.text.is_empty()
	locked_label.get_parent().visible = locked_label.visible

	var in_city: bool = session.location_id == GameSession.LOCATION_LIOREN
	var in_expedition: bool = session.location_id in GameSession.EXPEDITION_LOCATIONS
	if on_order:
		var stage: Dictionary = session.guild_order_stage()
		var contract: Dictionary = GuildOrders.definition(session.guild_order["id"])
		%OrderFight.visible = not stage.is_empty()
		%OrderFight.disabled = combat_blocked or _navigating
		%OrderToReport.visible = stage.is_empty()
		%OrderGuild.visible = not stage.is_empty()
		%OrderObjective.visible = not stage.is_empty()
		%OrderObjective.text = stage.get("objective", "")
		_order_progress.text = "%s · %s · %d/%d" % [contract["rank"], contract["title"], session.guild_order["cleared"], session.guild_order["total"]]
		_order_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elif _order_progress != null:
		var order: Dictionary = session.story_order(session.location_id)
		_order_progress.text = "%s · Бои %d/%d" % [order["rank"], int(order["cleared"]), order["nodes"].size()]
	equipment_strip.set_suppressed(in_city or in_expedition or on_order)
	checkpoint_button.visible = session.can_place_expedition_checkpoint()
	repeats_button.visible = not session.route_repeat_enemy_ids().is_empty()
	repeats_button.disabled = _navigating
	rest_button.visible = session.location_id == "lioren" and session.traces > 0
	_refresh_upgrade_button()

func _refresh_upgrade_button() -> void:
	upgrade_button.visible = not _story_frame and session.hero.pending_upgrade_choices > 0 and not session.awaiting_return and session.traces < 3
	upgrade_button.text = "Выбрать улучшение · %d" % session.hero.pending_upgrade_choices
