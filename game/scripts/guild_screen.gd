extends Control

signal navigate_requested(destination: String)
signal guild_registration_requested

const REGISTRATION_PATH := "res://data/narrative/guild_registration.json"
const HALL_PLAN := Vector2(180, 320)

var session: GameSession
var dialogue: DialogueOverlay

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
		$SafeArea.hide()
		dialogue.runner.changed.connect(_show_dialogue_shot)
		_show_dialogue_shot()
	else:
		_show_desk()

func handle_back() -> bool:
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
	_show_desk()

func _show_desk() -> void:
	_show_shot("guild_hall")
	$SafeArea.show()
	var rank: String = session.guild_rank()
	var registered: bool = not rank.is_empty()
	%Rank.text = ("Ранг %s · Знак Гильдии" % rank) if registered else "Регистрация"
	%OrderTitle.text = "Выдано первое задание" if session.quest_flags.get(GameSession.FIRST_GUILD_ORDER_ID, false) == true else "Первое задание"
	%Error.hide()
	register_button.visible = session.can_register_with_guild()
	if register_button.visible:
		register_button.grab_focus()
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
