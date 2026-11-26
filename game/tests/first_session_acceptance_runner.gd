extends SceneTree

const OUT := "res://../docs/reviews/first_session_iteration_2026_11_21"
const MERCHANT_OUT := "res://../docs/reviews/merchant_stage_2026_11_22/reaudit"
const GUILD_OUT := "res://.godot/guild_acceptance"
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(360, 800), Vector2i(390, 844), Vector2i(412, 915)]

var _checks: int = 0
var _failed: int = 0
var _actions: int = 0
var _save_path: String = ""
var _mode: String = "flow"
var _game: GameRoot
var _report: Dictionary = {"windows": [], "captures": [], "checks": []}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-path="):
			_save_path = argument.trim_prefix("--save-path=")
		elif argument.begins_with("--acceptance-mode="):
			_mode = argument.trim_prefix("--acceptance-mode=")
	if _save_path.is_empty():
		_save_path = "user://path_of_reborn_tests/first_session_%d.json" % Time.get_ticks_usec()
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(360, 640))
	await _frames(5)
	await _new_game_root()
	match _mode:
		"flow":
			await _flow()
		"continue":
			await _continue_flow()
		"checkpoint":
			await _checkpoint_flow()
		"movie":
			await _movie_flow()
		"active":
			await _active_flow()
		"merchant", "guild":
			await _merchant_flow()
		_:
			_check(false, "Unknown acceptance mode")
	if _mode == "guild":
		_check(_report.get("guild_finished", false), "The guild scenario reached its final check")
	_report["failed"] = _failed
	_report["checks_count"] = _checks
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir() + "/verification"))
	var file := FileAccess.open(_out_dir() + "/verification/" + _mode + "_report.json", FileAccess.WRITE)
	if file == null:
		printerr("FAIL cannot write report for mode %s" % _mode)
		quit(1)
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	print("FIRST_SESSION_ACCEPTANCE mode=%s checks=%d failed=%d" % [_mode, _checks, _failed])
	quit(1 if _failed > 0 else 0)

func _new_game_root() -> void:
	if is_instance_valid(_game):
		root.remove_child(_game)
		_game.free()
		await _frames(3)
	_game = load("res://scenes/game_root.tscn").instantiate()
	_game.save_path = _save_path
	root.add_child(_game)
	current_scene = _game
	await _frames(5)

func _flow() -> void:
	await _capture("01_title")
	var started_tick: int = _game.session.play_tick
	await _click(_game.router.current_screen.begin_button)
	_check(_game.router.current_screen.name == "Prologue", "Begin starts the prologue")
	await _capture("02_tokyo")
	var visited: Dictionary = {}
	var threshold_captured: bool = false
	var hold_captured: bool = false
	for step: int in range(300):
		var screen: Control = _game.router.current_screen
		if screen.name != "Prologue":
			break
		var runner: DialogueRunner = screen.runner
		visited[runner.current_cue().get("id", "")] = true
		if runner.current_shot() == "threshold" and not threshold_captured:
			threshold_captured = true
			await _capture("04_threshold")
		if runner.transition_ticks > 0:
			await _frames(1)
			continue
		match runner.current_kind():
			"look":
				await _drag(Vector2(90, 100), Vector2(30, 0))
			"hold":
				if not hold_captured:
					hold_captured = true
					await _capture("03_crosswalk_hold")
				await _hold(screen.hold_area, runner)
			_:
				await _click(screen.dialogue_panel)
	_check(_game.router.current_screen.name == "World", "First-pass prologue reaches World")
	_check(visited.size() == 15, "First pass visits the authored 15 cues")
	_report["prologue"] = {"actions": _actions - 1, "cues": visited.size(), "seconds_to_world": snappedf((_game.session.play_tick - started_tick) / 60.0, 0.01)}
	await _capture("05_first_trail")
	await _measure_windows("world")
	await _click(_game.router.current_screen.checkpoint_button)
	await _frames(16)
	await _capture("13_checkpoint")
	await _measure_windows("checkpoint")
	await _click(_game.router.current_screen.back_button)
	await _tap_world_progress()
	await _first_slime_dialogue(true)
	_check(_game.router.current_screen.name == "Combat", "Finishing the first dialogue starts the encounter")
	var combat: Control = _game.router.current_screen
	_check(combat.resolver.auto_dodge_enabled and not combat.dodge_button.visible, "Clean profile keeps full auto as the default")
	await _wait_intro(combat)
	await _capture("06_slime")
	_check(not combat.format_label.get_global_rect().intersects(combat.pause_button.get_global_rect()), "Mode HUD and Pause do not intersect at 360x640")
	await _wait_result(combat)
	await _dismiss_tutorial(combat)
	await _capture("07_first_loot")
	_check(_game.session.inventory.items.size() == 1 and not _has_item("echo_crystal") and _game.session.has_pending_battle_result(), "Victory waits for claim without granting the crystal")
	var result_id: String = String(_game.session.pending_battle_result.get("result_id", ""))
	await _frames(240)
	_check(combat.result_panel.visible and _game.session.has_pending_battle_result(), "Result remains open after four seconds")
	await _claim_result(combat)
	_check(_game.router.current_screen.name == "World" and not _game.session.has_pending_battle_result(), "One atomic claim returns to World")
	var claimed: Dictionary = _game.session.last_settlement.duplicate(true)
	_check(String(claimed.get("result_id", "")) == result_id, "Claim settles the displayed result")
	_check(not _has_item("training_sword"), "First route clear grants crystals, not the story sword")
	await _capture("08_trail_after_loot")
	_check(_game.router.current_screen.upgrade_button.visible, "World exposes the pending upgrade")
	await _click(_game.router.current_screen.upgrade_button)
	await _capture("09_bag")
	var inventory: Control = _game.router.current_screen
	_check(root.gui_get_focus_owner() == inventory.strength_upgrade, "First upgrade receives focus")
	_report["first_upgrade"] = {"actions": _actions, "seconds_from_new_game": snappedf((_game.session.play_tick - started_tick) / 60.0, 0.01), "strength_before": _game.session.hero.strength, "hp_before": _game.session.hero.max_hp}
	await _click(inventory.strength_upgrade)
	_check(_game.session.hero.strength == 4 and _game.session.hero.pending_upgrade_choices == 0, "Strength choice applies once and updates immediately")
	_report["first_upgrade"]["strength_after"] = _game.session.hero.strength
	await _measure_windows("inventory")
	await _click(inventory.back_button)
	await _click(_game.router.current_screen.inventory_button)
	_check(_game.router.current_screen.name == "Inventory", "The backpack displays the new equipment illustrations")
	await _frames(90)
	await _measure_windows("backpack")
	await _click(_game.router.current_screen.back_button)
	await _second_slime_and_lookout(true)
	await _advance_merchant_to_combat()
	combat = _game.router.current_screen
	_check(combat.name == "Combat" and not _has_item("training_sword"), "Daijiro's introduction starts the story fight without an early sword")
	await _wait_result(combat)
	await _capture("10_goblin_loot")
	await _claim_result(combat)
	_check(_game.router.current_screen.name == "Merchant" and not _has_item("training_sword"), "The story win returns to Daijiro before granting the sword")
	await _advance_merchant_to_gift()
	var merchant: Control = _game.router.current_screen
	_check(merchant.gift_layer.visible and not _has_item("training_sword"), "Gratitude opens the separate gift card before its claim")
	await _click(merchant.equip_button)
	_check(_game.router.current_screen.name == "World" and _has_item("training_sword"), "Daijiro grants exactly one sword after the completed introduction")
	await _dismiss_tutorial(_game.router.current_screen)
	await _capture("11_end_of_trail")
	_check("К испытанию" in _game.router.current_screen.main_action_button.text, "Scout completion promotes the trial")
	await _click(_game.router.current_screen.repeats_button)
	await _capture("12_encounter_sheet")
	_check(_game.router.current_screen.sheet_rows.get_child_count() >= 3, "Repeats remain available as secondary access")
	await _click(_game.router.current_screen.sheet_close)
	await _tap_world_progress()
	_check(_game.session.current_enemy_id == GameSession.TRIAL_ENEMY_ID and _game.router.current_screen.name == "Combat", "A free-area tap directly starts the trial")
	_report["final_actions"] = _actions

