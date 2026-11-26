extends Control

signal navigate_requested(destination: String)
signal guild_registration_requested
signal grove_command_requested(command: String)

const REGISTRATION_PATH := "res://data/narrative/guild_registration.json"
const HALL_PLAN := Vector2(180, 320)

var session: GameSession
var dialogue: DialogueOverlay
var _report_button: Button
var _grove_button: Button
var _report_view: CombatResultView
var _dialogue_kind: String = ""
var _route_map: TextureRect

@onready var backdrop: TextureRect = $Background
@onready var back_button: Button = %Back
@onready var register_button: Button = %Register

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null or not session.guild_visit_active():
		navigate_requested.emit.call_deferred("world")
		return
	%Badge.texture = ArtMap.texture(ArtMap.GUILD_ART["badge"])
	%Error.add_theme_color_override("font_color", AppTheme.COLOR_DANGER)
	back_button.pressed.connect(handle_back)
	register_button.pressed.connect(func() -> void: guild_registration_requested.emit())
	var desk: VBoxContainer = register_button.get_parent()
	_grove_button = _order_button(desk, "EnterGrove", "В Рощу")
	_grove_button.pressed.connect(func() -> void: grove_command_requested.emit("enter"))
	_report_button = _order_button(desk, "ReportGrove", "Сдать задание")
	_report_button.pressed.connect(_start_report)
	_report_view = CombatResultView.new()
	_report_view.name = "GroveReportReward"
	_report_view.claim_requested.connect(func() -> void: grove_command_requested.emit("report"))
	var order: Control = $SafeArea/Column/Order
	order.get_parent().add_child(_report_view)
	_report_view.hide()
	_route_map = TextureRect.new()
	_route_map.texture = ArtMap.texture(ArtMap.GROVE_PROPS["map"])
	_route_map.custom_minimum_size = Vector2(24, 24)
	_route_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_route_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	%Badge.get_parent().add_child(_route_map)
	$Merchant.texture = ArtMap.texture(ArtMap.DAIJIRO_MERCHANT_STILL)
	$Kenta.texture = ArtMap.texture(ArtMap.GUILD_ART["kenta"])
	$Midori.texture = ArtMap.texture(ArtMap.GUILD_ART["midori"])
	$Goro.texture = ArtMap.texture(ArtMap.GUILD_ART["goro"])
	resized.connect(_layout_actors)

	dialogue = DialogueOverlay.new()
	dialogue.name = "RegistrationDialogue"
	dialogue.configure(session)
	add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)
	if session.guild_rank().is_empty() and not session.can_register_with_guild() and dialogue.play(REGISTRATION_PATH, "К регистрации"):
		_dialogue_kind = "registration"
		$SafeArea.hide()
		dialogue.runner.changed.connect(_show_dialogue_shot)
		_show_dialogue_shot()
	else:
		_show_desk()
		_resume_story.call_deferred()

func handle_back() -> bool:
	if dialogue != null and dialogue.is_active() and _dialogue_kind != "registration":
		dialogue.stop()
		_show_desk()
		if _report_button.visible:
			_report_button.grab_focus()
		return true
	if _report_view != null and _report_view.visible:
		_show_desk()
		_report_button.grab_focus()
		return true
	if dialogue != null:
		dialogue.stop()
	if session != null:
		session.set_guild_visit_active(false)
	navigate_requested.emit("world_from_guild")
	return true

func registration_rejected() -> void:
	%Error.show()
	register_button.grab_focus()

func registration_committed() -> void:
	_show_desk()

func _on_dialogue_finished(_destination: String) -> void:
	if _dialogue_kind == "report":
		_present_report()
	else:
		_show_desk()

func grove_command_committed(command: String) -> void:
	if command == "enter":
		navigate_requested.emit("world")
	else:
		_show_desk()
		_show_growth()

func grove_command_rejected(_command: String) -> void:
	if _report_view.visible:
		_report_view.claim_button.text = "Повторить запись"
		_report_view.claim_button.grab_focus()
	else:
		%Error.show()
		_grove_button.grab_focus()

