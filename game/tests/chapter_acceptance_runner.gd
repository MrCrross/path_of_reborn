extends "res://tests/first_session_acceptance_runner.gd"

const CHAPTER_OUT := "res://../art_working/chapter_acceptance"
const CHECKPOINT_WINDOW := Vector2i(360, 800)

var _window_label: String
var _chapter_out: String = CHAPTER_OUT

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--chapter-out="):
			_chapter_out = argument.trim_prefix("--chapter-out=")
	_run.call_deferred()

func _run() -> void:
	for window_size: Vector2i in WINDOW_SIZES:
		_window_label = "%dx%d" % [window_size.x, window_size.y]
		DisplayServer.window_set_size(window_size)
		_actions = 0
		_report.erase("prologue")
		_save_path = "user://chapter_acceptance/%d_%d/%s/profile.json" % [OS.get_process_id(), Time.get_ticks_usec(), _window_label]
		await _new_game_root()
		_check(DisplayServer.window_get_size() == window_size, "%s uses the requested portrait size" % _window_label)
		var finished: bool = await _play_chapter()
		_check(finished == true, "%s reaches the end of the chapter" % _window_label)
		_report["windows"].append({"size": _window_label, "finished": finished, "prologue": _report.get("prologue", {})})
	var output := ProjectSettings.globalize_path(_chapter_out)
	DirAccess.make_dir_recursive_absolute(output)
	var report := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	_check(report != null, "Chapter report can be written")
	if report != null:
		_report["failed"] = _failed
		_report["checks_count"] = _checks
		report.store_string(JSON.stringify(_report, "\t"))
		report.close()
	print("CHAPTER_ACCEPTANCE checks=%d failures=%d" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)

func _play_chapter() -> bool:
	_check(not _game.save_service.has_profile(_save_path), "Every window starts with a clean profile")
	await _play_prologue()
	if not await _trail_and_city():
		return false
	if not await _grove():
		return false
	if not await _hollow():
		return false
	if not await _outpost():
		return false
	await _reload_from_title()
	_check(_game.router.current_screen.name == "Guild", "Continue returns to the completed Guild desk")
	_check("В следующей главе" in _game.router.current_screen.get_node("%Objectives").text and _game.router.current_screen.back_button.has_focus(), "The finale presents the archive as the next chapter and focuses the return to Lioren")
	_check(_game.session.quest_flags.has_all([GameSession.GROVE_REPORTED, GameSession.HOLLOW_REPORTED, GameSession.OUTPOST_FINISHED]), "All three report milestones survive Continue")
	_check(_game.session.wallet[GameSession.COPPER] == 10 and _game.session.wallet[GameSession.SILVER] == 140, "The branch sale, purchases and guild silver survive without a duplicate payout")
	_check(_game.session.guild_rank() == "E" and _game.session.hero.level == 4 and _game.session.inventory.filter("quest").size() == 2, "Rank E, level 4 and both key items survive the core route without grinding")
	var equipped: Dictionary = _game.session.inventory.equipment_for()
	_check(equipped.has_all(["weapon", "armor"]) and _game.session.inventory.get_item(equipped["weapon"]).definition_id == "training_sword" and _game.session.inventory.get_item(equipped["armor"]).definition_id == "wanderer_jacket", "The story sword and purchased jacket stay equipped through the finale")
	await _capture("10_chapter_completed")
	await _click(_game.router.current_screen.back_button)
	var local: Control = _game.router.current_screen
	_check(local.city_map and _node("MapShop") != null and _node("MapGuild").has_focus(), "The completed city map shows both visited buildings and restores Guild focus")
	await _capture("10b_lioren_map")
	await _press_back()
	_check(not _game.router.current_screen.city_map and _node("MapLioren").has_focus(), "Back from the city restores the Lioren pin on the world map")
	_check_map_points(["MapTrail", "MapLioren", "MapGrove", "MapHollow", "MapOutpost"])
	await _capture("10c_world_map")
	var city_pin: Control = _node("MapLioren")
	await _tap(Vector2(city_pin.get_global_rect().get_center().x, city_pin.get_global_rect().position.y + 6.0))
	_check(_game.router.current_screen.city_map, "Tapping the marker above the label opens the local map")
	_check_map_points(["MapGate", "MapShop", "MapGuild"])
	return true

