extends Control

signal navigate_requested(destination: String)
## Экран только запрашивает commit; граница записи (кандидат + SaveService) —
## в GameRoot, по образцу claim боевой добычи. payload: checkpoint_id для
## restore/delete, пустой для completion.
signal checkpoint_commit_requested(kind: String, payload: Dictionary)

const ERROR_TEXTS: Dictionary = {
	"completion": "Точка вычислена, но не сохранена. Повторите запись.",
	"delete": "Не удалось удалить точку. Повторите запись.",
	"restore": "Не удалось выполнить возврат. Повторите запись.",
}

var session: GameSession

@onready var contract_text: Label = %ContractText
@onready var block_label: Label = %BlockLabel
@onready var start_button: Button = %StartButton
@onready var channel_box: VBoxContainer = %ChannelBox
@onready var progress_text: Label = %ProgressText
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var points_list: VBoxContainer = %PointsList
@onready var points_count: Label = %PointsCount
@onready var preview: PanelContainer = %Preview
@onready var preview_art: TextureRect = %PreviewArt
@onready var preview_title: Label = %PreviewTitle
@onready var preview_text: Label = %PreviewText
@onready var confirm_return: Button = %ConfirmReturn
@onready var back_button: Button = %BackButton
@onready var set_fx: TextureRect = %SetFx
@onready var traces_icon: TextureRect = %TracesIcon
@onready var background_art: TextureRect = %BackgroundArt
@onready var error_box: VBoxContainer = %CommitErrorBox
@onready var error_label: Label = %CommitErrorLabel
@onready var error_retry: Button = %CommitRetryButton

var _set_fx_tween: Tween
## Выбранная в режиме возврата опция: {kind, id, label}.
var _selected_option: Dictionary = {}
var _built_signature: String = ""
## Последнее запрошенное действие commit: {kind, checkpoint_id}. Хранится
## и после неудачи — кнопка повтора использует его как payload.
var _pending_commit: Dictionary = {}
## Commit в GameRoot синхронен; флаг только от двойного нажатия до callback.
var _commit_in_flight: bool = false

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	# Возврат после смерти обязателен: Back не отменяет сам выбор точки,
	# но закрывает открытое превью (верхнее окно текущего экрана).
	if session.awaiting_return:
		if preview.visible:
			_selected_option = {}
			_refresh_preview()
			_grab_first_card_focus()
			return true
		return false
	navigate_requested.emit("world")
	return true

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	UiIcons.apply(back_button, "back", "К пути")
	UiIcons.apply(%HelpButton, "info", "О Печати Пути")
	for label: Label in [contract_text, %HelpText, block_label, points_count]:
		label.add_theme_stylebox_override("normal", AppTheme.flat(AppTheme.COLOR_HUD, AppTheme.COLOR_PANEL_BORDER, 1, 2))
	traces_icon.hide()
	_hide_error()
	_refresh_all()
	if session.awaiting_return:
		back_button.hide()
		_grab_first_card_focus()
	else:
		start_button.grab_focus()

func _physics_process(_delta: float) -> void:
	var service: CheckpointService = session.checkpoints
	if service.channel_active:
		# Непрерывный progress обновляется отдельно: список не пересобирается.
		progress_bar.value = float(service.channel_ticks) / CheckpointService.CHANNEL_TICKS * 100.0
		service.advance_ticks(1)
	if (
		service.has_pending_completion()
		and not _commit_in_flight
		and not error_box.visible
	):
		# Канал завершён (в кадре или staged при загрузке): домен staged снимок,
		# запись подтверждает GameRoot. После ошибки — только явный повтор.
		_request_commit("completion", "")

func _exit_tree() -> void:
	if session != null and session.checkpoints.channel_active:
		session.checkpoints.cancel()

func _on_start_pressed() -> void:
	if session.checkpoints.begin():
		_built_signature = ""
		_hide_error()
		_refresh_all()
		%CancelButton.grab_focus()

func _on_cancel_pressed() -> void:
	session.checkpoints.cancel()
	_built_signature = ""
	_refresh_all()
	start_button.grab_focus()