func _order_button(desk: VBoxContainer, node_name: String, caption: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size.y = UiIcons.TOUCH_SIZE
	button.theme_type_variation = &"PrimaryButton"
	desk.add_child(button)
	button.hide()
	return button

func _start_report() -> void:
	if not session.can_report_grove():
		return
	_dialogue_kind = "report"
	var cues: Array[String] = ["DIA_GROVE_016", "DIA_GROVE_017", "DIA_GROVE_018", "DIA_GROVE_019", "DIA_GROVE_020", "DIA_GROVE_021"]
	if dialogue.play(GameSession.GROVE_NARRATIVE_PATH, "Проверить награды", false, {}, cues):
		$SafeArea.hide()
	else:
		_present_report()

func _present_report() -> void:
	$SafeArea.show()
	$SafeArea/Column/Order.hide()
	_report_view.present_guild_report(session, GameSession.grove_definition()["report"])

func _resume_story() -> void:
	if not is_inside_tree():
		return
	if session.can_report_grove() and session.seen_cue_ids.has("DIA_GROVE_016"):
		_start_report()
	else:
		_show_growth()

func _show_growth() -> void:
	if not session.quest_flags.get(GameSession.GROVE_REPORTED, false):
		return
	var cues: Array[String] = ["DIA_GROVE_022", "DIA_GROVE_023"]
	if session.quest_flags.get(GameSession.GROVE_LEVEL_THREE, false):
		cues.append("DIA_GROVE_024")
	_dialogue_kind = "growth"
	if dialogue.play(GameSession.GROVE_NARRATIVE_PATH, "К заданию", false, {}, cues):
		$SafeArea.hide()

func _show_desk() -> void:
	_show_shot("guild_hall")
	$SafeArea.show()
	$SafeArea/Column/Order.show()
	_report_view.hide()
	var rank: String = session.guild_rank()
	var registered: bool = not rank.is_empty()
	%Rank.text = ("Ранг %s · Знак Гильдии" % rank) if registered else "Регистрация"
	var reported: bool = session.quest_flags.get(GameSession.GROVE_REPORTED, false)
	var flax: bool = session.quest_flags.get(GameSession.GROVE_FLAX, false)
	var marker: bool = session.quest_flags.get(GameSession.GROVE_MARKER, false)
	var ready_to_report: bool = session.can_report_grove()
	var order_title: String = "Выдано первое задание" if registered else "Первое задание"
	if ready_to_report:
		order_title = "Можно сдать задание"
	elif reported:
		order_title = "Задание завершено"
	%OrderTitle.text = order_title
	%Objectives.text = "%s\n%s лунный лён\n%s восточный маркер" % [
		UiText.location(GameSession.LOCATION_GROVE),
		"✓ Собран" if flax else "• Собрать",
		"✓ Осмотрен" if marker else "• Осмотреть",
	]
	_route_map.visible = registered
	%Error.hide()
	_grove_button.visible = registered
	_grove_button.disabled = not session.can_enter_grove()
	_grove_button.tooltip_text = "Снимите Следы отдыхом в Лиорене" if session.traces >= 3 else ""
	_grove_button.theme_type_variation = &"" if ready_to_report else &"PrimaryButton"
	_report_button.visible = ready_to_report
	register_button.visible = session.can_register_with_guild()
	if register_button.visible:
		register_button.grab_focus()
	elif _report_button.visible:
		_report_button.grab_focus()
	elif _grove_button.visible and not _grove_button.disabled:
		_grove_button.grab_focus()
	else:
		back_button.grab_focus()

func _show_dialogue_shot() -> void:
	if dialogue.runner != null and not dialogue.runner.is_finished:
		_show_shot(dialogue.runner.current_shot())

func _show_shot(shot: String) -> void:
	var background_key: String = "guild_registration" if shot == "guild_registration" else "guild_hall"
	backdrop.texture = ArtMap.texture(ArtMap.BACKGROUNDS[background_key])
	$Merchant.visible = shot == "guild_opening"
	$Kenta.visible = shot == "guild_opening"
	$Midori.visible = shot != "guild_registration"
	$Goro.visible = shot == "guild_mentor"
	_layout_actors()

func _layout_actors() -> void:
	# Match the floor and counter to the backdrop's cover transform.
	var art_scale: float = maxf(size.x / HALL_PLAN.x, size.y / HALL_PLAN.y)
	var origin: Vector2 = (size - HALL_PLAN * art_scale) * 0.5
	# Keep the two foreground figures inside the narrower crop on tall screens.
	var pair_scale: float = minf(art_scale, size.x / HALL_PLAN.x * 1.16)
	$Merchant.position = Vector2(size.x * (60.0 / HALL_PLAN.x), origin.y + 231.0 * art_scale).round()
	$Kenta.position = Vector2(size.x * (122.0 / HALL_PLAN.x), origin.y + 229.0 * art_scale).round()
	$Midori.position = (origin + Vector2(143, 151) * art_scale).round()
	$Goro.position = (origin + Vector2(82, 231) * art_scale).round()
	$Merchant.scale = Vector2.ONE * 0.39 * pair_scale
	$Kenta.scale = Vector2.ONE * 0.52 * pair_scale
	$Midori.scale = Vector2.ONE * 0.44 * art_scale
	$Goro.scale = Vector2.ONE * 0.56 * art_scale
