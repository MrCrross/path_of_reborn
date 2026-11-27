class_name OutpostRouteView
extends Node

signal command_requested(command: String)
signal encounter_requested(enemy_id: String)
signal shot_changed(dialogue_active: bool, story_frame: bool)

var session: GameSession
var dialogue: DialogueOverlay
var _background: TextureRect
var _props: Control
var _action: Button
var _error: Label
var _map_button: Button
var _cues: Array[String] = []

func configure(game_session: GameSession, world: Control, bottom: Control, map_button: Button, background: TextureRect) -> void:
	session = game_session
	_map_button = map_button
	_background = background
	_props = Control.new()
	_props.name = "OutpostProps"
	_props.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(_props)
	world.move_child(_props, background.get_index() + 1)
	_props.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_props.resized.connect(_layout_props)
	_action = Button.new()
	_action.name = "OutpostAction"
	_action.theme_type_variation = &"PrimaryButton"
	_action.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	_action.pressed.connect(_on_action)
	bottom.add_child(_action)
	_error = Label.new()
	_error.text = "Запись не удалась. Повторите действие."
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.add_theme_font_size_override("font_size", 8)
	_error.add_theme_color_override("font_color", AppTheme.COLOR_DANGER)
	bottom.add_child(_error)
	_error.hide()
	dialogue = DialogueOverlay.new()
	dialogue.name = "OutpostDialogue"
	dialogue.configure(session)
	world.add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)

func refresh(auto_dialogue: bool = true) -> void:
	for child: Node in _props.get_children():
		_props.remove_child(child)
		child.queue_free()
	var stage: String = session.outpost_stage()
	_cues.assign(GameSession.outpost_node(stage).get("cues", []))
	var captions: Dictionary = {
		"bowl": "Осмотреть сигнальную чашу",
		"seal": "Коснуться знака дозора",
		"ravens": "В бой с воронами",
		"warden": "В бой с дозорным",
		"alliance": "Подтвердить союз",
	}
	_action.text = captions.get(stage, "")
	if not session.seen_cue_ids.has_all(_cues):
		_action.text = "Продолжить разговор"
	_action.disabled = session.traces >= 3
	_error.hide()
	if stage in ["bowl", "seal"]:
		_add_prop("BowlProp", "bowl", Rect2(8, 14, 48, 42), Vector2(32, 28), Vector2(0.75, -5), stage == "bowl")
	if stage == "seal":
		_add_prop("FireSeal", "fire", Rect2(12, 58, 72, 28), Vector2(50, 19), Vector2(0.57, 0))
		_add_prop("WatchSign", "sign", Rect2(4, 6, 40, 36), Vector2(22, 20), Vector2(0.57, -2), true)
	if stage in ["ravens", "warden", "alliance", "return"]:
		_add_prop("Akari", "akari", Rect2(34, 30, 78, 82), Vector2(78, 82), Vector2(0.50, -9))
	_layout_props()
	_show_shot(false)
	_focus_action()
	if auto_dialogue and not _action.disabled and not session.seen_cue_ids.has_all(_cues):
		_play_dialogue()

func close_dialogue() -> bool:
	if not dialogue.is_active():
		return false
	dialogue.stop()
	refresh(false)
	return true

func rejected(_command: String) -> void:
	_error.show()
	_focus_action()

func _on_action() -> void:
	if not session.seen_cue_ids.has_all(_cues):
		_play_dialogue()
		return
	var stage: String = session.outpost_stage()
	match stage:
		"ravens", "warden":
			encounter_requested.emit(GameSession.outpost_node(stage)["enemy_id"])
		_:
			command_requested.emit(stage)

func _play_dialogue() -> void:
	var caption: String = "Согласиться" if session.outpost_stage() == "alliance" else "К бою"
	if dialogue.play(GameSession.OUTPOST_NARRATIVE_PATH, caption, false, {}, _cues):
		dialogue.runner.changed.connect(_show_shot.bind(true))
		_show_shot(true)

func _on_dialogue_finished(_destination: String) -> void:
	refresh(false)
	if session.outpost_stage() == "alliance":
		command_requested.emit("alliance")

func _show_shot(active: bool) -> void:
	var shot: String = dialogue.runner.current_shot() if active and not dialogue.runner.is_finished else "world_outpost"
	_background.texture = ArtMap.texture(ArtMap.BACKGROUNDS[shot])
	var story_frame: bool = shot != "world_outpost"
	_props.visible = not story_frame
	_action.visible = not active and session.outpost_stage() != "return"
	shot_changed.emit(active, story_frame)

func _add_prop(node_name: String, art_id: String, crop: Rect2, dimensions: Vector2, anchor: Vector2, interactive: bool = false) -> void:
	var prop := TextureRect.new()
	prop.name = node_name
	prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prop.texture = ArtMap.crop(ArtMap.OUTPOST_PROPS[art_id], crop)
	prop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prop.size = dimensions
	prop.set_meta("anchor", anchor)
	_props.add_child(prop)
	if not interactive:
		return
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.accessibility_name = _action.text
	hit.disabled = _action.disabled
	prop.add_child(hit)
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var padding: Vector2 = (Vector2.ONE * UiIcons.TOUCH_SIZE - dimensions).max(Vector2.ZERO) * 0.5
	hit.offset_left = -padding.x
	hit.offset_right = padding.x
	hit.offset_top = -padding.y
	hit.offset_bottom = padding.y
	hit.pressed.connect(_on_action)

func _layout_props() -> void:
	for prop: TextureRect in _props.get_children():
		var anchor: Vector2 = prop.get_meta("anchor")
		prop.position = (Vector2(_props.size.x * anchor.x, SceneStaging.floor_y(_props.size.y) + anchor.y) - Vector2(prop.size.x * 0.5, prop.size.y)).round()

func _focus_action() -> void:
	if _action.disabled or not _action.is_visible_in_tree():
		_map_button.grab_focus()
	else:
		_action.grab_focus()