func _continue_flow() -> void:
	await _click(_game.router.current_screen.begin_button)
	for step: int in range(40):
		var screen: Control = _game.router.current_screen
		if screen.runner.index > 0:
			break
		await _click(screen.dialogue_panel)
		await _frames(12)
	var seen: Array = _game.session.seen_cue_ids.keys()
	_check(not seen.is_empty(), "Continue fixture completes at least one cue")
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	var restored: Control = _game.router.current_screen
	_check(restored.name == "Prologue", "Continue returns to unfinished prologue")
	_check(not seen.has(restored.runner.current_cue().get("id", "")), "Continue starts at the first unseen cue")
	await _click(restored.skip_button)
	_check(_game.router.current_screen.name == "World" and _game.session.world_flags.get("prologue_skipped", false), "Skip still reaches World and records its outcome")
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	_check(_game.router.current_screen.name == "World", "Continue after completion returns to World")

func _checkpoint_flow() -> void:
	await _click(_game.router.current_screen.begin_button)
	await _click(_game.router.current_screen.skip_button)
	await _click(_game.router.current_screen.checkpoint_button)
	var blocker: String = ProjectSettings.globalize_path(_save_path + ".tmp")
	_check(DirAccess.make_dir_recursive_absolute(blocker) == OK, "Creation failure blocker is ready")
	await _click(_game.router.current_screen.start_button)
	for step: int in range(420):
		if _game.router.current_screen.error_box.visible:
			break
		await _frames(1)
	var screen: Control = _game.router.current_screen
	_check(screen.error_box.visible and screen._commit_in_flight == false, "Creation failure exposes retry")
	await _capture("14_checkpoint_failed")
	await _click(screen.back_button)
	DirAccess.remove_absolute(blocker)
	await _click(_game.router.current_screen.checkpoint_button)
	for step: int in range(30):
		if _game.session.checkpoints.manual_snapshots.size() == 1:
			break
		await _frames(1)
	screen = _game.router.current_screen
	_check(_game.session.checkpoints.manual_snapshots.size() == 1 and not screen._commit_in_flight, "Reopening commits exactly one pending point")
	_check(_disk_points() == 1, "Reopened creation reaches the disk once")
	await _capture("15_checkpoint_reopened")
	_check(DirAccess.make_dir_recursive_absolute(blocker) == OK, "Deletion failure blocker is ready")
	var row: HBoxContainer = screen.points_list.get_child(0)
	await _click(row.get_child(row.get_child_count() - 1))
	var dialog: ConfirmDialog = null
	for child: Node in screen.get_children():
		if child is ConfirmDialog:
			dialog = child
	_check(dialog != null, "Delete opens the real confirmation dialog")
	if dialog != null:
		await _click(dialog._confirm)
	_check(screen.error_box.visible and _game.session.checkpoints.manual_snapshots.size() == 1, "Failed deletion preserves the point")
	_check(root.gui_get_focus_owner() == screen.error_retry, "Delete failure focuses Retry after modal closes")
	_check(_disk_points() == 1, "Failed deletion preserves the disk point")
	DirAccess.remove_absolute(blocker)
	await _click(screen.error_retry)
	_check(_game.session.checkpoints.manual_snapshots.is_empty() and _disk_points() == 0, "Delete retry removes the point once")
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	_check(int(disk.get("schema_version", 0)) == SaveService.CURRENT_VERSION, "Checkpoint flow preserves the current save schema")

func _active_flow() -> void:
	await _click(_game.router.current_screen.begin_button)
	await _click(_game.router.current_screen.skip_button)
	await _frames(30)
	await _tap_world_progress()
	await _first_slime_dialogue()
	var combat: Control = _game.router.current_screen
	_check(combat.name == "Combat", "Active fixture enters its first combat")
	if combat.name != "Combat":
		return
	await _wait_intro(combat)
	await _click(combat.pause_button)
	_check(combat.format_switch.text.begins_with("Включить ручной бой"), "Pause names the next-click action")
	await _click(combat.format_switch)
	_check(combat.resolver.combat_format == GameSession.COMBAT_FORMAT_AUTO and _game.session.combat_format == GameSession.COMBAT_FORMAT_ACTIVE, "Pause changes only the next-battle preference")
	await _click(combat.resume_button)
	await _wait_result(combat)
	await _claim_result(combat)
	await _tap_world_progress()
	combat = _game.router.current_screen
	await _wait_intro(combat)
	_check(combat.attack_button.visible and combat.dodge_button.visible and combat.format_label.text == "Ручной", "Next encounter enables intentional manual attack and dodge")
	await _click(combat.attack_button)
	_check(combat.resolver.hero_attack_cooldown > 0, "The touch attack button drives the real resolver")
	_check(not combat.format_label.get_global_rect().intersects(combat.pause_button.get_global_rect()), "Active mode HUD does not overlap Pause")
	await _capture("17_active_next")

