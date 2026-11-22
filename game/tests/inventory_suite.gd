extends RefCounted

const DomainSuite = preload("res://tests/domain_suite.gd")
const TestContext = DomainSuite.TestContext

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_run_case("item_and_loot_resources_are_valid", _test_resources))
	results.append(_run_case("seeded_loot_is_deterministic", _test_seed_determinism))
	results.append(_run_case("victory_reward_and_claim_are_idempotent", _test_reward_transaction))
	results.append(_run_case("route_loot_is_crystal_only_and_repeatable", _test_first_route_reward))
	results.append(_run_case("inventory_add_stack_remove_and_invalid_operations", _test_stacks))
	results.append(_run_case("inventory_filter_returns_requested_types", _test_filter))
	results.append(_run_case("equip_unequip_restores_stats_and_preserves_hp", _test_equip_stats))
	results.append(_run_case("replacement_uses_instance_source_ids", _test_replacement))
	results.append(_run_case("equipment_details_include_replacement_losses", _test_equipment_details))
	results.append(_run_case("inventory_and_equipment_survive_encounter_transition", _test_session_transition))
	results.append(_run_case("all_new_battle_loot_sources_are_crystal_only", _test_all_loot_sources))
	results.append(_run_case("daijiro_sword_is_story_gated_atomic_and_rollback_safe", _test_daijiro_story_gift))
	results.append(_run_case("familiar_ownership_assignment_and_upgrade_are_distinct", _test_familiars))
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
	context.check(not session.settle_combat("run_000001", "moss_slime"), "Settlement of an unknown run is refused")
	var combat := session.start_combat("moss_slime")
	context.check(combat != null, "Combat starts for the settlement fixture")
	context.check(session.inventory.items.size() == 1, "No loot before the terminal event")
	combat.enemy.current_hp = 1
	combat.advance_ticks(combat.hero.definition.attack_startup_ticks + 1)
	context.check(combat.is_finished and combat.won, "Fixture combat ends in victory")
	# Двухэтапный контракт: win создаёт durable pending, inventory и XP не тронуты.
	context.check(session.hero.level == 1 and session.inventory.items.size() == 1, "Win leaves inventory and XP untouched until claim")
	context.check(not session.pending_battle_result.is_empty(), "A durable pending result exists after the terminal event")
	var rng_state: String = String(session.pending_battle_result.get("loot_state", ""))
	context.check(session.settle_combat(combat.run_id, "moss_slime") == false, "Settling the same run twice is refused")
	context.check(String(session.pending_battle_result.get("loot_state", "")) == rng_state, "Viewing does not re-roll the fixed loot RNG")
	var result_id: String = String(session.pending_battle_result.get("result_id", ""))
	context.check(not session.claim_battle_result("someone_else_result"), "A foreign result id is refused")
	context.check(session.inventory.items.size() == 1, "Refused claim changes nothing")
	context.check(DomainSuite.claim_pending(session), "The matching pending result is claimed once")
	context.check(session.hero.level == 2, "Claimed XP reaches the hero exactly once")
	context.check(session.inventory.items.size() > 0, "Claim delivers the fixed loot into the inventory")
	context.check(session.pending_battle_result.is_empty(), "Pending is closed by the claim")
	context.check(not session.claim_battle_result(result_id), "A repeated claim of the same id is a no-op")
	context.check(session.inventory.items.size() > 0 and session.hero.level == 2 and session.echoes == 1, "Repeated claim duplicates nothing")
	# Экипировка посреди боя закрыта, а вне боя работает. Меч добавляем
	# явно: состав дропа слизи — не предмет теста.
	var swords: Array[ItemInstance] = session.inventory.add(session.get_item_definition("training_sword"), 1)
	context.check(not swords.is_empty() and session.inventory.equip(swords[0].instance_id), "Equip works outside combat")

