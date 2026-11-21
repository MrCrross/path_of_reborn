extends SceneTree

## Asset/consumer contracts; never reads or writes a player save.
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _run() -> void:
	var families: Array[Dictionary] = [ArtMap.HERO_EXILED, ArtMap.ENEMY_SHEETS["moss_slime"],
		ArtMap.ENEMY_SHEETS["goblin_scout"], {"push": ArtMap.HERO_MODERN["push"]},
		{"wait": ArtMap.YUI["wait"], "step": ArtMap.YUI["step"]}, ArtMap.MITSUKI_FULL]
	var clips: int = 0
	var total_frames: int = 0
	for family: Dictionary in families:
		for key: String in family:
			var sheet: Dictionary = family[key]
			var spec: Dictionary = ArtMap.animation_spec(sheet)
			_check(spec.has("regions"), sheet["path"] + " native registration exists")
			var frames: SpriteFrames = ArtMap.sprite_frames(sheet, 10.0, true)
			_check(frames.get_frame_count(&"default") == sheet["count"], key + " count preserved")
			_check(not frames.get_animation_loop(&"default"), key + " one-shot respected")
			var atlas: Texture2D = ArtMap.texture(sheet["path"])
			_check(atlas.get_width() <= 4096 and atlas.get_height() <= 4096, key + " texture limit")
			for index: int in range(frames.get_frame_count(&"default")):
				var frame: AtlasTexture = frames.get_frame_texture(&"default", index) as AtlasTexture
				_check(frame.get_size().is_equal_approx(Vector2(spec["frame"])), key + " virtual size")
				_check(Rect2(Vector2.ZERO, atlas.get_size()).encloses(frame.region), key + " atlas region")
				_check(frame.region.size.y > 128, key + " native detail, not old tiny frame")
				total_frames += 1
			var sprite := AnimatedSprite2D.new()
			ArtMap.apply_animation_transform(sprite, sheet)
			var actual_pivot: Vector2 = (Vector2(spec["frame"]) * 0.5 - sprite.offset) * sprite.scale
			var expected: Vector2 = Vector2(sheet["frame"]) * 0.5 - Vector2(sheet.get("offset", Vector2.ZERO))
			# A wide strike can expand the virtual canvas sideways; its floor stays fixed.
			_check(absf(actual_pivot.y - expected.y) < 0.15, key + " logical floor preserved")
			sprite.free()
			clips += 1
	_check(clips == 15 and total_frames == 49, "all 15 live/preloaded clips and 49 frames covered")
	var centered_actor := AnimatedSprite2D.new()
	ArtMap.apply_animation_transform(centered_actor, ArtMap.YUI["wait"], true)
	_check(absf(centered_actor.offset.y * centered_actor.scale.y) < 0.15, "prologue centered canvas preserved")
	centered_actor.free()
	var host := Control.new()
	host.size = Vector2(180, 320)
	host.theme = AppTheme.build()
	root.add_child(host)
	var session := GameSession.new()
	for enemy_id: String in ["moss_slime", "goblin_scout"]:
		session.in_combat = false
		session.select_encounter(enemy_id)
		var screen: Control = load("res://scenes/combat.tscn").instantiate()
		screen.configure(session)
		host.add_child(screen)
		await process_frame
		screen.set_physics_process(false)
		if screen.arena_presenter._intro_tween != null:
			screen.arena_presenter._intro_tween.kill()
		for key: String in screen.arena_presenter._hero_frames:
			screen.arena_presenter._apply_clip(screen.hero_sprite, screen.arena_presenter._hero_frames[key])
			_check(screen.hero_sprite.scale.x < 0.3, "combat hero " + key + " native scale")
		for key: String in screen.arena_presenter._enemy_frames:
			screen.arena_presenter._apply_clip(screen.enemy_sprite, screen.arena_presenter._enemy_frames[key])
			_check(screen.enemy_sprite.scale.x < 0.3, enemy_id + " " + key + " native scale")
		screen.queue_free()
		await process_frame
	host.queue_free()
	await process_frame
	await _frame_contracts()
	if "--force-failure" in OS.get_cmdline_user_args():
		_check(false, "intentional runner exit-code check")
	print("ANIMATION RESULT: clips=%d frames=%d checks=%d failed=%d" % [clips, total_frames, checks, failures])
	quit(1 if failures > 0 else 0)