func _movie_flow() -> void:
	await _click(_game.router.current_screen.begin_button)
	await _click(_game.router.current_screen.skip_button)
	await _frames(90)
	await _tap_world_progress()
	await _first_slime_dialogue()
	var combat: Control = _game.router.current_screen
	await _wait_result(combat, 1200)
	await _frames(90)
	await _claim_result(combat)
	await _frames(90)
	_check(_game.router.current_screen.name == "World", "Movie route completes a normal-speed encounter")

## Штатный путь этапа «Дайдзиро и первая торговля»: первая слизь → кристалл →
## «В Лиорен» → ворота → оценка → продажа ×1 → покупка куртки → Сумка →
## повторный вход в лавку. Суммы учебного примера: 20 мед. → 12 мед. → 8 мед.
func _merchant_flow() -> void:
	await _click(_game.router.current_screen.begin_button)
	await _click(_game.router.current_screen.skip_button)
	await _frames(30)
	# Узел 1: первая слизь, гарантированный кристалл для будущей продажи.
	await _tap_world_progress()
	await _first_slime_dialogue()
	var combat: Control = _game.router.current_screen
	_check(combat.name == "Combat", "Merchant fixture enters its first combat")
	await _wait_intro(combat)
	await _wait_result(combat)
	_check(combat.result_panel.summary_button.visible and not combat.result_panel.card.visible, "Victory first shows HP and Echo with an OK button")
	await _click(combat.result_panel.summary_button)
	_check(combat.get_node_or_null("ConfirmDialog") != null, "The first item opens the gesture tutorial")
	await _capture("17_loot_tutorial")
	await _press_android_back()
	_check(_game.router.current_screen == combat and combat.get_node_or_null("ConfirmDialog") == null and _game.session.has_pending_battle_result(), "Android Back dismisses only the loot tutorial")
	await _click(combat.result_panel.detail_button)
	_check(combat.details_layer.visible and _game.session.has_pending_battle_result(), "The top-right information button opens details without claiming loot")
	await _click(combat.detail_close)
	await _measure_windows("loot")
	await _capture("18_loot_card")
	await _claim_result(combat)
	_check(_game.router.current_screen.name == "World" and _game.session.inventory.filter("echo").size() >= 1, "First slime grants an echo crystal for the future sale")
	# Вторая слизь, затем встреча у телеги, бой с разведчиком и подарок меча.
	await _second_slime_and_lookout()
	_check(_game.router.current_screen.name == "Merchant", "Daijiro lookout leads to the stone-throw scene before the scout")
	await _measure_windows("cart")
	await _capture("19_cart_dialogue")
	await _advance_merchant_to_combat()
	combat = _game.router.current_screen
	await _wait_result(combat)
	await _claim_result(combat)
	_check(_game.router.current_screen.name == "Merchant", "The story win returns to Daijiro before granting the sword")
	var aftermath: Control = _game.router.current_screen
	_check(aftermath._daijiro != null and aftermath._cart != null, "Daijiro and the cart have a separate post-battle composition")
	await _capture("19c_cart_aftermath")
	await _advance_merchant_to_gift()
	var merchant: Control = _game.router.current_screen
	_check(merchant.gift_layer.visible and not _has_item("training_sword"), "Gratitude opens the gift card before its claim")
	await _click(merchant.store_button)
	_check(_game.router.current_screen.name == "World" and _has_item("training_sword"), "Daijiro grants exactly one sword after the completed introduction")
	_check(_game.session.inventory.filter("weapon").size() == 2, "The old branch stays in the backpack beside the single new sword")
	# «В Лиорен»: сцена ворот открывает лавку.
	var world: Control = _game.router.current_screen
	_check(world.travel_button.visible, "Travel action appears after the gift")
	_check(world.get_node_or_null("ConfirmDialog") != null, "Trail instructions open as a dismissible tutorial")
	await _dismiss_tutorial(world)
	await _capture("19b_trail")
	await _click(world.travel_button)
	await _frames(5)
	_check(_game.session.location_id == "lioren", "Travel applies the Lioren location")
	world = _game.router.current_screen
	_check(world.gates_dialogue.is_active(), "First arrival opens the gates scene")
	await _measure_windows("gates")
	await _capture("20_gates")
	await _click(world.gates_dialogue.next_button)
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	world = _game.router.current_screen
	_check(world.gates_dialogue.is_active() and world.gates_dialogue.runner.current_cue().get("id") != "DIA_CITY_001", "Continue resumes the gates with the first unread line")
	for step: int in range(30):
		world = _game.router.current_screen
		if world.name != "World" or not world.gates_dialogue.is_active():
			break
		await _click(world.gates_dialogue.next_button)
	_check(_game.router.current_screen.name == "Shop" and _game.session.shop_access_unlocked(), "Gates finish opens the shop")
	# Первый визит: оценка с итоговым действием «Оценить кристалл».
	var shop: Control = _game.router.current_screen
	_check(shop.dialogue.is_active(), "First shop entry starts the appraisal")
	await _measure_windows("appraisal")
	await _capture("21_shop_intro")
	await _click_through_dialogue()
	shop = _game.router.current_screen
	_check(shop.name == "Shop" and not shop.dialogue.is_active(), "Appraisal completes back in the catalog")
	if _mode == "guild":
		_check(not _game.session.can_visit_guild(), "The guild stays closed before the recommendation")
	_check(bool(_game.session.world_flags.get(GameSession.WORLD_FLAG_SHOP_INTRO_DONE, false)), "Appraisal records its story flag")
	_check(shop.get_node_or_null("ConfirmDialog") != null, "The sale tutorial opens in a separate modal")
	await _press_android_back()
	_check(_game.router.current_screen == shop and shop.get_node_or_null("ConfirmDialog") == null and _game.session.seen_cue_ids.has("tutorial_shop_sale"), "Android Back dismisses and remembers the sale tutorial without leaving the shop")
	await _capture("22_shop_appraisal")
	await _click(shop.buy_tab)
	await _click(shop.rows_box.get_child(0))
	_check(shop.deal_confirm.disabled and "Не хватает" in shop.deal_reason.text, "An unaffordable purchase explains the missing balance")
	await _press_back()
	_check(not shop.deal_layer.visible and root.gui_get_focus_owner() == shop.rows_box.get_child(0), "Back closes only the deal and restores the row focus")
	await _click(shop.sell_tab)
	# Первая продажа: одна строка, карточка, «20 мед.».
	var sell_row: Button = shop.rows_box.get_child(0)
	await _click(sell_row)
	_check(shop.deal_layer.visible, "Sell row opens the deal card")
	_check("20 мед." in shop.deal_summary.text, "Deal card shows the live crystal revenue in copper")
	await _measure_windows("deal")
	await _capture("23_deal_sell")
	var blocker: String = ProjectSettings.globalize_path(_save_path + ".tmp")
	_check(DirAccess.make_dir_recursive_absolute(blocker) == OK, "The isolated profile blocks the next write")
	var quantity_before: int = _game.session.inventory.get_item(shop._deal["instance_id"]).quantity
	await _click(shop.deal_confirm)
	_check(_game.session.wallet[GameSession.COPPER] == 0 and shop.deal_layer.visible and not shop.deal_confirm.disabled, "Write failure keeps the sale card open and leaves the wallet unchanged")
	_check(_game.session.inventory.get_item(shop._deal["instance_id"]).quantity == quantity_before, "Failed sale leaves the original stack intact")
	DirAccess.remove_absolute(blocker)
	await _click(shop.deal_confirm)
	_check(_game.session.wallet[GameSession.COPPER] == 20, "Selling one crystal credits 20 copper")
	_check(bool(_game.session.world_flags.get(GameSession.WORLD_FLAG_SHOP_FIRST_SALE_DONE, false)), "The first sale records its milestone")
	_check(shop.get_node_or_null("ConfirmDialog") != null, "The first sale opens the purchase tutorial once")
	await _dismiss_tutorial(shop)
	# Первая покупка: куртка за 12 мед., остаток 8 мед.
	shop = _game.router.current_screen
	await _click(shop.buy_tab)
	await _click(shop.rows_box.get_child(0))
	_check("12 мед." in shop.deal_summary.text and "8 мед." in shop.deal_summary.text, "Jacket card shows the cost and the resulting balance")
	await _measure_windows("purchase")
	await _capture("24_deal_buy")
	await _click(shop.deal_confirm)
	_check(_game.session.wallet[GameSession.COPPER] == 8, "Jacket purchase leaves 8 copper")
	_check(_game.session.inventory.items.any(func(item: ItemInstance) -> bool: return item.definition_id == "wanderer_jacket"), "Bought jacket lands in the inventory")
	shop = _game.router.current_screen
	_check(shop.dialogue.is_active(), "First purchase opens the guild briefing")
	if _mode == "guild":
		_check(not _game.session.can_visit_guild(), "Buying the jacket alone does not finish the guild briefing")
	await _capture("24b_shop_purchase_dialogue")
	for step: int in range(12):
		if not shop.dialogue.is_active() or shop.dialogue.runner.current_cue().get("id") != "DIA_SHOP_P01":
			break
		await _click(shop.dialogue.next_button)
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	shop = _game.router.current_screen
	_check(shop.dialogue.is_active() and shop.dialogue.runner.current_cue().get("id") != "DIA_SHOP_P01", "Continue resumes the guild briefing without replaying read lines")
	await _click_through_dialogue()
	shop = _game.router.current_screen
	if _mode == "guild":
		await _click(shop.back_button)
		await _new_game_root()
		await _click(_game.router.current_screen.continue_button)
		await _guild_flow()
		return
	_check(shop.bag_button.visible, "Briefing offers the bag shortcut for the jacket")
	await _click(shop.bag_button)
	var bag: Control = _game.router.current_screen
	_check(bag.name == "Inventory" and bag.details_layer.visible, "Bag opens with the jacket card")
	await _capture("25_bag_jacket")
	await _click(bag.equip_action)
	_check(_game.session.hero.defense == 3, "Jacket equips from the bag and adds one defense")
	await _measure_windows("inventory")
	# Повторный вход: приветствие и торговля сразу. Back сначала закрывает
	# карточку предмета — повторяем штатный путь ввода.
	await _click(bag.detail_close)
	await _click(bag.back_button)
	var city: Control = _game.router.current_screen
	_check(city.name == "World" and _game.session.location_id == "lioren", "Bag returns to the Lioren city mode")
	_check(not city.main_action_button.visible, "The city keeps the hidden combat action")
	await _tap_world_progress()
	_check(_game.router.current_screen == city, "A background tap in Lioren does not start combat")
	await _measure_windows("city")
	await _click(city.shop_button)
	shop = _game.router.current_screen
	_check(shop.name == "Shop" and "Снова ты" in shop.status_label.text, "Repeat entry greets with one line and trade is open")
	_check(shop.talk_button.visible, "Optional conversation is available after the introduction")
	_check(shop.get_node_or_null("ConfirmDialog") == null and _game.session.seen_cue_ids.has("tutorial_shop_sale") and _game.session.seen_cue_ids.has("tutorial_shop_purchase"), "Dismissed shop tutorials stay closed across visits and profile reload")
	await _measure_windows("shop")
	await _capture("26_shop_welcome")
	await _click(shop.talk_button)
	_check(shop.dialogue.is_active(), "Optional talk opens on explicit interaction")
	await _press_android_back()
	_check(not shop.dialogue.is_active() and root.gui_get_focus_owner() == shop.talk_button, "Android Back dismisses only the optional talk and restores its focus")
	await _click(shop.talk_button)
	await _click_through_dialogue()
	_check(not shop.talk_button.visible, "The completed optional conversation leaves no inactive action")
	await _verify_merchant_edge_profiles()
	await _verify_shop_exchange()