func _test_first_route_reward(context: TestContext) -> void:
	var session := GameSession.new()
	session.set_loot_seed("33")
	var first := session.start_combat("moss_slime")
	first.enemy.current_hp = 1
	first.advance_ticks(first.hero.definition.attack_startup_ticks + 1)
	var loot_state_after_first: String = String(session.pending_battle_result.get("loot_state", ""))
	var first_items: Array = session.pending_battle_result.get("items", [])
	var crystal_only: bool = not first_items.is_empty()
	for item: Dictionary in first_items:
		crystal_only = crystal_only and item.get("item_id") == "echo_crystal"
	context.check(crystal_only, "First route victory and its clear reward contain only Echo Crystals")
	context.check(session.inventory.items.size() == 1, "Rolled crystals still wait for the explicit claim")
	context.check(DomainSuite.claim_pending(session), "Crystal loot claims through the existing transaction")
	var weapons: Array[ItemInstance] = session.inventory.filter("weapon")
	context.check(weapons.size() == 1 and weapons[0].definition_id == "broken_wanderer_branch", "The first clear grants no hidden sword and keeps the starting branch")
	session.select_encounter("moss_slime")
	var repeat := session.start_combat("moss_slime", true)
	repeat.enemy.current_hp = 1
	repeat.advance_ticks(repeat.hero.definition.attack_startup_ticks + 1)
	var control := GameSession.new()
	control.route_state["next_index"] = 1
	control.set_loot_seed("33")
	control.loot_rng.state = int(loot_state_after_first)
	var control_repeat := control.start_combat("moss_slime", true)
	control_repeat.enemy.current_hp = 1
	control_repeat.advance_ticks(control_repeat.hero.definition.attack_startup_ticks + 1)
	context.check(session.pending_battle_result.get("items", []) == control.pending_battle_result.get("items", []), "A repeat exactly matches the control random roll without a first-clear addition")

func _test_stacks(context: TestContext) -> void:
	var session := GameSession.new()
	var echo: ItemDefinition = session.get_item_definition("echo_crystal")
	var first: Array[ItemInstance] = session.inventory.add(echo, 3, "moss")
	var second: Array[ItemInstance] = session.inventory.add(echo, 2, "moss")
	context.check(session.inventory.items.size() == 2 and first[0] == second[0], "Matching stackable items share an instance")
	context.check(first[0].quantity == 5 and not first[0].instance_id.is_empty(), "Stack quantity and serial ID are stable")
	context.check(session.inventory.remove(first[0].instance_id, 2) and first[0].quantity == 3, "Partial remove decreases the stack")
	context.check(not session.inventory.remove(first[0].instance_id, 4) and first[0].quantity == 3, "Oversized remove is refused without partial mutation")
	context.check(session.inventory.remove(first[0].instance_id, 3) and session.inventory.items.size() == 1, "Removing the full stack releases its instance")
	var sword: ItemDefinition = session.get_item_definition("training_sword")
	session.inventory.add(sword, 2)
	context.check(session.inventory.items.size() == 3, "Non-stackable equipment gets separate instances")
	context.check(session.inventory.items[0].instance_id != session.inventory.items[1].instance_id, "Equipment instance IDs are unique")
	context.check(session.inventory.add(sword, 0).is_empty(), "Non-positive add is refused")

func _test_filter(context: TestContext) -> void:
	var session := GameSession.new()
	session.inventory.add(session.get_item_definition("training_sword"), 1)
	session.inventory.add(session.get_item_definition("moss_charm"), 1)
	session.inventory.add(session.get_item_definition("echo_crystal"), 1, "moss")
	context.check(session.inventory.filter().size() == 4, "Empty filter returns every item")
	context.check(session.inventory.filter("weapon").size() == 2, "Weapon filter excludes other types")
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

func _test_equipment_details(context: TestContext) -> void:
	var session := GameSession.new()
	var empty: Dictionary = EquipmentModel.slot(session, "ring")
	context.check(empty["item"] == null and empty["slot_label"] == "Кольцо", "Empty equipment slot has a stable accessible model")
	var swords: Array[ItemInstance] = session.inventory.add(session.get_item_definition("training_sword"), 2)
	var charms: Array[ItemInstance] = session.inventory.add(session.get_item_definition("moss_charm"), 1)
	context.check(session.equip_item(swords[0].instance_id) and session.equip_item(charms[0].instance_id), "Both supported slots can be occupied through the session")
	var equipped: Dictionary = EquipmentModel.for_instance(session, swords[0].instance_id)
	context.check(equipped["equipped"] and equipped["same_item"] and equipped["deltas"].is_empty(), "Selected equipment does not double its own modifiers")
	context.check(equipped["bonuses"].size() == 1 and int(equipped["bonuses"][0]["amount"]) == 2, "Selected equipment reports its actual bonus")
	var second: Dictionary = EquipmentModel.for_instance(session, swords[1].instance_id)
	context.check(second["current_instance_id"] == swords[0].instance_id and second["instance_id"] == swords[1].instance_id, "Identical equipment instances remain distinct in comparison")
	var plain_charm := ItemDefinition.new()
	plain_charm.id = "plain_charm_fixture"
	plain_charm.display_name = "Пустой оберег"
	plain_charm.type_id = "charm"
	plain_charm.slot_id = "charm"
	session.item_definitions[plain_charm.id] = plain_charm
	var replacement: Dictionary = EquipmentModel.for_reward(session, plain_charm.id, "")
	context.check(replacement["deltas"].size() == 1, "Candidate without the old modifier still produces a loss")
	context.check(replacement["deltas"][0]["stat_id"] == "max_hp" and int(replacement["deltas"][0]["before"]) == 16 and int(replacement["deltas"][0]["after"]) == 12, "Delta includes stats removed with the previous item")
	context.check(session.equip_item(swords[1].instance_id) and session.inventory.equipment["weapon"] == swords[1].instance_id, "Replacement changes exactly the selected instance")
	context.check(session.unequip_item("charm") and EquipmentModel.slot(session, "charm")["item"] == null, "Unequip returns the slot model to empty")
	var restored := GameSession.new()
	restored.apply_state_dto(SaveService.new().capture(session))
	context.check(EquipmentModel.slot(restored, "weapon")["instance_id"] == swords[1].instance_id and EquipmentModel.slot(restored, "charm")["item"] == null, "Equipment models follow restored source IDs")

