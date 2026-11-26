class_name GroveRouteView
extends Node

signal command_requested(command: String)
signal encounter_requested(enemy_id: String)
signal dialogue_visibility_changed(active: bool, bridge_shot: bool)

var session: GameSession
var actions: VBoxContainer
var backdrop: TextureRect
var dialogue: DialogueOverlay
var exit_button: Button
var props: Control
var _stage_art: Array[Control] = []
var _error: Label
var _resume_button: Button
var _retry_leave: Button
var _cue_ids: Array[String] = []

func configure(game_session: GameSession, world: Control, action_parent: Control, top_left: Control, background: TextureRect) -> void:
	session = game_session
	backdrop = background
	props = Control.new()
	props.name = "GroveProps"
	props.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(props)
	world.move_child(props, backdrop.get_index() + 1)
	props.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	props.resized.connect(_layout_props)
	actions = VBoxContainer.new()
	actions.name = "GroveActions"
	action_parent.add_child(actions)
	exit_button = Button.new()
	exit_button.name = "GroveExit"
	UiIcons.apply(exit_button, "back", "В Лиорен")
	top_left.add_child(exit_button)
	exit_button.pressed.connect(leave)
	dialogue = DialogueOverlay.new()
	dialogue.name = "GroveDialogue"
	dialogue.configure(session)
	world.add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)

func close_dialogue() -> bool:
	if not dialogue.is_active():
		return false
	dialogue.stop()
	_restore_route_shot()
	if _resume_button != null:
		_resume_button.grab_focus()
	return true

func refresh(play_dialogue: bool = true) -> void:
	for child: Node in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	for prop: Control in _stage_art:
		props.remove_child(prop)
		prop.queue_free()
	_stage_art.clear()
	_resume_button = null
	_retry_leave = null
	var stage: String = session.grove_stage()
	_cue_ids = _pending_cues(stage)
	if not _cue_ids.is_empty():
		_resume_button = _button("GroveContinue", "Продолжить", _play_dialogue)
	match stage:
		"approach":
			_encounter_art("hound_pair")
			_button("GroveNoise", "Отвлечь шумом", _command.bind("noise"))
			_button("GroveFight", "В бой", _command.bind("approach"))
		"hound_pair":
			_encounter_art(stage)
			_button("GroveFight", "В бой", _fight.bind("needle_hound"))
		"root_bridge":
			_button("KentaSafe", "Найти безопасный спуск", _command.bind("grove_kenta_safe"))
			_button("KentaHint", "Подсказать, куда поставить ногу", _command.bind("grove_kenta_hint"))
			if session.grove_bandage() != null:
				_button("KentaBandage", "Перевязать руку", _command.bind("grove_kenta_bandage"))
		"pollen_pair":
			_encounter_art(stage)
			_button("GroveFight", "В бой", _fight.bind("dust_moth"))
		"clearing":
			_clearing()
	if _resume_button != null:
		for child: Node in actions.get_children():
			if child is Button and child != _resume_button:
				child.hide()
	_error = Label.new()
	_error.add_theme_font_size_override("font_size", 8)
	_error.add_theme_color_override("font_color", AppTheme.COLOR_DANGER)
	_error.text = "Запись не удалась. Попробуйте ещё раз."
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(_error)
	_error.hide()
	_restore_route_shot()
	_layout_props()
	if play_dialogue and _resume_button != null:
		_play_dialogue()
	else:
		for child: Node in actions.get_children():
			var button := child as Button
			if button != null and button.visible and not button.disabled:
				button.grab_focus()
				return
		exit_button.grab_focus()

func committed(command: String) -> void:
	match command:
		"approach":
			_fight("needle_hound")
		"noise":
			refresh(false)
			_rustle_grass()
		"decline_point":
			refresh()
			if not dialogue.is_active():
				_command("leave")
		_:
			refresh()

func rejected(command: String) -> void:
	_error.show()
	if command == "leave":
		if _retry_leave == null:
			_retry_leave = _button("GroveRetryLeave", "Повторить выход", _command.bind("leave"))
		_retry_leave.grab_focus()

func leave() -> void:
	if dialogue.is_active():
		return
	if session.grove_stage() != "clearing" or session.world_flags.get(GameSession.GROVE_SEALED, false):
		_command("leave")
	elif session.world_flags.get(GameSession.GROVE_DECLINED_SEAL, false):
		if not _play_dialogue():
			_command("leave")
	else:
		exit_button.grab_focus()
		var confirm: ConfirmDialog = ConfirmDialog.open(get_parent(), "Вернуться в Лиорен", "На поляне можно оставить ручную точку Печатью Пути.", "Уйти без точки", "Остаться")
		confirm.confirmed.connect(_command.bind("decline_point"))

func _pending_cues(stage: String) -> Array[String]:
	var numbers: Array = []
	if stage == "pollen_pair" and session.npc_flags.get("grove_kenta_trust", false):
		numbers.append_array(GameSession.grove_node("root_bridge")["help_cues"])
	numbers.append_array(GameSession.grove_node(stage).get("cues", []))
	if stage == "clearing":
		if session.quest_flags.get(GameSession.GROVE_MARKER, false):
			numbers.append(13)
		if session.world_flags.get(GameSession.GROVE_SEALED, false):
			numbers.append(14)
		elif session.world_flags.get(GameSession.GROVE_DECLINED_SEAL, false):
			numbers.append(15)
	var result: Array[String] = []
	for number: int in numbers:
		var cue: String = "DIA_GROVE_%03d" % number
		if not session.seen_cue_ids.has(cue):
			result.append(cue)
	return result

