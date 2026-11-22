class_name CombatArenaPresenter
extends Node

signal intro_finished

const INTRO_SECONDS := 0.55
const CLIP_PRIORITY: Dictionary = {"idle": 0, "attack": 1, "hit": 2, "dodge": 2}
const UNARMED_CONTACT_FRAME: int = 3
const UNARMED_MOTION := {"idle": [0], "attack": [0, -2, 4, 12, 3], "hit": [-4, 0], "dodge": [0, -3, -8, -2]}
const GOBLIN_PREPARE_FRAMES: Array[int] = [0, 3]
const GOBLIN_CONTACT_FRAMES: Array[int] = [1, 4]
const GOBLIN_RECOVER_FRAME: int = 5

var arena: Control
var telegraph: Sprite2D
var phase_cue: Label
var hero_sprite: AnimatedSprite2D
var enemy_sprite: AnimatedSprite2D
var hero_health: ActorHealthDisplay
var enemy_health: ActorHealthDisplay
var resolver: CombatResolver
var session: GameSession
var intro_active: bool = false
var _intro_tween: Tween
var _telegraph_pulse: Tween
var _hero_frames: Dictionary = {}
var _enemy_frames: Dictionary = {}
var _enemy_head: Vector2 = Vector2(0, -54)
var _hero_clip_priority: int = 0
var _hero_clip_name: String = "idle"
var _hero_unarmed: bool = false
var _hero_contact_frame: int = UNARMED_CONTACT_FRAME
var _enemy_busy: bool = false
var _last_phase: int = -1
var _battle_tweens: Array[Tween] = []

func configure(target_session: GameSession, arena_node: Control, hero: AnimatedSprite2D, enemy: AnimatedSprite2D, telegraph_node: Sprite2D, cue: Label) -> void:
	session = target_session
	arena = arena_node
	hero_sprite = hero
	enemy_sprite = enemy
	telegraph = telegraph_node
	phase_cue = cue
	_setup_art()
	hero_health = ActorHealthDisplay.new()
	hero_health.name = "HeroHealth"
	hero_health.setup("hero", true)
	arena.add_child(hero_health)
	enemy_health = ActorHealthDisplay.new()
	enemy_health.name = "EnemyHealth"
	enemy_health.setup("enemy", true)
	arena.add_child(enemy_health)
	if not arena.resized.is_connected(layout):
		arena.resized.connect(layout)
	layout()

func bind_resolver(next_resolver: CombatResolver) -> void:
	resolver = next_resolver
	_last_phase = -1
	resolver.phase_changed.connect(_on_phase_changed)
	resolver.damage_dealt.connect(_on_damage_dealt)
	resolver.dodge_begun.connect(_on_dodge_begun)
	resolver.hero_attack_begun.connect(_on_hero_attack_begun)
	resolver.hero_attack_landed.connect(_on_hero_attack_landed)
	refresh()

func update_positions() -> void:
	telegraph.position = enemy_sprite.position + Vector2(0, 1)
	var cue_position := (enemy_sprite.position + Vector2(_enemy_head.x - 12.0, _enemy_head.y - 37.0)).round()
	cue_position.x = clampf(cue_position.x, 0.0, maxf(0.0, arena.size.x - phase_cue.size.x))
	phase_cue.position = cue_position
	var bounds := Rect2(Vector2.ZERO, arena.size)
	hero_health.follow(hero_sprite.position + Vector2(ArtMap.HERO_EXILED["idle"]["head"]), bounds)
	enemy_health.follow(enemy_sprite.position + _enemy_head, bounds)

func layout() -> void:
	var arena_size: Vector2 = arena.size
	if arena_size.x < 32.0 or arena_size.y < 32.0:
		return
	hero_sprite.position = SceneStaging.hero_anchor(arena_size).round()
	if not (intro_active and _intro_tween != null and _intro_tween.is_valid()):
		enemy_sprite.position = SceneStaging.enemy_anchor(arena_size).round()
	telegraph.scale = Vector2.ONE
	update_positions()

func start_intro() -> void:
	intro_active = true
	var target: Vector2 = SceneStaging.enemy_anchor(arena.size)
	enemy_sprite.position = target + Vector2(maxf(48.0, arena.size.x * 0.4), 0)
	_intro_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_intro_tween.tween_property(enemy_sprite, "position", target, INTRO_SECONDS)
	_intro_tween.tween_callback(_finish_intro)

