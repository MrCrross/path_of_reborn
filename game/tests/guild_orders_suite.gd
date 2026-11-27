extends RefCounted

const DomainSuite = preload("res://tests/domain_suite.gd")
const GroveSuite = preload("res://tests/grove_suite.gd")
const TestContext = DomainSuite.TestContext

func run() -> Array[Dictionary]:
	var ladder := TestContext.new()
	_test_ladder(ladder)
	var persistence := TestContext.new()
	_test_persistence(persistence)
	var loot := TestContext.new()
	_test_loot_curve(loot)
	return [
		{"name": "guild_orders_ranked_ladder", "checks": ladder.checks},
		{"name": "guild_orders_save_checkpoint_and_gear", "checks": persistence.checks},
		{"name": "guild_orders_stage_loot_curve", "checks": loot.checks},
	]

func _test_ladder(context: TestContext) -> void:
	var session := GameSession.new()
	GroveSuite.at_guild(session)
	session.set_loot_seed("ranked-ladder")
	var saves := SaveService.new()
	context.check(not session.apply_guild_order_command("accept", "hollow_hunt"), "The board requires the previous rank")
	var bounds: Array[Vector2i] = [Vector2i(1, 2), Vector2i(3, 4), Vector2i(5, 8), Vector2i(7, 10), Vector2i(10, 15), Vector2i(20, 30)]
	for order_id: String in GuildOrders.data()["orders"]:
		var order: Dictionary = GuildOrders.definition(order_id)
		var rules: Dictionary = GuildOrders.rank_rules(order["rank"])
		var level: int = int(rules["level"])
		context.check(session.apply_guild_order_command("accept", order_id), "Accept rank " + order["rank"])
		context.check(not session.apply_guild_order_command("accept", order_id) and not session.apply_guild_order_command("report", order_id), "Only one active order and no early payout")
		var total: int = int(session.guild_order["total"])
		context.check(total >= bounds[level - 1].x and total <= bounds[level - 1].y, "Stage count is within the rank bounds")
		if not session.apply_guild_order_command("depart", order_id):
			context.check(false, "Departure failed")
			return
		for index: int in total:
			var stage: Dictionary = session.guild_order_stage()
			var combat: CombatResolver = session.start_combat(stage["enemy_id"])
			if combat == null:
				context.check(false, "The next stage should start")
				return
			combat.advance_ticks(3000)
			var label: String = "%s %d/%d" % [order_id, index + 1, total]
			if not combat.won or not saves.validate(saves.capture(session)) or not DomainSuite.claim_pending(session):
				context.check(false, "%s could not be won and claimed (win=%s, HP=%d, attack=%d, defense=%d)" % [label, combat.won, session.hero.max_hp, session.hero.strength, session.hero.defense])
				return
			context.check(int(session.guild_order["cleared"]) == index + 1 and not DomainSuite.claim_pending(session), "Stage advances once " + label)
			while session.hero.pending_upgrade_choices > 0:
				session.choose_upgrade("max_hp" if session.hero.max_hp < 16 else "strength")
		context.check(session.apply_guild_order_command("leave"), "Completed field route can leave for the report")
		var copper: int = session.wallet[GameSession.COPPER]
		var reward_id: String = GuildOrders.order_type(order)["reward"]
		context.check(session.apply_guild_order_command("report", order_id) and not session.apply_guild_order_command("report", order_id), "Final reward pays once")
		context.check(session.wallet[GameSession.COPPER] == copper + int(rules["copper"]), "Copper follows the rank table")
		var reward: ItemInstance = session.inventory.items.back()
		context.check(reward.definition_id == reward_id and reward.level == level, "Guaranteed piece matches the contract rank")
		session.equip_item(reward.instance_id)
		for slot: String in ["armor", "weapon"]:
			var quote: Dictionary = session.equipment_upgrade_quote(session.inventory.equipment.get(slot, ""))
			if not quote.is_empty() and session.wallet[GameSession.COPPER] >= int(quote["price"]):
				session.upgrade_equipment(quote)

func _test_persistence(context: TestContext) -> void:
	var session := GameSession.new()
	GroveSuite.at_guild(session)
	session.wallet[GameSession.COPPER] = 30
	var sword_id: String = session.inventory.equipment["weapon"]
	var base_strength: int = session.hero.strength
	var quote: Dictionary = session.equipment_upgrade_quote(sword_id)
	context.check(session.upgrade_equipment(quote) and not session.upgrade_equipment(quote) and session.hero.strength == base_strength + 1, "An upgrade changes the equipped stat once per quote")
	var saves := SaveService.new()
	var legacy: Dictionary = saves.capture(session)
	legacy["profile"].erase("guild_order")
	context.check(saves.validate(legacy), "Old v7 profiles need no guild order field")
	var order_id := "herbalist_escort"
	session.apply_guild_order_command("accept", order_id)
	session.apply_guild_order_command("depart", order_id)
	context.check(session.checkpoints.begin(), "A field stage admits a Checkpoint")
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	context.check(session.checkpoints.apply_completion(), "Checkpoint records stage zero")
	session.start_combat(session.guild_order_stage()["enemy_id"]).advance_ticks(1800)
	var pending: Dictionary = saves.capture(session)
	var wrong_stage: Dictionary = pending.duplicate(true)
	wrong_stage["profile"]["guild_order"]["cleared"] = 1
	context.check(saves.validate(pending) and not saves.validate(wrong_stage), "A pending claim is tied to the same saved contract stage")
	var restored := GameSession.new()
	restored.apply_state_dto(pending)
	context.check(restored.hero.strength == base_strength + 1 and restored.pending_battle_result == session.pending_battle_result, "Continue restores the stat and the exact rolled items")
	context.check(DomainSuite.claim_pending(restored) and restored.apply_guild_order_command("leave"), "Claim then return to the city")
	context.check(restored.guild_order["cleared"] == 1 and restored.equipment_upgrade_quote(sword_id)["level"] == 2, "Progress is preserved at the shop")
	restored.awaiting_return = true
	context.check(restored.checkpoints.restore() and restored.guild_order["cleared"] == 0, "Checkpoint rewinds the stage and its loot together")

func _test_loot_curve(context: TestContext) -> void:
	for rank: String in GuildOrders.RANKS:
		var rules: Dictionary = GuildOrders.rank_rules(rank)
		var total: int = int(rules["max"])
		var previous_count: int = 0
		var valid_gear: bool = true
		var rng := RandomNumberGenerator.new()
		for stage: int in total:
			var count: int = 0
			for sample: int in 1000:
				# Each stage sees the same roll for a sample, even when a bonus selects an item.
				rng.seed = hash("%s-%d" % [rank, sample])
				var gear: Array[Dictionary] = GuildOrders.bonus_loot(rank, stage, total, rng)
				if not gear.is_empty():
					count += 1
					valid_gear = valid_gear and int(gear[0]["level"]) == maxi(1, int(rules["level"]) - 1)
			context.check(count > previous_count, "%s stage %d has a higher bonus chance" % [rank, stage + 1])
			previous_count = count
		context.check(valid_gear, "Only the configured bonus level can drop for rank " + rank)
