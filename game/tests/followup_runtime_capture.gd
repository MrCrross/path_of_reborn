extends Node

## Save an observed live state without advancing simulation or changing it.
func run(label: String) -> Dictionary:
	if not label.is_valid_identifier():
		return {"error": "Use an identifier for the capture label"}
	var root: GameRoot = get_tree().current_scene
	var screen: Control = root.router.current_screen
	var state: Dictionary = {"screen": screen.name, "label": label}
	if screen.get("resolver") is CombatResolver:
		var combat: CombatResolver = screen.resolver
		state.merge({"tick": combat.tick_count, "phase": combat.enemy_phase, "hero_hp": combat.hero.current_hp, "enemy_hp": combat.enemy.current_hp, "hero_frame": screen.hero_sprite.frame, "enemy_frame": screen.enemy_sprite.frame, "hero_clip_is_idle": screen.hero_sprite.sprite_frames == screen.arena_presenter._hero_frames["idle"]["frames"], "hero_begin_connections": combat.get_signal_connection_list("hero_attack_begun").size(), "finished": combat.is_finished})
	state["route"] = root.session.route_state.duplicate(true)
	state["level"] = root.session.hero.level
	state["pending_upgrades"] = root.session.hero.pending_upgrade_choices
	state["items"] = root.session.inventory.items.size()
	state["beaten_in_memory"] = root.session.completed_encounter_ids().duplicate(true)
	if FileAccess.file_exists(root.save_path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.save_path))
		if saved is Dictionary:
			state["beaten_on_disk"] = saved.get("profile", {}).get("completed_encounter_ids", {})
	if screen.name == "World":
		state["hero_foot_y"] = SceneStaging.hero_anchor(screen.size).y
		state["main_action_rect"] = str(screen.main_action_button.get_global_rect())
	var folder: String = ProjectSettings.globalize_path("res://../docs/reviews/followup_audit_2026_11_20")
	DirAccess.make_dir_recursive_absolute(folder)
	RenderingServer.force_draw()
	state["image_error"] = get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))
	var output := FileAccess.open(folder.path_join(label + ".json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(state, "\t"))
	output.close()
	return state
