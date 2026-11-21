extends SceneTree

## Real project scenes and imported textures. Visual fixtures freeze simulation;
## these captures validate rendering, not gameplay input or Android performance.
const OUT := "res://../art_working/animation_upgrade_2026_11_20/gpu/"
var viewport: SubViewport
var host: Control
var report: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _settle() -> void:
	for tick: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw


func _capture(name: String) -> void:
	await _settle()
	var screenshot: Image = viewport.get_texture().get_image()
	var error: Error = screenshot.save_png(OUT + name + ".png")
	report.append({"name": name, "size": [screenshot.get_width(), screenshot.get_height()],
		"method": "gpu_subviewport", "save_error": error})
	if error != OK:
		printerr("CAPTURE ERROR ", name, " ", error)
		quit(1)


func _screen(id: String, session: GameSession) -> Control:
	var scene: Control = load(SceneRouter.SCENES[id]).instantiate()
	scene.configure(session)
	host.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _settle()
	return scene


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	viewport = SubViewport.new()
	viewport.size = Vector2i(720, 1280)
	viewport.size_2d_override = Vector2i(180, 320)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	host = Control.new()
	host.size = Vector2(180, 320)
	host.theme = AppTheme.build()
	viewport.add_child(host)
	for enemy: String in ["moss_slime", "goblin_scout"]:
		var session := GameSession.new()
		session.select_encounter(enemy)
		var scene: Control = await _screen("combat", session)
		scene.set_physics_process(false)
		if scene.arena_presenter._intro_tween != null:
			scene.arena_presenter._intro_tween.kill()
		scene._finish_intro()
		for resolution: Vector2i in [Vector2i(360, 640), Vector2i(720, 1280), Vector2i(1080, 1920)]:
			viewport.size = resolution
			scene.hero_sprite.stop()
			scene.enemy_sprite.stop()
			await _capture(enemy + "_idle_%dx%d" % [resolution.x, resolution.y])
		viewport.size = Vector2i(720, 1280)
		for key: String in scene.arena_presenter._enemy_frames:
			scene.arena_presenter._apply_clip(scene.enemy_sprite, scene.arena_presenter._enemy_frames[key])
			scene.enemy_sprite.stop()
			for frame: int in range(scene.enemy_sprite.sprite_frames.get_frame_count(&"default")):
				scene.enemy_sprite.frame = frame
				await _capture(enemy + "_" + key + "_%02d" % frame)
		if enemy == "moss_slime":
			for key: String in scene.arena_presenter._hero_frames:
				scene.arena_presenter._apply_clip(scene.hero_sprite, scene.arena_presenter._hero_frames[key])
				scene.hero_sprite.stop()
				for frame: int in range(scene.hero_sprite.sprite_frames.get_frame_count(&"default")):
					scene.hero_sprite.frame = frame
					await _capture("haruto_exiled_" + key + "_%02d" % frame)
		scene.queue_free()
		await process_frame
	var world: Control = await _screen("world", GameSession.new())
	await _capture("world_720x1280")
	world.queue_free()
	await process_frame
	# Prologue sheet consumers in their actual scene. Presentation only: no save.
	var prologue: Control = await _screen("prologue", GameSession.new())
	prologue.set_physics_process(false)
	prologue.shot_frame.hide()
	prologue.dialogue_panel.hide()
	prologue.hotspot_marker.hide()
	for family: Dictionary in [{"push": ArtMap.HERO_MODERN["push"]},
		{"wait": ArtMap.YUI["wait"], "step": ArtMap.YUI["step"]}, ArtMap.MITSUKI_FULL]:
		for key: String in family:
			var full: bool = key in ["offer", "wing_glitch"]
			var sprite: AnimatedSprite2D = prologue.full_clip if full else prologue.action_sprite
			prologue.full_clip.visible = full
			prologue.action_sprite.visible = not full
			sprite.sprite_frames = ArtMap.sprite_frames(family[key])
			ArtMap.apply_animation_transform(sprite, family[key], not full)
			sprite.stop()
			for frame: int in range(sprite.sprite_frames.get_frame_count(&"default")):
				sprite.frame = frame
				await _capture("prologue_" + key + "_%02d" % frame)
	prologue.queue_free()
	await process_frame
	var output := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("GPU REVIEW: %d real scene captures" % report.size())
	quit(0)