func _on_back_pressed() -> void:
	navigate_requested.emit("world")

func _on_help_pressed() -> void:
	%HelpText.visible = not %HelpText.visible

func _on_confirm_return_pressed() -> void:
	if _selected_option.is_empty() or _commit_in_flight:
		return
	_request_commit("restore", String(_selected_option.get("id", "")))

## Удаление точки — с подтверждением; отмена ничего не удаляет.
func _on_delete_pressed(checkpoint_id: String, label: String) -> void:
	var dialog: ConfirmDialog = ConfirmDialog.open(
		self,
		"Удалить точку?",
		"%s будет удалена безвозвратно." % label,
		"Удалить",
		"Отмена",
		true
	)
	dialog.confirmed.connect(_delete_confirmed.bind(checkpoint_id))

func _delete_confirmed(checkpoint_id: String) -> void:
	if not _commit_in_flight:
		_request_commit("delete", checkpoint_id)

## GameRoot подтвердил запись: экран переходит в успешное состояние.
func checkpoint_committed(kind: String) -> void:
	_commit_in_flight = false
	_pending_commit = {}
	_hide_error()
	_built_signature = ""
	_refresh_all()
	match kind:
		"completion":
			_play_set_fx()
			_focus_points_or_start()
		"delete":
			_focus_points_or_start()
		"restore":
			# Навигацией в World управляет GameRoot.
			pass

## GameRoot не смог записать: живое состояние не тронуто, ошибка — рядом
## с действием, справка и причины недоступности остаются видимыми.
func show_checkpoint_error(kind: String) -> void:
	_commit_in_flight = false
	error_label.text = String(ERROR_TEXTS.get(kind, "Не удалось сохранить. Повторите запись."))
	# Канал завершён, запись не подтверждена: убираем устаревшую панель канала,
	# остаются действие повтора, справка и причины недоступности.
	_refresh_channel()
	error_box.show()
	error_retry.grab_focus()

func _on_error_retry_pressed() -> void:
	if error_box.visible and not _pending_commit.is_empty():
		_request_commit(String(_pending_commit.get("kind", "")), String(_pending_commit.get("checkpoint_id", "")))

func _hide_error() -> void:
	if error_box != null:
		error_box.hide()

func _request_commit(kind: String, checkpoint_id: String) -> void:
	if _commit_in_flight:
		return
	_commit_in_flight = true
	_pending_commit = {"kind": kind, "checkpoint_id": checkpoint_id}
	_hide_error()
	var payload: Dictionary = {}
	if not checkpoint_id.is_empty():
		payload["checkpoint_id"] = checkpoint_id
	checkpoint_commit_requested.emit(kind, payload)

func _on_option_pressed(option: Dictionary) -> void:
	_selected_option = option
	_hide_error()
	_refresh_preview()

func _focus_points_or_start() -> void:
	# В manage-режиме карточки — HBox (не фокусируемы): основной следующий
	# шаг — повторная фиксация; иначе — кнопка удаления последней карточки.
	if start_button.visible:
		start_button.grab_focus()
	elif points_list.get_child_count() > 0:
		var last: Node = points_list.get_child(points_list.get_child_count() - 1)
		if last is HBoxContainer:
			(last.get_child(last.get_child_count() - 1) as Button).grab_focus()

func _grab_first_card_focus() -> void:
	if points_list.get_child_count() > 0:
		(points_list.get_child(0) as Control).grab_focus()

func _refresh_all() -> void:
	_refresh_background()
	_refresh_contract()
	_refresh_channel()
	_refresh_points()
	_refresh_preview()

## Фон — та же локация, что видел игрок в World: по session.location_id.
func _refresh_background() -> void:
	var background_key: String = (
		"world_lioren" if session.location_id == "lioren" else "world_forest_edge"
	)
	background_art.texture = ArtMap.texture(ArtMap.BACKGROUNDS[background_key])