func _frame_contracts() -> void:
	var fixture_host := Control.new()
	fixture_host.size = Vector2(180, 320)
	fixture_host.theme = AppTheme.build()
	root.add_child(fixture_host)
	var session := GameSession.new()
	session.select_encounter("moss_slime")
	var screen: Control = load("res://scenes/combat.tscn").instantiate()
	screen.configure(session)
	fixture_host.add_child(screen)
	await process_frame
	screen.set_physics_process(false)
	if screen.arena_presenter._intro_tween != null:
		screen.arena_presenter._intro_tween.kill()
	screen._finish_intro()
	screen.resolver.advance_ticks(1)
	_check(screen.hero_sprite.sprite_frames == screen.arena_presenter._hero_frames["attack"]["frames"] and screen.hero_sprite.frame == 0, "hero startup begins on the preparation frame")
	screen.resolver.advance_ticks(18)
	_check(screen.resolver.tick_count == 19 and screen.hero_sprite.frame == CombatArenaPresenter.HERO_CONTACT_FRAME, "hero first landed tick 19 uses the contact pose")
	_check(screen.resolver.enemy.current_hp == 17, "hero contact pose follows resolver damage, not a new hit")
	screen.resolver.advance_ticks(60)
	_check(screen.resolver.tick_count == 79 and screen.arena_presenter._hero_clip_name == "dodge", "hero second landed tick 79 preserves the higher-priority dodge pose")
	_check(not screen.arena_presenter._battle_tweens.is_empty(), "hero contact during hit uses a local effect instead of replacing the pose")
	screen.arena_presenter.spawn_damage_number("moss_slime", 1)
	var active_tweens: int = screen.arena_presenter._battle_tweens.size()
	_check(active_tweens > 0, "arena tracks its transient visual tween")
	screen._set_pause(true)
	var paused_frame: int = screen.hero_sprite.frame
	var paused_progress: float = screen.hero_sprite.frame_progress
	for index: int in range(8):
		await process_frame
	_check(screen.hero_sprite.frame == paused_frame and screen.hero_sprite.frame_progress == paused_progress, "presenter preserves frame and progress on pause")
	screen._set_pause(false)
	for index: int in range(120):
		if screen.arena_presenter._battle_tweens.is_empty():
			break
		await process_frame
	_check(not screen.arena_presenter._battle_tweens.has(null) and screen.arena_presenter._battle_tweens.is_empty(), "completed arena tween references are cleared")
	screen.queue_free()
	await process_frame

	var goblin_session := GameSession.new()
	goblin_session.route_state["next_index"] = 1
	goblin_session.select_encounter("goblin_scout")
	var goblin: Control = load("res://scenes/combat.tscn").instantiate()
	goblin.configure(goblin_session)
	fixture_host.add_child(goblin)
	await process_frame
	goblin.set_physics_process(false)
	if goblin.arena_presenter._intro_tween != null:
		goblin.arena_presenter._intro_tween.kill()
	goblin._finish_intro()
	goblin.resolver.advance_ticks(37)
	_check(goblin.enemy_sprite.frame == CombatArenaPresenter.GOBLIN_PREPARE_FRAMES[0], "goblin first startup has an explicit preparation frame")
	_check(goblin.hero_sprite.sprite_frames == goblin.arena_presenter._hero_frames["dodge"]["frames"], "auto dodge presentation starts from the resolver event")
	goblin.arena_presenter._on_damage_dealt("goblin_scout", 0)
	_check(not goblin.arena_presenter._enemy_frames.has("hit") and goblin.enemy_sprite.sprite_frames == goblin.arena_presenter._enemy_frames["attack"]["frames"], "goblin hit during startup uses the explicit no-hit-clip fallback without creating damage")
	goblin.resolver.advance_ticks(11)
	_check(goblin.resolver.tick_count == 48 and goblin.enemy_sprite.frame == CombatArenaPresenter.GOBLIN_CONTACT_FRAMES[0], "goblin first contact at tick 48 uses its own contact frame")
	_check(goblin.resolver.hero.current_hp == goblin.resolver.hero.max_hp, "auto dodge covers the first mapped goblin contact")
	goblin.resolver.advance_ticks(18)
	_check(goblin.resolver.tick_count == 66 and goblin.resolver.strike_index == 1 and goblin.enemy_sprite.frame == CombatArenaPresenter.GOBLIN_CONTACT_FRAMES[1], "goblin second contact at tick 66 does not depend on clip timing")
	_check(goblin.hero_sprite.sprite_frames == goblin.arena_presenter._hero_frames["hit"]["frames"], "second contact switches to hit only after real dodge expiry")
	_check(goblin.resolver.hero.current_hp == goblin.resolver.hero.max_hp - 1, "second contact follows the real dodge expiry rather than the animation")
	goblin.resolver.enemy.current_hp = 1
	while not goblin.resolver.is_finished and goblin.resolver.tick_count < 200:
		goblin.resolver.advance_ticks(1)
	_check(goblin.resolver.won and goblin.victory_label.visible and not goblin.enemy_health.visible, "terminal resolver event owns victory and final presentation")
	_check(not goblin.telegraph.visible and goblin.phase_cue.text.is_empty(), "terminal presentation clears telegraph and phase cue")
	goblin.queue_free()
	await process_frame
	fixture_host.queue_free()
	await process_frame
