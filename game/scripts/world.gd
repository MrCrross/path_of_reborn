extends Control

signal navigate_requested(destination: String)

var session: GameSession

@onready var art_background: TextureRect = %ArtBackground
@onready var hero_label: Label = %HeroLabel
@onready var traces_label: Label = %TracesLabel
@onready var location_label: Label = %LocationLabel
@onready var settings_button: Button = %SettingsButton
@onready var balance_button: Button = %BalanceButton
@onready var hero_sprite: TextureRect = %HeroSprite
@onready var main_action_button: Button = %MainActionButton
@onready var upgrade_button: Button = %UpgradeButton
@onready var locked_label: Label = %LockedLabel
@onready var repeats_button: Button = %RepeatsButton
@onready var inventory_button: Button = %InventoryButton
@onready var checkpoint_button: Button = %CheckpointButton
@onready var characters_button: Button = %CharactersButton
@onready var rest_button: Button = %RestButton
@onready var encounter_sheet: Control = %EncounterSheet
@onready var sheet_rows: VBoxContainer = %SheetRows
@onready var sheet_close: Button = %SheetClose
@onready var travel_button: Button = %TravelButton
@onready var shop_button: Button = %ShopButton

var hero_health: ActorHealthDisplay
var equipment_strip: EquipmentStrip
var details_layer: Control
var details_view: ItemDetailsView
var gates_dialogue: DialogueOverlay
var _travel_actions: HBoxContainer
var _tutorial: ConfirmDialog
var _shown_background: String = ""
var _hero_still_id: String = ""
var _main_enemy_id: String = "moss_slime"
var _navigating: bool = false
var _sheet_open: bool = false
var _inventory_badge: Label
var _balance_exact: bool = false
var _focus_guard := ModalFocus.new()

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	if gates_dialogue != null and gates_dialogue.is_active():
		return true
	if details_layer != null and details_layer.visible:
		_close_item_details()
		return true
	if _sheet_open:
		_close_encounter_sheet()
		return true
	return false

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	UiIcons.apply_texture(settings_button, ArtMap.texture(ArtMap.UI["settings"]), "Настройки")
	settings_button.theme_type_variation = &"HudIconButton"
	settings_button.add_theme_constant_override("icon_max_width", UiIcons.TOUCH_SIZE)
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
	main_action_button.expand_icon = false
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
		checkpoint_button, ArtMap.texture(ArtMap.UI["path_seal"]), "Печать Пути"
	)
	UiIcons.apply(rest_button, "rest", "Отдохнуть · снять Следы")
	var nav_bar: Control = inventory_button.get_parent()
	UiIcons.apply(repeats_button, "repeat", "Повторы и испытание")
	repeats_button.reparent(nav_bar)
	upgrade_button.custom_minimum_size = Vector2(0, 22)
	upgrade_button.add_theme_font_size_override("font_size", 8)
	nav_bar.move_child(checkpoint_button, 0)
	nav_bar.move_child(inventory_button, 1)
	nav_bar.move_child(characters_button, 2)
	var bottom: Control = nav_bar.get_parent()
	_travel_actions = HBoxContainer.new()
	_travel_actions.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(_travel_actions)
	bottom.move_child(_travel_actions, travel_button.get_index())
	for route_button: Button in [travel_button, shop_button]:
		route_button.reparent(_travel_actions, false)
		route_button.custom_minimum_size.x = 64
	equipment_strip = EquipmentStrip.new()
	equipment_strip.name = "EquipmentStrip"
	nav_bar.get_parent().add_child(equipment_strip)
	nav_bar.get_parent().move_child(equipment_strip, main_action_button.get_index())
	equipment_strip.configure(session, "world")
	nav_bar.get_parent().move_child(upgrade_button, maxi(0, nav_bar.get_index() - 1))
	equipment_strip.item_requested.connect(_open_equipment_details)
	equipment_strip.empty_slot_requested.connect(func(_slot_id: String) -> void: navigate_requested.emit("inventory"))
	equipment_strip.familiar_requested.connect(func(_character_id: String) -> void: _on_hero_profile_pressed())
	_build_item_details()
	_build_inventory_badge()
	hero_health = ActorHealthDisplay.new()
	hero_health.name = "HeroHealth"
	hero_health.setup("hero")
	add_child(hero_health)
	gates_dialogue = DialogueOverlay.new()
	gates_dialogue.name = "GatesDialogue"
	gates_dialogue.configure(session)
	gates_dialogue.command_requested.connect(_on_dialogue_command)
	gates_dialogue.finished.connect(_on_gates_finished)
	add_child(gates_dialogue)
	_refresh()
	session.profile_changed.connect(_refresh_hero_art)
	_refresh_hero_art()
	if not resized.is_connected(_layout_scene):
		resized.connect(_layout_scene)
	inventory_button.grab_focus()
	_try_start_gates_dialogue()
	_show_trail_tutorial.call_deferred()

