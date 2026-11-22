extends Control

signal navigate_requested(destination: String)

var session: GameSession
var dialogue: DialogueOverlay
var backdrop: TextureRect
var hero: Sprite2D
var slime: AnimatedSprite2D
var cart: Sprite2D
var merchant: Sprite2D
var goblin: AnimatedSprite2D

var _approach: String
var _leaping: bool = false
var _leap_progress: float = 0.0

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	_approach = session.next_route_approach()
	if _approach not in ["first_slime", "daijiro_lookout"]:
		_finish.call_deferred()
		return
	backdrop = TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.texture = ArtMap.texture(ArtMap.BACKGROUNDS["world_forest_edge"])
	add_child(backdrop)
	if _approach == "first_slime":
		slime = _actor(ArtMap.ENEMY_SHEETS["moss_slime"]["idle"])
		slime.play()
	else:
		cart = _prop(ArtMap.DAIJIRO_CART_PROP, Vector2(180, 215), 0.22)
		merchant = _prop(ArtMap.DAIJIRO_MERCHANT_STILL, Vector2(144, 374), 0.17)
		goblin = _actor(ArtMap.GOBLIN_SCOUT_SHEETS["attack"])
		goblin.scale *= 0.77
		goblin.frame = 3
	var still_id := ArtMap.hero_still_id(session.inventory)
	var still: Dictionary = ArtMap.SOURCE_STILLS[still_id]
	hero = _prop(still["path"], still["pivot"], ArtMap.still_scale(still_id))
	resized.connect(_layout)
	_layout()

	dialogue = DialogueOverlay.new()
	dialogue.name = "Dialogue"
	dialogue.configure(session)
	dialogue.command_requested.connect(_on_command)
	dialogue.finished.connect(_on_dialogue_finished)
	add_child(dialogue)
	var is_slime: bool = _approach == "first_slime"
	var path: String = "res://data/narrative/first_slime.json" if is_slime else "res://data/narrative/daijiro_lookout.json"
	var caption: String = "В бой" if is_slime else "Бросить камень"
	if dialogue.play(path, caption):
		dialogue.runner.changed.connect(_refresh_pose)
		_refresh_pose()
	else:
		_finish.call_deferred()

func _prop(path: String, pivot: Vector2, art_scale: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = ArtMap.texture(path)
	sprite.centered = false
	sprite.offset = -pivot
	sprite.scale = Vector2.ONE * art_scale
	add_child(sprite)
	return sprite

func _actor(clip: Dictionary) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	_set_clip(sprite, clip, true)
	add_child(sprite)
	return sprite

func _set_clip(sprite: AnimatedSprite2D, clip: Dictionary, loop: bool) -> void:
	sprite.sprite_frames = ArtMap.sprite_frames(clip, 9.0, not loop)
	ArtMap.apply_animation_transform(sprite, clip)

func _layout() -> void:
	var ground := SceneStaging.floor_y(size.y)
	hero.position = SceneStaging.hero_anchor(size).round()
	if slime != null:
		_place_slime(_leap_progress)
	else:
		hero.position.x = roundf(size.x * 0.20)
		cart.position = Vector2(size.x * 0.76, ground - 36).round()
		merchant.position = Vector2(size.x * 0.61, ground - 8).round()
		goblin.position = Vector2(size.x * 0.84, ground - 6).round()

func _refresh_pose() -> void:
	if slime == null or _leaping or dialogue.runner.current_shot() != "slime_leaps":
		return
	_leaping = true
	_set_clip(slime, ArtMap.ENEMY_SHEETS["moss_slime"]["attack"], false)
	slime.play()
	create_tween().tween_method(_place_slime, 0.0, 1.0, 0.48)

func _place_slime(progress: float) -> void:
	_leap_progress = progress
	var offset := Vector2(-24.0 * progress, -20.0 * sin(progress * PI))
	slime.position = (SceneStaging.enemy_anchor(size) + offset).round()

func _on_command(command: Dictionary) -> void:
	if command["type"] == "set_world_flag":
		session.world_flags[String(command["key"])] = command["value"]

func _on_dialogue_finished(_destination: String) -> void:
	_finish()

func _finish() -> void:
	if not is_inside_tree():
		return
	if _approach == "daijiro_lookout" and session.next_route_approach() == "daijiro_cart":
		navigate_requested.emit("merchant")
	elif _approach == "first_slime" and session.select_encounter("moss_slime"):
		navigate_requested.emit("combat")
	else:
		navigate_requested.emit("world")