func _check_map_points(names: Array[String]) -> void:
	var bounds: Rect2 = _game.router.current_screen.get_node("%MapBoard").get_global_rect()
	var touch_regions: Array[Rect2] = []
	for point_name: String in names:
		var point: Control = _node(point_name)
		if point == null:
			_check(false, "Visited point is visible: " + point_name)
			continue
		var region: Rect2 = point.get_global_rect()
		_check(bounds.encloses(region) and region.size.x >= UiIcons.TOUCH_SIZE and region.size.y >= UiIcons.TOUCH_SIZE, "Map point fits its board with a usable target: " + point_name)
		_check(not touch_regions.any(func(other: Rect2) -> bool: return region.intersects(other)), "Map point does not overlap another target: " + point_name)
		touch_regions.append(region)

func _trail_and_city() -> bool:
	await _tap_world_progress()
	await _first_slime_dialogue()
	if not await _win_and_claim():
		return false
	await _choose_strength()
	await _second_slime_and_lookout()
	await _advance_merchant_to_combat()
	if not await _win_and_claim():
		return false
	await _advance_merchant_to_gift()
	await _click(_game.router.current_screen.equip_button)
	var world: Control = _game.router.current_screen
	await _dismiss_tutorial(world)
	await _capture("02_trail_sword")
	await _click(world.map_button)
	_check(_node("MapTrail") != null and _node("MapLioren") == null and _node("MapGrove") == null and _node("MapHollow") == null and _node("MapOutpost") == null and _node("FirstRoute").visible, "Only the visited Trail is marked before the first journey")
	await _capture("02b_map_trail")
	await _press_back()
	world = _game.router.current_screen
	_check(world.name == "World" and _game.session.location_id == GameSession.LOCATION_FOREST_EDGE and world.map_button.has_focus(), "Esc closes the map in the same location and restores the map button focus")
	await _map_visit("MapLioren")
	await _read(_game.router.current_screen.gates_dialogue)
	_check(_game.router.current_screen.name == "WorldMap" and _game.router.current_screen.city_map and _node("MapShop") == null and _node("MapGuild") == null and _node("FirstRoute").visible, "The gates open the local map with a first route and no unvisited building pins")
	await _capture("02c_map_lioren")
	if DisplayServer.window_get_size() == CHECKPOINT_WINDOW:
		var city_map: Control = _game.router.current_screen
		var temp_path: String = ProjectSettings.globalize_path(_save_path + ".tmp")
		_check(DirAccess.make_dir_absolute(temp_path) == OK, "Reserve the temporary profile path for a failed first visit")
		await _map_visit("MapShop")
		_check(_game.router.current_screen == city_map and _node("MapShop") == null and _node("TravelError").visible and _node("FirstRoute").has_focus(), "A failed first visit reveals no pin and keeps the route focused for retry")
		_check(DirAccess.remove_absolute(temp_path) == OK, "Release the temporary profile path before retry")
	await _map_visit("MapShop")
	var shop: Control = _game.router.current_screen
	if shop.name != "Shop":
		return false
	await _click_through_dialogue()
	await _dismiss_tutorial(shop)
	await _click(shop.sell_tab)
	await _click(shop.rows_box.get_child(0))
	await _click(shop.deal_confirm)
	await _dismiss_tutorial(shop)
	var branch: ItemInstance = _game.session.inventory.filter("weapon").filter(func(item: ItemInstance) -> bool: return item.definition_id == "broken_wanderer_branch").front()
	var branch_row: Button
	for row: Node in shop.rows_box.get_children():
		if row.get_meta(&"trade_row", "") == "sell:" + branch.instance_id:
			branch_row = row
			break
	await _capture("02b_shop_sell")
	await _click(branch_row)
	await _click(shop.deal_confirm)
	_check(_game.session.wallet[GameSession.COPPER] == 22 and _game.session.inventory.get_item(branch.instance_id) == null, "An unequipped starter branch can be sold in the shop")
	await _click(shop.buy_tab)
	await _click(shop.rows_box.get_child(0))
	await _click(shop.deal_confirm)
	await _click_through_dialogue()
	await _click(shop.bag_button)
	var bag: Control = _game.router.current_screen
	await _click(bag.equip_action)
	await _capture("03_jacket_equipped")
	await _click(bag.detail_close)
	await _click(bag.back_button)
	await _enter_guild()
	var guild: Control = _game.router.current_screen
	await _read(guild.dialogue)
	await _click(guild.register_button)
	_check(_game.session.guild_rank() == "E", "Registration unlocks the Grove after ordinary shopping")
	return _game.session.guild_rank() == "E"

