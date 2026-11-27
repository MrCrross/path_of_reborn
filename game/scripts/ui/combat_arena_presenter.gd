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

class GroveEnemyView:
	var sprite: AnimatedSprite2D
	var health: ActorHealthDisplay
	var warning: Sprite2D
	var cue: Label
	var clips: Dictionary = {}
	var head: Vector2
	var body_width: float
	var body_bottom: float
	var phase: int = -1
	var stunned: bool = false
	var defeated: bool = false

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
var _paused_sprites: Array[AnimatedSprite2D] = []
var _battle_tweens: Array[Tween] = []
var _grove_enemies: Array[GroveEnemyView] = []
var _pollen_cloud: Sprite2D
var _akari: AnimatedSprite2D
var _akari_clips: Dictionary = {}
var _ally_cue: Label
var _ally_notice: Tween
var _ally_fire: Sprite2D

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
	if _uses_enemy_slot_presentation():
		_build_grove_enemies()
		resolver.enemy_phase_changed.connect(_on_grove_actor_changed)
		resolver.target_changed.connect(_on_grove_actor_changed)
		if session.location_id == GameSession.LOCATION_OUTPOST:
			_build_outpost_ally()
			resolver.ally_action.connect(_on_ally_action)
	else:
		resolver.phase_changed.connect(_on_phase_changed)
	resolver.damage_dealt.connect(_on_damage_dealt)
	resolver.dodge_begun.connect(_on_dodge_begun)
	resolver.hero_attack_begun.connect(_on_hero_attack_begun)
	resolver.hero_attack_landed.connect(_on_hero_attack_landed)
	refresh()

func update_positions() -> void:
	if not _grove_enemies.is_empty():
		_update_grove_positions()
		return
	telegraph.position = enemy_sprite.position + Vector2(0, 1)
	var cue_position := (enemy_sprite.position + _enemy_head - Vector2(phase_cue.size.x * 0.5, 17.0 + phase_cue.size.y)).round()
	cue_position.x = clampf(cue_position.x, 0.0, maxf(0.0, arena.size.x - phase_cue.size.x))
	phase_cue.position = cue_position
	var bounds := Rect2(Vector2.ZERO, arena.size)
	hero_health.follow(hero_sprite.position + Vector2(ArtMap.HERO_EXILED["idle"]["head"]), bounds)
	enemy_health.follow(enemy_sprite.position + _enemy_head, bounds)

func layout() -> void:
	var arena_size: Vector2 = arena.size
	if arena_size.x < 32.0 or arena_size.y < 32.0:
		return
	var hero_anchor: Vector2 = SceneStaging.hero_anchor(arena_size) if _grove_enemies.is_empty() else SceneStaging.grove_hero_anchor(arena_size)
	hero_sprite.position = hero_anchor.round()
	if _akari != null:
		_akari.position = SceneStaging.outpost_ally_anchor(arena_size).round()
	if not (intro_active and _intro_tween != null and _intro_tween.is_valid()):
		if _grove_enemies.is_empty():
			enemy_sprite.position = SceneStaging.enemy_anchor(arena_size).round()
		else:
			for index: int in range(_grove_enemies.size()):
				_grove_enemies[index].sprite.position = _grove_anchor(index)
	if _grove_enemies.is_empty():
		telegraph.scale = Vector2.ONE / ArtMap.DETAIL_SCALE
	update_positions()

func start_intro() -> void:
	intro_active = true
	var target: Vector2 = SceneStaging.enemy_anchor(arena.size)
	enemy_sprite.position = target + Vector2(maxf(48.0, arena.size.x * 0.4), 0)
	_intro_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if _grove_enemies.is_empty():
		_intro_tween.tween_property(enemy_sprite, "position", target, INTRO_SECONDS)
	else:
		_intro_tween.set_parallel(true)
		for index: int in range(_grove_enemies.size()):
			var sprite: AnimatedSprite2D = _grove_enemies[index].sprite
			var end: Vector2 = _grove_anchor(index)
			sprite.position = end + Vector2(maxf(48.0, arena.size.x * 0.4), 0)
			_intro_tween.tween_property(sprite, "position", end, INTRO_SECONDS)
		_intro_tween.chain()
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
		# Domain-driven strike frames already stand still before the pause.
		# Resume only animations which were actually playing.
		for child: Node in arena.get_children():
			var sprite := child as AnimatedSprite2D
			if sprite != null and sprite.is_playing():
				_paused_sprites.append(sprite)
				sprite.pause()
	else:
		for sprite: AnimatedSprite2D in _paused_sprites:
			sprite.play()
		_paused_sprites.clear()
	var tweens: Array[Tween] = _battle_tweens.duplicate()
	tweens.append(_intro_tween)
	tweens.append(_telegraph_pulse)
	for tween: Tween in tweens:
		if tween != null and tween.is_valid():
			if open:
				tween.pause()
			else:
				tween.play()