func _guild_flow() -> void:
	var city: Control = _game.router.current_screen
	_check(city.name == "World" and city.guild_button.visible and city.shop_button.visible and city.travel_button.visible, "The finished briefing opens the guild beside the usual city actions")
	_check(not city.equipment_strip.visible and city.inventory_button.visible, "Lioren hides the equipment strip and keeps the bag shortcut")
	await _click(city.inventory_button)
	_check(_game.router.current_screen.name == "Inventory", "The bag shortcut still opens inventory from Lioren")
	await _press_back()
	city = _game.router.current_screen
	_check(not _game.session.inventory.equipment_for().has("armor"), "Guild entry does not require wearing the jacket")
	await _measure_windows("guild_city")
	await _click(city.checkpoint_button)
	var seal: Control = _game.router.current_screen
	await _click(seal.start_button)
	for step: int in range(420):
		if not _game.session.checkpoints.manual_snapshots.is_empty():
			break
		await _frames(1)
	var points := _game.session.checkpoints.manual_snapshots
	_check(points.size() == 1, "The city checkpoint precedes registration")
	if points.is_empty():
		return
	var checkpoint_id: String = points[0]["checkpoint_id"]
	await _click(seal.back_button)

	await _click(_game.router.current_screen.guild_button)
	var guild: Control = _game.router.current_screen
	_check(guild.name == "Guild" and guild.dialogue.is_active(), "The normal city button opens the registration dialogue")
	if guild.name != "Guild" or not guild.dialogue.is_active():
		return
	_check(guild.dialogue.runner.current_cue()["id"] == "DIA_GUILD_001" and not guild.get_node("SafeArea").visible, "The first unread line hides the desk controls")
	_check(_game.session.guild_rank().is_empty() and not _game.session.register_with_guild(), "Rank cannot be granted before reading the introduction")
	for step: int in range(12):
		if guild.dialogue.runner.current_cue()["id"] == "DIA_GUILD_002":
			break
		await _click(guild.dialogue.next_button)
	_check(guild.get_node("Kenta").visible, "The hall plan shows Kenta when he speaks")
	await _measure_windows("guild_opening")
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	guild = _game.router.current_screen
	_check(guild.name == "Guild" and guild.dialogue.runner.current_cue()["id"] == "DIA_GUILD_002", "Continue resumes the first unread registration cue")
	await _press_android_back()
	city = _game.router.current_screen
	_check(city.name == "World" and root.gui_get_focus_owner() == city.guild_button, "Android Back returns to the city and restores the guild button focus")
	_check(GameRoot.route_for_continue(_game.session) == "world", "Leaving explicitly clears the active guild visit")
	await _click(city.guild_button)
	guild = _game.router.current_screen
	_check(guild.dialogue.runner.current_cue()["id"] == "DIA_GUILD_002", "Opening the guild again preserves progress")
	for step: int in range(32):
		if guild.dialogue.runner.current_cue()["id"] == "DIA_GUILD_014":
			break
		await _click(guild.dialogue.next_button)
	_check(guild.dialogue.runner.current_shot() == "guild_registration" and not guild.get_node("Midori").visible, "The seal check uses the painted close-up without doubling the registrar")
	await _measure_windows("guild_register_dialogue")
	for step: int in range(40):
		if guild.dialogue.runner.current_cue()["id"] == "DIA_GUILD_027":
			break
		await _click(guild.dialogue.next_button)
	_check(guild.get_node("Goro").visible, "Goro appears in the hall when he gives his advice")
	await _measure_windows("guild_mentor")
	for step: int in range(100):
		if not guild.dialogue.is_active():
			break
		await _click(guild.dialogue.next_button)
	_check(not guild.dialogue.is_active() and guild.register_button.visible and _game.session.guild_rank().is_empty(), "Reading all lines opens the explicit registration action")
	await _measure_windows("guild_desk")
	var blocker: String = ProjectSettings.globalize_path(_save_path + ".tmp")
	_check(DirAccess.make_dir_recursive_absolute(blocker) == OK, "The fixture blocks the registration write")
	var wallet := _game.session.wallet.duplicate()
	await _click(guild.register_button)
	_check(guild.get_node("%Error").visible and root.gui_get_focus_owner() == guild.register_button, "Write failure keeps registration actionable and focused")
	_check(_game.session.guild_rank().is_empty() and not _game.session.quest_flags.has(GameSession.FIRST_GUILD_ORDER_ID), "Failed registration applies neither rank nor order")
	var saved := GameSession.new()
	_check(_game.save_service.load_into(saved, _save_path) and saved.guild_rank().is_empty(), "The last saved profile still has no rank")
	DirAccess.remove_absolute(blocker)
	await _click(guild.register_button)
	_check(_game.session.guild_rank() == "E" and _game.session.quest_flags.get(GameSession.FIRST_GUILD_ORDER_ID, false), "Retry grants rank E and the first order together")
	_check(_game.session.wallet == wallet and not guild.register_button.visible, "Registration is free and removes the spent action")
	_check(not _game.session.register_with_guild(), "Duplicate registration is rejected by the session")
	await _measure_windows("guild_order")
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	guild = _game.router.current_screen
	_check(guild.name == "Guild" and not guild.dialogue.is_active() and not guild.register_button.visible and _game.session.guild_rank() == "E", "Continue restores the registered desk and skips the one-time talk")
	await _click(guild.back_button)
	city = _game.router.current_screen
	_check(city.name == "World" and root.gui_get_focus_owner() == city.guild_button, "The desk back button restores the city action")
	await _click(city.guild_button)
	_check(not _game.router.current_screen.dialogue.is_active(), "A return visit opens the desk directly")
	await _press_back()
	_game.session.awaiting_return = true
	_check(_game._commit_checkpoint_restore(checkpoint_id), "The root restores the isolated city checkpoint")
	_check(_game.session.guild_rank().is_empty() and not _game.session.quest_flags.has(GameSession.FIRST_GUILD_ORDER_ID), "Checkpoint rolls back the rank and order together")
	await _click(_game.router.current_screen.guild_button)
	guild = _game.router.current_screen
	_check(not guild.dialogue.is_active() and guild.register_button.visible, "After rollback the remembered dialogue still leads to registration")
	await _click(guild.register_button)
	_check(_game.session.guild_rank() == "E" and _game.session.quest_flags.get(GameSession.FIRST_GUILD_ORDER_ID, false), "The restored timeline can register again")
	await _verify_forced_city_profile()
	_report["guild_finished"] = true

