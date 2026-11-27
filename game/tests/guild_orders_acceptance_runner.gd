extends "res://tests/first_session_acceptance_runner.gd"

const GuildFixture = preload("res://tests/grove_suite.gd")
const ORDER := "herbalist_escort"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for viewport_size: Vector2i in WINDOW_SIZES:
		var label: String = "%dx%d" % [viewport_size.x, viewport_size.y]
		DisplayServer.window_set_size(viewport_size)
		_save_path = "user://guild_orders/%d/%s/profile.json" % [OS.get_process_id(), label]
		await _new_game_root()
		if not await _play_order(label):
			break
	print("GUILD_ORDERS_ACCEPTANCE checks=%d failures=%d" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)

func _out_dir() -> String:
	return "res://.godot/guild_orders_qa/windows"

func _play_order(label: String) -> bool:
	GuildFixture.at_guild(_game.session)
	_game.session.wallet[GameSession.COPPER] = 40
	for seed: int in range(16):
		_game.session.set_loot_seed("orders-window-%d" % seed)
		var rng := RandomNumberGenerator.new()
		rng.state = _game.session.loot_rng.state
		if rng.randi_range(1, 2) == 2:
			break
	_game.router.go_to("guild")
	await _click(_node("GuildOrdersButton"))
	await _capture(label + "_board")
	await _click(_node(ORDER))
	await _capture(label + "_offer")
	_game.save_path = _save_path + "/blocked.json"
	await _click(_node("OrderAccept"))
	_check(_game.session.guild_order.is_empty() and _node("OrderAccept").has_focus(), "Failed acceptance preserves focus and state")
	_game.save_path = _save_path
	await _click(_node("OrderAccept"))
	_check(int(_game.session.guild_order.get("total", 0)) == 2, "The fixture accepts a two-stage order")
	await _click(_node("OrderDepart"))
	await _capture(label + "_stage1")
	var field: Control = _game.router.current_screen
	_check(field.name == "World" and field.hero_sprite.is_visible_in_tree(), "A guild expedition uses the world HUD and equipped hero")
	await _click(field.map_button)
	_check(_node("MapGrove").disabled, "The world map marks the contract's physical location")
	await _press_back()
	field = _game.router.current_screen
	_check(field.map_button.has_focus() and _node("OrderFight").visible, "Map Back returns to the same contract and map icon")
	await _click(field.settings_button)
	await _press_back()
	field = _game.router.current_screen
	await _click(field.inventory_button)
	await _press_back()
	_check(_node("OrderFight").is_visible_in_tree() and _game.session.guild_order["cleared"] == 0, "Settings and inventory return to the current field")
	await _click(_node("OrderFight"))
	var combat: Control = _game.router.current_screen
	if combat.name != "Combat":
		_check(false, "Field action starts combat")
		return false
	await _wait_result(combat, 1800)
	_check(_game.session.has_pending_battle_result() and _game.session.guild_order["cleared"] == 0, "The stage waits for the reward claim")
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	combat = _game.router.current_screen
	if combat.name != "Combat" or combat.resolver != null:
		_check(false, "Continue restores pending loot without restarting the fight")
		return false
	await _claim_result(combat)
	_check(_game.session.guild_order["cleared"] == 1, "Claim unlocks the next stage")
	await _click(_node("OrderShop"))
	var shop: Control = _game.router.current_screen
	var sword_id: String = _game.session.inventory.equipment["weapon"]
	var upgrade_name: String = "Upgrade_" + sword_id
	var strength: int = _game.session.hero.strength
	var copper: int = _game.session.wallet[GameSession.COPPER]
	await _click(_node(upgrade_name))
	await _capture(label + "_upgrade")
	await _press_back()
	_check(_node(upgrade_name).has_focus(), "Back restores focus to the upgrade row")
	_game.save_path = _save_path + "/blocked.json"
	await _confirm_upgrade(upgrade_name)
	_check(_game.session.hero.strength == strength and _game.session.wallet[GameSession.COPPER] == copper, "A failed upgrade leaves gear and currency intact")
	_game.save_path = _save_path
	await _confirm_upgrade(upgrade_name)
	_check(_game.session.hero.strength == strength + 1 and _game.session.wallet[GameSession.COPPER] == copper - 12, "Upgrade applies once")
	await _click(shop.back_button)
	await _click(_node("OrderDepart"))
	await _capture(label + "_stage2")
	await _click(_node("OrderFight"))
	combat = _game.router.current_screen
	await _wait_result(combat, 1800)
	await _claim_result(combat)
	await _click(_node("OrderToReport"))
	await _capture(label + "_report")
	_game.save_path = _save_path + "/blocked.json"
	copper = _game.session.wallet[GameSession.COPPER]
	await _click(_node("OrderReport"))
	_check(not _game.session.guild_order_is_completed(ORDER) and _game.session.wallet[GameSession.COPPER] == copper, "A failed report leaves the payout claimable")
	_game.save_path = _save_path
	await _click(_node("OrderReport"))
	_check(_game.session.guild_order_is_completed(ORDER) and _game.session.wallet[GameSession.COPPER] == copper + 30, "Report pays exactly the promised copper")
	_check(_game.session.guild_order_is_unlocked("hollow_hunt"), "Report unlocks the next rank")
	await _press_back()
	_check(_node("GuildOrdersButton").has_focus(), "Back from the board focuses its opener")
	return true

func _confirm_upgrade(row_name: String) -> void:
	await _click(_node(row_name))
	var modal: ConfirmDialog = get_nodes_in_group(ConfirmDialog.MODAL_GROUP).back()
	await _click(modal.get_node("%Confirm"))

func _node(node_name: String) -> Control:
	return _game.router.current_screen.find_child(node_name, true, false) as Control