func _test_session_transition(context: TestContext) -> void:
	var session := GameSession.new()
	var swords: Array[ItemInstance] = session.inventory.add(session.get_item_definition("training_sword"), 1)
	session.inventory.equip(swords[0].instance_id)
	session.route_state["next_index"] = 2
	session.select_encounter("goblin_scout")
	var combat := session.start_combat(session.current_enemy_id)
	context.check(session.inventory.items.size() == 2 and session.inventory.equipment.get("weapon") == swords[0].instance_id, "Starting another encounter preserves inventory and equipment")
	context.check(combat.hero.strength == 5 and combat.hero == session.hero, "Combat uses the session's derived stats")


func _test_all_loot_sources(context: TestContext) -> void:
	for enemy_id: String in ["moss_slime", "goblin_scout"]:
		var table: LootTableDefinition = load(GameSession.LOOT_PATHS[enemy_id])
		var crystal_table: bool = not table.entries.is_empty()
		for entry: LootEntryDefinition in table.entries:
			crystal_table = crystal_table and entry.item_id == "echo_crystal"
		context.check(crystal_table, "%s loot table contains only Echo Crystals" % enemy_id)
	for node: Dictionary in GameSession.route_definition().get("nodes", []):
		var clear_crystals: bool = true
		for reward: Dictionary in node.get("first_clear_rewards", []):
			clear_crystals = clear_crystals and reward.get("item_id") == "echo_crystal"
		context.check(clear_crystals, "%s first clear has no equipment or non-crystal reward" % node.get("node_id", ""))
	var session := GameSession.new()
	for encounter: String in ["moss_slime", "moss_slime", "goblin_scout", "goblin_scout", GameSession.TRIAL_ENEMY_ID]:
		context.check(session.select_encounter(encounter), "Encounter selection is legal: %s" % encounter)
		var resolver: CombatResolver = session.start_combat(encounter)
		resolver.enemy.current_hp = 1
		resolver.advance_ticks(resolver.hero.definition.attack_startup_ticks + 1)
		var crystal_only: bool = not session.pending_battle_result.is_empty()
		for entry: Dictionary in session.pending_battle_result.get("items", []):
			crystal_only = crystal_only and entry.get("item_id") == "echo_crystal"
		context.check(resolver.won and crystal_only and DomainSuite.claim_pending(session), "Route/repeat/trial pays only crystals: %s" % encounter)
		for item: ItemInstance in session.inventory.items:
			context.check(item.definition_id != "training_sword", "No monster encounter grants the story sword: %s" % encounter)


