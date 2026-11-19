extends Control

signal navigate_requested(destination: String)

var session: GameSession
var resolver: CombatResolver
var last_event: String = ""

@onready var enemy_name: Label = %EnemyName
@onready var hero_hp_text: Label = %HeroHpText
@onready var hero_hp_bar: ProgressBar = %HeroHpBar
@onready var enemy_hp_text: Label = %EnemyHpText
@onready var enemy_hp_bar: ProgressBar = %EnemyHpBar
@onready var hero_marker: Label = %HeroMarker
@onready var enemy_marker: Label = %EnemyMarker
@onready var phase_label: Label = %PhaseLabel
@onready var hint_label: Label = %HintLabel
@onready var result_label: Label = %ResultLabel
@onready var actions: HBoxContainer = %Actions
@onready var attack_button: Button = %AttackButton
@onready var dodge_button: Button = %DodgeButton
@onready var retry_button: Button = %RetryButton
@onready var continue_button: Button = %ContinueButton

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null:
		session = GameSession.new()
		session.select_encounter("moss_slime")
	_set_resolver(session.start_combat(session.current_enemy_id))
	attack_button.grab_focus()

func _physics_process(_delta: float) -> void:
	if resolver != null:
		resolver.advance_ticks(1)
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("primary"):
		_on_attack_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("secondary"):
		_on_dodge_pressed()
		get_viewport().set_input_as_handled()

func _set_resolver(next_resolver: CombatResolver) -> void:
	resolver = next_resolver
	last_event = ""
	resolver.phase_changed.connect(_on_phase_changed)
	resolver.damage_dealt.connect(_on_damage_dealt)
	resolver.dodge_resolved.connect(_on_dodge_resolved)
	resolver.finished.connect(_on_finished)
	result_label.text = ""
	retry_button.hide()
	continue_button.hide()
	_refresh()

func _on_attack_pressed() -> void:
	if resolver != null and resolver.request_attack():
		last_event = ""
		_refresh()

func _on_dodge_pressed() -> void:
	if resolver != null and resolver.request_dodge():
		last_event = "Уклонение активно"
		_refresh()

func _on_retry_pressed() -> void:
	navigate_requested.emit("checkpoint")

func _on_continue_pressed() -> void:
	navigate_requested.emit("reward" if not session.pending_reward.is_empty() else "world")

func _on_phase_changed(_phase: int, _ticks_remaining: int) -> void:
	last_event = ""
	_refresh()

func _on_damage_dealt(_target_id: String, _amount: int) -> void:
	_refresh()

func _on_dodge_resolved(success: bool) -> void:
	last_event = "Удар отклонён" if success else "Удар получен"
	_refresh()

func _on_finished(player_won: bool) -> void:
	if player_won:
		session.apply_victory(session.current_enemy_id)
		continue_button.text = "Получить награду" if not session.pending_reward.is_empty() else "Вернуться к пути"
		result_label.text = "ПОБЕДА\nУровень %d · XP %d/%d" % [
			session.hero.level,
			session.hero.experience,
			session.hero.xp_to_next_level(),
		]
	else:
		retry_button.text = "Выбрать возврат"
		result_label.text = "ПОРАЖЕНИЕ\nПечать Пути требует возврата."
	_refresh()
	if player_won:
		continue_button.grab_focus()
	else:
		retry_button.grab_focus()

func _refresh() -> void:
	if resolver == null:
		return
	enemy_name.text = resolver.enemy.definition.display_name
	hero_hp_text.text = "Харуто · %d/%d" % [resolver.hero.current_hp, resolver.hero.max_hp]
	hero_hp_bar.max_value = resolver.hero.max_hp
	hero_hp_bar.value = resolver.hero.current_hp
	enemy_hp_text.text = "Противник · %d/%d" % [resolver.enemy.current_hp, resolver.enemy.max_hp]
	enemy_hp_bar.max_value = resolver.enemy.max_hp
	enemy_hp_bar.value = resolver.enemy.current_hp
	hero_marker.text = "ГЕРОЙ\nСила %d" % resolver.hero.strength
	enemy_marker.text = resolver.enemy.definition.display_name.to_upper()
	phase_label.text = "%s\n%02d ticks" % [_phase_text(), resolver.phase_ticks_remaining]
	if not last_event.is_empty():
		hint_label.text = last_event
	elif resolver.is_vulnerable():
		hint_label.text = "Окно ответа: урон ×%d" % roundi(resolver.enemy.definition.vulnerability_multiplier)
	else:
		hint_label.text = "Space: атака · E: уклонение"
	actions.visible = not resolver.is_finished
	attack_button.disabled = resolver.is_finished or resolver.hero_attack_cooldown > 0
	dodge_button.disabled = resolver.is_finished or resolver.dodge_cooldown > 0
	retry_button.visible = resolver.is_finished and not resolver.won
	continue_button.visible = resolver.is_finished and resolver.won

func _phase_text() -> String:
	var is_slime: bool = resolver.enemy.definition.behavior_id == "slime"
	match resolver.enemy_phase:
		CombatResolver.Phase.TELEGRAPH:
			return "!! СЖАТИЕ — ПРИГОТОВЬСЯ" if is_slime else "!! ЗАМАХ — ПРИГОТОВЬСЯ"
		CombatResolver.Phase.STARTUP:
			return "ПРЫЖОК" if is_slime else "ЗАМАХ %d/2" % (resolver.strike_index + 1)
		CombatResolver.Phase.ACTIVE:
			return "СТОЛКНОВЕНИЕ" if is_slime else "SLASH %d/2" % (resolver.strike_index + 1)
		CombatResolver.Phase.RECOVERY:
			return "ПРИЗЕМЛЕНИЕ" if is_slime else "ОТСТУПЛЕНИЕ"
		CombatResolver.Phase.VULNERABILITY:
			return "ЯДРО ОТКРЫТО — АТАКУЙ" if is_slime else "ПРОТИВНИК ОТКРЫТ — АТАКУЙ"
	return ""
