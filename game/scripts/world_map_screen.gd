extends Control

signal navigate_requested(destination: String)
signal travel_requested(destination: String)
signal grove_command_requested(command: String)

const CITY_GATE := "city_gate"
const GROVE_EXIT_CUE := "DIA_GROVE_015"
const HOLLOW_ORDER_CUES: Array[String] = [
	"DIA_HOLLOW_ORDER", "DIA_HOLLOW_001", "DIA_HOLLOW_002", "DIA_HOLLOW_003", "DIA_HOLLOW_004",
]
const POINTS := {
	GameSession.LOCATION_FOREST_EDGE: ["MapTrail", "Тропа Первого\nВдоха", Vector2(0.26, 0.83)],
	GameSession.LOCATION_LIOREN: ["MapLioren", "Лиорен", Vector2(0.74, 0.64)],
	GameSession.LOCATION_GROVE: ["MapGrove", "Роща\nШелестящих Трав", Vector2(0.26, 0.50)],
	GameSession.LOCATION_HOLLOW: ["MapHollow", "Синий Овраг", Vector2(0.73, 0.14)],
	GameSession.LOCATION_OUTPOST: ["MapOutpost", "Край Ветров", Vector2(0.26, 0.09)],
	GameSession.MAP_SHOP: ["MapShop", "Лавка «Сверчок\nи Сумрак»", Vector2(0.26, 0.54)],
	GameSession.MAP_GUILD: ["MapGuild", "Гильдия\nРассветной Тропы", Vector2(0.73, 0.22)],
	GameSession.MAP_HOLLOW_BASIN: ["MapBasin", "Гнездо\nКристальной жабы", Vector2(0.26, 0.29)],
	GameSession.MAP_HOLLOW_LEDGE: ["MapLedge", "Уступ Оврага", Vector2(0.73, 0.39)],
	CITY_GATE: ["MapGate", "Южные ворота", Vector2(0.77, 0.79)],
}
const BLOCKED_LABELS := {
	"current": "Вы здесь",
	"busy": "Завершите текущее действие",
	"checkpoint": "Идёт фиксация Печати",
	"daijiro": "Помогите Дайдзиро",
	"gates": "Пройдите городские ворота",
	"merchant": "Получите совет Дайдзиро",
	"rest": "Нужен отдых в Лиорене",
	"via_lioren": "Через Лиорен",
	"via_ledge": "Сначала вернитесь на уступ",
	"registration": "Нужен ранг E",
	"grove_report": "Нужен отчёт о Роще",
	"hollow_report": "Нужен отчёт об Овраге",
	"completed": "Задание завершено",
}
const MAP_SURFACE := Color("1a2e27")
const MAP_INK := Color("101e19")
const MAP_GOLD := Color("e4c38a")
const MAP_DIM := Color("a4ab91")
const POINT_HIT_SIZE := Vector2(76, 43)
const PIN_OFFSET := Vector2(0, 7)
const CAPTION_TOP := 14.0

var session: GameSession
var city_map: bool = false
var initial_destination: String = ""
var dialogue: DialogueOverlay
var _background: Texture2D
var _art_rect: Rect2
var _buttons: Dictionary[String, Button] = {}
var _current_point: String = ""
var _unvisited_destination: String = ""
var _selected: String = ""
var _travelling: bool = false
var _guild_stage: Control

