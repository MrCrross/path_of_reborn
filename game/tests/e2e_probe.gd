extends Node

const CAPTURE_DIR := "res://../docs/reviews/plan_acceptance_repair_2026_11_20/live"

## Хелперы input-playthrough и визуальной приёмки. Состояние и fixtures
## используются только изолированным прогоном с
## --save-path=user://path_of_reborn_tests/...

func state() -> Dictionary:
	var root: GameRoot = get_tree().current_scene
	if root == null or root.session == null:
		return {"error": "no root/session"}
	var screen: Control = root.router.current_screen
	var info: Dictionary = {
		"screen": screen.name if screen != null else "",
		"location_id": root.session.location_id,
		"route": root.session.route_state.duplicate(true),
		"route_completed": root.session.route_completed(),
		"pending": root.session.pending_battle_result.duplicate(true),
		"has_pending": root.session.has_pending_battle_result(),
		"awaiting_return": root.session.awaiting_return,
		"traces": root.session.traces,
		"echoes": root.session.echoes,
		"level": root.session.hero.level,
		"experience": root.session.hero.experience,
		"upgrades": root.session.hero.pending_upgrade_choices,
		"inventory_items": root.session.inventory.items.size(),
		"equipment": root.session.inventory.equipment.duplicate(true),
		"hero_hp": root.session.hero.current_hp,
		"hero_max_hp": root.session.hero.max_hp,
		"strength": root.session.hero.strength,
		"combat_format": root.session.combat_format,
		"save_path": root.save_path,
		"autosaves": root._autosave_count if "_autosave_count" in root else -1,
	}
	if screen.get("resolver") is CombatResolver:
		var resolver: CombatResolver = screen.resolver
		info["resolver"] = {
			"finished": resolver.is_finished,
			"won": resolver.won,
			"tick": resolver.tick_count,
			"enemy_hp": resolver.enemy.current_hp,
			"hero_hp": resolver.hero.current_hp,
			"auto_dodge": resolver.auto_dodge_enabled,
		}
	if screen.get("_result_visible") != null:
		info["result_visible"] = screen._result_visible
	return info

func full_equipment_fixture() -> Dictionary:
	var root: GameRoot = get_tree().current_scene
	root.session.new_game()
	var sword: ItemInstance = root.session.inventory.add(root.session.get_item_definition("training_sword"), 1)[0]
	var charm: ItemInstance = root.session.inventory.add(root.session.get_item_definition("moss_charm"), 1)[0]
	root.session.equip_item(sword.instance_id)
	root.session.equip_item(charm.instance_id)
	root.router.go_to("world")
	await get_tree().process_frame
	return state()

func wait_for_result(max_frames: int = 1800) -> Dictionary:
	var root: GameRoot = get_tree().current_scene
	for index: int in range(max_frames):
		var screen: Control = root.router.current_screen
		if screen == null or screen.name != "Combat":
			break
		if bool(screen.get("_result_visible")):
			break
		await get_tree().process_frame
	return state()

func capture(label: String, width: int = 0, height: int = 0) -> Dictionary:
	if width > 0 and height > 0:
		get_window().size = Vector2i(width, height)
	for index: int in range(12 if width > 0 and height > 0 else 3):
		await get_tree().process_frame
	RenderingServer.force_draw()
	var path: String = ProjectSettings.globalize_path(CAPTURE_DIR + "/" + label + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(path)
	return {"path": path, "size": [image.get_width(), image.get_height()], "window_size": str(get_window().size), "display_size": str(DisplayServer.window_get_size()), "viewport_rect": str(get_viewport().get_visible_rect()), "save_error": error}