func _refresh_contract() -> void:
	var service: CheckpointService = session.checkpoints
	if session.awaiting_return:
		contract_text.text = "Возврат · Следы %d/3" % session.traces
	else:
		contract_text.text = "Печать · Следы %d/3" % session.traces
	traces_icon.hide()
	var reason: String = ""
	if not session.awaiting_return and not service.channel_active:
		if session.traces >= 3:
			reason = "Следы 3/3 — дальше только переход в Лиорен. Отдых там сбросит Следы."
		elif service.manual_snapshots.size() >= CheckpointService.MANUAL_LIMIT:
			reason = "Сохранены 3 точки. Удалите ненужную."
		elif session.in_combat:
			reason = "Фиксация недоступна в бою."
	block_label.text = reason
	block_label.visible = not reason.is_empty()

func _refresh_channel() -> void:
	var service: CheckpointService = session.checkpoints
	start_button.visible = not session.awaiting_return and not service.channel_active
	start_button.disabled = not service.can_begin()
	start_button.icon = ArtMap.texture(
		ArtMap.UI["checkpoint_active"] if service.can_begin() else ArtMap.UI["checkpoint_inactive"]
	)
	start_button.add_theme_constant_override("icon_max_width", 20)
	channel_box.visible = service.channel_active
	if service.channel_active:
		progress_bar.value = float(service.channel_ticks) / CheckpointService.CHANNEL_TICKS * 100.0
	back_button.visible = not session.awaiting_return

## Подпись точки из реальных данных снимка: номер, локация, уровень героя.
func _snapshot_label(snapshot: Dictionary) -> String:
	var location: String = UiText.location(String(snapshot.get("location_id", "")))
	var level: int = 0
	var profile: Dictionary = snapshot.get("profile", {})
	if profile.has("hero"):
		level = int((profile["hero"] as Dictionary).get("level", 0))
	var parts: Array[String] = ["Точка №%d" % int(snapshot.get("sequence", 0)), location]
	if level > 0:
		# Неразрывный пробел: «ур.» и число не разводятся по разным строкам.
		parts.append("ур.\u00A0%d" % level)
	return " · ".join(parts)

func _refresh_points() -> void:
	var service: CheckpointService = session.checkpoints
	var signature: String = "return" if session.awaiting_return else "manage"
	if session.awaiting_return:
		signature += "|first:%s" % service.first_trace_available
		for snapshot: Dictionary in service.manual_snapshots:
			signature += "|%s" % snapshot["checkpoint_id"]
	else:
		for snapshot: Dictionary in service.manual_snapshots:
			signature += "|%s" % snapshot["checkpoint_id"]
	if signature == _built_signature:
		return
	_built_signature = signature
	_selected_option = {}
	for child: Node in points_list.get_children():
		points_list.remove_child(child)
		child.queue_free()
	if session.awaiting_return:
		_build_return_options()
	else:
		_build_manage_cards()
	var count: int = service.manual_snapshots.size()
	points_count.visible = count > 0
	if count > 0:
		points_count.text = "Точек: %d/3" % count

func _build_return_options() -> void:
	var service: CheckpointService = session.checkpoints
	if service.first_trace_available:
		_add_option_button(
			{"kind": "first_trace", "id": "first_trace", "label": "Первый след"},
			"Первый след\nСтарт пути · +1 След"
		)
	for index: int in range(service.manual_snapshots.size() - 1, -1, -1):
		var snapshot: Dictionary = service.manual_snapshots[index]
		var option: Dictionary = {
			"kind": "manual",
			"id": snapshot["checkpoint_id"],
			"label": _snapshot_label(snapshot),
			"index": index,
		}
		_add_option_button(option, "%s\n+1 След" % option["label"])
	if not service.first_trace_available and service.manual_snapshots.is_empty():
		_add_option_button(
			{"kind": "fallback", "id": "", "label": "Исходный след"},
			"Исходный след\n+2 Следа · потеря незакреплённых Кристаллов"
		)

func _add_option_button(option: Dictionary, text: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 34)
	button.add_theme_font_size_override("font_size", 9)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.icon = ArtMap.texture(ArtMap.UI["checkpoint_spent"])
	button.add_theme_constant_override("icon_max_width", 20)
	button.pressed.connect(_on_option_pressed.bind(option))
	points_list.add_child(button)