func advance_pose() -> void:
	for index: int in range(_grove_enemies.size()):
		var slot: CombatResolver.EnemySlot = resolver.enemy_slots[index]
		if not slot.dormant and not slot.actor.is_dead():
			_update_grove_attack_frame(_grove_enemies[index], slot)

func refresh() -> void:
	if resolver == null:
		return
	hero_health.set_hp(resolver.hero.current_hp, resolver.hero.max_hp)
	if not _grove_enemies.is_empty():
		_refresh_grove_enemies()
		return
	enemy_health.set_hp(resolver.enemy.current_hp, resolver.enemy.max_hp)
	if not resolver.is_finished and _last_phase != resolver.enemy_phase:
		_last_phase = resolver.enemy_phase
		_update_enemy_clip()
		_update_phase_cue()
		update_positions()

func finish(player_won: bool) -> void:
	if not _grove_enemies.is_empty():
		for enemy_view: GroveEnemyView in _grove_enemies:
			enemy_view.warning.hide()
			enemy_view.cue.hide()
		_pollen_cloud.hide()
		if _ally_cue != null:
			_ally_cue.hide()
			_ally_fire.hide()
		return
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
	elif _grove_enemies.is_empty():
		_play_enemy_clip("hit", true)
	else:
		var enemy_view: GroveEnemyView = _grove_enemy_view(target_id)
		if enemy_view != null and not enemy_view.defeated:
			var sprite: AnimatedSprite2D = enemy_view.sprite
			sprite.self_modulate = Color(1.65, 1.36, 1.22)
			var flash := create_tween()
			flash.tween_property(sprite, "self_modulate", Color.WHITE, 0.16)
			_track_tween(flash)
	spawn_damage_number(target_id, amount)
	refresh()

func _on_dodge_begun(_source: String) -> void:
	_play_hero_clip("dodge")

func _on_hero_attack_begun(_run_id: String) -> void:
	_play_hero_clip("attack")
	if _hero_clip_name == "attack":
		hero_sprite.set_frame_and_progress(0, 0.0)

func _on_hero_attack_landed(_run_id: String, target_id: String, _amount: int) -> void:
	if _hero_clip_name == "attack":
		hero_sprite.set_frame_and_progress(_hero_contact_frame, 0.0)
	if _hero_clip_name != "attack" or _hero_unarmed or not _grove_enemies.is_empty():
		_spawn_contact_flash(target_id)

func _update_phase_cue() -> void:
	_stop_telegraph_pulse()
	match resolver.enemy_phase:
		CombatResolver.Phase.TELEGRAPH:
			phase_cue.text = "!"
			phase_cue.add_theme_color_override("font_color", Color("e08a6a"))
			_start_telegraph_pulse()
		CombatResolver.Phase.STARTUP:
			phase_cue.text = "Замах"
			phase_cue.add_theme_color_override("font_color", Color("ffb095"))
		CombatResolver.Phase.VULNERABILITY:
			phase_cue.text = "Уязвим"
			phase_cue.add_theme_color_override("font_color", AppTheme.COLOR_ACCENT)
		_:
			phase_cue.text = ""
	phase_cue.reset_size()

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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 4
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("f2e3c9") if target_id != "hero" else Color("e89a86"))
	var side := Vector2(-16, -30) if target_id == "hero" else Vector2(12, -30)
	label.position = (_actor_position(target_id) + side).round()
	arena.add_child(label)
	label.reset_size()
	label.position.x = clampf(label.position.x, 0.0, maxf(0.0, arena.size.x - label.size.x))
	label.position.y = clampf(label.position.y, 0.0, maxf(0.0, arena.size.y - label.size.y))
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", maxf(0.0, label.position.y - 16.0), 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)
	_track_tween(tween)

func _spawn_contact_flash(target_id: String) -> void:
	var label := Label.new()
	label.text = "◆"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 4
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", AppTheme.COLOR_ACCENT)
	var enemy_view: GroveEnemyView = _grove_enemy_view(target_id)
	var body_offset: float = enemy_view.head.y * 0.5 if enemy_view != null else -30.0
	label.position = (_actor_position(target_id) + Vector2(-5, body_offset)).round()
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
	if not _uses_enemy_slot_presentation():
		enemy_sprite.animation_finished.connect(_on_enemy_clip_finished)