func _finish_intro() -> void:
	if not intro_active:
		return
	intro_active = false
	_intro_tween = null
	layout()
	intro_finished.emit()

func set_pause(open: bool) -> void:
	if open:
		hero_sprite.pause()
		enemy_sprite.pause()
		if _intro_tween != null and _intro_tween.is_valid():
			_intro_tween.pause()
		if _telegraph_pulse != null and _telegraph_pulse.is_valid():
			_telegraph_pulse.pause()
		for tween: Tween in _battle_tweens:
			if tween.is_valid():
				tween.pause()
	else:
		hero_sprite.play()
		enemy_sprite.play()
		if _intro_tween != null and _intro_tween.is_valid():
			_intro_tween.play()
		if _telegraph_pulse != null and _telegraph_pulse.is_valid():
			_telegraph_pulse.play()
		for tween: Tween in _battle_tweens:
			if tween.is_valid():
				tween.play()

func refresh() -> void:
	if resolver == null:
		return
	hero_health.set_hp(resolver.hero.current_hp, resolver.hero.max_hp)
	enemy_health.set_hp(resolver.enemy.current_hp, resolver.enemy.max_hp)
	_update_enemy_clip()
	_update_phase_cue()

func finish(player_won: bool) -> void:
	telegraph.hide()
	_stop_telegraph_pulse()
	phase_cue.text = ""
	hero_sprite.play()
	enemy_sprite.play()
	enemy_sprite.modulate = Color.WHITE
	if player_won:
		play_enemy_defeat()
		enemy_health.hide()

func show_restored() -> void:
	enemy_sprite.hide()
	enemy_health.hide()
	telegraph.hide()
	_reset_hero_to_idle()
	layout()

func _on_phase_changed(_phase: int, _ticks_remaining: int) -> void:
	refresh()

func _on_damage_dealt(target_id: String, amount: int) -> void:
	if target_id == "hero":
		_play_hero_clip("hit")
	else:
		_play_enemy_clip("hit", true)
	spawn_damage_number(target_id, amount)
	refresh()

func _on_dodge_begun(_source: String) -> void:
	_play_hero_clip("dodge")

func _on_hero_attack_begun(_run_id: String) -> void:
	_play_hero_clip("attack")
	if _hero_clip_name == "attack":
		hero_sprite.set_frame_and_progress(0, 0.0)

func _on_hero_attack_landed(_run_id: String, _target_id: String, _amount: int) -> void:
	if _hero_clip_name == "attack":
		hero_sprite.set_frame_and_progress(_hero_contact_frame, 0.0)
	if _hero_clip_name != "attack" or _hero_unarmed:
		_spawn_contact_flash()

func _update_phase_cue() -> void:
	if resolver == null or resolver.is_finished or _last_phase == resolver.enemy_phase:
		return
	_last_phase = resolver.enemy_phase
	_stop_telegraph_pulse()
	match resolver.enemy_phase:
		CombatResolver.Phase.TELEGRAPH:
			phase_cue.text = "!"
			phase_cue.add_theme_color_override("font_color", Color("e08a6a"))
			_start_telegraph_pulse()
		_:
			phase_cue.text = ""

func _start_telegraph_pulse() -> void:
	if not telegraph.visible or (_telegraph_pulse != null and _telegraph_pulse.is_valid()):
		return
	_telegraph_pulse = create_tween().set_loops()
	_telegraph_pulse.tween_property(telegraph, "self_modulate:a", 0.45, 0.28)
	_telegraph_pulse.tween_property(telegraph, "self_modulate:a", 1.0, 0.28)

func _stop_telegraph_pulse() -> void:
	if _telegraph_pulse != null and _telegraph_pulse.is_valid():
		_telegraph_pulse.kill()
	_telegraph_pulse = null
	telegraph.self_modulate.a = 1.0

