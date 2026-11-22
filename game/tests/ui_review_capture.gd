extends Node

## Manual review helper. Run only with an isolated --save-path profile.
## Routes/fixtures are explicit; this is not a substitute for an input playthrough.
func run(task: String, argument: String = "") -> Dictionary:
	var root: GameRoot = get_tree().current_scene
	match task:
		"goblin_fixture":
			root.session.in_combat = false
			root.session.awaiting_return = false
			root.session.route_state["next_index"] = 2
			root.session.select_encounter("goblin_scout")
			root.router.go_to("combat")
			var goblin_screen: Control = root.router.current_screen
			if goblin_screen.has_method("_finish_intro"):
				goblin_screen._finish_intro()
		"reset":
			root.session.new_game()
			root.router.go_to("title")
		"inventory_fixture":
			root.session.in_combat = false
			for item: ItemDefinition in root.session.item_definitions.values():
				root.session.inventory.add(item, 2)
			root.router.go_to("inventory")
		"inspect":
			var item: ItemInstance = root.session.inventory.filter("weapon")[0]
			root.router.current_screen._on_item_pressed(item.instance_id)
		"checkpoint_fixture":
			root.session.in_combat = false
			for point: int in range(3):
				if root.session.checkpoints.begin():
					root.session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
			root.router.go_to("checkpoint")
		"world_fixture":
			root.session.in_combat = false
			root.session.route_state["next_index"] = 1
			root.router.go_to("world")
		"world_damaged":
			root.session.hero.take_damage(3)
			var world_screen: Control = root.router.current_screen
			if world_screen.has_method("_refresh"):
				world_screen._refresh()
				world_screen._layout_scene()
		"combat_intro":
			root.session.in_combat = false
			root.session.awaiting_return = false
			root.session.traces = 0
			root.session.select_encounter("moss_slime")
			root.router.go_to("combat")
		"combat_intro_capture":
			root.session.in_combat = false
			root.session.awaiting_return = false
			root.session.traces = 0
			root.session.select_encounter("moss_slime")
			root.router.go_to("combat")
			var intro_screen: Control = root.router.current_screen
			# Стабильный ранний кадр появления: ~половина slide, действий ещё нет.
			if intro_screen.arena_presenter._intro_tween != null and intro_screen.arena_presenter._intro_tween.is_valid():
				intro_screen.arena_presenter._intro_tween.kill()
			intro_screen.enemy_sprite.position = Vector2(166, intro_screen.enemy_sprite.position.y)
			intro_screen._update_marker_positions()
			await get_tree().process_frame
			var intro_path: String = ProjectSettings.globalize_path(
				"res://../docs/reviews/scene_first_ui_2026_11_20/" + argument + ".png"
			)
			DirAccess.make_dir_recursive_absolute(intro_path.get_base_dir())
			RenderingServer.force_draw()
			var intro_err: Error = get_viewport().get_texture().get_image().save_png(intro_path)
			return {"screen": "Combat", "path": intro_path, "save_error": intro_err}
		"combat_fight":
			root.session.in_combat = false
			root.session.awaiting_return = false
			root.session.traces = 0
			root.session.select_encounter("moss_slime")
			root.router.go_to("combat")
			var fight_screen: Control = root.router.current_screen
			if fight_screen.has_method("_finish_intro"):
				fight_screen._finish_intro()
			fight_screen.resolver.advance_ticks(6)
			fight_screen._on_dodge_pressed()
			fight_screen.resolver.advance_ticks(4)
			# Доводим до окна уязвимости и замираем: стабильный кадр маркера «×N».
			while (
				not fight_screen.resolver.is_finished
				and fight_screen.resolver.enemy_phase != CombatResolver.Phase.VULNERABILITY
			):
				fight_screen.resolver.advance_ticks(1)
			fight_screen._refresh()
			if argument == "pause":
				get_tree().paused = true
		"goblin_fight":
			root.session.in_combat = false
			root.session.awaiting_return = false
			root.session.traces = 0
			root.session.route_state["next_index"] = 2
			root.session.select_encounter("goblin_scout")
			root.router.go_to("combat")
			var goblin_screen: Control = root.router.current_screen
			if goblin_screen.has_method("_finish_intro"):
				goblin_screen._finish_intro()
			while (
				not goblin_screen.resolver.is_finished
				and goblin_screen.resolver.enemy_phase != CombatResolver.Phase.VULNERABILITY
			):
				goblin_screen.resolver.advance_ticks(1)
			goblin_screen._refresh()
			get_tree().paused = true
		"unpause":
			get_tree().paused = false
		"return_fixture":
			root.session.in_combat = false
			root.session.awaiting_return = true
			root.router.go_to("checkpoint")
		"combat_finish":
			var combat: Control = root.router.current_screen
			var resolver: CombatResolver = combat.resolver
			for step: int in range(600):
				if resolver.is_finished:
					break
				if argument == "win":
					resolver.request_attack()
				resolver.advance_ticks(12)
		"route":
			if argument == "combat":
				root.session.select_encounter("moss_slime")
			root.router.go_to(argument)
			var routed: Control = root.router.current_screen
			if routed.has_method("_finish_intro"):
				routed._finish_intro()
		"advance":
			var screen: Control = root.router.current_screen
			var runner: DialogueRunner = screen.get("runner")
			for step: int in range(600):
				if runner.is_finished or runner.current_kind() == argument or runner.current_shot() == argument:
					break
				runner.advance_ticks(60)
				match runner.current_kind():
					"look": runner.look()
					"hold":
						runner.begin_hold()
						runner.advance_ticks(60)
					_: runner.tap()
		"resize":
			var values: PackedStringArray = argument.split("x")
			DisplayServer.window_set_size(Vector2i(int(values[0]), int(values[1])))
	await get_tree().process_frame
	await get_tree().process_frame
	var current: Control = root.router.current_screen
	var result: Dictionary = {"screen": current.name, "viewport": str(current.size)}
	if current.get("runner") is DialogueRunner:
		var runner: DialogueRunner = current.runner
		result["dialogue"] = {"index": runner.index, "page": runner.page_index, "kind": runner.current_kind(), "holding": runner.holding, "hold_ticks": runner.hold_ticks}
	if current.get("resolver") is CombatResolver:
		var resolver: CombatResolver = current.resolver
		result["combat"] = {"phase": resolver.enemy_phase, "enemy_hp": resolver.enemy.current_hp, "hero_hp": resolver.hero.current_hp, "finished": resolver.is_finished}
	for control: Node in current.find_children("*", "Control", true, false):
		if control.name in ["DialoguePanel", "StoryText", "Arena", "HeroHealth", "EnemyHealth", "Actions", "TopBar", "NavBar", "Details", "Scroll", "HintLabel"]:
			result[String(control.name)] = {"rect": str(control.get_global_rect()), "visible": control.is_visible_in_tree()}
	if task == "capture":
		var path: String = ProjectSettings.globalize_path("res://../docs/reviews/scene_first_ui_2026_11_20/" + argument + ".png")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		RenderingServer.force_draw()
		result["save_error"] = get_viewport().get_texture().get_image().save_png(path)
		result["path"] = path
	return result
