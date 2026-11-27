extends RefCounted

const ACTOR_PATHS: Array[String] = [
	"res://data/actors/haruto.tres",
	"res://data/actors/moss_slime.tres",
	"res://data/actors/goblin_scout.tres",
	"res://data/actors/goblin_trial.tres",
]

class TestContext:
	extends RefCounted

	var checks: Array[Dictionary] = []

	func check(condition: bool, message: String) -> void:
		checks.append({"passed": condition, "message": message})

static func prepare_pending_choices(session: GameSession) -> void:
	for entry: Dictionary in session.pending_battle_result.get("items", []):
		var entry_id: String = String(entry.get("entry_id", ""))
		if not session.pending_battle_result.get("choices", {}).has(entry_id):
			session.choose_battle_reward(entry_id, "store")

static func claim_pending(session: GameSession) -> bool:
	prepare_pending_choices(session)
	return session.claim_battle_result(String(session.pending_battle_result.get("result_id", "")))

class SignalCounter:
	extends RefCounted

	var count: int = 0

	func increment() -> void:
		count += 1

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_run_case("actor_definitions_load_and_ids", _test_actor_definitions))
	results.append(_run_case("item_and_modifier_contract", _test_item_contract))
	results.append(_run_case("runtime_instances_are_independent", _test_runtime_independence))
	results.append(_run_case("hp_damage_heal_and_clamp", _test_hp_boundaries))
	results.append(_run_case("death_at_zero_and_only_once", _test_death_once))
	results.append(_run_case("xp_remainder_levels_and_upgrades", _test_xp_and_upgrades))
	results.append(_run_case("character_power_and_upgrade_preview", _test_character_power_and_upgrade_preview))
	results.append(_run_case("damage_formula_and_minimum", _test_damage_formula))
	results.append(_run_case("shop_deals_and_travel_contract", _test_shop_and_travel))
	return results

func _run_case(case_name: String, test: Callable) -> Dictionary:
	var context := TestContext.new()
	test.call(context)
	return {"name": case_name, "checks": context.checks}

func _hero() -> CharacterState:
	var definition: ActorDefinition = load("res://data/actors/haruto.tres")
	return CharacterState.new(definition)

func _test_actor_definitions(context: TestContext) -> void:
	var ids: Dictionary = {}
	for path: String in ACTOR_PATHS:
		context.check(ResourceLoader.exists(path), "Resource exists: %s" % path)
		if not ResourceLoader.exists(path):
			continue
		var resource: Resource = load(path)
		context.check(resource is ActorDefinition, "Expected ActorDefinition: %s" % path)
		if resource is ActorDefinition:
			var actor: ActorDefinition = resource
			context.check(not actor.id.is_empty(), "Non-empty ID: %s" % path)
			context.check(not ids.has(actor.id), "Unique ID: %s" % actor.id)
			ids[actor.id] = true
	var hero_resource: Resource = load("res://data/actors/haruto.tres")
	if hero_resource is ActorDefinition:
		var hero: ActorDefinition = hero_resource
		context.check(hero.strength == 3, "Haruto starts with 3 strength")
		context.check(hero.defense == 2, "Haruto starts with 2 defense")
		context.check(hero.mana == 1, "Haruto starts with 1 mana")
		context.check(hero.xp_thresholds == [4, 30, 19, 23], "Haruto unlocks Focused Strike early and gains later levels at expedition milestones")

func _test_item_contract(context: TestContext) -> void:
	var modifier := StatModifierDefinition.new()
	modifier.source_id = "item_000001"
	modifier.stat_id = "strength"
	modifier.amount = 2
	var item := ItemDefinition.new()
	item.id = "training_sword"
	item.slot_id = "weapon"
	item.stack_limit = 1
	item.modifiers.append(modifier)
	context.check(item.id == "training_sword", "Item has a stable string ID")
	context.check(item.slot_id == "weapon", "Item declares an equipment slot")
	context.check(item.modifiers.size() == 1, "Item owns its modifier list")
	context.check(item.modifiers[0].source_id == "item_000001", "Modifier names its removable source")
	context.check(item.modifiers[0].stat_id == "strength", "Modifier names its derived stat")

func _test_runtime_independence(context: TestContext) -> void:
	var first := _hero()
	var second := _hero()
	context.check(first.definition == second.definition, "Runtime states may share a read-only definition")
	context.check(first.current_hp == 12 and second.current_hp == 12, "Both states start at full HP")
	first.take_damage(5)
	context.check(first.current_hp == 7, "Damage changes the first state")
	context.check(second.current_hp == 12, "Damage does not leak into the second state")
	context.check(first.definition.max_hp == 12, "Damage does not mutate the Resource")
	first.gain_xp(4)
	context.check(first.choose_upgrade("max_hp"), "First state accepts its earned upgrade")
	context.check(first.max_hp == 16 and second.max_hp == 12, "Upgrades are instance-local")
	context.check(first.definition.max_hp == 12, "Upgrade does not mutate base max HP")
	first.choose_upgrade("strength")
	context.check(second.strength == 3 and first.definition.strength == 3, "Other state and base strength stay unchanged")

