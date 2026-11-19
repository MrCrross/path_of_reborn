extends RefCounted

const ACTOR_PATHS: Array[String] = [
	"res://data/actors/haruto.tres",
	"res://data/actors/moss_slime.tres",
	"res://data/actors/goblin_scout.tres",
]

class TestContext:
	extends RefCounted

	var checks: Array[Dictionary] = []

	func check(condition: bool, message: String) -> void:
		checks.append({"passed": condition, "message": message})

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
	results.append(_run_case("damage_formula_and_minimum", _test_damage_formula))
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
		context.check(hero.xp_thresholds == [4, 8, 12], "Haruto uses the blockout XP table")

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
	multiple.gain_xp(12)
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