@onready var _back: Button = %Back
@onready var _safe: SafeArea = %SafeArea
@onready var _board: Control = %MapBoard
@onready var _first_route: Button = %FirstRoute
@onready var _error: Label = %TravelError
@onready var _story_background: TextureRect = %StoryBackground

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	%Title.text = "Локация Лиорен" if city_map else "Карта мира"
	_background = ArtMap.texture(ArtMap.BACKGROUNDS["lioren_map" if city_map else "world_map"])
	UiIcons.apply(_back, "back", "Назад к карте мира" if city_map else "Назад к локации")
	_back.pressed.connect(handle_back)
	_error.add_theme_color_override("font_color", AppTheme.COLOR_DANGER)
	_current_point = _get_current_point()
	if city_map:
		_add_point(CITY_GATE)
		for destination: String in GameSession.MAP_CITY_LOCATIONS:
			_add_point(destination)
	else:
		for destination: String in GameSession.MAP_WORLD_LOCATIONS:
			_add_point(destination)
		if session.location_id == GameSession.LOCATION_HOLLOW:
			_add_point(GameSession.MAP_HOLLOW_LEDGE)
			_add_point(GameSession.MAP_HOLLOW_BASIN)
	_unvisited_destination = session.first_unvisited_map_route(city_map)
	_first_route.visible = not _unvisited_destination.is_empty()
	_first_route.pressed.connect(_select_destination.bind(_unvisited_destination))
	_board.resized.connect(_position_points)
	_board.draw.connect(_draw_map)
	_position_points()
	dialogue = DialogueOverlay.new()
	dialogue.name = "MapTravelDialogue"
	dialogue.configure(session)
	dialogue.finished.connect(_on_dialogue_finished)
	add_child(dialogue)
	_focus_destination(initial_destination)

func handle_back() -> bool:
	if dialogue.is_active():
		dialogue.stop()
		_show_routes()
	elif not _travelling and not ConfirmDialog.has_open(self):
		navigate_requested.emit("map_from_lioren" if city_map else "world_from_map")
	return true

func _get_current_point() -> String:
	if city_map:
		return CITY_GATE
	if session.location_id == GameSession.LOCATION_HOLLOW:
		match session.hollow_stage():
			"elite": return GameSession.MAP_HOLLOW_BASIN
			"ledge": return GameSession.MAP_HOLLOW_LEDGE
	return session.location_id

func _add_point(destination: String) -> void:
	if destination != CITY_GATE and not session.has_visited_map_location(destination):
		return
	var details: Array = POINTS[destination]
	var city_entrance: bool = destination == GameSession.LOCATION_LIOREN and session.location_id == destination
	var blocker: String = "" if destination == CITY_GATE or city_entrance else session.map_travel_blocker(destination)
	var button := Button.new()
	button.name = details[0]
	button.text = details[1]
	button.disabled = not blocker.is_empty()
	button.pressed.connect(_select_destination.bind(destination))
	button.mouse_entered.connect(_board.queue_redraw)
	button.mouse_exited.connect(_board.queue_redraw)
	button.focus_entered.connect(_board.queue_redraw)
	button.focus_exited.connect(_board.queue_redraw)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var text_inset := StyleBoxEmpty.new()
	text_inset.content_margin_top = CAPTION_TOP
	if not button.text.contains("\n"):
		text_inset.content_margin_bottom = 8.0
	text_inset.content_margin_left = 4.0
	text_inset.content_margin_right = 4.0
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, text_inset)
	var caption: String = String(details[1]).replace("\n", " ")
	var status: String = "Вы здесь" if destination == _current_point else BLOCKED_LABELS.get(blocker, "")
	if destination == GameSession.LOCATION_HOLLOW and _current_point != destination and blocker == "current":
		status = ""
	button.tooltip_text = caption if status.is_empty() else "%s · %s" % [caption, status]
	button.accessibility_name = button.tooltip_text
	if destination == _current_point:
		button.add_theme_color_override("font_disabled_color", AppTheme.COLOR_TEXT)
	elif button.disabled:
		button.add_theme_color_override("font_disabled_color", AppTheme.COLOR_TEXT_DIM)
	_board.add_child(button)
	var font: Font = button.get_theme_font("font")
	var font_size: int = 8
	for line: String in button.text.split("\n"):
		if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > POINT_HIT_SIZE.x - text_inset.get_minimum_size().x:
			font_size = 7
			break
	button.add_theme_font_size_override("font_size", font_size)
	_buttons[destination] = button