func _grove() -> bool:
	await _click(_game.router.current_screen.back_button)
	await _map_visit("MapGrove")
	var world: Control = _game.router.current_screen
	await _capture("03b_grove_hounds")
	await _read(world.grove_route.dialogue)
	await _click(_node("GroveNoise"))
	await _click(_node("GroveFight"))
	if not await _win_and_claim():
		return false
	world = _game.router.current_screen
	await _read(world.grove_route.dialogue)
	await _click(_node("KentaBandage"))
	await _read(world.grove_route.dialogue)
	await _capture("03c_grove_moth_root")
	await _click(_node("GroveFight"))
	if not await _win_and_claim(true):
		return false
	world = _game.router.current_screen
	await _read(world.grove_route.dialogue)
	await _capture("03d_grove_flax")
	await _click_prop("MoonFlaxProp")
	await _read(world.grove_route.dialogue)
	_check(_node("InspectMarker").has_focus(), "Gathering flax focuses the remaining marker objective")
	await _click_prop("EasternMarkerProp")
	await _read(world.grove_route.dialogue)
	await _capture("04_grove_objectives")
	_check(_node("MapButton").is_visible_in_tree() and _node("GroveSetSeal").is_visible_in_tree(), "Grove clearing offers the map and the Seal")
	await _map_visit("MapLioren")
	var map: Control = _game.router.current_screen
	await _capture("04b_grove_return_modal")
	await _dismiss_tutorial(map)
	await _read(map.dialogue)
	await _map_visit("MapGate")
	await _choose_strength()
	await _enter_guild()
	await _report_to_guild("ReportGrove")
	_check(_game.session.wallet[GameSession.SILVER] == 35, "The Grove report grants 35 silver")
	return _game.session.quest_flags.has(GameSession.GROVE_REPORTED)

func _hollow() -> bool:
	await _click(_game.router.current_screen.back_button)
	await _map_visit("MapGate")
	await _choose_strength()
	await _map_visit("MapHollow")
	var guild: Control = _game.router.current_screen
	while is_instance_valid(guild) and guild.dialogue.is_active():
		if guild.dialogue.runner.current_shot() == "hollow_shizuka":
			var shizuka: Sprite2D = guild.find_child("Shizuka", true, false)
			var midori: Sprite2D = guild.find_child("Midori", true, false)
			_check(shizuka.is_visible_in_tree() and not midori.is_visible_in_tree(), "Shizuka's warning shows its speaker")
			await _capture("04c_shizuka")
			break
		await _click(guild.dialogue.next_button)
	if is_instance_valid(guild):
		await _read(guild.dialogue)
	await _read(_game.router.current_screen.hollow_route.dialogue)
	await _click(_node("HollowFight"))
	if not await _win_and_claim():
		return false
	await _click_prop("MarkerProp")
	await _read(_game.router.current_screen.hollow_route.dialogue)
	_check(_node("HollowSetSeal").is_visible_in_tree(), "The lower marker opens a safe checkpoint before the shelf encounter")
	await _click_prop("ShelfProp")
	await _click(_node("HollowFight"))
	if not await _win_and_claim():
		return false
	await _read(_game.router.current_screen.hollow_route.dialogue)
	await _click(_node("RestoreMarker"))
	await _read(_game.router.current_screen.hollow_route.dialogue)
	await _click(_node("InspectWall"))
	await _read(_game.router.current_screen.hollow_route.dialogue)
	await _capture("05_hollow_ledge")
	await _map_visit("MapLioren")
	await _enter_guild()
	await _report_to_guild("ReportHollow")
	_check(_game.session.wallet[GameSession.SILVER] == 80, "Both reports total 80 silver")
	return _game.session.quest_flags.has(GameSession.HOLLOW_REPORTED)