func _verify_shop_exchange() -> void:
	var shop: Control = _game.router.current_screen
	var copper: String = GameSession.COPPER
	var silver: String = GameSession.SILVER
	var gold: String = GameSession.GOLD
	await _click(shop.exchange_tab)
	var first_rate: Button = shop.rows_box.get_child(0)
	await _click(first_rate)
	_check(shop.deal_confirm.disabled and "Не хватает 73 мед." in shop.deal_reason.text, "Exchange explains exactly how much copper is missing")
	await _press_android_back()
	_check(not shop.deal_layer.visible and root.gui_get_focus_owner() == first_rate, "Back cancels an exchange and restores its row focus")
	_game.session.wallet[copper] = 128
	_game.session.wallet[silver] = 99
	_check(_game.save_service.save(_game.session, _save_path), "The isolated exchange wallet is saved")
	await _click(shop.back_button)
	await _click(_game.router.current_screen.shop_button)
	shop = _game.router.current_screen
	await _click(shop.exchange_tab)
	var rates: Array[String] = ["100 мед. → 1 сер.", "100 сер. → 1 зол.", "1 зол. → 100 сер.", "1 сер. → 100 мед."]
	var row_indices: Array[int] = [0, 2, 3, 1]
	var expected: Array[Dictionary] = [
		{copper: 28, silver: 100, gold: 0}, {copper: 28, silver: 0, gold: 1},
		{copper: 28, silver: 100, gold: 0}, {copper: 128, silver: 99, gold: 0},
	]
	for index: int in range(WINDOW_SIZES.size()):
		var window_size: Vector2i = WINDOW_SIZES[index]
		DisplayServer.window_set_size(window_size)
		await _frames(8)
		var row: Button = shop.rows_box.get_child(row_indices[index])
		row.grab_focus()
		await _frames(3)
		_check(shop._catalog_scroll.get_global_rect().encloses(row.get_global_rect()), "Exchange reveals a focused rate at %s" % window_size)
		await _click(row)
		_check(DisplayServer.window_get_size() == window_size and shop.deal_layer.visible and _out_of_window_control(shop).is_empty(), "Exchange card fits the real %s window" % window_size)
		_check(rates[index] in shop.deal_summary.text and "После обмена" in shop.deal_summary.text, "The card shows the rate and both resulting balances")
		if index == 0:
			var blocker: String = ProjectSettings.globalize_path(_save_path + ".tmp")
			_check(DirAccess.make_dir_recursive_absolute(blocker) == OK, "Exchange fixture blocks its next write")
			await _click(shop.deal_confirm)
			_check(shop.deal_layer.visible and not shop.deal_confirm.disabled and "сохранить" in shop.deal_reason.text, "Exchange retains an actionable confirmation after a write failure")
			_check(_game.session.wallet == {copper: 128, silver: 99, gold: 0}, "Failed exchange keeps both balances")
			DirAccess.remove_absolute(blocker)
		await _capture("exchange_deal_%dx%d" % [window_size.x, window_size.y])
		await _click(shop.deal_confirm)
		_check(not shop.deal_layer.visible and _game.session.wallet == expected[index], "Each exchange changes only the selected coin balances")
		for coin: String in GameSession.COIN_TYPES:
			var amount: Label = shop.wallet_labels[coin]
			var icon: TextureRect = amount.get_parent().get_child(0)
			_check(amount.accessibility_name == UiText.astra(expected[index][coin], coin) and icon.texture == UiIcons.astra(coin), "The shop shows the exact balance and icon for %s" % coin)
		_check(root.gui_get_focus_owner() == shop.rows_box.get_child(row_indices[index]), "Exchange returns focus to the selected rate")
		await _capture("exchange_catalog_%dx%d" % [window_size.x, window_size.y])
	var restored := GameSession.new()
	_check(_game.save_service.load_into(restored, _save_path) and restored.wallet == expected.back(), "Reload restores the three coin balances after exchange")

