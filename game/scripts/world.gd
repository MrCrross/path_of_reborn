extends Control

signal navigate_requested(destination: String)

var session: GameSession

@onready var heading: Label = %Heading
@onready var status_text: Label = %StatusText
@onready var slime_button: Button = %SlimeButton
@onready var goblin_button: Button = %GoblinButton
@onready var inventory_button: Button = %InventoryButton
@onready var checkpoint_button: Button = %CheckpointButton
@onready var rest_button: Button = %RestButton

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	_refresh()
	slime_button.grab_focus()

func _on_slime_pressed() -> void:
	if session.select_encounter("moss_slime"):
		navigate_requested.emit("combat")

func _on_goblin_pressed() -> void:
	if session.select_encounter("goblin_scout"):
		navigate_requested.emit("combat")

func _on_inventory_pressed() -> void:
	navigate_requested.emit("inventory")

func _on_checkpoint_pressed() -> void:
	session.checkpoints.notify_movement()
	navigate_requested.emit("checkpoint")

func _on_rest_pressed() -> void:
	if session.checkpoints.rest():
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		_on_inventory_pressed()
	elif event.is_action_pressed("checkpoint"):
		get_viewport().set_input_as_handled()
		_on_checkpoint_pressed()

func _refresh() -> void:
	var location_name: String = "Лиорен" if session.location_id == "lioren" else "Граница леса"
	heading.text = location_name.to_upper()
	status_text.text = "Харуто · ур. %d · HP %d/%d\nСила %d · Защита %d · XP %d/%d\nСледы %d/3 · Отголоски %d" % [
		session.hero.level,
		session.hero.current_hp,
		session.hero.max_hp,
		session.hero.strength,
		session.hero.defense,
		session.hero.experience,
		session.hero.xp_to_next_level(),
		session.traces,
		session.echoes,
	]
	var combat_blocked: bool = session.awaiting_return or session.traces == 3
	slime_button.disabled = combat_blocked
	goblin_button.disabled = combat_blocked or not session.completed_encounter_ids.has("moss_slime")
	rest_button.visible = session.location_id == "lioren" and session.traces > 0
	if session.completed_encounter_ids.has("goblin_scout"):
		status_text.text += "\nОба противника побеждены. Бои можно повторить."
	if session.awaiting_return:
		status_text.text += "\nТребуется возврат через Печать Пути."
