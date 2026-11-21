extends Node

const OUT := "res://../docs/reviews/plan_acceptance_repair_2026_11_20/graphics"

func run() -> Dictionary:
	var game: GameRoot = get_tree().current_scene
	var report: Dictionary = {
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"logical_viewport": [ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height")],
		"stretch": ProjectSettings.get_setting("display/window/stretch/mode"),
		"scale_mode": ProjectSettings.get_setting("display/window/stretch/scale_mode"),
		"measurements": [],
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_size(Vector2i(360, 640))
	await _frames()
	report["measurements"].append(await _measure(game, "prologue", "prologue_first"))
	var skip_started: int = Time.get_ticks_usec()
	game.router.current_screen._on_skip_pressed()
	await _draw()
	report["skip_to_world_ms"] = (Time.get_ticks_usec() - skip_started) / 1000.0
	report["measurements"].append(await _measure(game, "prologue", "prologue_repeat"))
	game.session.new_game()
	game.session.select_encounter("moss_slime")
	report["measurements"].append(await _measure(game, "combat", "combat_first"))
	report["combat_360x640"] = await _capture("combat_360x640.png")
	DisplayServer.window_set_size(Vector2i(1080, 1920))
	await _frames()
	report["combat_1080x1920"] = await _capture("combat_1080x1920.png")
	report["native_memory_static_bytes"] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	DisplayServer.window_set_size(Vector2i(360, 640))
	await _frames()
	game.session.new_game()
	game.router.go_to("world")
	game.session.select_encounter("moss_slime")
	report["measurements"].append(await _measure(game, "combat", "combat_repeat"))
	var file := FileAccess.open(OUT + "/profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("GRAPHICS_PROFILE ", JSON.stringify(report))
	return report

func _measure(game: GameRoot, scene_id: String, label: String) -> Dictionary:
	var memory_before: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var started: int = Time.get_ticks_usec()
	game.router.go_to(scene_id)
	var load_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	await _draw()
	return {
		"name": label,
		"scene": scene_id,
		"load_ms": snappedf(load_ms, 0.001),
		"first_draw_ms": snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.001),
		"memory_static_before_bytes": memory_before,
		"memory_static_after_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}

func _capture(file_name: String) -> Dictionary:
	await _draw()
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT + "/" + file_name)
	var error: Error = image.save_png(path)
	return {"path": path, "size": [image.get_width(), image.get_height()], "save_error": error}

func _frames() -> void:
	for index: int in range(3):
		await get_tree().process_frame
	RenderingServer.force_draw()

func _draw() -> void:
	await get_tree().process_frame
	RenderingServer.force_draw()
