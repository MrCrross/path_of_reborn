extends Control

signal navigate_requested(destination: String)
signal story_claim_requested(reward_id: String)

var session: GameSession
var gift_layer: Control
var details_view: ItemDetailsView
var store_button: Button
var equip_button: Button
var dialogue: DialogueOverlay
var after_panel: PanelContainer
var _intro: bool = false
var _claiming: bool = false
var _cart: TextureRect
var _haruto: TextureRect
var _daijiro: TextureRect

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	_build_scene()
	if not session.pending_story_reward.is_empty():
		_show_gift()
	elif session.story_rewards.has(GameSession.DAIJIRO_SWORD_REWARD_ID):
		after_panel.show()
	elif session.world_flags.get("daijiro_introduction_completed", false) and session.prepare_daijiro_sword_reward():
		_show_gift()
	else:
		_start_dialogue()

func _build_scene() -> void:
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var scout_defeated: bool = session.world_flags.get("daijiro_scout_defeated", false)
	background.texture = ArtMap.texture(
		ArtMap.BACKGROUNDS["world_forest_edge"] if scout_defeated else ArtMap.PROLOGUE_SHOTS["daijiro_cart"]
	)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	if scout_defeated:
		_cart = _add_story_art(ArtMap.DAIJIRO_CART_PROP)
		_haruto = _add_story_art(ArtMap.HERO_EXILED_STILL)
		_daijiro = _add_story_art(ArtMap.DAIJIRO_MERCHANT_STILL)
		resized.connect(_place_aftermath_art)
		_place_aftermath_art()
	dialogue = DialogueOverlay.new()
	dialogue.name = "Dialogue"
	dialogue.configure(session)
	dialogue.command_requested.connect(_on_command)
	dialogue.finished.connect(_on_dialogue_finished)
	add_child(dialogue)
	_build_after_panel()
	_build_gift()

func _add_story_art(path: String) -> TextureRect:
	var art := TextureRect.new()
	art.texture = ArtMap.texture(path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	return art

func _place_aftermath_art() -> void:
	var ground := SceneStaging.floor_y(size.y)
	_place_art(_cart, Vector2(size.x * 0.75, ground - 18), Vector2(180, 215), 0.25)
	_place_art(_haruto, SceneStaging.hero_anchor(size), ArtMap.SOURCE_STILLS["haruto_exiled"]["pivot"], ArtMap.still_scale("haruto_exiled"))
	_place_art(_daijiro, Vector2(size.x * 0.61, ground), Vector2(144, 371), 0.25)

func _place_art(art: TextureRect, anchor: Vector2, pivot: Vector2, scale: float) -> void:
	art.size = art.texture.get_size() * scale
	art.position = (anchor - pivot * scale).round()

## Состояние после выданного меча: торговля живёт в лавке Лиорена.
func _build_after_panel() -> void:
	after_panel = PanelContainer.new()
	after_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	after_panel.offset_left = 7
	after_panel.offset_right = -7
	after_panel.offset_top = -36
	after_panel.offset_bottom = -7
	after_panel.theme_type_variation = &"HudPanel"
	add_child(after_panel)
	var after_button := Button.new()
	after_button.text = "Вернуться на тропу"
	after_button.custom_minimum_size = Vector2(0, 28)
	after_button.theme_type_variation = &"PrimaryButton"
	after_button.pressed.connect(func() -> void: navigate_requested.emit("world"), CONNECT_ONE_SHOT)
	after_panel.add_child(after_button)
	after_panel.hide()

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

func _start_dialogue() -> void:
	_intro = not session.world_flags.get("daijiro_intervened", false)
	var path: String = "res://data/narrative/merchant_intro.json" if _intro else "res://data/narrative/merchant_after.json"
	var caption: String = "Вмешаться" if _intro else ""
	if not dialogue.play(path, caption, true):
		after_panel.show()

func _on_command(command: Dictionary) -> void:
	var key: String = String(command.get("key", ""))
	if command.get("type", "") == "set_world_flag":
		session.world_flags[key] = command.get("value")
	elif command.get("type", "") == "set_npc_flag":
		session.npc_flags[key] = command.get("value")

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

func retry_gift() -> void:
	_claiming = false
	store_button.disabled = false
	equip_button.disabled = false
	store_button.grab_focus()