func spawn_damage_number(target_id: String, amount: int) -> void:
	var label := Label.new()
	label.text = "-%d" % amount
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("f2e3c9") if target_id != "hero" else Color("e89a86"))
	var side := Vector2(-16, -30) if target_id == "hero" else Vector2(12, -30)
	label.position = ((hero_sprite.position if target_id == "hero" else enemy_sprite.position) + side).round()
	arena.add_child(label)
	label.reset_size()
	label.position.x = clampf(label.position.x, 0.0, maxf(0.0, arena.size.x - label.size.x))
	label.position.y = clampf(label.position.y, 0.0, maxf(0.0, arena.size.y - label.size.y))
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", maxf(0.0, label.position.y - 16.0), 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)
	_track_tween(tween)

func _spawn_contact_flash() -> void:
	var label := Label.new()
	label.text = "◆"
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", AppTheme.COLOR_ACCENT)
	label.position = (enemy_sprite.position + Vector2(-5, -30)).round()
	arena.add_child(label)
	label.reset_size()
	label.position.x = clampf(label.position.x, 0.0, maxf(0.0, arena.size.x - label.size.x))
	label.position.y = clampf(label.position.y, 0.0, maxf(0.0, arena.size.y - label.size.y))
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 0.18)
	tween.tween_callback(label.queue_free)
	_track_tween(tween)

func _track_tween(tween: Tween) -> void:
	_battle_tweens.append(tween)
	tween.finished.connect(_on_battle_tween_finished.bind(tween))

func _on_battle_tween_finished(tween: Tween) -> void:
	_battle_tweens.erase(tween)

func play_enemy_defeat() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(enemy_sprite, "modulate:a", 0.0, 0.55)
	tween.tween_property(enemy_sprite, "position:y", enemy_sprite.position.y + 6.0, 0.55)
	_track_tween(tween)

func _setup_art() -> void:
	var still_id: String = ArtMap.hero_still_id(session.inventory)
	_hero_unarmed = still_id == "haruto_exiled_unarmed"
	if _hero_unarmed:
		_setup_unarmed_art(still_id)
	else:
		var sheets: Dictionary = ArtMap.HERO_EXILED_SWORD if still_id == "haruto_exiled_sword" else ArtMap.HERO_EXILED
		_hero_contact_frame = sheets["attack"]["contact_frame"]
		for clip_name: String in sheets:
			_hero_frames[clip_name] = _build_clip(sheets[clip_name], clip_name != "idle")
	var enemy_id: String = session.current_enemy_id
	for clip_name: String in ArtMap.ENEMY_SHEETS.get(enemy_id, {}):
		_enemy_frames[clip_name] = _build_clip(ArtMap.ENEMY_SHEETS[enemy_id][clip_name], clip_name not in ["idle", "attack"])
	_enemy_head = ArtMap.ENEMY_SHEETS.get(enemy_id, {}).get("idle", {}).get("head", Vector2(0, -54))
	enemy_sprite.scale = Vector2.ONE
	_apply_clip(hero_sprite, _hero_frames["idle"])
	hero_sprite.play(&"default")
	_apply_clip(enemy_sprite, _enemy_frames["idle"])
	enemy_sprite.play(&"default")
	hero_sprite.animation_finished.connect(_reset_hero_to_idle)
	enemy_sprite.animation_finished.connect(_on_enemy_clip_finished)

func _setup_unarmed_art(still_id: String) -> void:
	# Until there are unarmed pose sheets, move the empty-handed stance on the
	# ground line for each action. Contact feedback still comes from the resolver.
	var still: Dictionary = ArtMap.SOURCE_STILLS[still_id]
	var texture: Texture2D = ArtMap.texture(still["path"])
	var scale_factor: float = ArtMap.still_scale(still_id)
	var padding: float = ceilf(12.0 / scale_factor)
	var canvas_offset: Vector2 = texture.get_size() * 0.5 - Vector2(still["pivot"])
	for clip_name: String in UNARMED_MOTION:
		var frames := SpriteFrames.new()
		frames.set_animation_speed(&"default", 10.0)
		frames.set_animation_loop(&"default", clip_name == "idle")
		for shift: int in UNARMED_MOTION[clip_name]:
			var frame := AtlasTexture.new()
			frame.atlas = texture
			frame.region = Rect2(Vector2.ZERO, texture.get_size())
			frame.margin = Rect2(padding + roundf(shift / scale_factor), 0.0, padding * 2.0, 0.0)
			frames.add_frame(&"default", frame)
		_hero_frames[clip_name] = {"frames": frames, "offset": canvas_offset, "scale": Vector2.ONE * scale_factor}

