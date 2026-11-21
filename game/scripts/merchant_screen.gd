extends Control

signal navigate_requested(destination: String)
signal story_claim_requested(reward_id: String)
signal sale_requested(instance_id: String, quantity: int)

var session: GameSession
var runner: DialogueRunner
var speaker_label: Label
var story_text: Label
var next_button: Button
var gift_layer: Control
var details_view: ItemDetailsView
var store_button: Button
var equip_button: Button
var sale_list: VBoxContainer
var _intro: bool = false
var _claiming: bool = false

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	_build_scene()
	if not session.pending_story_reward.is_empty():
		_show_gift()
	elif session.story_rewards.has(GameSession.DAIJIRO_SWORD_REWARD_ID):
		speaker_label.text = "Дайдзиро"
		story_text.text = "Меч уже твой. С кристаллами помогу у телеги или в Лиорене."
		next_button.text = "Вернуться на тропу"
		next_button.pressed.connect(func() -> void: navigate_requested.emit("world"), CONNECT_ONE_SHOT)
		_refresh_sale()
	else:
		_start_dialogue()

func _build_scene() -> void:
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture = ArtMap.texture(ArtMap.PROLOGUE_SHOTS["daijiro_cart"])
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.035, 0.045, 0.16)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var title := Label.new()
	title.text = "Телега Дайдзиро"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", AppTheme.COLOR_TEXT)
	title.add_theme_color_override("font_shadow_color", AppTheme.COLOR_PANEL)
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 7
	add_child(title)
	var panel := PanelContainer.new()
	panel.name = "DialoguePanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 7
	panel.offset_right = -7
	panel.offset_top = -142
	panel.offset_bottom = -7
	panel.theme_type_variation = &"HudPanel"
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	speaker_label = Label.new()
	speaker_label.add_theme_font_size_override("font_size", 8)
	speaker_label.add_theme_color_override("font_color", AppTheme.COLOR_ACCENT_TEXT)
	column.add_child(speaker_label)
	story_text = Label.new()
	story_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	story_text.add_theme_font_size_override("font_size", 9)
	column.add_child(story_text)
	sale_list = VBoxContainer.new()
	sale_list.add_theme_constant_override("separation", 2)
	column.add_child(sale_list)
	next_button = Button.new()
	next_button.text = "Далее"
	next_button.custom_minimum_size = Vector2(0, 28)
	next_button.theme_type_variation = &"PrimaryButton"
	next_button.pressed.connect(_on_next_pressed)
	column.add_child(next_button)
	_build_gift()

func _build_gift() -> void:
	gift_layer = Control.new()
	gift_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gift_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(gift_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.8)
	gift_layer.add_child(dim)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.offset_left = -78
	column.offset_right = 78
	column.offset_top = -132
	column.offset_bottom = 132
	column.add_theme_constant_override("separation", 5)
	gift_layer.add_child(column)
	var heading := Label.new()
	heading.text = "Благодарность Дайдзиро"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 10)
	column.add_child(heading)
	details_view = ItemDetailsView.new()
	details_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(details_view)
	details_view.configure(session, false)
	details_view.close_button.hide()
	var reward: Dictionary = session.pending_story_reward.get("items", [{}])[0]
	details_view.present_reward(String(reward.get("item_id", "training_sword")), String(reward.get("aspect_id", "")), int(reward.get("quantity", 1)), reward)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	store_button = Button.new()
	store_button.text = "В рюкзак"
	store_button.custom_minimum_size = Vector2(0, 30)
	store_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	store_button.pressed.connect(_claim_gift.bind("store"))
	actions.add_child(store_button)
	equip_button = Button.new()
	equip_button.text = "Надеть"
	equip_button.custom_minimum_size = Vector2(0, 30)
	equip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_button.theme_type_variation = &"PrimaryButton"
	equip_button.pressed.connect(_claim_gift.bind("equip"))
	actions.add_child(equip_button)
	gift_layer.hide()

func _refresh_sale() -> void:
	for child: Node in sale_list.get_children():
		sale_list.remove_child(child)
		child.queue_free()
	for item: ItemInstance in session.inventory.filter("echo"):
		if not item.sellable:
			continue
		var button := Button.new()
		button.text = "Продать ×1 · %s" % UiText.astra(item.sale_price_copper)
		button.accessibility_name = "Продать один Кристалл Эха за %s" % UiText.astra(item.sale_price_copper)
		button.custom_minimum_size = Vector2(0, 28)
		button.pressed.connect(sale_requested.emit.bind(item.instance_id, 1))
		sale_list.add_child(button)
	if sale_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Кристаллов для обмена нет"
		empty.add_theme_font_size_override("font_size", 8)
		sale_list.add_child(empty)

func _start_dialogue() -> void:
	_intro = not session.world_flags.get("daijiro_intervened", false)
	runner = DialogueRunner.new()
	runner.configure(session)
	runner.page_character_limit = 96
	var path: String = "res://data/narrative/merchant_intro.json" if _intro else "res://data/narrative/merchant_after.json"
	if not runner.load_file(path):
		story_text.text = "Сцена недоступна."
		next_button.disabled = true
		return
	runner.command_requested.connect(_on_command)
	runner.finished.connect(_on_dialogue_finished)
	runner.changed.connect(_refresh_dialogue)
	runner.start()
	_refresh_dialogue()
	next_button.grab_focus()

func _refresh_dialogue() -> void:
	if runner == null:
		return
	speaker_label.text = runner.current_speaker()
	story_text.text = runner.current_text()
	next_button.text = "Вмешаться" if _intro and runner.index == runner.entries.size() - 1 else "Далее"

func _on_next_pressed() -> void:
	if runner != null:
		runner.tap()

func _on_command(command: Dictionary) -> void:
	var key: String = String(command.get("key", ""))
	if command.get("type", "") == "set_world_flag":
		session.world_flags[key] = command.get("value")
	elif command.get("type", "") == "set_npc_flag":
		session.npc_flags[key] = command.get("value")
	session.profile_changed.emit()

func _on_dialogue_finished(_destination: String) -> void:
	if _intro:
		if session.select_encounter("goblin_scout"):
			navigate_requested.emit("combat")
		return
	if session.prepare_daijiro_sword_reward():
		_show_gift()
	else:
		navigate_requested.emit("world")

func _show_gift() -> void:
	gift_layer.show()
	store_button.grab_focus()

func _claim_gift(action: String) -> void:
	if _claiming or session.pending_story_reward.is_empty():
		return
	var reward: Dictionary = session.pending_story_reward["items"][0]
	if not session.choose_story_reward(String(reward["entry_id"]), action):
		return
	_claiming = true
	store_button.disabled = true
	equip_button.disabled = true
	story_claim_requested.emit(String(session.pending_story_reward["reward_id"]))
