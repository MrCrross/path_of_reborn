extends Control

signal navigate_requested(destination: String)

var session: GameSession

@onready var contract_text: Label = %ContractText
@onready var progress_text: Label = %ProgressText
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var start_button: Button = %StartButton
@onready var cancel_button: Button = %CancelButton
@onready var points_list: VBoxContainer = %PointsList
@onready var back_button: Button = %BackButton

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	_refresh()
	if session.awaiting_return:
		back_button.hide()
		if points_list.get_child_count() > 0:
			(points_list.get_child(0) as Control).grab_focus()
	else:
		start_button.grab_focus()

func _physics_process(_delta: float) -> void:
	if session.checkpoints.channel_active:
		session.checkpoints.advance_ticks(1)
		_refresh()

func _exit_tree() -> void:
	if session != null and session.checkpoints.channel_active:
		session.checkpoints.cancel()

func _on_start_pressed() -> void:
	session.checkpoints.begin()
	_refresh()

func _on_cancel_pressed() -> void:
	session.checkpoints.cancel()
	_refresh()

func _on_back_pressed() -> void:
	navigate_requested.emit("world")

func _on_restore_pressed(checkpoint_id: String) -> void:
	if session.checkpoints.restore(checkpoint_id):
		navigate_requested.emit("world")

func _on_delete_pressed(checkpoint_id: String) -> void:
	session.checkpoints.delete_checkpoint(checkpoint_id)
	_refresh()

func _refresh() -> void:
	var service: CheckpointService = session.checkpoints
	if session.awaiting_return:
		contract_text.text = "ВОЗВРАТ — НЕ БЕСПЛАТНЫЙ RETRY\nТочка: +1 След. Без точек: +2 и потеря незакреплённых Кристаллов."
	else:
		contract_text.text = "ПЕЧАТЬ ПУТИ\n5 сек неподвижно · вне боя\nРучные %d/3 · Следы %d/3 · Отголоски %d" % [service.manual_snapshots.size(), session.traces, session.echoes]
	progress_text.visible = service.channel_active
	progress_bar.visible = service.channel_active
	progress_text.text = "Фиксация: оставайся на месте"
	progress_bar.value = float(service.channel_ticks) / CheckpointService.CHANNEL_TICKS * 100.0
	start_button.visible = not session.awaiting_return
	start_button.disabled = not service.can_begin()
	cancel_button.visible = service.channel_active
	back_button.visible = not session.awaiting_return
	for child: Node in points_list.get_children():
		points_list.remove_child(child)
		child.queue_free()
	if session.awaiting_return:
		_build_return_buttons()
	else:
		_build_delete_buttons()

func _build_return_buttons() -> void:
	var service: CheckpointService = session.checkpoints
	if service.first_trace_available:
		_add_return_button("Первый след · +1 След", "first_trace")
	for index: int in range(service.manual_snapshots.size() - 1, -1, -1):
		var snapshot: Dictionary = service.manual_snapshots[index]
		_add_return_button("К %s · +1 След" % snapshot["checkpoint_id"], snapshot["checkpoint_id"])
	if not service.first_trace_available and service.manual_snapshots.is_empty():
		_add_return_button("Исходный след · +2\nПотеря незакреплённых Кристаллов", "")

func _add_return_button(text: String, checkpoint_id: String) -> void:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, 34)
	button.add_theme_font_size_override("font_size", 10)
	button.pressed.connect(_on_restore_pressed.bind(checkpoint_id))
	points_list.add_child(button)

func _build_delete_buttons() -> void:
	for snapshot: Dictionary in session.checkpoints.manual_snapshots:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = snapshot["checkpoint_id"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 9)
		var delete := Button.new()
		delete.text = "Удалить"
		delete.custom_minimum_size = Vector2(0, 28)
		delete.add_theme_font_size_override("font_size", 9)
		delete.pressed.connect(_on_delete_pressed.bind(snapshot["checkpoint_id"]))
		row.add_child(label)
		row.add_child(delete)
		points_list.add_child(row)