func _uses_enemy_slot_presentation() -> bool:
	return session.location_id in GameSession.EXPEDITION_LOCATIONS or session.location_id == GameSession.LOCATION_GUILD_ORDER or ArtMap.GROVE_STILLS.has(session.current_enemy_id) or ArtMap.HOLLOW_STILLS.has(session.current_enemy_id)

func _build_outpost_ally() -> void:
	_akari = AnimatedSprite2D.new()
	_akari.name = "Akari"
	_akari.z_index = 1
	arena.add_child(_akari)
	_akari.position = SceneStaging.outpost_ally_anchor(arena.size).round()
	for clip_name: String in ArtMap.AKARI_SHEETS:
		_akari_clips[clip_name] = _build_clip(ArtMap.AKARI_SHEETS[clip_name], clip_name != "idle")
	_akari.animation_finished.connect(_play_akari_idle)
	_play_akari_idle()
	_ally_fire = Sprite2D.new()
	_ally_fire.name = "AkariSeal"
	_ally_fire.z_index = 1
	_ally_fire.texture = ArtMap.crop(ArtMap.OUTPOST_PROPS["fire"], Rect2(12, 58, 72, 28))
	_ally_fire.scale = Vector2.ONE * 0.65 / ArtMap.DETAIL_SCALE
	_ally_fire.hide()
	arena.add_child(_ally_fire)
	_ally_cue = Label.new()
	_ally_cue.name = "AllyCue"
	_ally_cue.z_index = 4
	_ally_cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ally_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ally_cue.add_theme_font_size_override("font_size", 8)
	_ally_cue.add_theme_color_override("font_color", Color("ffdea0"))
	_ally_cue.add_theme_color_override("font_outline_color", Color("171a12"))
	_ally_cue.add_theme_constant_override("outline_size", 4)
	arena.add_child(_ally_cue)
	_ally_cue.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_ally_cue.hide()

func _play_akari_idle() -> void:
	_apply_clip(_akari, _akari_clips["idle"])
	_akari.play(&"default")

func _on_ally_action(action: String) -> void:
	var thrust: bool = action in ["hold", "joint_break"]
	if thrust:
		_apply_clip(_akari, _akari_clips["seal" if action == "hold" else "thrust"])
		_akari.play(&"default")
		_ally_fire.position = _grove_anchor(1 if action == "hold" else 0) + Vector2(0, 1)
	_ally_fire.visible = thrust
	_ally_cue.text = {
		"hold": "Акари · Одного держу я!",
		"dive_warning": "Акари · Берегись пикирования!",
		"summon_warning": "Акари · Он зовёт воронов!",
		"joint_break": "Акари · Сейчас! По колену!",
	}[action]
	_ally_cue.show()
	if _ally_notice != null and _ally_notice.is_valid():
		_battle_tweens.erase(_ally_notice)
		_ally_notice.kill()
	_ally_notice = create_tween()
	_ally_notice.tween_interval(1.8 / float(session.active_encounter_context.get("auto_speed", 1)))
	_ally_notice.tween_callback(_ally_cue.hide)
	_ally_notice.tween_callback(_ally_fire.hide)
	_track_tween(_ally_notice)