func _build_item_details() -> void:
	details_layer = Control.new()
	details_layer.name = "ItemDetailsLayer"
	details_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	details_layer.visible = false
	add_child(details_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_item_details_dismiss)
	details_layer.add_child(dim)
	details_view = ItemDetailsView.new()
	details_view.name = "ItemDetails"
	details_view.anchor_left = 0.5
	details_view.anchor_top = 0.5
	details_view.anchor_right = 0.5
	details_view.anchor_bottom = 0.5
	details_view.offset_left = -76.0
	details_view.offset_top = -100.0
	details_view.offset_right = 76.0
	details_view.offset_bottom = 100.0
	details_layer.add_child(details_view)
	details_view.configure(session)
	details_view.close_requested.connect(_close_item_details)

func _open_equipment_details(instance_id: String) -> void:
	if not details_view.present_instance(instance_id):
		return
	details_layer.show()
	_focus_guard.capture(details_layer)
	details_view.close_button.grab_focus()

func _close_item_details() -> void:
	details_layer.hide()
	_focus_guard.restore()
	inventory_button.grab_focus()

func _on_item_details_dismiss(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		_close_item_details()

## Badge сумки: доступное улучшение или новые вещи после claim. Ведёт в
## существующий экран сумки, где живёт и выбор улучшения.
func _build_inventory_badge() -> void:
	_inventory_badge = Label.new()
	_inventory_badge.name = "InventoryBadge"
	_inventory_badge.text = "!"
	_inventory_badge.add_theme_font_size_override("font_size", 8)
	_inventory_badge.add_theme_color_override("font_color", Color("1a1208"))
	_inventory_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory_badge.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.949, 0.761, 0.306, 1)
	bg.corner_radius_top_left = 5
	bg.corner_radius_top_right = 5
	bg.corner_radius_bottom_right = 5
	bg.corner_radius_bottom_left = 5
	_inventory_badge.add_theme_stylebox_override("normal", bg)
	inventory_button.add_child(_inventory_badge)

func _refresh_hero_art() -> void:
	var still_id: String = ArtMap.hero_still_id(session.inventory)
	if still_id == _hero_still_id:
		return
	_hero_still_id = still_id
	hero_sprite.texture = ArtMap.texture(ArtMap.SOURCE_STILLS[still_id]["path"])
	_layout_scene()

func _layout_scene() -> void:
	var view := Rect2(Vector2.ZERO, size)
	var anchor := SceneStaging.hero_anchor(size)
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
	if _inventory_badge != null:
		_inventory_badge.position = Vector2(inventory_button.size.x - 9, -2)

func _on_main_action_pressed() -> void:
	if _navigating or _sheet_open or gates_dialogue.is_active() or is_instance_valid(_tutorial):
		return
	# Лиорен — безопасная зона: свободное касание по городу не начинает бой.
	if session.location_id == GameSession.LOCATION_LIOREN:
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
	if session.route_completed() and _main_enemy_id.is_empty():
		_open_encounter_sheet()
		return
	if session.select_encounter(_main_enemy_id):
		_navigating = true
		main_action_button.disabled = true
		navigate_requested.emit("combat")

func _on_repeats_pressed() -> void:
	if _navigating:
		return
	_open_encounter_sheet()

func _on_sheet_enemy_pressed(enemy_id: String) -> void:
	if _navigating:
		return
	if session.select_encounter(enemy_id, enemy_id != GameSession.TRIAL_ENEMY_ID):
		_close_encounter_sheet()
		_navigating = true
		navigate_requested.emit("combat")

func _on_travel_pressed() -> void:
	if _navigating or gates_dialogue.is_active():
		return
	var target: String = (
		GameSession.LOCATION_FOREST_EDGE
		if session.location_id == GameSession.LOCATION_LIOREN
		else GameSession.LOCATION_LIOREN
	)
	if not session.travel_to(target):
		return
	_refresh()
	_layout_scene()
	if session.location_id == GameSession.LOCATION_LIOREN:
		_try_start_gates_dialogue()
	else:
		_show_trail_tutorial()

func _on_shop_pressed() -> void:
	if _navigating or not session.can_trade():
		return
	navigate_requested.emit("shop")

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
	if gates_dialogue.is_active():
		return
	# Сцена ворот принадлежит Лиорену: на Тропе экран мира может открываться
	# сразу после подарка, и диалог не должен блокировать переезд «В Лиорен».
	if session.location_id != GameSession.LOCATION_LIOREN:
		return
	if not session.story_rewards.has(GameSession.DAIJIRO_SWORD_REWARD_ID):
		return
	if session.shop_access_unlocked():
		return
	if gates_dialogue.play("res://data/narrative/lioren_gates.json", "В лавку", true):
		$Margin.hide()
		hero_sprite.hide()
		hero_health.hide()

func _on_gates_finished(_destination: String) -> void:
	navigate_requested.emit("shop")