func _outpost() -> bool:
	await _click(_game.router.current_screen.back_button)
	await _map_visit("MapGate")
	await _choose_strength()
	await _map_visit("MapOutpost")
	await _read(_game.router.current_screen.dialogue)
	var world: Control = _game.router.current_screen
	await _click_prop("BowlProp")
	await _click_prop("WatchSign")
	await _capture("06_akari")
	await _read(world.outpost_route.dialogue)
	await _click(_node("OutpostAction"))
	if not await _win_and_claim():
		return false
	world = _game.router.current_screen
	await _read(world.outpost_route.dialogue)
	if DisplayServer.window_get_size() == CHECKPOINT_WINDOW and not await _return_at_outpost(world):
		return false
	await _click(_node("OutpostAction"))
	await _wait_intro(_game.router.current_screen)
	await _capture("07_warden")
	if not await _win_and_claim(true):
		return false
	world = _game.router.current_screen
	await _capture("07b_akari_joint")
	if world.outpost_route.dialogue.is_active():
		while world.outpost_route.dialogue.runner.current_shot() == "outpost_joint":
			await _click(world.outpost_route.dialogue.next_button)
		await _capture("07c_akari_key")
	await _read(world.outpost_route.dialogue)
	await _map_visit("MapLioren")
	await _enter_guild()
	await _report_to_guild("ReportOutpost", false)
	var guild: Control = _game.router.current_screen
	await _capture("08_epilogue_letter")
	await _reload_from_title()
	guild = _game.router.current_screen
	_check(guild.name == "Guild" and guild.dialogue.is_active(), "Continue resumes the epilogue after the paid report")
	for page: int in range(30):
		if not guild.dialogue.is_active() or guild.get_node("EpilogueMap").visible:
			break
		await _click(guild.dialogue.next_button)
	_check(guild.get_node("EpilogueMap").visible, "The epilogue reveals the map")
	await _capture("09_epilogue_map")
	await _read(guild.dialogue)
	return _game.session.quest_flags.has(GameSession.OUTPOST_FINISHED)

func _return_at_outpost(world: Control) -> bool:
	await _click(world.checkpoint_button)
	var seal: Control = _game.router.current_screen
	await _click(seal.start_button)
	for frame: int in range(CheckpointService.CHANNEL_TICKS + 120):
		if _game.session.checkpoints.manual_snapshots.size() == 1:
			break
		await _frames(1)
	var points := _game.session.checkpoints.manual_snapshots
	_check(points.size() == 1, "The Seal records the route immediately before the Warden")
	if points.size() != 1:
		return false
	await _click(seal.back_button)
	await _click(_node("OutpostAction"))
	var combat: Control = _game.router.current_screen
	await _wait_intro(combat)
	await _click(combat.pause_button)
	await _click(combat.forfeit_button)
	await _reload_from_title()
	seal = _game.router.current_screen
	_check(seal.name == "Checkpoint" and _game.session.awaiting_return, "Continue restores the Seal selection after defeat")
	var manual_point: Button = null
	for option: Button in seal.points_list.get_children():
		if not option.text.begins_with("Первый след"):
			manual_point = option
			break
	await _click(manual_point)
	await _capture("06_seal_return")
	await _click(seal.confirm_return)
	var restored: bool = (
		_game.session.location_id == GameSession.LOCATION_OUTPOST
		and _game.session.quest_flags.has(GameSession.OUTPOST_RAVENS_WON)
		and _game.session.wallet[GameSession.SILVER] == 80
		and _game.session.checkpoints.manual_snapshots.is_empty()
		and not _game.session.awaiting_return
		and _game.session.traces == 1
	)
	_check(restored, "Returning spends the Seal, adds one Trace and preserves the completed route")
	return restored