func _build_manage_cards() -> void:
	for snapshot: Dictionary in session.checkpoints.manual_snapshots:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.texture = ArtMap.texture(ArtMap.UI["checkpoint_active"])
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var label := Label.new()
		label.text = _snapshot_label(snapshot)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_stylebox_override("normal", AppTheme.flat(AppTheme.COLOR_HUD, AppTheme.COLOR_PANEL_BORDER, 1, 2))
		row.add_child(label)
		var delete := Button.new()
		UiIcons.apply(delete, "delete", "Удалить точку")
		delete.pressed.connect(_on_delete_pressed.bind(snapshot["checkpoint_id"], label.text))
		row.add_child(delete)
		points_list.add_child(row)
	if points_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Точек пока нет"
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", AppTheme.COLOR_TEXT_DIM)
		empty.add_theme_stylebox_override("normal", AppTheme.flat(AppTheme.COLOR_HUD, AppTheme.COLOR_PANEL_BORDER, 1, 2))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		points_list.add_child(empty)

func _refresh_preview() -> void:
	preview.visible = session.awaiting_return and not _selected_option.is_empty()
	if not preview.visible:
		return
	var cost: int = 2 if _selected_option.get("kind", "") == "fallback" else 1
	var next_traces: int = mini(3, session.traces + cost)
	match String(_selected_option.get("kind", "")):
		"first_trace":
			preview_title.text = "Возврат к Первому следу"
			preview_text.text = (
				"Цена: +1 След (будет %d/3).\nРучные точки после возврата сгорят." % next_traces
			)
			confirm_return.text = "Вернуться · +1 След"
		"manual":
			preview_title.text = "Возврат: %s" % _selected_option.get("label", "")
			preview_text.text = (
				"Цена: +1 След (будет %d/3).\nВыбранная и более поздние точки сгорят." % next_traces
			)
			confirm_return.text = "Вернуться · +1 След"
		_:
			preview_title.text = "Возврат к Исходному следу"
			preview_text.text = (
				"Цена: +2 Следа (будет %d/3).\nНезакреплённые Кристаллы Эха будут потеряны." % mini(3, session.traces + 2)
			)
			confirm_return.text = "Вернуться · +2 Следа"
	if next_traces == 3:
		preview_text.text += "\n3/3: возврат в Лиорен."
	_refresh_preview_art()

## Миниатюра выбранной точки: фон её локации из того же маппинга, что у
## основного фона экрана. До подтверждения выбор ничего не расходует.
func _refresh_preview_art() -> void:
	var location_id: String = ""
	var service: CheckpointService = session.checkpoints
	match String(_selected_option.get("kind", "")):
		"manual":
			for snapshot: Dictionary in service.manual_snapshots:
				if snapshot.get("checkpoint_id", "") == _selected_option.get("id", ""):
					location_id = String(snapshot.get("location_id", ""))
					break
		"first_trace", "fallback":
			location_id = String(service.first_trace_snapshot.get("location_id", ""))
	if location_id.is_empty():
		preview_art.hide()
		return
	var background_key: String = "world_lioren" if location_id == "lioren" else "world_forest_edge"
	preview_art.texture = ArtMap.texture(ArtMap.BACKGROUNDS[background_key])
	preview_art.show()

func _play_set_fx() -> void:
	if _set_fx_tween != null and _set_fx_tween.is_valid():
		_set_fx_tween.kill()
	set_fx.modulate.a = 0.0
	set_fx.scale = Vector2(0.7, 0.7)
	set_fx.show()
	_set_fx_tween = create_tween().set_parallel(true)
	_set_fx_tween.tween_property(set_fx, "modulate:a", 1.0, 0.15)
	_set_fx_tween.tween_property(set_fx, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fade := create_tween()
	fade.tween_property(set_fx, "modulate:a", 0.0, 0.5).set_delay(0.8)
	fade.tween_callback(set_fx.hide)