func _verify_forced_city_profile() -> void:
	var forced := GameSession.new()
	forced.world_flags["prologue_completed"] = true
	forced.mark_path_started()
	forced.location_id = GameSession.LOCATION_LIOREN
	forced.traces = 3
	forced.hero.set_void_traces(3)
	_check(_game.save_service.save(forced, _save_path), "Forced Lioren fixture is saved in isolation")
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	var city: Control = _game.router.current_screen
	_check(city.name == "World" and city.rest_button.visible and not city.shop_button.visible and not city.guild_button.visible and not city.gates_dialogue.is_active(), "Forced Lioren offers rest before meeting Daijiro")
	await _click(city.rest_button)
	await _click(city.travel_button)
	_check(_game.session.location_id == GameSession.LOCATION_FOREST_EDGE and _game.session.traces == 0, "Rest opens the route back to the Trail")
	_check(_game.router.current_screen.equipment_strip.visible, "The Trail restores the equipment strip after leaving Lioren")

func _verify_merchant_edge_profiles() -> void:
	await _verify_forced_city_profile()
	var legacy := GameSession.new()
	legacy.world_flags["prologue_completed"] = true
	legacy.mark_path_started()
	legacy.inventory.add(legacy.get_item_definition("training_sword"), 1)
	legacy.story_rewards[GameSession.DAIJIRO_SWORD_REWARD_ID] = true
	legacy.wallet[GameSession.COPPER] = 12
	_check(_game.save_service.save(legacy, _save_path), "Historically funded profile with a sword and no crystals saves")
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	var trail: Control = _game.router.current_screen
	_check(trail.name == "World" and trail.travel_button.visible and not trail.gates_dialogue.is_active(), "Continue opens travel for older owners of the sword")
	await _click(trail.travel_button)
	for step: int in range(30):
		if _game.router.current_screen != trail or not trail.gates_dialogue.is_active():
			break
		await _click(trail.gates_dialogue.next_button)
	var shop: Control = _game.router.current_screen
	_check(shop.name == "Shop" and shop.dialogue.runner.current_cue().get("text", "").begins_with("Кристаллы Эха можно продать"), "Appraisal with no crystal gives the right dialogue")
	if shop.name != "Shop":
		return
	await _click_through_dialogue()
	_check(shop.get_node_or_null("ConfirmDialog") == null and shop.rows_box.get_child(0) is Label, "Empty Sell shows the route to loot without a blocked tutorial")
	await _click(shop.buy_tab)
	await _click(shop.rows_box.get_child(0))
	_check(not shop.deal_confirm.disabled and "12 мед." in shop.deal_summary.text, "The funded player can buy without selling first")
	await _press_back()
	await _press_back()
	_check(_game.router.current_screen.name == "World" and _game.session.wallet[GameSession.COPPER] == 12, "Esc leaves an unconfirmed purchase and returns to the city")
	var crystal: ItemDefinition = _game.session.get_item_definition("echo_crystal")
	_game.session.inventory.add(crystal, 1)
	var second_stack: ItemInstance = _game.session.inventory.add(crystal, 2, "", {"sale_price_copper": 15})[0]
	var second_stack_id: String = second_stack.instance_id
	var city: Control = _game.router.current_screen
	await _click(city.shop_button)
	shop = _game.router.current_screen
	await _dismiss_tutorial(shop)
	await _click(shop.rows_box.get_child(1))
	await _click(shop.deal_confirm)
	await _dismiss_tutorial(shop)
	_check(_game.session.inventory.get_item(second_stack_id).quantity == 1 and _game.session.wallet[GameSession.COPPER] == 27, "Partial sale keeps the rest of the second stack at its own price")
	_check(root.gui_get_focus_owner() == shop.rows_box.get_child(1), "Partial sale restores focus to the second row after rebuilding the list")

