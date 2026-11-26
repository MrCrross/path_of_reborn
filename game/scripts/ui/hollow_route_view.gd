class_name HollowRouteView
extends Node

signal command_requested(command: String)
signal encounter_requested(enemy_id: String)
signal shot_changed(dialogue_active: bool, story_frame: bool)

var session: GameSession
var dialogue: DialogueOverlay
var _actions: VBoxContainer
var _props: Control
var _background: TextureRect
var _exit_button: Button
var _resume_button: Button
var _error: Label
var _cue_ids: Array[String] = []

func configure(game_session: GameSession, world: Control, action_parent: Control, top_left: Control, background: TextureRect) -> void:
	session = game_session
	_background = background
	_props = Control.new()
	_props.name = "HollowProps"
	_props.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(_props)
	world.move_child(_props, background.get_index() + 1)
	_props.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_props.resized.connect(_layout_props)
	_actions = VBoxContainer.new()
	_actions.name = "HollowActions"
	action_parent.add_child(_actions)
	_exit_button = Button.new()
	_exit_button.name = "HollowExit"
	UiIcons.apply(_exit_button, "back", "В Лиорен")
	top_left.add_child(_exit_button)
	_exit_button.pressed.connect(leave)
	dialogue = DialogueOverlay.new()
	dialogue.name = "HollowDialogue"
	dialogue.configure(session)
	world.add_child(dialogue)
	dialogue.finished.connect(func(_destination: String) -> void: refresh(false))

func refresh(play_dialogue: bool = true) -> void:
	for parent: Control in [_actions, _props]:
		for child: Node in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	_resume_button = null
	var stage: String = session.hollow_stage()
	var exit_caption: String = "Назад к уступу" if stage == "elite" else "В Лиорен"
	_exit_button.tooltip_text = exit_caption
	_exit_button.accessibility_name = exit_caption
	var node: Dictionary = GameSession.hollow_node(stage)
	_cue_ids.assign(node.get("cues", []))
	if stage == "upper_marker":
		_cue_ids.append_array(["DIA_HOLLOW_020", "DIA_HOLLOW_021"])
	elif stage == "elite":
		_cue_ids.append("DIA_HOLLOW_009")
	elif stage == "ledge":
		if session.quest_flags.get(GameSession.HOLLOW_CLOTH, false):
			_cue_ids.append("DIA_HOLLOW_010")
		if session.quest_flags.get(GameSession.HOLLOW_RETREATED, false):
			_cue_ids.append("DIA_HOLLOW_008")
	_cue_ids = _cue_ids.filter(func(cue: String) -> bool: return not session.seen_cue_ids.has(cue))
	_show_encounter(node.get("enemies", []))
	if not _cue_ids.is_empty():
		_resume_button = _button("HollowContinue", "Продолжить", _play_dialogue)
	else:
		match stage:
			"river":
				_fight_button(node, "Панцирь уязвим после выпада.")
			"water_marker", "upper_marker":
				var text: String = "Восстановить нижний маркер" if stage == "water_marker" else "Восстановить верхний маркер"
				var marker := _button("RestoreMarker", text, _command.bind(stage))
				var path: String = ArtMap.GROVE_PROPS["marker"]
				var crop: Rect2 = ArtMap.GROVE_PROP_CROPS[path]
				_prop("MarkerProp", ArtMap.crop(path, crop), crop.size, Vector2(0.66, 0.60), marker)
			"shelf":
				if not session.quest_flags.get(GameSession.HOLLOW_COLLAPSED, false):
					var collapse := _button("CollapseShelf", "Обрушить полку", _command.bind("collapse"))
					var crop := Rect2(28, 16, 40, 24)
					_prop("ShelfProp", ArtMap.crop(ArtMap.HOLLOW_PROPS["shelf"], crop), crop.size, Vector2(0.82, 0.38), collapse)
				_fight_button(node, "Первый грызун оглушён" if session.quest_flags.get(GameSession.HOLLOW_COLLAPSED, false) else "")
			"ledge":
				if not session.quest_flags.get(GameSession.HOLLOW_CLOTH, false):
					var inspect := _button("InspectWall", "Осмотреть стену", _command.bind("cloth"))
					_prop("ClothProp", ArtMap.texture(ArtMap.HOLLOW_PROPS["cloth"]), Vector2(24, 24), Vector2(0.69, 0.48), inspect)
				else:
					if not session.quest_flags.get(GameSession.HOLLOW_ELITE_WON, false):
						_button("DescendToElite", "К гнезду жабы", _confirm_descent)
					_button("ReturnToLioren", "В Лиорен", leave)
			"elite":
				_button("RetreatFromBasin", "Назад к уступу", _command.bind("retreat"))
				_fight_button(node, "Элитная цель · повышенный риск")
	_error = Label.new()
	_error.text = "Запись не удалась. Попробуйте ещё раз."
	_error.add_theme_color_override("font_color", AppTheme.COLOR_DANGER)
	_error.add_theme_font_size_override("font_size", 8)
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_actions.add_child(_error)
	_error.hide()
	_show_shot(false)
	_layout_props()
	if play_dialogue and _resume_button != null:
		_play_dialogue()
	else:
		_focus_action()

