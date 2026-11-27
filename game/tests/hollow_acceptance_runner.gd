extends "res://tests/grove_acceptance_runner.gd"

const HollowSuite = preload("res://tests/hollow_suite.gd")
const HOLLOW_OUT := "res://../art_working/blue_hollow_qa/windows"

var _hollow_out: String = HOLLOW_OUT

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--hollow-out="):
			_hollow_out = argument.trim_prefix("--hollow-out=")
	for window_size: Vector2i in WINDOWS:
		DisplayServer.window_set_size(window_size)
		await _frames(10)
		_window_label = "%dx%d" % [window_size.x, window_size.y]
		_save_path = "user://hollow_acceptance/%d/%s/profile.json" % [OS.get_process_id(), _window_label]
		await _new_root()
		HollowSuite.at_hollow_order(_game.session)
		_game.session.set_guild_visit_active(false)
		_game.router.go_to("world")
		await _frames(6)
		await _map_visit("MapHollow")
		await _capture("01_order")
		await _read(_game.router.current_screen.dialogue)
		if not _check(_game.session.location_id == GameSession.LOCATION_HOLLOW, "The map briefing opens Blue Hollow"):
			break
		await _read(_game.router.current_screen.hollow_route.dialogue)
		await _click(_node("HollowFight"))
		var combat: Control = _game.router.current_screen
		if not _check(combat.name == "Combat", "Shieldback starts through World"):
			break
		await _frames(39)
		_check_pair_framing(combat.arena_presenter)
		await _capture("02_shieldback")
		await _win_auto(combat)
		await _continue_profile()
		combat = _game.router.current_screen
		_check(combat.name == "Combat" and combat.resolver == null and combat._result_visible, "Continue restores the pending shieldback result")
		await _open_claim(combat)
		await _click(combat.result_panel.claim_button)
		if not _check(_game.session.hollow_stage() == "water_marker", "Claim unlocks the water marker"):
			break
		var marker: Control = _node("MarkerProp")
		var marker_hotspot: Button = marker.get_child(0)
		_check(marker_hotspot.size.x >= UiIcons.TOUCH_SIZE and marker_hotspot.size.y >= UiIcons.TOUCH_SIZE, "Marker hotspot has a 24 px touch target")
		_block_write()
		await _click(marker_hotspot)
		_check(_game.session.hollow_stage() == "water_marker" and _game.session.inventory.filter("echo").is_empty(), "Failed write keeps the marker and crystal available")
		_unblock_write()
		await _click(marker_hotspot)
		_check(_game.session.hollow_stage() == "shelf" and _game.session.inventory.filter("echo").size() == 1, "Tapping the marker delivers one crystal")
		await _read(_game.router.current_screen.hollow_route.dialogue)
		await _capture("03_shelf")
		await _click(_node("ShelfProp").get_child(0))
		_check(_game.session.quest_flags.has(GameSession.HOLLOW_COLLAPSED), "Scene shelf can be collapsed by touch")
		_game.session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
		await _click(_node("HollowFight"))
		combat = _game.router.current_screen
		if not _check(combat.name == "Combat" and combat.resolver.enemy_slots.size() == 3, "Shelf fight starts with three actors"):
			break
		await _frames(39)
		combat.set_physics_process(false)
		_check_pair_framing(combat.arena_presenter)
		await _capture("04_shelf_battle")
		var raven_hp: Control = _node("ThirdEnemyHealth")
		await _touch(raven_hp.get_global_rect().get_center())
		_check(combat.resolver.target.instance_id == "ash_raven", "Touch targets the raven independently")
		await _touch(combat.enemy_health.get_global_rect().get_center())
		_check(combat.resolver.target.stunned, "First rodent remains stunned at start")
		await _win_active(combat)
		await _open_claim(combat)
		await _click(combat.result_panel.claim_button)
		_check(_game.session.quest_flags.has(GameSession.HOLLOW_TEMPO), "Result unlocks Tempo")
		await _read(_game.router.current_screen.hollow_route.dialogue)
		await _click(_node("RestoreMarker"))
		await _read(_game.router.current_screen.hollow_route.dialogue)
		await _click(_node("InspectWall"))
		await _capture("05_cloth")
		await _read(_game.router.current_screen.hollow_route.dialogue)
		var world: Control = _game.router.current_screen
		await _click(world.checkpoint_button)
		var seal: Control = _game.router.current_screen
		await _click(seal.get_node("%StartButton"))
		_game.session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
		await _frames(8)
		_check(_game.session.checkpoints.manual_snapshots.size() == 1, "Safe ledge can be fixed")
		await _click(seal.get_node("%BackButton"))
		await _map_visit("MapBasin")
		await _capture("06_risk")
		if window_size.y == 800:
			_game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		else:
			var cancel := InputEventKey.new()
			cancel.keycode = KEY_ESCAPE
			cancel.pressed = true
			root.push_input(cancel, true)
		await _frames(2)
		_check(_game.session.hollow_stage() == "ledge" and _node("MapBasin") == null and _node("FirstRoute").has_focus(), "Back cancels the warning, conceals the unvisited basin and returns focus")
		await _map_visit("MapBasin")
		var modal: Node = get_nodes_in_group(ConfirmDialog.MODAL_GROUP).back()
		await _click(modal.get_node("%Confirm"))
		await _read(_game.router.current_screen.hollow_route.dialogue)
		if window_size.y == 800:
			await _click(_game.router.current_screen.map_button)
			_check(_node("MapLioren").disabled, "The map leads back to the ledge before leaving the elite basin")
			await _map_visit("MapLedge")
			await _read(_game.router.current_screen.hollow_route.dialogue)
			_check(not _game.session.quest_flags.has(GameSession.HOLLOW_ELITE_WON), "Retreat preserves the report without elite reward")
		else:
			_game.session.set_combat_format(GameSession.COMBAT_FORMAT_AUTO)
			_game.session.choose_upgrade("strength")
			_game.session.choose_upgrade("max_hp")
			await _click(_node("HollowFight"))
			combat = _game.router.current_screen
			if not _check(combat.name == "Combat", "Elite encounter starts after confirmation"):
				break
			await _frames(39)
			_check_pair_framing(combat.arena_presenter)
			await _capture("07_elite")
			await _win_auto(combat)
			await _open_claim(combat)
			await _click(combat.result_panel.claim_button)
			_check(_game.session.quest_flags.has(GameSession.HOLLOW_ELITE_WON), "Elite victory is recorded")
		await _map_visit("MapLioren")
		_check(_game.session.location_id == GameSession.LOCATION_LIOREN, "Route can leave for Lioren")
		await _map_visit("MapGuild")
		await _read(_game.router.current_screen.dialogue)
		await _click(_node("ReportHollow"))
		await _read(_game.router.current_screen.dialogue)
		var rewards: CombatResultView = _node("GroveReportReward")
		await _capture("08_report")
		_block_write()
		await _click(rewards.claim_button)
		_check(_game.session.wallet[GameSession.SILVER] == 35 and rewards.claim_button.text == "Повторить запись", "Failed report stays available and pays nothing")
		_unblock_write()
		await _click(rewards.claim_button)
		_check(_game.session.wallet[GameSession.SILVER] == 80 and not _game.commit_hollow_command("report"), "Report pays once after retry")
		await _continue_profile()
		_check(_node("OrderTitle").text == "Отчёт об Овраге принят", "Continue shows the accepted report")
		await _capture("09_completed")
	print("HOLLOW_ACCEPTANCE checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _win_auto(combat: Control) -> void:
	combat.resolver.advance_ticks(1800)
	await _frames(45)
	_check(combat._result_visible and combat.resolver.won, "Automatic win presents battle results")

func _win_active(combat: Control) -> void:
	var resolver: CombatResolver = combat.resolver
	for step: int in range(60):
		if resolver.is_finished:
			break
		for slot: CombatResolver.EnemySlot in resolver.enemy_slots:
			if not slot.actor.is_dead() and slot.phase == CombatResolver.Phase.STARTUP and slot.remaining <= 6:
				await _click(combat.dodge_button)
		if resolver.hero_attack_cooldown == 0:
			await _click(combat.ability_button if resolver.hero_ability_cooldown == 0 else combat.attack_button)
		resolver.advance_ticks(10)
		combat._refresh_cooldowns()
	await _frames(45)
	_check(combat._result_visible and resolver.won, "Active win presents battle results")

func _capture(label: String) -> void:
	await _frames(4)
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(_hollow_out.path_join(_window_label).path_join(label + ".png"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(image != null and image.save_png(path) == OK, "Capture %s" % label)