func _dismiss_tutorial(screen: Control) -> void:
	var dialog: ConfirmDialog = screen.get_node_or_null("ConfirmDialog")
	if dialog != null:
		await _click(dialog._confirm)

func _press_back() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_ESCAPE
	press.pressed = true
	root.push_input(press, true)
	var release := InputEventKey.new()
	release.keycode = KEY_ESCAPE
	root.push_input(release, true)
	await _frames(3)

func _press_android_back() -> void:
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(3)


func _click_through_dialogue() -> void:
	for step: int in range(40):
		var screen: Control = _game.router.current_screen
		if screen.name != "Shop" or screen.dialogue == null or not screen.dialogue.is_active():
			return
		await _click(screen.dialogue.next_button)


func _tap_world_progress() -> void:
	var screen: Control = _game.router.current_screen
	var point: Vector2 = Vector2(screen.size.x * 0.5, screen.size.y * 0.42)
	await _tap(point)

func _first_slime_dialogue(capture: bool = false) -> void:
	var screen: Control = _game.router.current_screen
	_check(screen.name == "TrailDialogue" and not _game.session.in_combat, "First trail tap opens dialogue before starting combat")
	if screen.name != "TrailDialogue":
		return
	if capture:
		await _measure_windows("slime_approach")
	for step: int in range(8):
		if _game.router.current_screen != screen:
			break
		if capture and screen.dialogue.runner.current_shot() == "slime_leaps":
			for frame: int in range(60):
				if screen._leap_progress >= 0.4:
					break
				await _frames(1)
			_check(screen.slime.position.y < SceneStaging.floor_y(screen.size.y) - 8, "The slime jumps toward Haruto while the second line is visible")
			await _capture("05b_slime_leap")
		await _click(screen.dialogue.next_button)

func _second_slime_and_lookout(capture: bool = false) -> void:
	await _tap_world_progress()
	var combat: Control = _game.router.current_screen
	_check(combat.name == "Combat" and _game.session.active_encounter_context.get("route_node_id") == "forest_edge_cart_slime", "Second trail tap starts a distinct slime encounter")
	if combat.name != "Combat":
		return
	await _wait_result(combat)
	_check(not _game.session.pending_battle_result.get("echo_gained", true), "Second slime does not award the first-species Echo again")
	await _claim_result(combat)
	var lookout: Control = _game.router.current_screen
	_check(lookout.name == "TrailDialogue" and not _game.session.world_flags.get("daijiro_intervened", false), "The second slime leads to the separate lookout before Haruto throws")
	if lookout.name != "TrailDialogue":
		return
	if capture:
		await _measure_windows("cart_lookout")
		await _click(lookout.dialogue.next_button)
		await _new_game_root()
		await _click(_game.router.current_screen.continue_button)
		lookout = _game.router.current_screen
		_check(lookout.name == "TrailDialogue" and lookout.dialogue.runner.current_cue().get("id") == "DIA_TRAIL_CART_002", "Continue restores the unread lookout line after the second battle")
		if lookout.name != "TrailDialogue":
			return
	for step: int in range(8):
		if _game.router.current_screen != lookout:
			break
		await _click(lookout.dialogue.next_button)