func _position_points() -> void:
	_art_rect = Rect2(Vector2.ZERO, _board.size)
	if _background != null:
		var art_size: Vector2 = _background.get_size()
		var cover_scale: float = maxf(_board.size.x / art_size.x, _board.size.y / art_size.y)
		var cover_size: Vector2 = art_size * cover_scale
		_art_rect = Rect2((_board.size - cover_size) * 0.5, cover_size)
	for destination: String in _buttons:
		var point: Vector2 = _point_position(destination)
		var button: Button = _buttons[destination]
		var left: float = clampf(point.x - POINT_HIT_SIZE.x / 2.0, 4.0, _board.size.x - POINT_HIT_SIZE.x - 4.0)
		button.position = Vector2(left, point.y - PIN_OFFSET.y)
		button.size = POINT_HIT_SIZE
	_board.queue_redraw()

func _point_position(destination: String) -> Vector2:
	var relative: Vector2 = POINTS[destination][2]
	var point: Vector2 = _art_rect.position + relative * _art_rect.size
	point.x = clampf(point.x, 12.0, _board.size.x - 12.0)
	point.y = clampf(point.y, 8.0, _board.size.y - POINT_HIT_SIZE.y + PIN_OFFSET.y - 4.0)
	return point.round()

func _draw_map() -> void:
	var bounds := Rect2(Vector2.ZERO, _board.size)
	if bounds.size.x < 20.0 or bounds.size.y < 20.0:
		return
	if _background != null:
		var pixels_per_unit: Vector2 = _background.get_size() / _art_rect.size
		var crop := Rect2(-_art_rect.position * pixels_per_unit, bounds.size * pixels_per_unit)
		_board.draw_texture_rect_region(_background, bounds, crop)
	else:
		_board.draw_rect(bounds, MAP_SURFACE)
	_board.draw_rect(bounds.grow(-1), MAP_INK, false, 2.0)
	_board.draw_rect(bounds.grow(-3), Color("e4c38a9c"), false, 1.0)
	for destination: String in _buttons:
		var point: Vector2 = _point_position(destination)
		var button: Button = _buttons[destination]
		var current: bool = destination == _current_point
		var color: Color = MAP_DIM if button.disabled else MAP_GOLD
		if current:
			color = AppTheme.COLOR_MAGIC
		var width: float = minf(button.get_minimum_size().x + 6.0, button.size.x)
		var height: float = 21.0 if not button.text.contains("\n") else button.size.y - CAPTION_TOP
		var plate := Rect2(button.position + Vector2((button.size.x - width) * 0.5, CAPTION_TOP), Vector2(width, height))
		var stem := Vector2(clampf(point.x, plate.position.x + 4.0, plate.end.x - 4.0), plate.position.y + 1.0)
		_board.draw_line(point, stem, MAP_INK, 3.0, true)
		_board.draw_line(point, stem, color, 1.0, true)
		_board.draw_circle(point, 7.0 if current else 5.0, MAP_INK, true, -1, true)
		_board.draw_circle(point, 3.5, color, true, -1, true)
		if current:
			_board.draw_arc(point, 5.7, 0.0, TAU, 24, color, 1.0, true)
		var fill := Color("13251fed")
		if button.is_hovered() and not button.disabled:
			fill = AppTheme.COLOR_PANEL_LIGHT
		var focused: bool = button.has_focus()
		var rim: Color = color.lightened(0.5) if focused else color
		_board.draw_style_box(AppTheme.flat(fill, rim, 2 if focused else 1, 4), plate)

func _select_destination(destination: String) -> void:
	if _travelling or dialogue.is_active() or ConfirmDialog.has_open(self):
		return
	if destination == CITY_GATE:
		navigate_requested.emit("world_from_map")
		return
	if destination == GameSession.LOCATION_LIOREN and session.location_id == destination:
		navigate_requested.emit("lioren_map")
		return
	if destination.is_empty() or not session.map_travel_blocker(destination).is_empty():
		return
	_selected = destination
	_error.hide()
	match destination:
		GameSession.LOCATION_LIOREN:
			_prepare_lioren_return()
		GameSession.LOCATION_HOLLOW:
			_play_travel_dialogue(GameSession.HOLLOW_NARRATIVE_PATH, HOLLOW_ORDER_CUES, "В Синий Овраг", "guild_hall")
		GameSession.LOCATION_OUTPOST:
			_play_travel_dialogue(GameSession.OUTPOST_NARRATIVE_PATH, [GameSession.OUTPOST_ORDER_CUE], "На Край Ветров", "guild_hall")
		GameSession.MAP_HOLLOW_BASIN:
			var message: String = "Жаба атакует дважды подряд. Её броня раскрывается после второй атаки."
			if session.checkpoints.can_begin():
				message += " На уступе можно оставить точку Печати."
			_confirm_travel("Гнездо Кристальной жабы", message, "Спуститься")
		_:
			_request_travel()