func _build_clip(sheet: Dictionary, one_shot: bool) -> Dictionary:
	var spec: Dictionary = ArtMap.animation_spec(sheet)
	return {"frames": ArtMap.sprite_frames(sheet, 10.0, one_shot), "offset": spec["offset"], "scale": Vector2.ONE * float(spec.get("scale", 1.0))}

func _apply_clip(sprite: AnimatedSprite2D, clip: Dictionary) -> void:
	if sprite.sprite_frames != clip["frames"]:
		sprite.sprite_frames = clip["frames"]
		sprite.offset = clip["offset"]
		sprite.scale = clip["scale"]

func _play_hero_clip(clip_name: String) -> void:
	var priority: int = int(CLIP_PRIORITY.get(clip_name, 0))
	if _hero_clip_priority > 0 and priority < _hero_clip_priority:
		return
	_hero_clip_name = clip_name
	_hero_clip_priority = 0 if clip_name == "idle" else priority
	_apply_clip(hero_sprite, _hero_frames[clip_name])
	hero_sprite.play(&"default")

func _reset_hero_to_idle() -> void:
	_hero_clip_priority = 0
	_hero_clip_name = "idle"
	_apply_clip(hero_sprite, _hero_frames["idle"])
	hero_sprite.play(&"default")

func _play_enemy_clip(clip_name: String, force: bool = false) -> void:
	if not _enemy_frames.has(clip_name) or (_enemy_busy and not force):
		return
	_enemy_busy = clip_name == "hit"
	_apply_clip(enemy_sprite, _enemy_frames[clip_name])
	enemy_sprite.play(&"default")

func _on_enemy_clip_finished() -> void:
	_enemy_busy = false
	if resolver != null and not resolver.is_finished:
		_apply_clip(enemy_sprite, _enemy_frames["idle"])
		enemy_sprite.play(&"default")

func _update_enemy_clip() -> void:
	if resolver == null or resolver.is_finished:
		return
	var is_slime: bool = resolver.enemy.definition.behavior_id == "slime"
	match resolver.enemy_phase:
		CombatResolver.Phase.TELEGRAPH:
			_enemy_busy = false
			enemy_sprite.modulate = Color.WHITE
			telegraph.modulate = Color(1, 0.55, 0.45, 0.9)
			telegraph.show()
			_play_enemy_clip("idle")
		CombatResolver.Phase.STARTUP:
			telegraph.hide()
			enemy_sprite.modulate = Color.WHITE
			_play_enemy_clip("attack")
			_set_enemy_strike_frame(false)
		CombatResolver.Phase.ACTIVE:
			telegraph.hide()
			enemy_sprite.modulate = Color.WHITE
			_enemy_busy = false
			_play_enemy_clip("attack", true)
			_set_enemy_strike_frame(true)
		CombatResolver.Phase.RECOVERY:
			telegraph.hide()
			enemy_sprite.modulate = Color.WHITE
			if is_slime:
				_play_enemy_clip("idle")
			elif not _enemy_busy:
				_play_enemy_clip("attack", true)
				enemy_sprite.frame = mini(GOBLIN_RECOVER_FRAME, enemy_sprite.sprite_frames.get_frame_count(&"default") - 1)
				enemy_sprite.frame_progress = 0.0
				_enemy_busy = true
		CombatResolver.Phase.VULNERABILITY:
			enemy_sprite.modulate = Color(1.15, 1.05, 0.75)
			telegraph.modulate = Color(1.2, 1.0, 0.45, 0.9)
			telegraph.show()
			_enemy_busy = false
			_play_enemy_clip("idle")

func _set_enemy_strike_frame(contact: bool) -> void:
	if resolver.enemy.definition.behavior_id != "goblin" or enemy_sprite.sprite_frames != _enemy_frames["attack"]["frames"]:
		return
	var roles: Array[int] = GOBLIN_CONTACT_FRAMES if contact else GOBLIN_PREPARE_FRAMES
	var index: int = clampi(resolver.strike_index, 0, roles.size() - 1)
	enemy_sprite.frame = mini(roles[index], enemy_sprite.sprite_frames.get_frame_count(&"default") - 1)
	enemy_sprite.frame_progress = 0.0