func _test_daijiro_story_gift(context: TestContext) -> void:
	var session := GameSession.new()
	context.check(not session.prepare_daijiro_sword_reward(), "No sword is prepared before Daijiro's intervention")
	session.world_flags["daijiro_intervened"] = true
	session.world_flags["daijiro_scout_defeated"] = true
	context.check(not session.prepare_daijiro_sword_reward(), "A scout win alone does not prepare the sword")
	session.world_flags["daijiro_introduction_completed"] = true
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.checkpoints.apply_completion()
	context.check(session.prepare_daijiro_sword_reward(), "Intervention, the story win and completed introduction prepare the gift")
	context.check(session.inventory.filter("weapon").size() == 1 and not session.story_rewards.has(GameSession.DAIJIRO_SWORD_REWARD_ID), "Preparing the card grants neither item nor reward flag")
	context.check(session.choose_story_reward("daijiro_sword_01", "equip") and session.claim_story_reward(GameSession.DAIJIRO_SWORD_REWARD_ID), "The explicit card choice claims the gift atomically")
	var weapons: Array[ItemInstance] = session.inventory.filter("weapon")
	context.check(weapons.size() == 2 and session.story_rewards.has(GameSession.DAIJIRO_SWORD_REWARD_ID), "The gift adds exactly one sword while the branch stays in the backpack")
	context.check(EquipmentModel.slot(session, "weapon")["definition"].id == "training_sword", "The chosen equip action equips the gifted sword")
	context.check(not session.prepare_daijiro_sword_reward() and not session.claim_story_reward(GameSession.DAIJIRO_SWORD_REWARD_ID), "Reopening the completed conversation cannot duplicate the gift")
	var restored := GameSession.new()
	restored.apply_state_dto(SaveService.new().capture(session))
	context.check(restored.inventory.filter("weapon").size() == 2 and not restored.prepare_daijiro_sword_reward(), "Restart preserves the reward flag and prevents a duplicate")
	var combat: CombatResolver = session.start_combat("moss_slime")
	session.abandon_combat()
	context.check(combat != null and session.checkpoints.restore(), "A confirmed return can roll back the post-gift state")
	context.check(not session.story_rewards.has(GameSession.DAIJIRO_SWORD_REWARD_ID) and session.inventory.filter("weapon").size() == 1, "Checkpoint rolls back the sword and its reward flag together")
	context.check(EquipmentModel.slot(session, "weapon")["definition"].id == "broken_wanderer_branch", "Rollback consistently restores the branch as the equipped weapon")


func _test_familiars(context: TestContext) -> void:
	var session := GameSession.new()
	context.check(session.available_character_ids() == ["haruto"] and session.familiars["owned"].is_empty() and session.assigned_familiar("haruto") == null, "The initial profile has no companions or familiars")
	context.check(session.grant_familiar("moss_sprite") and session.grant_familiar("ember_sprite"), "Two data-driven familiars can be acquired by a prepared scenario")
	context.check(session.assign_familiar("haruto", "moss_sprite") and session.hero.max_hp == 13 and session.hero.strength == 3, "Assigning Moss Spirit applies its modifier once")
	context.check(session.assign_familiar("haruto", "moss_sprite") and session.hero.max_hp == 13 and session.familiar_level("moss_sprite") == 1, "Repeated assignment neither stacks modifiers nor levels the familiar")
	context.check(session.assign_familiar("haruto", "ember_sprite") and session.hero.strength == 4 and session.hero.max_hp == 12, "Switching to Ember Spirit replaces the previous modifier")
	context.check(not session.upgrade_familiar("haruto") and session.familiar_level("ember_sprite") == 1, "Haruto's selection action grants no free familiar level")
	context.check(not session.assign_familiar("haruto", "warden_fox"), "A companion-bound familiar cannot be assigned to Haruto")
	session.world_flags["road_companion_joined"] = true
	var companion: CharacterState = session.character_state("road_companion")
	context.check(companion != null and companion.defense == 3 and session.familiar_level("warden_fox") == 1, "The companion's bound familiar applies its base modifier on first synchronization")
	context.check(session.upgrade_familiar("road_companion") and session.familiar_level("warden_fox") == 2 and companion.defense == 4, "Only the bound companion familiar gains the development level and modifier")
	context.check(not session.assign_familiar("road_companion", "ember_sprite") and companion.defense == 4, "The companion cannot take Haruto's unbound familiar")
	var restored := GameSession.new()
	restored.apply_state_dto(SaveService.new().capture(session))
	context.check(restored.assigned_familiar("haruto").id == "ember_sprite" and restored.hero.strength == 4, "Haruto's ownership and assignment survive save/load")
	context.check(restored.familiar_level("warden_fox") == 2 and restored.character_state("road_companion").defense == 4, "The companion's familiar level and modifier survive save/load")
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.checkpoints.apply_completion()
	session.assign_familiar("haruto", "moss_sprite")
	session.start_combat("moss_slime")
	session.abandon_combat()
	context.check(session.checkpoints.restore() and session.assigned_familiar("haruto").id == "ember_sprite" and session.hero.strength == 4, "Checkpoint restores assignment and derived modifiers together")