func _prepare_lioren_return() -> void:
	match session.location_id:
		GameSession.LOCATION_GROVE:
			if session.grove_stage() == "clearing" and not session.world_flags.get(GameSession.GROVE_SEALED, false):
				if session.world_flags.get(GameSession.GROVE_DECLINED_SEAL, false):
					grove_command_committed("decline_point")
				else:
					var confirm: ConfirmDialog = ConfirmDialog.open(
						self, "Вернуться в Лиорен?", "Печать Пути сохранит эту поляну как точку возврата после поражения.",
						"Уйти без точки", "Остаться"
					)
					confirm.confirmed.connect(func() -> void: grove_command_requested.emit("decline_point"))
				return
		GameSession.LOCATION_HOLLOW:
			if not session.quest_flags.get(GameSession.HOLLOW_CLOTH, false) and session.traces < 3:
				_confirm_travel("Вернуться в Лиорен?", "Восстановленные маркеры сохранятся.", "Вернуться")
				return
		GameSession.LOCATION_OUTPOST:
			if session.outpost_stage() != "return" and session.traces < 3:
				_confirm_travel("Вернуться в Лиорен?", "Текущие цели поста сохранятся.", "Вернуться")
				return
	_request_travel()

func _confirm_travel(title: String, message: String, caption: String) -> void:
	var confirm: ConfirmDialog = ConfirmDialog.open(self, title, message, caption, "Остаться")
	confirm.confirmed.connect(_request_travel)

func grove_command_committed(_command: String) -> void:
	_play_travel_dialogue(GameSession.GROVE_NARRATIVE_PATH, [GROVE_EXIT_CUE], "В Лиорен", "world_grove")

func grove_command_rejected(_command: String) -> void:
	travel_rejected()

func _play_travel_dialogue(path: String, cues: Array[String], caption: String, background: String) -> void:
	if session.seen_cue_ids.has_all(cues):
		_request_travel()
	elif dialogue.play(path, caption, false, {}, cues):
		_safe.hide()
		if background == "guild_hall":
			if _guild_stage == null:
				_guild_stage = preload("res://scenes/guild.tscn").instantiate()
				_guild_stage.call("configure_as_briefing_stage")
				add_child(_guild_stage)
				move_child(_guild_stage, _safe.get_index())
			_guild_stage.show()
			dialogue.runner.changed.connect(_show_briefing_shot)
			_show_briefing_shot()
		else:
			_story_background.texture = ArtMap.texture(ArtMap.BACKGROUNDS[background])
			_story_background.show()
	else:
		travel_rejected()

func _show_briefing_shot() -> void:
	_guild_stage.call("show_shot", dialogue.runner.current_shot())

func _on_dialogue_finished(_destination: String) -> void:
	_show_routes()
	_request_travel()

func _show_routes() -> void:
	_story_background.hide()
	if _guild_stage != null:
		_guild_stage.hide()
	_safe.show()
	_focus_destination(_selected)

func _request_travel() -> void:
	if not _travelling:
		_travelling = true
		travel_requested.emit(_selected)

func travel_rejected() -> void:
	_travelling = false
	_error.show()
	_focus_destination(_selected)

func _focus_destination(destination: String) -> void:
	var button: Button = _buttons.get(destination)
	if button != null and not button.disabled:
		button.grab_focus()
	elif _first_route.visible and (destination == _unvisited_destination or (destination.is_empty() and city_map)):
		_first_route.grab_focus()
	else:
		_back.grab_focus()
