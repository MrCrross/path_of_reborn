extends "res://tests/hollow_acceptance_runner.gd"

const OutpostSuite = preload("res://tests/outpost_suite.gd")
const OUTPOST_OUT := "res://../art_working/winds_edge_qa/windows"

func _run() -> void:
	for window_size: Vector2i in WINDOWS:
		DisplayServer.window_set_size(window_size)
		await _frames(10)
		_window_label = "%dx%d" % [window_size.x, window_size.y]
		_save_path = "user://outpost_acceptance/%d/%s/profile.json" % [OS.get_process_id(), _window_label]
		await _new_root()
		OutpostSuite.at_outpost_order(_game.session, window_size.y == 844)
		_game.session.set_guild_visit_active(false)
		_game.router.go_to("world")
		await _frames(6)
		await _map_visit("MapOutpost")
		await _read(_game.router.current_screen.dialogue)
		if not _check(_game.session.location_id == GameSession.LOCATION_OUTPOST, "Hollow report unlocks travel"):
			break
		await _capture("01_arrival")
		var bowl: Button = _node("BowlProp").get_child(0)
		_check(bowl.size.x >= UiIcons.TOUCH_SIZE and bowl.size.y >= UiIcons.TOUCH_SIZE, "Bowl has a mobile touch target")
		_block_write()
		await _touch(bowl.get_global_rect().get_center())
		_check(_game.session.outpost_stage() == "bowl", "Failed inspection write keeps the first objective")
		_unblock_write()
		await _touch(bowl.get_global_rect().get_center())
		_check(_game.session.outpost_stage() == "seal", "Touching the bowl completes inspection")
		var sign: Button = _node("WatchSign").get_child(0)
		_check(sign.size.x >= UiIcons.TOUCH_SIZE and sign.size.y >= UiIcons.TOUCH_SIZE, "Seal has a mobile touch target")
		await _touch(sign.get_global_rect().get_center())
		var world: Control = _game.router.current_screen
		_check(world.outpost_route.dialogue.is_active(), "The seal triggers first contact")
		await _capture("02_first_contact")
		_game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await _frames(3)
		_check(not world.outpost_route.dialogue.is_active() and _node("OutpostAction").has_focus(), "System Back restores the route action")
		await _click(_node("OutpostAction"))
		await _read(world.outpost_route.dialogue)
		await _click(_node("OutpostAction"))
		var combat: Control = _game.router.current_screen
		if not _check(combat.name == "Combat", "First battle starts from the outpost"):
			break
		await _frames(40)
		_check_pair_framing(combat.arena_presenter)
		await _capture("03_ravens")
		await _win_auto(combat)
		await _open_claim(combat)
		await _click(combat.result_panel.claim_button)
		for stage: String in ["gate_patrol", "stairs_patrol", "tower_patrol"]:
			_check(_game.session.outpost_stage() == stage, "Outpost advances to " + stage)
			await _click(_node("OutpostAction"))
			combat = _game.router.current_screen
			await _frames(40)
			await _win_auto(combat)
			await _open_claim(combat)
			await _click(combat.result_panel.claim_button)
		world = _game.router.current_screen
		await _read(world.outpost_route.dialogue)
		_check(world.checkpoint_button.visible and _game.session.checkpoints.can_begin(), "Seal is available before the boss")
		if window_size.y == 844:
			_game.session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
		await _click(_node("OutpostAction"))
		combat = _game.router.current_screen
		if not _check(combat.name == "Combat" and combat.resolver.enemy.definition.id == "bone_warden", "The fifth battle starts through the existing combat screen"):
			break
		await _frames(40)
		combat.set_physics_process(false)
		_check(not combat.get_node("Arena/SecondEnemySprite").visible, "A dormant raven has no sprite or hit target")
		_check_pair_framing(combat.arena_presenter)
		await _capture("04_warden")
		if window_size.y == 844:
			await _play_active_warden(combat)
		else:
			await _capture_boss_phases(combat)
			await _win_auto(combat)
		await _continue_profile()
		combat = _game.router.current_screen
		if not _check(combat.name == "Combat" and combat.resolver == null and combat._result_visible, "Continue restores the boss reward without replaying combat"):
			break
		await _open_claim(combat)
		_block_write()
		await _click(combat.result_panel.claim_button)
		_check(_game.session.inventory.filter("quest").is_empty() and _game.session.hero.level == 4, "A failed boss claim leaves items, XP and the stage untouched")
		_unblock_write()
		await _click(combat.result_panel.claim_button)
		var expected_level: int = 5 if window_size.y == 844 else 4
		_check(_game.session.inventory.filter("quest").size() == 2 and _game.session.hero.level == expected_level, "Boss loot and route-dependent XP are delivered atomically")
		world = _game.router.current_screen
		await _capture("07_alliance")
		await _read(world.outpost_route.dialogue)
		await _map_visit("MapLioren")
		_check(_game.session.location_id == GameSession.LOCATION_LIOREN and _game.session.quest_flags.has(GameSession.OUTPOST_ALLIANCE), "The map returns to Lioren after the alliance")
		await _map_visit("MapGuild")
		await _read(_game.router.current_screen.dialogue)
		await _click(_node("ReportOutpost"))
		var guild: Control = _game.router.current_screen
		await _read(guild.dialogue)
		var silver: int = _game.session.wallet[GameSession.SILVER]
		var echoes: int = _game.session.echoes
		_block_write()
		await _click(guild._report_view.claim_button)
		_check(_game.session.wallet[GameSession.SILVER] == silver and guild._report_view.claim_button.text == "Повторить запись", "Failed report pays nothing and retains focus")
		_unblock_write()
		await _click(guild._report_view.claim_button)
		_check(_game.session.wallet[GameSession.SILVER] == silver + 60 and _game.session.echoes == echoes + 3, "The report grants both rewards once")
		await _capture("08_letter")
		await _continue_profile()
		guild = _game.router.current_screen
		_check(guild.name == "Guild" and guild.dialogue.is_active(), "Continue resumes the epilogue after the paid report")
		await _read_to_map(guild)
		await _capture("09_map")
		_block_write()
		await _read(guild.dialogue)
		_check(not _game.session.quest_flags.has(GameSession.OUTPOST_FINISHED) and _node("OutpostEpilogue").text == "Повторить запись", "A failed final write leaves the chapter open with a retry")
		_unblock_write()
		await _click(_node("OutpostEpilogue"))
		_check(_game.session.quest_flags.has(GameSession.OUTPOST_FINISHED) and _node("OrderTitle").text == "Глава завершена", "The map and letter close the chapter")
		await _continue_profile()
		_check(_node("OrderTitle").text == "Глава завершена" and _game.session.wallet[GameSession.SILVER] == silver + 60, "Completed chapter and single payment remain after Continue")
		await _capture("10_completed")
	print("OUTPOST_ACCEPTANCE checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _capture_boss_phases(combat: Control) -> void:
	var resolver: CombatResolver = combat.resolver
	for index: int in range(600):
		if resolver.warden_move == "void" and resolver.enemy_phase == CombatResolver.Phase.STARTUP:
			break
		resolver.advance_ticks(1)
	await _capture("05_void")
	_check(combat.get_node("Arena/SecondEnemySprite").visible and resolver.warden_move == "void", "The summoned raven and void zone are visible")
	for index: int in range(600):
		if resolver.enemy_slots[0].stunned or resolver.is_finished:
			break
		resolver.advance_ticks(1)
	_check(resolver.enemy_slots[0].stunned and _node("AllyCue").visible, "The joint opening shows Akari's signal")
	await _capture("06_joint_break")

func _play_active_warden(combat: Control) -> void:
	var resolver: CombatResolver = combat.resolver
	for index: int in range(46):
		if resolver.is_finished or not resolver.enemy_slots[1].dormant:
			break
		if combat.ability_button.visible and not combat.ability_button.disabled:
			await _click(combat.ability_button)
		elif combat.attack_button.visible and not combat.attack_button.disabled:
			await _click(combat.attack_button)
		if resolver.enemy_phase == CombatResolver.Phase.STARTUP and resolver.phase_ticks_remaining <= 7:
			await _click(combat.dodge_button)
		resolver.advance_ticks(7)
		combat._refresh_cooldowns()
	var raven_hp: Control = _node("SecondEnemyHealth")
	await _touch(raven_hp.get_global_rect().get_center())
	_check(resolver.target.instance_id == "warden_raven", "Active mode can select the summoned raven by touch")
	await _win_active(combat)

func _read_to_map(guild: Control) -> void:
	for index: int in range(28):
		if not guild.dialogue.is_active() or guild.get_node("EpilogueMap").visible:
			break
		await _click(guild.dialogue.next_button)
	_check(guild.get_node("EpilogueMap").visible, "Epilogue reveals the new route on Midori's map")

func _capture(label: String) -> void:
	await _frames(4)
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUTPOST_OUT.path_join(_window_label).path_join(label + ".png"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(image != null and image.save_png(path) == OK, "Capture %s" % label)