func _build_grove_enemies() -> void:
	_pollen_cloud = Sprite2D.new()
	_pollen_cloud.name = "PollenCloud"
	_pollen_cloud.texture = ArtMap.crop(ArtMap.FX["moth_pollen"], Rect2(28, 38, 40, 22))
	_pollen_cloud.scale = Vector2.ONE * 1.4 / ArtMap.DETAIL_SCALE
	_pollen_cloud.z_index = 2
	_pollen_cloud.hide()
	arena.add_child(_pollen_cloud)
	for index: int in range(resolver.enemy_slots.size()):
		var slot: CombatResolver.EnemySlot = resolver.enemy_slots[index]
		var view := GroveEnemyView.new()
		if index == 0:
			view.sprite = enemy_sprite
			view.health = enemy_health
			view.warning = telegraph
			view.cue = phase_cue
		else:
			view.sprite = AnimatedSprite2D.new()
			view.sprite.name = "SecondEnemySprite" if index == 1 else "ThirdEnemySprite"
			view.health = ActorHealthDisplay.new()
			view.health.name = "SecondEnemyHealth" if index == 1 else "ThirdEnemyHealth"
			view.health.setup("enemy", true)
			view.warning = Sprite2D.new()
			view.warning.texture = telegraph.texture
			view.cue = Label.new()
			view.cue.name = "SecondPhaseCue" if index == 1 else "ThirdPhaseCue"
			for control: Node in [view.warning, view.sprite, view.health, view.cue]:
				arena.add_child(control)
		view.sprite.z_index = 2
		view.health.z_index = 3
		view.cue.z_index = 3
		view.cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.cue.add_theme_font_size_override("font_size", 8)
		view.cue.add_theme_color_override("font_color", Color("ffe3a2"))
		view.cue.add_theme_color_override("font_outline_color", Color("171a12"))
		view.cue.add_theme_constant_override("outline_size", 4)
		var species: String = slot.actor.definition.id
		var sheets: Dictionary = ArtMap.ENEMY_SHEETS[species]
		view.head = sheets["idle"]["head"]
		var still: Dictionary = ArtMap.WARDEN_STILL if species == "bone_warden" else ArtMap.HOLLOW_STILLS.get(species, ArtMap.GROVE_STILLS.get(species, {}))
		var dimensions: Vector2 = still.get("size", Vector2(55, 55))
		view.body_width = dimensions.x
		view.body_bottom = 17.0 if slot.pollen_slow_ticks > 0 else 5.0
		for clip_name: String in sheets:
			view.clips[clip_name] = _build_clip(sheets[clip_name], clip_name not in ["idle", "stunned"])
		_grove_enemies.append(view)

func _grove_anchor(index: int) -> Vector2:
	var location: String = session.guild_order_location() if session.location_id == GameSession.LOCATION_GUILD_ORDER else session.location_id
	if location == GameSession.LOCATION_FOREST_EDGE:
		var slot: CombatResolver.EnemySlot = resolver.enemy_slots[index]
		var anchor: Vector2 = SceneStaging.hollow_enemy_anchor(arena.size, index, resolver.enemy_slots.size())
		if slot.pollen_slow_ticks > 0 or slot.actor.definition.id == "ash_raven":
			anchor.y -= 28.0
		return anchor.round()
	if location == GameSession.LOCATION_OUTPOST:
		if resolver.enemy_slots.size() > 1 and resolver.enemy.definition.id != "bone_warden" and session.outpost_stage() != "ravens":
			return SceneStaging.hollow_enemy_anchor(arena.size, index, resolver.enemy_slots.size()).round()
		return SceneStaging.outpost_enemy_anchor(arena.size, index, resolver.enemy_slots[0].actor.definition.id == "bone_warden").round()
	if location == GameSession.LOCATION_HOLLOW:
		return SceneStaging.hollow_enemy_anchor(arena.size, index, resolver.enemy_slots.size()).round()
	return SceneStaging.grove_enemy_anchor(arena.size, index, resolver.enemy_slots[index].pollen_slow_ticks > 0).round()

func _update_grove_positions() -> void:
	var bounds := Rect2(Vector2.ZERO, arena.size)
	hero_health.follow(hero_sprite.position + Vector2(ArtMap.HERO_EXILED["idle"]["head"]), bounds)
	if _ally_cue != null:
		_ally_cue.position.y = roundf(SceneStaging.floor_y(arena.size.y) + 32.0)
	for index: int in range(_grove_enemies.size()):
		var slot: CombatResolver.EnemySlot = resolver.enemy_slots[index]
		var view: GroveEnemyView = _grove_enemies[index]
		view.health.follow(view.sprite.position + view.head, bounds)
		var hazard_at_hero: bool = slot.pollen_slow_ticks > 0 or (slot.actor.definition.id == "bone_warden" and resolver.warden_move == "void")
		view.warning.position = (hero_sprite.position if hazard_at_hero else view.sprite.position) + Vector2(0, 1)
		if hazard_at_hero and slot.actor.definition.id == "bone_warden":
			view.warning.position.x = maxf(44.0, view.warning.position.x)
		var cue_x: float = clampf(view.sprite.position.x - view.cue.size.x * 0.5, 0.0, maxf(0.0, arena.size.x - view.cue.size.x))
		view.cue.position = Vector2(cue_x, view.health.position.y - 15.0).round()
	if _pollen_cloud.visible:
		_pollen_cloud.position = hero_sprite.position + Vector2(19, -12)