func _play_dialogue() -> bool:
	if _cue_ids.is_empty() or dialogue.is_active():
		return false
	if _resume_button != null:
		_resume_button.grab_focus()
	if not dialogue.play(GameSession.GROVE_NARRATIVE_PATH, "", false, {}, _cue_ids):
		return false
	dialogue.runner.changed.connect(_update_shot)
	_update_shot()
	return true

func _update_shot() -> void:
	_show_shot(true, dialogue.runner.current_shot() == "grove_bridge")

func _show_shot(active: bool, bridge: bool) -> void:
	backdrop.texture = ArtMap.texture(ArtMap.BACKGROUNDS["grove_bridge" if bridge else "world_grove"])
	props.visible = not bridge
	dialogue_visibility_changed.emit(active, bridge)

func _restore_route_shot() -> void:
	_show_shot(false, session.grove_stage() == "root_bridge")

func _on_dialogue_finished(_destination: String) -> void:
	refresh(false)
	if session.world_flags.get(GameSession.GROVE_DECLINED_SEAL, false) and not session.world_flags.get(GameSession.GROVE_SEALED, false):
		_command("leave")

func _rustle_grass() -> void:
	var region := AtlasTexture.new()
	region.atlas = backdrop.texture
	region.region = Rect2(64, 639, 122, 77)
	var cover: float = maxf(backdrop.size.x / region.atlas.get_width(), backdrop.size.y / region.atlas.get_height())
	var origin: Vector2 = (backdrop.size - region.atlas.get_size() * cover) * 0.5
	var grass := TextureRect.new()
	grass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grass.texture = region
	grass.size = region.region.size * cover
	grass.position = (origin + region.region.position * cover).round()
	props.add_child(grass)
	var base: Vector2 = grass.position
	var tween := create_tween()
	tween.tween_property(grass, "position", base + Vector2(2, -1), 0.10)
	tween.tween_property(grass, "position", base + Vector2(-1, 0), 0.08)
	tween.tween_property(grass, "position", base, 0.08)
	tween.tween_callback(grass.queue_free)

func _clearing() -> void:
	for key: String in ["flax", "marker"]:
		var path: String = ArtMap.GROVE_PROPS[key]
		var crop: Rect2 = ArtMap.GROVE_PROP_CROPS[path]
		_prop("MoonFlaxProp" if key == "flax" else "EasternMarkerProp", ArtMap.crop(path, crop), crop.size)
	var flax: bool = session.quest_flags.get(GameSession.GROVE_FLAX, false)
	var marker: bool = session.quest_flags.get(GameSession.GROVE_MARKER, false)
	_stage_art[0].visible = not flax
	if marker:
		for offset: int in [0, 3, 6]:
			var scratch := Line2D.new()
			scratch.width = 1.0
			scratch.default_color = Color("ecd6a4")
			scratch.points = PackedVector2Array([Vector2(12 + offset, 13), Vector2(15 + offset, 8)])
			_stage_art[1].add_child(scratch)
	var gather := _button("GatherFlax", "Лён собран" if flax else "Собрать лён", _command.bind("flax"))
	gather.disabled = flax
	var inspect := _button("InspectMarker", "Маркер осмотрен" if marker else "Осмотреть маркер", _command.bind("marker"))
	inspect.disabled = marker
	if _cue_ids.is_empty():
		_hotspot(_stage_art[0], gather)
		_hotspot(_stage_art[1], inspect)

func _hotspot(prop: Control, action: Button) -> void:
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.disabled = action.disabled
	hit.tooltip_text = action.text
	hit.accessibility_name = action.text
	prop.add_child(hit)
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad: float = maxf(0.0, (UiIcons.TOUCH_SIZE - prop.size.x) * 0.5)
	hit.offset_left = -pad
	hit.offset_right = pad
	hit.pressed.connect(func() -> void: action.pressed.emit())

func _encounter_art(stage: String) -> void:
	for slot: Dictionary in GameSession.grove_node(stage)["enemies"]:
		var species: String = slot["actor_id"]
		var still: Dictionary = ArtMap.GROVE_STILLS[species]
		_prop(String(slot["id"]), ArtMap.crop(still["path"], still["crop"]), still["size"])

func _prop(node_name: String, texture: Texture2D, dimensions: Vector2) -> void:
	var art := TextureRect.new()
	art.name = node_name
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = texture
	art.size = dimensions
	props.add_child(art)
	_stage_art.append(art)

func _layout_props() -> void:
	for index: int in range(_stage_art.size()):
		var prop: Control = _stage_art[index]
		var airborne: bool = prop.name == &"dust_moth"
		var anchor: Vector2 = SceneStaging.grove_enemy_anchor(props.size, index, airborne)
		if airborne:
			# Мотылёк парит вокруг центра кадра, а реквизит и остальные враги стоят на земле.
			anchor.y += prop.size.y * 0.5
		prop.position = (anchor - Vector2(prop.size.x * 0.5, prop.size.y)).round()

func _button(node_name: String, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	button.add_theme_font_size_override("font_size", 9)
	button.pressed.connect(callback)
	actions.add_child(button)
	return button

func _command(command: String) -> void:
	if not dialogue.is_active():
		command_requested.emit(command)

func _fight(enemy_id: String) -> void:
	if not dialogue.is_active():
		encounter_requested.emit(enemy_id)