func close_dialogue() -> bool:
	if not dialogue.is_active():
		return false
	dialogue.stop()
	refresh(false)
	return true

func leave() -> void:
	if dialogue.is_active() or ConfirmDialog.has_open(get_parent()):
		return
	if session.hollow_stage() == "elite":
		_command("retreat")
		return
	if session.quest_flags.get(GameSession.HOLLOW_CLOTH, false) or session.traces >= 3:
		_command("leave")
		return
	var confirm: ConfirmDialog = ConfirmDialog.open(get_parent(), "Вернуться в Лиорен?", "Восстановленные маркеры сохранятся.", "Вернуться", "Остаться")
	confirm.confirmed.connect(_command.bind("leave"))

func rejected(_command_id: String) -> void:
	_error.show()

func _command(command: String) -> void:
	if not dialogue.is_active():
		command_requested.emit(command)

func _confirm_descent() -> void:
	_actions.get_node("DescendToElite").grab_focus()
	var message: String = "Элитная цель. Основное задание можно сдать без победы над жабой."
	if session.checkpoints.can_begin():
		message += " На уступе можно оставить точку Печати."
	var confirm: ConfirmDialog = ConfirmDialog.open(get_parent(), "Гнездо Кристальной жабы", message, "Спуститься", "Остаться")
	confirm.confirmed.connect(_command.bind("descend"))

func _play_dialogue() -> void:
	if dialogue.play(GameSession.HOLLOW_NARRATIVE_PATH, "", false, {}, _cue_ids):
		dialogue.runner.changed.connect(_show_shot.bind(true))
		_show_shot(true)

func _show_shot(active: bool) -> void:
	var story_frame: bool = active and dialogue.runner.current_shot() == "hollow_cloth"
	var key: String = "world_hollow"
	if story_frame:
		key = "hollow_cloth"
	elif session.hollow_stage() == "elite":
		key = "hollow_basin"
	_background.texture = ArtMap.texture(ArtMap.BACKGROUNDS[key])
	_props.visible = not story_frame
	shot_changed.emit(active, story_frame)

func _show_encounter(slots: Array) -> void:
	for index: int in range(slots.size()):
		var slot: Dictionary = slots[index]
		var art: Dictionary = ArtMap.HOLLOW_STILLS[slot["actor_id"]]
		var prop: TextureRect = _prop(slot.get("id", slot["actor_id"]), ArtMap.crop(art["path"], art["crop"]), art["size"], Vector2.ZERO)
		prop.set_meta("enemy_index", index)
		prop.set_meta("enemy_count", slots.size())

func _prop(node_name: String, texture: Texture2D, dimensions: Vector2, anchor: Vector2, action: Button = null) -> TextureRect:
	var art := TextureRect.new()
	art.name = node_name
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.size = dimensions
	art.set_meta("anchor", anchor)
	_props.add_child(art)
	if action != null:
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.accessibility_name = action.text
		hit.disabled = action.disabled
		art.add_child(hit)
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var padding: Vector2 = (Vector2.ONE * UiIcons.TOUCH_SIZE - dimensions).max(Vector2.ZERO) * 0.5
		hit.offset_left = -padding.x
		hit.offset_right = padding.x
		hit.offset_top = -padding.y
		hit.offset_bottom = padding.y
		hit.pressed.connect(func() -> void: action.pressed.emit())
	return art

func _layout_props() -> void:
	for art: TextureRect in _props.get_children():
		var anchor: Vector2 = _props.size * Vector2(art.get_meta("anchor"))
		if art.has_meta("enemy_index"):
			anchor = SceneStaging.hollow_enemy_anchor(_props.size, art.get_meta("enemy_index"), art.get_meta("enemy_count"))
		art.position = (anchor - Vector2(art.size.x * 0.5, art.size.y)).round()

func _fight_button(node: Dictionary, hint: String) -> void:
	if not hint.is_empty():
		var label := Label.new()
		label.text = hint
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 9)
		_actions.add_child(label)
	var fight := _button("HollowFight", "В бой", func() -> void: encounter_requested.emit(node["enemy_id"]))
	fight.theme_type_variation = &"PrimaryButton"

func _button(node_name: String, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	button.disabled = session.traces >= 3 and node_name not in ["ReturnToLioren", "RetreatFromBasin"]
	button.add_theme_font_size_override("font_size", 9)
	button.pressed.connect(callback)
	_actions.add_child(button)
	return button

func _focus_action() -> void:
	for child: Node in _actions.get_children():
		var button := child as Button
		if button != null and not button.disabled:
			button.grab_focus()
			return
	_exit_button.grab_focus()