func _on_grove_actor_changed(_instance_id: String) -> void:
	_refresh_grove_enemies()

func _refresh_grove_enemies() -> void:
	_pollen_cloud.hide()
	for index: int in range(_grove_enemies.size()):
		var slot: CombatResolver.EnemySlot = resolver.enemy_slots[index]
		var view: GroveEnemyView = _grove_enemies[index]
		if view.defeated:
			continue
		view.sprite.visible = not slot.dormant
		if slot.dormant:
			view.health.hide()
			view.warning.hide()
			view.cue.hide()
			continue
		var alive: bool = not slot.actor.is_dead()
		view.health.visible = alive
		view.health.set_hp(slot.actor.current_hp, slot.actor.max_hp)
		view.health.set_targeted(resolver.combat_format == "active" and resolver.target == slot)
		var is_void: bool = slot.actor.definition.id == "bone_warden" and resolver.warden_move == "void"
		view.warning.visible = alive and (slot.phase in [CombatResolver.Phase.TELEGRAPH, CombatResolver.Phase.STARTUP] or (is_void and slot.phase == CombatResolver.Phase.ACTIVE))
		view.cue.visible = alive and (view.warning.visible or slot.stunned or (slot.actor.definition.guarded_damage_multiplier < 1.0 and slot.phase == CombatResolver.Phase.VULNERABILITY))
		if not alive:
			view.defeated = true
			var fade := create_tween()
			fade.tween_property(view.sprite, "modulate:a", 0.0, 0.4)
			_track_tween(fade)
			continue
		if slot.pollen_slow_ticks > 0 and slot.phase == CombatResolver.Phase.ACTIVE:
			_pollen_cloud.show()
		if view.phase == slot.phase and view.stunned == slot.stunned:
			continue
		view.phase = slot.phase
		view.stunned = slot.stunned
		var species: String = slot.actor.definition.id
		var attack: bool = slot.phase in [CombatResolver.Phase.STARTUP, CombatResolver.Phase.ACTIVE, CombatResolver.Phase.RECOVERY]
		var clip_name: String = _attack_clip(slot) if attack else "idle"
		if slot.stunned:
			clip_name = "stunned" if view.clips.has("stunned") else "idle"
		_apply_clip(view.sprite, view.clips[clip_name])
		view.sprite.modulate = Color(1.16, 1.05, 0.76) if slot.phase == CombatResolver.Phase.VULNERABILITY else Color.WHITE
		if not attack:
			view.sprite.play(&"default")
		else:
			view.sprite.pause()
		view.warning.modulate = Color(1.0, 0.8, 0.35, 0.8) if species == "dust_moth" else Color(1.0, 0.55, 0.45, 0.8)
		if is_void:
			view.warning.modulate = Color(0.81, 0.50, 1.0, 0.9)
		view.warning.scale = Vector2.ONE * (0.98 if is_void else 0.76) / ArtMap.DETAIL_SCALE
		view.cue.add_theme_color_override("font_color", Color("e8c2ff") if is_void else Color("ffe3a2"))
		view.cue.text = _grove_warning(slot)
		view.cue.reset_size()
	_update_grove_positions()
	advance_pose()

func _update_grove_attack_frame(view: GroveEnemyView, slot: CombatResolver.EnemySlot) -> void:
	if slot.phase not in [CombatResolver.Phase.STARTUP, CombatResolver.Phase.ACTIVE, CombatResolver.Phase.RECOVERY]:
		return
	var definition: ActorDefinition = slot.actor.definition
	if definition.behavior_id == "goblin":
		view.sprite.frame = _goblin_frame(slot.phase, slot.strike_index)
		return
	var spec: Dictionary = ArtMap.ENEMY_SHEETS[definition.id][_attack_clip(slot)]
	var contact: int = int(spec["contact_frame"])
	var last: int = int(spec["count"]) - 1
	var frame: int
	match slot.phase:
		CombatResolver.Phase.STARTUP:
			var progress: float = 1.0 - float(slot.remaining) / definition.startup_ticks
			frame = mini(contact - 1, floori(progress * contact))
		CombatResolver.Phase.ACTIVE:
			var progress: float = 1.0 - float(slot.remaining) / definition.active_ticks
			frame = mini(last - 1, contact + floori(progress * (last - contact)))
		CombatResolver.Phase.RECOVERY:
			frame = last
		_:
			return
	if view.sprite.frame != frame:
		view.sprite.set_frame_and_progress(frame, 0.0)

