class_name GameSession
extends RefCounted

signal profile_changed

const ACTOR_PATHS: Dictionary = {
	"haruto": "res://data/actors/haruto.tres",
	"moss_slime": "res://data/actors/moss_slime.tres",
	"goblin_scout": "res://data/actors/goblin_scout.tres",
}
const ITEM_PATHS: Dictionary = {
	"training_sword": "res://data/items/training_sword.tres",
	"moss_charm": "res://data/items/moss_charm.tres",
	"echo_crystal": "res://data/items/echo_crystal.tres",
	"slime_residue": "res://data/items/slime_residue.tres",
}
const LOOT_PATHS: Dictionary = {
	"moss_slime": "res://data/loot/moss_slime.tres",
	"goblin_scout": "res://data/loot/goblin_scout.tres",
}

var hero: CharacterState
var inventory: InventoryService
var checkpoints: CheckpointService
var current_enemy_id: String = ""
var completed_encounter_ids: Dictionary = {}
var pending_reward: Array[Dictionary] = []
var item_definitions: Dictionary = {}
var loot_generator: LootGenerator
var loot_rng: RandomNumberGenerator
var loot_seed: String = "path_of_reborn_blockout"
var currency: int = 0
var echoes: int = 0
var claimed_echo_enemy_ids: Dictionary = {}
var quest_flags: Dictionary = {}
var npc_flags: Dictionary = {}
var world_flags: Dictionary = {}
var seen_cue_ids: Dictionary = {}
var memory_flags: Dictionary = {}
var adaptation_nodes: Dictionary = {}
var techniques: Dictionary = {}
var enemy_journal: Dictionary = {}
var traces: int = 0
var play_tick: int = 0
var location_id: String = "forest_edge"
var in_combat: bool = false
var is_pursued: bool = false
var is_moving: bool = false
var awaiting_return: bool = false
var _won_encounter_ids: Dictionary = {}

func _init() -> void:
	for item_id: String in ITEM_PATHS:
		item_definitions[item_id] = load(ITEM_PATHS[item_id])
	loot_generator = LootGenerator.new()
	loot_rng = RandomNumberGenerator.new()
	new_game()

func new_game() -> void:
	var hero_definition: ActorDefinition = load(ACTOR_PATHS["haruto"])
	hero = CharacterState.new(hero_definition)
	inventory = InventoryService.new(hero, item_definitions)
	current_enemy_id = ""
	completed_encounter_ids.clear()
	pending_reward.clear()
	_won_encounter_ids.clear()
	currency = 0
	echoes = 0
	claimed_echo_enemy_ids.clear()
	quest_flags.clear()
	npc_flags.clear()
	world_flags.clear()
	seen_cue_ids.clear()
	memory_flags.clear()
	adaptation_nodes.clear()
	techniques.clear()
	enemy_journal.clear()
	traces = 0
	play_tick = 0
	location_id = "forest_edge"
	in_combat = false
	is_pursued = false
	is_moving = false
	awaiting_return = false
	set_loot_seed("path_of_reborn_blockout")
	checkpoints = CheckpointService.new(self)
	checkpoints.initialize()
	profile_changed.emit()

func set_loot_seed(seed_value: String) -> void:
	loot_seed = seed_value
	loot_rng.seed = seed_value.to_int() if seed_value.is_valid_int() else seed_value.hash()

func select_encounter(enemy_id: String) -> bool:
	if not ACTOR_PATHS.has(enemy_id) or enemy_id == "haruto":
		return false
	current_enemy_id = enemy_id
	return true

func start_combat(enemy_id: String) -> CombatResolver:
	if not ACTOR_PATHS.has(enemy_id) or enemy_id == "haruto" or awaiting_return or traces == 3:
		return null
	current_enemy_id = enemy_id
	in_combat = true
	checkpoints.cancel()
	hero.restore_full_health()
	var enemy_definition: ActorDefinition = load(ACTOR_PATHS[enemy_id])
	var resolver := CombatResolver.new(hero, enemy_definition)
	resolver.finished.connect(_on_combat_finished.bind(enemy_id))
	return resolver

func retry_combat() -> CombatResolver:
	return start_combat(current_enemy_id)