func _show_trail_tutorial() -> void:
	if session.location_id != GameSession.LOCATION_FOREST_EDGE or session.awaiting_return or session.traces == 3:
		return
	if session.trial_encounter_available() and not session.trial_echo_claimed:
		_tutorial = ConfirmDialog.tutorial(self, session, "tutorial_trail_trial", "Испытание на Тропе",
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
	session.checkpoints.notify_movement()
	navigate_requested.emit("checkpoint")

func _on_rest_pressed() -> void:
	if session.checkpoints.rest():
		_refresh()
		_layout_scene()

func _gui_input(event: InputEvent) -> void:
	# Касание/клик по свободной игровой области начинает следующую встречу.
	# STOP-контролы (навигация, слоты, листы) обрабатывают своё раньше.
	var pressed: bool = event is InputEventScreenTouch and event.pressed
	pressed = pressed or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION)
	if pressed:
		accept_event()
		_on_main_action_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if _sheet_open or details_layer.visible or gates_dialogue.is_active() or is_instance_valid(_tutorial):
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

## --- Sheet выбора встречи: повторы и испытание, добровольно ---

func _open_encounter_sheet() -> void:
	for child: Node in sheet_rows.get_children():
		sheet_rows.remove_child(child)
		child.queue_free()
	for enemy_id: String in session.route_repeat_enemy_ids():
		sheet_rows.add_child(_sheet_button(
			"Повторить: %s" % UiText.enemy_name(enemy_id),
			enemy_id
		))
	if session.trial_encounter_available():
		var trial_bonus: String = "первый раз: суммарно +2 Эхо" if not session.trial_echo_claimed else "Эхо за первый раз уже получено"
		sheet_rows.add_child(_sheet_button(
			"Испытание: %s — %s; Эхо не откатывается Печатью" % [UiText.enemy_name(GameSession.TRIAL_ENEMY_ID), trial_bonus],
			GameSession.TRIAL_ENEMY_ID
		))
	if sheet_rows.get_child_count() == 0:
		return
	encounter_sheet.show()
	_sheet_open = true
	_focus_guard.capture(encounter_sheet)
	sheet_close.grab_focus()

func _sheet_button(label: String, enemy_id: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 26)
	button.add_theme_font_size_override("font_size", 9)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(_on_sheet_enemy_pressed.bind(enemy_id))
	return button

func _close_encounter_sheet() -> void:
	encounter_sheet.hide()
	_sheet_open = false
	_focus_guard.restore()
	inventory_button.grab_focus()

func _on_sheet_close_pressed() -> void:
	_close_encounter_sheet()

func _on_sheet_dismiss(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		_close_encounter_sheet()

func _refresh() -> void:
	var background_key: String = "world_lioren" if session.location_id == "lioren" else "world_forest_edge"
	if background_key != _shown_background:
		_shown_background = background_key
		art_background.texture = ArtMap.texture(ArtMap.BACKGROUNDS[background_key])
	hero_label.text = "Ур. %d" % session.hero.level
	balance_button.text = UiText.astra_compact(session.wallet[GameSession.COPPER])
	var balance_width: float = ceilf(balance_button.get_combined_minimum_size().x)
	var side_width: float = maxf(48.0, balance_width)
	balance_button.offset_left = -balance_width
	balance_button.get_parent_control().custom_minimum_size.x = side_width
	settings_button.get_parent_control().custom_minimum_size.x = side_width
	balance_button.tooltip_text = UiText.wallet(session.wallet)
	balance_button.accessibility_name = "Баланс: " + balance_button.tooltip_text
	traces_label.text = balance_button.tooltip_text if _balance_exact else "Следы %d/3 · Эхо %d" % [session.traces, session.echoes]
	traces_label.visible = _balance_exact or session.traces > 0 or session.echoes > 0
	location_label.text = UiText.location(session.location_id)
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
		main_action_button.text = "Выбор встречи"
		main_action_button.tooltip_text = "Повторы и испытание"
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

	repeats_button.tooltip_text = "Повторы и испытание"
	repeats_button.accessibility_name = repeats_button.tooltip_text
	var in_city: bool = session.location_id == GameSession.LOCATION_LIOREN
	repeats_button.visible = not in_city and not combat_blocked and not session.route_repeat_enemy_ids().is_empty()
	var has_daijiro_sword: bool = session.story_rewards.has(GameSession.DAIJIRO_SWORD_REWARD_ID)
	travel_button.visible = (in_city or has_daijiro_sword) and not session.awaiting_return
	travel_button.disabled = in_city and session.traces == 3
	travel_button.text = "На Тропу" if in_city else "В Лиорен"
	travel_button.accessibility_name = travel_button.text
	shop_button.visible = session.can_trade()
	_travel_actions.visible = travel_button.visible or shop_button.visible
	rest_button.visible = session.location_id == "lioren" and session.traces > 0
	_inventory_badge.visible = session.hero.pending_upgrade_choices > 0 or session.pending_receive_fx
	upgrade_button.visible = session.hero.pending_upgrade_choices > 0 and not combat_blocked
	upgrade_button.text = "Выбрать улучшение · %d" % session.hero.pending_upgrade_choices