func _test_character_power_and_upgrade_preview(context: TestContext) -> void:
	var state := _hero()
	context.check(state.power_rating() == 34, "Power includes all four effective stats")
	state.take_damage(1)
	context.check(state.power_rating() == 34, "Power is independent of current HP")
	state.set_void_traces(3)
	var before: int = state.max_hp
	var gains: Dictionary[String, int] = state.upgrade_gains()
	context.check(gains["max_hp"] == 3 and state.max_hp == before, "HP preview includes trace rounding without changing the character")
	state.gain_xp(4)
	state.choose_upgrade("max_hp")
	context.check(state.max_hp - before == gains["max_hp"], "Applying the choice matches the displayed gain")

func _test_hp_boundaries(context: TestContext) -> void:
	var state := _hero()
	context.check(state.take_damage(2) == 2 and state.current_hp == 10, "Damage subtracts HP")
	context.check(state.heal(3) == 2 and state.current_hp == 12, "Healing restores only missing HP")
	context.check(state.heal(999) == 0 and state.current_hp == state.max_hp, "Healing clamps at max HP")
	context.check(state.take_damage(-5) == 0 and state.current_hp == state.max_hp, "Negative damage has no effect")
	context.check(state.heal(-5) == 0 and state.current_hp == state.max_hp, "Negative healing has no effect")
	context.check(state.take_damage(999) == 12 and state.current_hp == 0, "Overkill returns actual damage and clamps at zero")
	context.check(state.heal(5) == 0 and state.is_dead(), "Healing does not implicitly revive a dead state")

func _test_death_once(context: TestContext) -> void:
	var state := _hero()
	var counter := SignalCounter.new()
	state.died.connect(counter.increment)
	state.take_damage(11)
	context.check(not state.is_dead() and counter.count == 0, "Above-zero HP is not death")
	state.take_damage(1)
	context.check(state.is_dead() and counter.count == 1, "Zero HP emits death once")
	state.take_damage(1)
	state.take_damage(999)
	context.check(counter.count == 1 and state.current_hp == 0, "Further damage has no repeated terminal effect")

func _test_xp_and_upgrades(context: TestContext) -> void:
	var boundary := _hero()
	boundary.gain_xp(3)
	context.check(boundary.level == 1 and boundary.experience == 3, "XP below the threshold does not level")
	boundary.gain_xp(1)
	context.check(boundary.level == 2 and boundary.experience == 0, "XP at the threshold levels exactly once")
	context.check(boundary.pending_upgrade_choices == 1, "Level-up grants one upgrade choice")
	context.check(not boundary.choose_upgrade("unknown"), "Unknown upgrade is refused")
	context.check(boundary.choose_upgrade("strength"), "Earned strength upgrade is accepted")
	context.check(boundary.strength == 4 and boundary.definition.strength == 3, "Strength upgrade changes derived state only")
	context.check(not boundary.choose_upgrade("strength"), "A level cannot spend the same choice twice")
	var remainder := _hero()
	remainder.gain_xp(5)
	context.check(remainder.level == 2 and remainder.experience == 1, "XP remainder survives level-up")
	var multiple := _hero()
	multiple.gain_xp(34)
	context.check(multiple.level == 3 and multiple.experience == 0, "One grant can cross several thresholds")
	context.check(multiple.pending_upgrade_choices == 2, "Each gained level has its own choice")
	context.check(multiple.choose_upgrade("max_hp"), "Max HP upgrade is available")
	context.check(multiple.max_hp == 16 and multiple.current_hp == 12, "Increasing max HP preserves absolute current HP")
	context.check(multiple.choose_upgrade("strength") and multiple.pending_upgrade_choices == 0, "Multiple level choices can be spent independently")

func _test_damage_formula(context: TestContext) -> void:
	context.check(CharacterState.calculate_damage(3, 2) == 1, "Base damage subtracts defense")
	context.check(CharacterState.calculate_damage(3, 2, 1.5) == 2, "Window multiplier rounds once")
	context.check(CharacterState.calculate_damage(4, 2, 1.25) == 3, "Half values round once at the end")
	context.check(CharacterState.calculate_damage(1, 5) == 1, "Defense cannot reduce damage below one")
	context.check(CharacterState.calculate_damage(5, 1, 0.0) == 1, "Even a zero multiplier respects minimum damage")