func apply_victory(encounter_id: String) -> bool:
	if not _won_encounter_ids.has(encounter_id) or completed_encounter_ids.has(encounter_id):
		return false
	if not LOOT_PATHS.has(encounter_id):
		return false
	var enemy_definition: ActorDefinition = load(ACTOR_PATHS[encounter_id])
	var loot_table: LootTableDefinition = load(LOOT_PATHS[encounter_id])
	hero.gain_xp(enemy_definition.xp_reward)
	pending_reward = loot_generator.generate(loot_table, loot_rng)
	completed_encounter_ids[encounter_id] = true
	if not claimed_echo_enemy_ids.has(encounter_id):
		claimed_echo_enemy_ids[encounter_id] = true
		echoes += 1
	profile_changed.emit()
	return true

func claim_reward(equip_items: bool = false) -> bool:
	if pending_reward.is_empty():
		return false
	for reward: Dictionary in pending_reward:
		if get_item_definition(reward.get("item_id", "")) == null:
			return false
	for reward: Dictionary in pending_reward:
		var definition: ItemDefinition = get_item_definition(reward["item_id"])
		var affected: Array[ItemInstance] = inventory.add(
			definition,
			int(reward.get("quantity", 0)),
			String(reward.get("aspect_id", ""))
		)
		if equip_items:
			for item: ItemInstance in affected:
				if not definition.slot_id.is_empty():
					inventory.equip(item.instance_id)
	pending_reward.clear()
	profile_changed.emit()
	return true

func get_item_definition(item_id: String) -> ItemDefinition:
	return item_definitions.get(item_id)

func choose_upgrade(upgrade_id: String) -> bool:
	if not hero.choose_upgrade(upgrade_id):
		return false
	profile_changed.emit()
	return true

func apply_state_dto(dto: Dictionary) -> void:
	var meta: Dictionary = dto["meta"]
	traces = int(meta["traces"])
	apply_profile_dto(dto["profile"])
	echoes = int(meta["echoes"])
	claimed_echo_enemy_ids = meta["claimed_echo_enemy_ids"].duplicate(true)
	seen_cue_ids = meta["seen_cue_ids"].duplicate(true)
	memory_flags = meta["memory_flags"].duplicate(true)
	adaptation_nodes = meta["adaptation_nodes"].duplicate(true)
	techniques = meta["techniques"].duplicate(true)
	enemy_journal = meta["enemy_journal"].duplicate(true)
	location_id = String(dto["location_id"])
	current_enemy_id = String(dto["current_enemy_id"])
	pending_reward.assign(dto["pending_reward"].duplicate(true))
	set_loot_seed(String(dto["loot"]["seed"]))
	loot_rng.state = int(dto["loot"]["state"])
	awaiting_return = bool(dto["awaiting_return"])
	in_combat = false
	is_pursued = false
	is_moving = false
	checkpoints.apply_dto(dto["checkpoints"])
	profile_changed.emit()

func capture_profile_dto() -> Dictionary:
	return {
		"hero": hero.capture_dto(),
		"inventory": inventory.capture_dto(),
		"currency": currency,
		"quest_flags": quest_flags.duplicate(true),
		"npc_flags": npc_flags.duplicate(true),
		"world_flags": world_flags.duplicate(true),
		"completed_encounter_ids": completed_encounter_ids.duplicate(true),
		"play_tick": play_tick,
	}

func apply_profile_dto(dto: Dictionary) -> void:
	hero = CharacterState.new(load(ACTOR_PATHS["haruto"]))
	inventory = InventoryService.new(hero, item_definitions)
	inventory.apply_dto(dto.get("inventory", {}))
	hero.set_void_traces(traces)
	hero.apply_dto(dto.get("hero", {}))
	currency = maxi(0, int(dto.get("currency", 0)))
	quest_flags = dto.get("quest_flags", {}).duplicate(true)
	npc_flags = dto.get("npc_flags", {}).duplicate(true)
	world_flags = dto.get("world_flags", {}).duplicate(true)
	completed_encounter_ids = dto.get("completed_encounter_ids", {}).duplicate(true)
	play_tick = maxi(0, int(dto.get("play_tick", 0)))
	pending_reward.clear()
	_won_encounter_ids.clear()

func _on_combat_finished(won: bool, enemy_id: String) -> void:
	in_combat = false
	if won:
		_won_encounter_ids[enemy_id] = true
	else:
		awaiting_return = true
		profile_changed.emit()
