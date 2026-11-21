extends SceneTree

const OUT := "res://../docs/reviews/plan_acceptance_repair_2026_11_20/visual"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var label: String = "window"
	var window_size := Vector2i.ZERO
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			label = argument.trim_prefix("--capture-prefix=")
		if argument.begins_with("--capture-size="):
			var dimensions: PackedStringArray = argument.trim_prefix("--capture-size=").split("x")
			window_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	if window_size != Vector2i.ZERO:
		DisplayServer.window_set_size(window_size)
		root.size = window_size
		await _frames(4)
	var game: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await _frames(4)
	game.session.new_game()
	var sword: ItemInstance = game.session.inventory.add(game.session.get_item_definition("training_sword"), 1)[0]
	var charm: ItemInstance = game.session.inventory.add(game.session.get_item_definition("moss_charm"), 1)[0]
	game.session.equip_item(sword.instance_id)
	game.session.equip_item(charm.instance_id)
	game.router.go_to("world")
	await _capture(label + "_world")
	game.router.go_to("inventory")
	await _capture(label + "_inventory")
	game.router.go_to("world")
	game.session.select_encounter("moss_slime")
	game.router.go_to("combat")
	var combat: Control = game.router.current_screen
	combat._finish_intro()
	combat.set_physics_process(false)
	await _capture(label + "_combat")
	print("VISUAL_ACCEPTANCE ", label, " ", root.size)
	quit(0)

func _capture(label: String) -> void:
	await _frames(4)
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT + "/" + label + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = image.save_png(path)
	print("CAPTURE ", path, " size=", image.get_size(), " error=", error)

func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame
