extends RefCounted

const DomainSuite = preload("res://tests/domain_suite.gd")
const TestContext = DomainSuite.TestContext

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_run_case("item_and_loot_resources_are_valid", _test_resources))
	results.append(_run_case("seeded_loot_is_deterministic", _test_seed_determinism))
	results.append(_run_case("victory_reward_and_claim_are_idempotent", _test_reward_transaction))
	results.append(_run_case("inventory_add_stack_remove_and_invalid_operations", _test_stacks))
	results.append(_run_case("inventory_filter_returns_requested_types", _test_filter))
	results.append(_run_case("equip_unequip_restores_stats_and_preserves_hp", _test_equip_stats))
	results.append(_run_case("replacement_uses_instance_source_ids", _test_replacement))
	results.append(_run_case("inventory_and_equipment_survive_encounter_transition", _test_session_transition))
	return results

func _run_case(case_name: String, test: Callable) -> Dictionary:
	var context := TestContext.new()
	test.call(context)
	return {"name": case_name, "checks": context.checks}

func _test_resources(context: TestContext) -> void:
	var ids: Dictionary = {}
	for path: String in GameSession.ITEM_PATHS.values():
		var resource: Resource = load(path)
		context.check(resource is ItemDefinition, "Expected ItemDefinition: %s" % path)
		if resource is ItemDefinition:
			context.check(not resource.id.is_empty() and not ids.has(resource.id), "Unique item ID: %s" % resource.id)
			ids[resource.id] = true
	for path: String in GameSession.LOOT_PATHS.values():
		var resource: Resource = load(path)
		context.check(resource is LootTableDefinition, "Expected LootTableDefinition: %s" % path)
		if resource is LootTableDefinition:
			var table: LootTableDefinition = resource
			for entry: LootEntryDefinition in table.entries:
				context.check(ids.has(entry.item_id), "Loot references known item %s: %s" % [entry.item_id, path])

func _test_seed_determinism(context: TestContext) -> void:
	var table: LootTableDefinition = load(GameSession.LOOT_PATHS["moss_slime"])
	var generator := LootGenerator.new()
	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = 123456
	second_rng.seed = 123456
	var first: Array[Dictionary] = generator.generate(table, first_rng)
	var second: Array[Dictionary] = generator.generate(table, second_rng)
	context.check(first == second and not first.is_empty(), "Same seed and table produce identical rewards")
	context.check(first_rng.state == second_rng.state, "Same generation advances RNG state identically")
	var echo_table := LootTableDefinition.new()
	echo_table.rolls = 1
	var entry := LootEntryDefinition.new()
	entry.item_id = "echo_crystal"
	entry.min_quantity = 2
	entry.max_quantity = 2
	entry.aspect_id = "moss"
	echo_table.entries.append(entry)
	var echo_reward: Array[Dictionary] = generator.generate(echo_table, first_rng)
	context.check(echo_reward[0]["quantity"] == 2 and echo_reward[0]["aspect_id"] == "moss", "Echo reward keeps its quantity and aspect")

func _test_reward_transaction(context: TestContext) -> void:
	var session := GameSession.new()
	context.check(not session.apply_victory("moss_slime"), "Reward is refused before a victory")
	var combat := session.start_combat("moss_slime")
	combat.enemy.current_hp = 1
	combat.request_attack()
	context.check(session.apply_victory("moss_slime"), "Actual victory creates a reward")
	context.check(session.inventory.items.is_empty() and not session.pending_reward.is_empty(), "Reward waits for an explicit claim")
	context.check(not session.apply_victory("moss_slime"), "Repeated terminal transaction has no effect")
	context.check(session.claim_reward(), "Reward can be claimed into inventory")
	var count: int = session.inventory.items.size()
	context.check(count > 0 and session.pending_reward.is_empty(), "Claim moves the pending reward into inventory")
	context.check(not session.claim_reward() and session.inventory.items.size() == count, "Repeated claim cannot duplicate items")

func _test_stacks(context: TestContext) -> void:
	var session := GameSession.new()
	var echo: ItemDefinition = session.get_item_definition("echo_crystal")
	var first: Array[ItemInstance] = session.inventory.add(echo, 3, "moss")
	var second: Array[ItemInstance] = session.inventory.add(echo, 2, "moss")
	context.check(session.inventory.items.size() == 1 and first[0] == second[0], "Matching stackable items share an instance")
	context.check(first[0].quantity == 5 and first[0].instance_id == "item_000001", "Stack quantity and serial ID are stable")
	context.check(session.inventory.remove(first[0].instance_id, 2) and first[0].quantity == 3, "Partial remove decreases the stack")
	context.check(not session.inventory.remove(first[0].instance_id, 4) and first[0].quantity == 3, "Oversized remove is refused without partial mutation")
	context.check(session.inventory.remove(first[0].instance_id, 3) and session.inventory.items.is_empty(), "Removing the full stack releases its instance")
	var sword: ItemDefinition = session.get_item_definition("training_sword")
	session.inventory.add(sword, 2)
	context.check(session.inventory.items.size() == 2, "Non-stackable equipment gets separate instances")
	context.check(session.inventory.items[0].instance_id != session.inventory.items[1].instance_id, "Equipment instance IDs are unique")
	context.check(session.inventory.add(sword, 0).is_empty(), "Non-positive add is refused")

func _test_filter(context: TestContext) -> void:
	var session := GameSession.new()
	session.inventory.add(session.get_item_definition("training_sword"), 1)
	session.inventory.add(session.get_item_definition("moss_charm"), 1)
	session.inventory.add(session.get_item_definition("echo_crystal"), 1, "moss")
	context.check(session.inventory.filter().size() == 3, "Empty filter returns every item")
	context.check(session.inventory.filter("weapon").size() == 1, "Weapon filter excludes other types")
	context.check(session.inventory.filter("charm").size() == 1, "Charm filter excludes other types")
	context.check(session.inventory.filter("echo").size() == 1, "Echo filter includes crystal aspects")
	context.check(session.inventory.filter("material").is_empty(), "Filter can return an empty type")

func _test_equip_stats(context: TestContext) -> void:
	var session := GameSession.new()
	session.hero.take_damage(2)
	var sword: Array[ItemInstance] = session.inventory.add(session.get_item_definition("training_sword"), 1)
	var charm: Array[ItemInstance] = session.inventory.add(session.get_item_definition("moss_charm"), 1)
	context.check(session.inventory.equip(sword[0].instance_id), "Weapon can be equipped")
	context.check(session.hero.strength == 5 and session.hero.defense == 2 and session.hero.max_hp == 12, "Weapon changes only strength")
	context.check(session.hero.current_hp == 10, "Weapon equip does not heal")
	context.check(session.inventory.equip(sword[0].instance_id) and session.hero.strength == 5, "Repeated equip does not stack modifiers")
	context.check(session.inventory.equip(charm[0].instance_id), "Charm can be equipped independently")
	context.check(session.hero.max_hp == 16 and session.hero.current_hp == 10, "Max HP modifier preserves absolute current HP")
	session.hero.heal(999)
	context.check(session.hero.current_hp == 16, "Healing can use the modified maximum")
	var restored := GameSession.new()
	restored.apply_profile_dto(session.capture_profile_dto())
	context.check(restored.hero.current_hp == 16 and restored.hero.max_hp == 16, "Profile restores HP above the unequipped maximum")
	context.check(session.inventory.unequip("charm") and session.hero.max_hp == 12 and session.hero.current_hp == 12, "Unequip clamps HP without changing base stats")
	context.check(session.inventory.unequip("weapon") and session.hero.strength == 3, "Unequip restores the exact original stat")
	context.check(not session.inventory.equip("missing"), "Unknown item cannot be equipped")

func _test_replacement(context: TestContext) -> void:
	var session := GameSession.new()
	var sword: ItemDefinition = session.get_item_definition("training_sword")
	var swords: Array[ItemInstance] = session.inventory.add(sword, 2)
	context.check(session.inventory.equip(swords[0].instance_id) and session.hero.strength == 5, "First source applies its modifier")
	var charm: ItemDefinition = session.get_item_definition("moss_charm")
	session.hero.set_void_traces(2)
	var preview: Dictionary[String, int] = session.hero.preview_stats([swords[0].instance_id], charm.modifiers)
	context.check(preview["strength"] == 3 and preview["max_hp"] == 12, "Preview removes the source and applies the HP multiplier after adding gear")
	context.check(session.hero.strength == 5 and session.hero.max_hp == 9, "Preview leaves the live stats intact")
	session.hero.set_void_traces(0)
	context.check(session.inventory.equip(swords[1].instance_id) and session.hero.strength == 5, "Replacement removes only the old source")
	context.check(session.inventory.unequip("weapon") and session.hero.strength == 3, "Removing replacement leaves no foreign modifier")
	context.check(session.inventory.equip(swords[0].instance_id) and session.hero.strength == 5, "Earlier instance can be equipped again")
	context.check(session.inventory.remove(swords[0].instance_id) and session.hero.strength == 3, "Removing equipped item also removes its source")

func _test_session_transition(context: TestContext) -> void:
	var session := GameSession.new()
	var swords: Array[ItemInstance] = session.inventory.add(session.get_item_definition("training_sword"), 1)
	session.inventory.equip(swords[0].instance_id)
	session.select_encounter("goblin_scout")
	var combat := session.start_combat(session.current_enemy_id)
	context.check(session.inventory.items.size() == 1 and session.inventory.equipment.get("weapon") == swords[0].instance_id, "Starting another encounter preserves inventory and equipment")
	context.check(combat.hero.strength == 5 and combat.hero == session.hero, "Combat uses the session's derived stats")