func _tap(point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	root.push_input(press, true)
	_actions += 1
	await _frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.pressed = false
	root.push_input(release, true)
	await _frames(5)


func _claim_result(screen: Control) -> void:
	if screen.result_panel.summary_button.is_visible_in_tree():
		await _click(screen.result_panel.summary_button)
	await _dismiss_tutorial(screen)
	var items: Array = _game.session.pending_battle_result.get("items", [])
	for _item: Dictionary in items:
		if not screen.result_panel.card.is_visible_in_tree():
			break
		await _click(screen.result_panel.card)
	_check(screen.result_panel.can_claim() and _game.session.has_pending_battle_result(), "The last reward leads to the level card before the atomic claim")
	if screen.result_panel.can_claim():
		await _click(screen.result_panel.claim_button)
	_check(not _game.session.has_pending_battle_result(), "Confirming the level applies every reward in one atomic claim")


func _advance_merchant_to_combat() -> void:
	for step: int in range(24):
		var screen: Control = _game.router.current_screen
		if screen.name != "Merchant" or screen.dialogue == null or not screen.dialogue.is_active():
			break
		await _click(screen.dialogue.next_button)
	_check(_game.router.current_screen.name == "Combat", "Daijiro's intervention leads to the story scout encounter")


func _advance_merchant_to_gift() -> void:
	for step: int in range(24):
		var screen: Control = _game.router.current_screen
		if screen.name != "Merchant" or screen.gift_layer.visible:
			break
		if screen.dialogue == null or not screen.dialogue.is_active():
			break
		await _click(screen.dialogue.next_button)


func _wait_intro(screen: Control) -> void:
	for step: int in range(120):
		if not screen._intro_active:
			return
		await _frames(1)
	_check(false, "Combat intro finishes")

func _wait_result(screen: Control, limit: int = 900) -> void:
	for step: int in range(limit):
		if screen._result_visible:
			await _frames(3)
			return
		await _frames(1)
	_check(false, "Combat reaches its visible result")

func _measure_windows(label: String) -> void:
	for window_size: Vector2i in WINDOW_SIZES:
		DisplayServer.window_set_size(window_size)
		await _frames(8)
		var screen: Control = _game.router.current_screen
		var transform: Transform2D = root.get_screen_transform()
		var gameplay_rect := Rect2(transform * screen.global_position, screen.size * transform.get_scale())
		var measurement: Dictionary = {
			"screen_state": label,
			"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
			"image": [root.get_texture().get_width(), root.get_texture().get_height()],
			"logical_viewport": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
			"screen_host": [screen.size.x, screen.size.y],
			"scale": [transform.get_scale().x, transform.get_scale().y],
			"offset": [transform.origin.x, transform.origin.y],
			"gameplay_pixels": [gameplay_rect.size.x, gameplay_rect.size.y],
			"gameplay_area_ratio": snappedf(gameplay_rect.get_area() / float(window_size.x * window_size.y), 0.001),
			"safe_area": str(DisplayServer.get_display_safe_area()),
			"safe_margins": [_game.get_node("SafeArea").get_theme_constant("margin_left"), _game.get_node("SafeArea").get_theme_constant("margin_top"), _game.get_node("SafeArea").get_theme_constant("margin_right"), _game.get_node("SafeArea").get_theme_constant("margin_bottom")],
		}
		_report["windows"].append(measurement)
		_check(screen.size.y >= 320.0 and Rect2(Vector2.ZERO, Vector2(window_size)).encloses(gameplay_rect), "%s uses the real %s window within integer-scale bounds" % [label, window_size])
		var offender: String = _out_of_window_control(screen)
		_check(offender.is_empty(), "%s has no visible out-of-window controls at %s%s" % [label, window_size, ": " + offender if not offender.is_empty() else ""])
		if label == "world" and window_size == Vector2i(390, 844):
			await _capture("16_tall_view")
		if label == "shop":
			_check_shop_portrait(screen, window_size)
			if window_size == Vector2i(412, 915):
				await _capture("26b_shop_welcome_tall")
		if label in ["slime_approach", "cart_lookout", "backpack"]:
			await _capture("%s_%dx%d" % [label, window_size.x, window_size.y])
		if label.begins_with("guild_"):
			await _capture("%s_%dx%d" % [label, window_size.x, window_size.y])
		if label in ["guild_opening", "guild_mentor"]:
			_check_guild_actor_framing(screen, window_size)
	DisplayServer.window_set_size(Vector2i(360, 640))
	await _frames(8)

func _check_shop_portrait(shop: Control, window_size: Vector2i) -> void:
	var portrait: TextureRect = shop.merchant_still
	var texture_size: Vector2 = portrait.texture.get_size()
	var rect: Rect2 = portrait.get_global_rect()
	var scale_factor: float = minf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
	var offset_y: float = rect.position.y + (rect.size.y - texture_size.y * scale_factor) * 0.5
	var solid: Rect2 = Rect2(portrait.texture.get_image().get_used_rect())
	var head_top: float = offset_y + solid.position.y * scale_factor
	var head_bottom: float = head_top + solid.size.y * scale_factor * 0.27
	var counter_y: float = portrait.get_parent_control().get_global_rect().end.y
	var catalog_y: float = shop._catalog_scroll.get_global_rect().position.y
	_check(shop.buy_tab.get_global_rect().end.y <= head_top and catalog_y >= maxf(head_bottom, counter_y), "The face stays clear and the catalog starts below the counter at %s" % window_size)

func _check_guild_actor_framing(guild: Control, window_size: Vector2i) -> void:
	var dialogue_top: float = guild.dialogue.next_button.get_global_rect().position.y
	var hall: Rect2 = guild.get_global_rect()
	hall.end.y = dialogue_top
	# Measure the visible art so transparent padding does not count as character height.
	var minimum_heights := {"Merchant": 125.0, "Kenta": 105.0, "Goro": 125.0, "Midori": 55.0}
	for actor_name: String in minimum_heights:
		var actor: Sprite2D = guild.get_node(actor_name)
		if not actor.visible:
			continue
		var opaque: Rect2 = actor.texture.get_image().get_used_rect()
		if actor.region_enabled:
			opaque = opaque.intersection(actor.region_rect)
			opaque.position -= actor.region_rect.position
		var silhouette := Rect2(actor.to_global(opaque.position + actor.offset), opaque.size * actor.scale)
		_check(silhouette.size.y >= minimum_heights[actor_name] and hall.encloses(silhouette), "%s fills the hall and stays above the dialogue at %s" % [actor_name, window_size])

## Имя первого видимого контрола за пределами экрана; пусто — всё в границах.
func _out_of_window_control(screen: Control) -> String:
	for node: Node in screen.find_children("*", "Control", true, false):
		var control: Control = node
		if not control.is_visible_in_tree() or not (control is Button or control is Label):
			continue
		var visible_rect: Rect2 = control.get_global_rect()
		var ancestor: Control = control.get_parent_control()
		while ancestor != null and ancestor != screen:
			if ancestor is ScrollContainer:
				visible_rect = visible_rect.intersection(ancestor.get_global_rect())
				break
			ancestor = ancestor.get_parent_control()
		if visible_rect.has_area() and not screen.get_global_rect().grow(0.5).encloses(visible_rect):
			return "%s rect=%s screen=%s" % [control.name, control.get_global_rect(), screen.get_global_rect()]
	return ""

func _has_item(item_id: String) -> bool:
	for item: ItemInstance in _game.session.inventory.items:
		if item.definition_id == item_id:
			return true
	return false

func _disk_points() -> int:
	var restored := GameSession.new()
	if not SaveService.new().load_into(restored, _save_path):
		return -1
	return restored.checkpoints.manual_snapshots.size()

func _click(control: Control) -> void:
	await _frames(2)
	var point: Vector2 = control.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	root.push_input(press, true)
	_actions += 1
	await _frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.pressed = false
	root.push_input(release, true)
	await _frames(3)

func _drag(point: Vector2, relative: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	root.push_input(press, true)
	_actions += 1
	await _frames(2)
	var motion := InputEventMouseMotion.new()
	motion.position = point + relative
	motion.relative = relative
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await _frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point + relative
	release.pressed = false
	root.push_input(release, true)
	await _frames(3)

func _hold(control: Control, runner: DialogueRunner) -> void:
	var cue_index: int = runner.index
	var point: Vector2 = control.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	root.push_input(press, true)
	_actions += 1
	for step: int in range(70):
		if runner.index != cue_index or runner.is_finished:
			break
		await _frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.pressed = false
	root.push_input(release, true)
	await _frames(3)

func _out_dir() -> String:
	if _mode == "guild":
		return GUILD_OUT
	return MERCHANT_OUT if _mode == "merchant" else OUT


func _capture(label: String) -> void:
	if _mode == "guild" and not label.begins_with("guild_"):
		return
	await _frames(4)
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(_out_dir() + "/" + label + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = image.save_png(path)
	_report["captures"].append({"label": label, "size": [image.get_width(), image.get_height()], "error": error})
	_check(error == OK, "Capture %s" % label)

func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame

func _check(ok: bool, message: String) -> void:
	_checks += 1
	_report["checks"].append({"ok": ok, "message": message})
	if not ok:
		_failed += 1
		printerr("FAIL ", message)