func _test_shop_and_travel(context: TestContext) -> void:
	var session := GameSession.new()
	context.check(session.location_id == GameSession.LOCATION_FOREST_EDGE, "New game starts on the trail")
	context.check(session.has_visited_map_location(GameSession.LOCATION_FOREST_EDGE) and not session.has_visited_map_location(GameSession.LOCATION_LIOREN) and session.first_unvisited_map_route(false).is_empty(), "A new profile knows only the Trail and has no first travel route")
	context.check(session.travel_to("unknown_place") == false, "Unknown location is refused")
	context.check(session.map_travel_blocker(GameSession.LOCATION_LIOREN) == "daijiro" and not session.apply_map_travel(GameSession.LOCATION_LIOREN), "The map gates Lioren until Daijiro's sword")
	# Лавка закрыта до сцены ворот.
	context.check(not session.buy_item("wanderer_jacket"), "Purchase before the gates scene is refused")
	session.world_flags[GameSession.WORLD_FLAG_LIOREN_SHOP_UNLOCKED] = true
	context.check(not session.buy_item("wanderer_jacket"), "Purchase without funds is refused")
	var crystals: Array[ItemInstance] = session.inventory.add(session.get_item_definition("echo_crystal"), 1, "moss")
	context.check(session.sell_item(crystals[0].instance_id, 1) and session.wallet[GameSession.COPPER] == 20, "One crystal sells for 20 copper")
	context.check(bool(session.world_flags.get(GameSession.WORLD_FLAG_SHOP_FIRST_SALE_DONE, false)), "First successful sale records its milestone")
	context.check(session.buy_item("wanderer_jacket") and session.wallet[GameSession.COPPER] == 8, "Jacket purchase deducts 12 copper")
	context.check(bool(session.world_flags.get(GameSession.WORLD_FLAG_WANDERER_JACKET_PURCHASED, false)) and bool(session.world_flags.get(GameSession.WORLD_FLAG_SHOP_FIRST_PURCHASE_DONE, false)), "Purchase records its one-time flag and milestone")
	var jacket: ItemInstance = session.inventory.get_item(String(session.last_deal.get("instance_ids", [""])[0]))
	context.check(jacket != null and jacket.definition_id == "wanderer_jacket", "Bought jacket lands in the inventory")
	var offers: Array[Dictionary] = session.shop_offers()
	context.check(offers.size() == 1 and bool(offers[0].get("sold_out", false)) and int(offers[0].get("remaining", -1)) == 0, "One-per-story offer is sold out after the purchase")
	context.check(not session.buy_item("wanderer_jacket"), "Sold-out offer cannot be bought twice")
	context.check(session.equip_item(jacket.instance_id) and session.hero.defense == 3, "Jacket equips into the armor slot and adds one defense")
	context.check(not session.sell_item(jacket.instance_id), "Equipped story items cannot be sold")
	context.check(String(session.last_deal.get("kind", "")) == "buy" and int(session.last_deal.get("balance_after", -1)) == 8, "Last deal carries the kind and resulting balance for presentation")
	context.check(session.travel_to(GameSession.LOCATION_LIOREN) and session.location_id == GameSession.LOCATION_LIOREN, "Travel to Lioren applies")
	context.check(session.travel_to(GameSession.LOCATION_LIOREN), "Travel to the current location is a harmless no-op")
	session.start_combat("moss_slime")
	context.check(not session.travel_to(GameSession.LOCATION_FOREST_EDGE), "Travel is refused during combat")
	var returning := GameSession.new()
	returning.location_id = GameSession.LOCATION_LIOREN
	returning.traces = 3
	context.check(not returning.can_trade() and not returning.travel_to(GameSession.LOCATION_FOREST_EDGE), "A forced arrival needs rest and leaves the shop closed before the introduction")
	context.check(returning.map_travel_blocker(GameSession.LOCATION_FOREST_EDGE) == "rest" and not returning.apply_map_travel(GameSession.LOCATION_FOREST_EDGE), "The map blocks returning to the Trail before rest")
	context.check(returning.checkpoints.rest() and returning.apply_map_travel(GameSession.LOCATION_FOREST_EDGE), "Rest opens the map route to the Trail without a sword or shop access")
	returning.travel_to(GameSession.LOCATION_LIOREN)
	returning.world_flags[GameSession.WORLD_FLAG_LIOREN_SHOP_UNLOCKED] = true
	context.check(not returning.has_visited_map_location(GameSession.MAP_SHOP) and returning.first_unvisited_map_route(true) == GameSession.MAP_SHOP, "The gates allow a first visit without revealing a shop pin")
	var before_shop: Dictionary = returning.capture_profile_dto()
	context.check(returning.apply_map_travel(GameSession.MAP_SHOP) and returning.has_visited_map_location(GameSession.MAP_SHOP), "Entering the shop records the discovery")
	returning.apply_profile_dto(before_shop)
	var restored := GameSession.new()
	restored.apply_state_dto(SaveService.new().capture(returning))
	context.check(restored.has_visited_map_location(GameSession.MAP_SHOP) and restored.first_unvisited_map_route(true).is_empty(), "Discovered places are retained after profile rollback and save DTO reload")
	returning.wallet[GameSession.COPPER] = 12
	context.check(not returning.buy_item("wanderer_jacket", 1, 11) and returning.wallet[GameSession.COPPER] == 12, "A stale buy quote changes neither the balance nor the offer")
	context.check(returning.can_trade() and returning.buy_item("wanderer_jacket", 1, 12) and not returning.world_flags.has(GameSession.WORLD_FLAG_SHOP_FIRST_SALE_DONE), "A funded player can buy before the first sale")
	var stack: ItemInstance = returning.inventory.add(returning.get_item_definition("echo_crystal"), 3, "moss")[0]
	context.check(not returning.sell_item(stack.instance_id, 1, 19, 3) and stack.quantity == 3, "A stale sale price leaves the stack intact")
	returning.inventory.changed.connect(func() -> void:
		context.check(returning.is_transaction_active(), "Inventory observers see the pending sale")
		context.check(not returning.sell_item(stack.instance_id), "An inventory observer cannot start a second sale during settlement")
	, CONNECT_ONE_SHOT)
	context.check(returning.sell_item(stack.instance_id, 1, 20, 3) and stack.quantity == 2, "A partial sale leaves the correct remainder")
	context.check(not returning.sell_item(stack.instance_id, 1, 20, 3) and returning.wallet[GameSession.COPPER] == 20, "A repeated confirmation with the old stock credits no additional money")
	context.check(GameSession.trade_total(GameSession.MAX_ASTRAS, 2) == 0, "An overflowing trade total is rejected before multiplication")
	var copper: String = GameSession.COPPER
	var silver: String = GameSession.SILVER
	var gold: String = GameSession.GOLD
	returning.wallet[copper] = 99
	var quote: Dictionary = returning.coin_exchange_quote(copper, silver)
	context.check(not returning.exchange_coins(copper, silver, 1, quote) and returning.wallet[copper] == 99, "99 copper cannot buy silver")
	returning.wallet[copper] = 10007
	context.check(returning.wallet[silver] == 0 and returning.wallet[gold] == 0, "Coin balances never convert automatically")
	quote = returning.coin_exchange_quote(copper, silver)
	context.check(returning.exchange_coins(copper, silver, 100, quote) and returning.wallet[copper] == 7 and returning.wallet[silver] == 100, "Batch exchange keeps the copper remainder")
	context.check(not returning.exchange_coins(copper, silver, 100, quote), "A repeated confirmation with old balances has no effect")
	context.check(returning.exchange_coins(silver, gold, 1, returning.coin_exchange_quote(silver, gold)) and returning.wallet[silver] == 0 and returning.wallet[gold] == 1, "100 silver buys one gold")
	context.check(returning.exchange_coins(gold, silver, 1, returning.coin_exchange_quote(gold, silver)) and returning.wallet[silver] == 100 and returning.wallet[gold] == 0, "One gold yields 100 silver")
	context.check(returning.exchange_coins(silver, copper, 1, returning.coin_exchange_quote(silver, copper)) and returning.wallet[copper] == 107 and returning.wallet[silver] == 99, "One silver yields 100 copper")
	context.check(returning.coin_exchange_quote(copper, gold).is_empty() and not returning.exchange_coins(copper, copper, 1, {}), "Only neighboring denominations can be exchanged")
	returning.wallet[copper] = GameSession.MAX_ASTRAS - 99
	context.check(not returning.exchange_coins(silver, copper, 1, returning.coin_exchange_quote(silver, copper)) and returning.wallet[silver] == 99, "An overflowing exchange leaves both balances unchanged")
	returning.travel_to(GameSession.LOCATION_FOREST_EDGE)
	context.check(not returning.exchange_coins(copper, silver, 1, returning.coin_exchange_quote(copper, silver)), "Exchange requires presence at the shop")
	var silver_only := GameSession.new()
	silver_only.world_flags[GameSession.WORLD_FLAG_LIOREN_SHOP_UNLOCKED] = true
	silver_only.wallet[silver] = 1
	context.check(not silver_only.buy_item("wanderer_jacket"), "Silver must be exchanged before buying a copper-priced item")