func _choose_strength() -> void:
	if _game.session.hero.pending_upgrade_choices == 0:
		return
	var world: Control = _game.router.current_screen
	await _click(world.upgrade_button)
	var bag: Control = _game.router.current_screen
	while _game.session.hero.pending_upgrade_choices > 0:
		var pending: int = _game.session.hero.pending_upgrade_choices
		await _click(bag.strength_upgrade)
		if _game.session.hero.pending_upgrade_choices >= pending:
			_check(false, "Applying a strength improvement spends one choice")
			break
	await _click(bag.back_button)

func _win_and_claim(reload: bool = false) -> bool:
	var combat: Control = _game.router.current_screen
	if combat.name != "Combat":
		_check(false, "The route starts combat")
		return false
	await _wait_result(combat, 1800)
	if not _game.session.has_pending_battle_result():
		_check(false, "An automatic battle on the main route can be won with earned equipment")
		return false
	if reload:
		var result: Dictionary = _game.session.pending_battle_result.duplicate(true)
		await _reload_from_title()
		combat = _game.router.current_screen
		_check(combat.name == "Combat" and combat.resolver == null and _game.session.pending_battle_result == result, "Continue restores exactly the pending result without replaying the fight")
	await _claim_result(combat)
	return not _game.session.has_pending_battle_result()

func _reload_from_title() -> void:
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)

func _enter_guild() -> void:
	await _map_visit("MapGuild")
	await _read(_game.router.current_screen.dialogue)

func _report_to_guild(action: String, read_follow_up: bool = true) -> void:
	await _click(_node(action))
	var guild: Control = _game.router.current_screen
	await _read(guild.dialogue)
	await _click(guild._report_view.claim_button)
	if read_follow_up:
		await _read(guild.dialogue)

func _read(dialogue: DialogueOverlay) -> void:
	for page: int in range(120):
		if not is_instance_valid(dialogue) or not dialogue.is_active():
			return
		await _click(dialogue.next_button)
	_check(false, "Dialogue ends after a bounded number of pages")

func _node(node_name: String) -> Control:
	return _game.router.current_screen.find_child(node_name, true, false)

func _click(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		_check(false, "Expected control is visible: %s" % (control.name if is_instance_valid(control) else "(missing)"))
		return
	await super._click(control)

func _click_prop(prop_name: String) -> void:
	var prop: Control = _node(prop_name)
	var hotspot: Control = prop.get_child(0) as Control if prop != null else null
	if not is_instance_valid(hotspot) or not hotspot.is_visible_in_tree():
		_check(false, "Scene has a visible touch target for %s" % prop_name)
		return
	var press := InputEventScreenTouch.new()
	press.position = hotspot.get_global_rect().get_center()
	press.pressed = true
	root.push_input(press, true)
	_actions += 1
	await _frames(2)
	var release := InputEventScreenTouch.new()
	release.position = press.position
	root.push_input(release, true)
	await _frames(5)

func _capture(label: String) -> void:
	await _frames(4)
	RenderingServer.force_draw()
	var directory := ProjectSettings.globalize_path(_chapter_out.path_join(_window_label))
	DirAccess.make_dir_recursive_absolute(directory)
	var image: Image = root.get_texture().get_image()
	var captured: bool = image != null and image.save_png(directory.path_join(label + ".png")) == OK
	if captured:
		_report["captures"].append({"window": _window_label, "label": label, "size": [image.get_width(), image.get_height()]})
	_check(captured, "%s capture %s" % [_window_label, label])
