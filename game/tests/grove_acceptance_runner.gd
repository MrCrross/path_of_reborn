extends SceneTree

const GroveSuite = preload("res://tests/grove_suite.gd")
const WINDOWS: Array[Vector2i] = [Vector2i(360, 640), Vector2i(360, 800), Vector2i(390, 844), Vector2i(412, 915)]
const OUT := "res://../art_working/grove_acceptance"

var _game: GameRoot
var _failures: int = 0
var _checks: int = 0
var _window_label: String
var _save_path: String

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for window_size: Vector2i in WINDOWS:
		DisplayServer.window_set_size(window_size)
		await _frames(10)
		_window_label = "%dx%d" % [window_size.x, window_size.y]
		_save_path = "user://grove_acceptance/%d/%s/profile.json" % [OS.get_process_id(), _window_label]
		await _new_root()
		GroveSuite.at_guild(_game.session)
		_game.session.set_combat_format(GameSession.COMBAT_FORMAT_AUTO)
		_game.session.set_auto_speed(1)
		_game.session.set_guild_visit_active(false)
		_game.router.go_to("world")
		await _frames(6)
		await _map_visit("MapGuild")
		await _capture("01_order")
		await _click(_game.router.current_screen.back_button)
		await _map_visit("MapGrove")
		var world: Control = _game.router.current_screen
		_check(world.name == "World" and _game.session.location_id == GameSession.LOCATION_GROVE, "Grove is entered from the world map")
		if _game.session.location_id != GameSession.LOCATION_GROVE:
			break
		_check(world.grove_route.props.get_child_count() == 2, "Both hounds are visible during the approach")
		await _capture("02_approach")
		for page: int in range(5):
			if _game.session.seen_cue_ids.has("DIA_GROVE_001"):
				break
			await _click(world.grove_route.dialogue.next_button)
		await _continue_profile()
		world = _game.router.current_screen
		_check(world.grove_route.dialogue.is_active() and world.grove_route.dialogue.runner.current_cue()["id"] != "DIA_GROVE_001", "Continue resumes after the completed approach cue")
		await _read(world.grove_route.dialogue)
		if window_size.y != 800:
			await _click(_node("GroveNoise"))
		else:
			_check(_game.session.choose_upgrade("strength"), "The direct approach uses the level earned on the trail")
		await _click(_node("GroveFight"))
		var combat: Control = _game.router.current_screen
		if not _check(combat.name == "Combat", "First encounter starts through World"):
			break
		await _frames(39)
		var pair: CombatResolver = combat.resolver
		_check(pair.enemy_slots.size() == 2 and pair.combat_format == GameSession.COMBAT_FORMAT_AUTO, "Both hounds share one automatic encounter")
		_check_pair_framing(combat.arena_presenter)
		await _capture("03_hounds")
		pair.advance_ticks(1200)
		await _frames(45)
		if not _check(combat._result_visible and _game.session.has_pending_battle_result(), "Win waits for the reward cards"):
			break
		await _capture("04_hounds_result")
		await _continue_profile()
		combat = _game.router.current_screen
		_check(combat.name == "Combat" and combat.resolver == null and combat._result_visible, "Continue restores the first battle result without restarting")
		await _open_claim(combat)
		var first_id: String = _game.session.pending_battle_result["result_id"]
		_block_write()
		await _click(combat.result_panel.claim_button)
		_check(_game.session.has_pending_battle_result() and _game.session.grove_stage() == "hound_pair" and _game.session.grove_bandage() == null, "Failed battle claim leaves result, inventory and stage intact")
		_unblock_write()
		await _click(combat.result_panel.claim_button)
		_check(not _game.claim_battle_result(first_id) and _game.session.grove_bandage() != null, "Battle claim retry delivers once")
		world = _game.router.current_screen
		await _capture("05_kenta")
		await _read(world.grove_route.dialogue)
		_check(world.art_background.texture == ArtMap.texture(ArtMap.BACKGROUNDS["grove_bridge"]) and not world.hero_sprite.visible, "Kenta remains in the bridge shot during the decision")
		_check(not world.traces_label.is_visible_in_tree() and not world.hero_label.is_visible_in_tree() and world.map_button.is_visible_in_tree(), "Bridge choices keep the map while clearing the HUD from Kenta's face")
		_check(world.inventory_button.is_visible_in_tree() and world.map_button.text.is_empty(), "The bridge uses the same bag and map icons as the trail")
		await _capture("06_kenta_choices")
		if window_size.y == 800:
			await _click(_node("KentaSafe"))
			_check(_game.session.grove_kenta_outcome() == "grove_kenta_safe" and _game.session.grove_bandage() != null, "Safe descent saves the branch and keeps the bandage")
		elif window_size.y == 844:
			_game.session.inventory.remove(_game.session.grove_bandage().instance_id, 1)
			world.grove_route.refresh(false)
			await _frames(3)
			_check(_node("KentaBandage") == null, "Bandage choice is hidden with an empty stack")
			await _click(_node("KentaHint"))
			_check(_game.session.grove_kenta_outcome() == "grove_kenta_hint", "Short hint reaches the second encounter")
		else:
			_block_write()
			await _click(_node("KentaBandage"))
			_check(_game.session.grove_bandage() != null and _game.session.grove_kenta_outcome().is_empty(), "Failed choice does not consume the bandage")
			_unblock_write()
			await _click(_node("KentaBandage"))
			_check(_game.session.grove_bandage() == null and _game.session.grove_kenta_outcome() == "grove_kenta_bandage", "Retry consumes one bandage and saves the outcome")
			_check(not _game.commit_grove_command("grove_kenta_bandage"), "Repeated Kenta choice is rejected")
		await _read(world.grove_route.dialogue)
		_check(_game.session.seen_cue_ids.has("DIA_GROVE_010") == (window_size.y != 844), "Only the two help routes show the pollen warning from Kenta")
		_game.session.set_combat_format(GameSession.COMBAT_FORMAT_ACTIVE)
		await _click(_node("GroveFight"))
		combat = _game.router.current_screen
		if not _check(combat.name == "Combat", "Second encounter starts through World"):
			break
		await _frames(38)
		combat.set_physics_process(false)
		pair = combat.resolver
		_check(pair.combat_format == GameSession.COMBAT_FORMAT_ACTIVE and pair.target.instance_id == "dust_moth", "Manual fight defaults to moth")
		_check_pair_framing(combat.arena_presenter)
		var second_health: Control = combat.arena.get_node("SecondEnemyHealth")
		await _touch(second_health.get_global_rect().get_center())
		_check(pair.target.instance_id == "root_weaver", "A touch on the second HP bar selects the weaver")
		await _touch(combat.enemy_health.get_global_rect().get_center())
		_check(pair.target.instance_id == "dust_moth", "A touch on the first HP bar selects the moth")
		var weaver: AnimatedSprite2D = combat.arena.get_node("SecondEnemySprite")
		await _touch(weaver.position + Vector2(18, -14))
		_check(pair.target.instance_id == "root_weaver", "A touch on the weaver's outer silhouette selects it")
		await _touch(combat.enemy_health.get_global_rect().get_center())
		await _capture("07_pollen_warning")
		var moth: CombatResolver.EnemySlot = pair.enemy_slots[0]
		pair.advance_ticks(moth.remaining + moth.actor.definition.startup_ticks - 2)
		await _click(combat.dodge_button)
		pair.advance_ticks(2)
		_check(pair.slowed_ticks == 0, "The ordinary dodge button avoids pollen")
		await _capture("08_pollen_contact")
		for step: int in range(20):
			if pair.is_finished:
				break
			for slot: CombatResolver.EnemySlot in pair.enemy_slots:
				if not slot.actor.is_dead() and slot.phase == CombatResolver.Phase.STARTUP and slot.remaining <= 7:
					await _click(combat.dodge_button)
			if pair.hero_attack_cooldown == 0:
				await _click(combat.ability_button if pair.hero_ability_cooldown == 0 else combat.attack_button)
			pair.advance_ticks(20)
			combat._refresh_cooldowns()
		await _frames(45)
		if not _check(pair.won and combat._result_visible and _game.session.battle_echo_reward(_game.session.pending_battle_result) == 2, "Manual win yields one result for two enemy types"):
			break
		await _open_claim(combat)
		await _click(combat.result_panel.claim_button)
		world = _game.router.current_screen
		await _read(world.grove_route.dialogue)
		await _capture("09_clearing")
		var flax_hotspot: Button = _node("MoonFlaxProp").get_child(0)
		_check(flax_hotspot.size.x >= UiIcons.TOUCH_SIZE and flax_hotspot.size.y >= UiIcons.TOUCH_SIZE, "Flax keeps a full touch target at its native art size")
		await _click(_node("EasternMarkerProp").get_child(0))
		_check(_game.session.quest_flags.has(GameSession.GROVE_MARKER), "The marker can be inspected directly in the scene")
		await _capture("10_marker")
		await _read(world.grove_route.dialogue)
		await _continue_profile()
		world = _game.router.current_screen
		_check(_game.session.quest_flags.has(GameSession.GROVE_MARKER) and not _game.session.quest_flags.has(GameSession.GROVE_FLAX), "Continue preserves just one gathered objective")
		var keep_point: bool = window_size.y in [640, 844]
		if keep_point:
			await _click(world.checkpoint_button)
			var seal: Control = _game.router.current_screen
			await _click(seal.get_node("%StartButton"))
			_game.session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
			await _frames(8)
			_check(_game.session.world_flags.get(GameSession.GROVE_SEALED, false), "Seal is recorded on successful completion")
			await _capture("11_seal")
			await _click(seal.get_node("%BackButton"))
			world = _game.router.current_screen
			_check(world.grove_route.dialogue.is_active() and world.grove_route.dialogue.runner.current_cue()["id"] == "DIA_GROVE_014", "The Seal line appears after the confirmed write")
			await _read(world.grove_route.dialogue)
		await _leave(world, keep_point, window_size.y == 800)
		await _map_visit("MapGuild")
		_check(not _node("ReportGrove").is_visible_in_tree(), "The Guild refuses a partial report")
		await _click(_game.router.current_screen.back_button)
		await _map_visit("MapGrove")
		world = _game.router.current_screen
		await _click(_node("MoonFlaxProp").get_child(0))
		_check(not _node("MoonFlaxProp").visible and _node("GatherFlax") == null and (_node("MapButton").has_focus() or _node("GroveSetSeal") != null and _node("GroveSetSeal").has_focus()), "Gathering the last objective focuses the Seal or map")
		await _leave(world, keep_point)
		await _map_visit("MapGuild")
		_check(_node("OrderTitle").text == "Можно сдать задание" and _node("ReportGrove").theme_type_variation == &"PrimaryButton" and _node("EnterGrove") == null, "With both objectives ready, reporting is the primary Guild action")
		await _click(_node("ReportGrove"))
		var guild: Control = _game.router.current_screen
		await _capture("12_midori")
		await _read(guild.dialogue)
		await _continue_profile()
		guild = _game.router.current_screen
		_check(guild._report_view.visible, "Continue reopens the completed report before the reward claim")
		await _capture("13_report_reward")
		var xp: int = _game.session.hero.experience
		var echoes: int = _game.session.echoes
		_block_write()
		await _click(guild._report_view.claim_button)
		_check(not _game.session.quest_flags.has(GameSession.GROVE_REPORTED) and _game.session.wallet[GameSession.SILVER] == 0 and _game.session.hero.experience == xp, "Failed report keeps rewards and progress intact")
		_unblock_write()
		await _click(guild._report_view.claim_button)
		_check(_game.session.echoes == echoes + 2 and _game.session.wallet[GameSession.SILVER] == 35 and _game.session.quest_flags.has(GameSession.GROVE_REPORTED), "Retry commits report and rewards")
		_check(not _game.commit_grove_command("report"), "Duplicate report cannot grant another reward")
		await _read(guild.dialogue)
		await _continue_profile()
		_check(_game.router.current_screen.name == "Guild" and _node("OrderTitle").text == "Следующее задание · Синий Овраг", "Continue shows the next assignment after the completed report")
		await _capture("14_completed")
	print("GROVE_ACCEPTANCE checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _new_root() -> void:
	if is_instance_valid(_game):
		root.remove_child(_game)
		_game.free()
	_game = load("res://scenes/game_root.tscn").instantiate()
	root.add_child(_game)
	current_scene = _game
	_game.save_path = _save_path
	_game.preferences_path = PreferencesService.path_for_profile(_save_path)
	_game.preferences.load_preferences(_game.preferences_path)
	await _frames(5)

func _continue_profile() -> void:
	await _new_root()
	_game.router.current_screen.set_profile_status(_game.save_service.has_profile(_save_path), _game.save_service.last_error)
	await _click(_game.router.current_screen.get_node("%ContinueButton"))

func _node(node_name: String) -> Control:
	return _game.router.current_screen.find_child(node_name, true, false)

func _map_visit(destination: String) -> void:
	var screen: Control = _game.router.current_screen
	if screen.name == "World":
		await _click(screen.map_button)
	screen = _game.router.current_screen
	var city_destination: bool = destination in ["MapShop", "MapGuild", "MapGate"]
	if city_destination and not screen.city_map:
		await _click(_node("MapLioren"))
	elif not city_destination and screen.city_map:
		await _click(screen.get_node("%Back"))
	var option: Button = _node(destination)
	if option == null:
		option = _node("FirstRoute")
	await _click(option)

func _leave(_world: Control, keep_point: bool, fail_final_write: bool = false) -> void:
	await _map_visit("MapLioren")
	if not keep_point:
		var map: Control = _game.router.current_screen
		var dialogs: Array[Node] = get_nodes_in_group(ConfirmDialog.MODAL_GROUP)
		if not dialogs.is_empty():
			await _press_key(KEY_I)
			await _press_key(KEY_C)
			_check(_game.router.current_screen == map and ConfirmDialog.has_open(map), "Inventory and Seal shortcuts stay behind the map confirmation")
			await _click(dialogs[-1].get_node("%Confirm"))
		if _game.router.current_screen == map:
			_check(map.dialogue.is_active() and map.dialogue.runner.current_cue()["id"] == "DIA_GROVE_015", "Leaving without a Seal keeps the optional line")
			if fail_final_write:
				_block_write()
			await _read(map.dialogue)
			if fail_final_write:
				var retry: Button = _node("MapLioren")
				_check(_game.router.current_screen == map and _game.session.location_id == GameSession.LOCATION_GROVE and not map.dialogue.is_active() and _node("TravelError").visible and retry.has_focus(), "A failed transition keeps the current location and focuses the map destination for retry")
				_unblock_write()
				await _click(retry)
	_check(_game.session.location_id == GameSession.LOCATION_LIOREN, "The map returns the player to Lioren")

func _check_pair_framing(presenter: CombatArenaPresenter) -> void:
	var arena_bounds := Rect2(Vector2.ZERO, presenter.arena.size)
	for view: CombatArenaPresenter.GroveEnemyView in presenter._grove_enemies:
		for clip: Dictionary in view.clips.values():
			var frames: SpriteFrames = clip["frames"]
			var scale_factor: Vector2 = clip["scale"]
			var offset: Vector2 = clip["offset"]
			for index: int in range(frames.get_frame_count(&"default")):
				var frame: AtlasTexture = frames.get_frame_texture(&"default", index)
				var pixels: Image = frame.atlas.get_image().get_region(Rect2i(frame.region))
				var solid: Rect2 = Rect2(pixels.get_used_rect())
				var origin: Vector2 = offset - frame.get_size() * 0.5 + solid.position
				var visual := Rect2(view.sprite.position + origin * scale_factor, solid.size * scale_factor)
				_check(arena_bounds.encloses(visual), "Every enemy pose stays in frame: %s" % frame.atlas.resource_path)
				_check(view.health.get_rect().end.y <= visual.position.y, "Enemy HP stays above every pose: %s" % frame.atlas.resource_path)

func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	root.push_input(event, true)
	await _frames(1)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await _frames(2)

func _open_claim(combat: Control) -> void:
	await _click(combat.result_panel.summary_button)
	var dialogs: Array[Node] = get_nodes_in_group(ConfirmDialog.MODAL_GROUP)
	if not dialogs.is_empty():
		await _click(dialogs[-1].get_node("%Confirm"))
	for index: int in range(4):
		if combat.result_panel.can_claim():
			break
		await _click(combat.result_panel.card)
	_check(combat.result_panel.can_claim(), "Reward cards lead to the existing claim button")

func _read(dialogue: DialogueOverlay) -> void:
	for index: int in range(28):
		if not is_instance_valid(dialogue) or not dialogue.is_active():
			return
		await _click(dialogue.next_button)
	_check(false, "Dialogue finishes within the input limit")

func _click(control: Control) -> void:
	if not _check(control != null and control.is_visible_in_tree(), "Visible input target: %s" % (control.name if control != null else "<missing>")):
		return
	var rect: Rect2 = control.get_global_rect()
	_check(root.get_visible_rect().encloses(rect), "Input target fits the viewport: %s" % control.name)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = rect.get_center()
	event.pressed = true
	root.push_input(event, true)
	await _frames(1)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await _frames(5)

func _touch(point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = true
	root.push_input(event, true)
	await _frames(1)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await _frames(3)

func _block_write() -> void:
	_check(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(_save_path + ".tmp")) == OK, "Write failure injected by reserving the temp path")

func _unblock_write() -> void:
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path + ".tmp")) == OK, "Temporary write blocker removed")

func _capture(label: String) -> void:
	await _frames(4)
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT + "/" + _window_label + "/" + label + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(image != null and image.save_png(path) == OK, "Capture %s" % label)

func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", _window_label, " ", message)
	return condition