func _attack_clip(slot: CombatResolver.EnemySlot) -> String:
	if slot.actor.definition.id == "bone_warden":
		return "attack" if resolver.warden_move == "attack" else "summon"
	if slot.actor.definition.id == "crystal_toad" and slot.strike_index == 1:
		return "leap"
	return slot.attack_id

func _grove_warning(slot: CombatResolver.EnemySlot) -> String:
	if slot.stunned:
		return "Сустав открыт" if slot.actor.definition.id == "bone_warden" else "Оглушён"
	match slot.actor.definition.id:
		"dust_moth": return "Пыльца"
		"root_weaver": return "Захват"
		"river_shieldback": return "Уязвим" if slot.phase == CombatResolver.Phase.VULNERABILITY else "Удар клешнёй"
		"stone_rodent": return "Бросок"
		"goblin_scout": return "Замах"
		"ash_raven": return "Пикирование"
		"crystal_toad":
			if slot.phase == CombatResolver.Phase.VULNERABILITY:
				return "Броня раскрылась"
			return "2 · Прыжок" if slot.strike_index == 1 else "1 · Удар языком"
		"bone_warden":
			if slot.phase == CombatResolver.Phase.VULNERABILITY:
				return "Уязвим"
			return {"attack": "Широкий взмах", "summon": "Призыв ворона", "void": "Зона Пустоты"}[resolver.warden_move]
		_: return "Прыжок" if slot.attack_id == "leap" else "Иглы"

func target_at(position: Vector2) -> String:
	var nearest_id: String = ""
	var nearest_distance: float = INF
	for index: int in range(_grove_enemies.size()):
		var view: GroveEnemyView = _grove_enemies[index]
		if view.defeated or resolver.enemy_slots[index].dormant:
			continue
		var instance_id: String = resolver.enemy_slots[index].instance_id
		if view.health.get_rect().grow(2.0).has_point(position):
			return instance_id
		var anchor: Vector2 = view.sprite.position
		var body := Rect2(
			Vector2(anchor.x - view.body_width * 0.5, anchor.y + view.head.y),
			Vector2(view.body_width, view.body_bottom - view.head.y)
		)
		var distance: float = position.distance_squared_to(body.get_center())
		if body.has_point(position) and distance < nearest_distance:
			nearest_id = instance_id
			nearest_distance = distance
	return nearest_id

func _grove_enemy_view(instance_id: String) -> GroveEnemyView:
	for index: int in range(_grove_enemies.size()):
		if resolver.enemy_slots[index].instance_id == instance_id:
			return _grove_enemies[index]
	return null

func _actor_position(instance_id: String) -> Vector2:
	if instance_id == "hero":
		return hero_sprite.position
	var view: GroveEnemyView = _grove_enemy_view(instance_id)
	return view.sprite.position if view != null else enemy_sprite.position

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
		_update_enemy_clip()

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
			_hold_goblin_strike_pose()
		CombatResolver.Phase.ACTIVE:
			telegraph.hide()
			enemy_sprite.modulate = Color.WHITE
			_enemy_busy = false
			_play_enemy_clip("attack", true)
			_hold_goblin_strike_pose()
		CombatResolver.Phase.RECOVERY:
			telegraph.hide()
			enemy_sprite.modulate = Color.WHITE
			if is_slime:
				_play_enemy_clip("idle")
			elif not _enemy_busy:
				_play_enemy_clip("attack", true)
				_hold_goblin_strike_pose()
				_enemy_busy = true
		CombatResolver.Phase.VULNERABILITY:
			enemy_sprite.modulate = Color(1.15, 1.05, 0.75)
			telegraph.hide()
			_enemy_busy = false
			_play_enemy_clip("idle")

func _hold_goblin_strike_pose() -> void:
	if resolver.enemy.definition.behavior_id == "goblin" and enemy_sprite.sprite_frames == _enemy_frames["attack"]["frames"]:
		enemy_sprite.pause()
		enemy_sprite.set_frame_and_progress(_goblin_frame(resolver.enemy_phase, resolver.strike_index), 0.0)

func _goblin_frame(phase: int, strike: int) -> int:
	if phase == CombatResolver.Phase.RECOVERY:
		return GOBLIN_RECOVER_FRAME
	var roles: Array[int] = GOBLIN_CONTACT_FRAMES if phase == CombatResolver.Phase.ACTIVE else GOBLIN_PREPARE_FRAMES
	return roles[clampi(strike, 0, roles.size() - 1)]
