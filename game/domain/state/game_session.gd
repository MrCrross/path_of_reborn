class_name GameSession
extends RefCounted

signal profile_changed
signal combat_format_changed(format: String)
signal auto_speed_changed(speed: int)
signal auto_ability_changed(enabled: bool)
signal battle_result_claimed(result: Dictionary)
signal story_reward_claimed(result: Dictionary)

const COMBAT_FORMAT_AUTO: String = "auto"
const COMBAT_FORMAT_ACTIVE: String = "active"
const TRIAL_ENEMY_ID: String = "goblin_trial"
const DAIJIRO_SWORD_REWARD_ID: String = "daijiro_first_training_sword"
## Испытание — добровольный технический вариант после учебного участка:
## тот же approved art гоблина (actor ID отдельно, presentation общий).
const ENCOUNTER_ROUTE: String = "route"
const ENCOUNTER_REPEAT: String = "repeat"
const ENCOUNTER_TRIAL: String = "trial"
const ENCOUNTER_GROVE: String = "grove"
const ENCOUNTER_HOLLOW: String = "hollow"
const ENCOUNTER_OUTPOST: String = "outpost"
const ENCOUNTER_GUILD_ORDER := "guild_order"
const LOCATION_GUILD_ORDER := "guild_order"
const LOCATION_GROVE: String = "whispering_grass_grove"
const LOCATION_HOLLOW: String = "blue_hollow"
const LOCATION_OUTPOST: String = "winds_edge"
const EXPEDITION_LOCATIONS: Array[String] = [LOCATION_GROVE, LOCATION_HOLLOW, LOCATION_OUTPOST]
const EXPEDITION_ROUTES: Dictionary = {
	ENCOUNTER_GROVE: LOCATION_GROVE,
	ENCOUNTER_HOLLOW: LOCATION_HOLLOW,
	ENCOUNTER_OUTPOST: LOCATION_OUTPOST,
}
const OUTPOST_NARRATIVE_PATH: String = "res://data/narrative/winds_edge.json"
const OUTPOST_ORDER_CUE: String = "DIA_OUTPOST_ORDER"
const OUTPOST_BOWL: String = "outpost_bowl_checked"
const OUTPOST_SEAL: String = "outpost_seal_triggered"
const OUTPOST_RAVENS_WON: String = "outpost_ravens_won"
const OUTPOST_WARDEN_WON: String = "outpost_warden_won"
const OUTPOST_ALLIANCE: String = "outpost_alliance"
const OUTPOST_REPORTED: String = "outpost_reported"
const OUTPOST_FINISHED: String = "outpost_finished"
const OUTPOST_ECHOES_GRANTED: String = "outpost_report_echoes"
const HOLLOW_NARRATIVE_PATH: String = "res://data/narrative/blue_hollow.json"
const HOLLOW_WATER_MARKER: String = "hollow_water_marker"
const HOLLOW_STARTED: String = "hollow_started"
const HOLLOW_UPPER_MARKER: String = "hollow_upper_marker"
const HOLLOW_COLLAPSED: String = "hollow_shelf_collapsed"
const HOLLOW_TEMPO: String = "hollow_tempo_unlocked"
const HOLLOW_LEVEL_FOUR: String = "hollow_reached_level_four"
const HOLLOW_CLOTH: String = "hollow_cloth_found"
const HOLLOW_REPORTED: String = "hollow_reported"
const HOLLOW_ECHOES_GRANTED: String = "hollow_report_echoes"
const HOLLOW_ELITE_ENTERED: String = "hollow_elite_entered"
const HOLLOW_ELITE_WON: String = "hollow_elite_won"
const HOLLOW_RETREATED: String = "hollow_retreated"
const HOLLOW_SHIELDBACK_WON: String = "hollow_shieldback_won"
const HOLLOW_SHELF_WON: String = "hollow_shelf_won"
const GROVE_ROUTE_PATH: String = "res://data/route/whispering_grass_grove.json"
const GROVE_NARRATIVE_PATH: String = "res://data/narrative/whispering_grass_grove.json"
const GROVE_BANDAGE: String = "moon_flax_bandage"
const GROVE_HOUNDS_WON: String = "grove_hounds_won"
const GROVE_POLLEN_WON: String = "grove_pollen_won"
const GROVE_FLAX: String = "grove_flax"
const GROVE_MARKER: String = "grove_marker"
const GROVE_REPORTED: String = "grove_reported"
const GROVE_SEALED: String = "grove_sealed"
const GROVE_DECLINED_SEAL: String = "grove_left_without_point"
const GROVE_LEVEL_THREE: String = "grove_reached_level_three"
const GROVE_ECHOES_GRANTED: String = "grove_report_echoes"
const GROVE_KENTA_CHOICES: Array[String] = ["grove_kenta_safe", "grove_kenta_hint", "grove_kenta_bandage"]

const ACTOR_PATHS: Dictionary = {
	"haruto": "res://data/actors/haruto.tres",
	"moss_slime": "res://data/actors/moss_slime.tres",
	"goblin_scout": "res://data/actors/goblin_scout.tres",
	TRIAL_ENEMY_ID: "res://data/actors/goblin_trial.tres",
	"needle_hound": "res://data/actors/needle_hound.tres",
	"dust_moth": "res://data/actors/dust_moth.tres",
	"root_weaver": "res://data/actors/root_weaver.tres",
	"river_shieldback": "res://data/actors/river_shieldback.tres",
	"stone_rodent": "res://data/actors/stone_rodent.tres",
	"ash_raven": "res://data/actors/ash_raven.tres",
	"crystal_toad": "res://data/actors/crystal_toad.tres",
	"bone_warden": "res://data/actors/bone_warden.tres",
}
const COMPANION_ACTOR_PATHS: Dictionary = {
	"road_companion": "res://data/actors/road_companion.tres",
}
const FAMILIAR_PATHS: Dictionary = {
	"moss_sprite": "res://data/familiars/moss_sprite.tres",
	"ember_sprite": "res://data/familiars/ember_sprite.tres",
	"warden_fox": "res://data/familiars/warden_fox.tres",
}
const ITEM_PATHS: Dictionary = {
	"broken_wanderer_branch": "res://data/items/broken_wanderer_branch.tres",
	"training_sword": "res://data/items/training_sword.tres",
	"moss_charm": "res://data/items/moss_charm.tres",
	"echo_crystal": "res://data/items/echo_crystal.tres",
	"slime_residue": "res://data/items/slime_residue.tres",
	"wanderer_jacket": "res://data/items/wanderer_jacket.tres",
	GROVE_BANDAGE: "res://data/items/moon_flax_bandage.tres",
	"needle_hound_quills": "res://data/items/needle_hound_quills.tres",
	"moth_pollen_jar": "res://data/items/moth_pollen_jar.tres",
	"river_shieldback_shell": "res://data/items/river_shieldback_shell.tres",
	"old_masonry_shard": "res://data/items/old_masonry_shard.tres",
	"old_watch_badge": "res://data/items/old_watch_badge.tres",
	"shoma_key_fragment": "res://data/items/shoma_key_fragment.tres",
}
const LOCATION_FOREST_EDGE: String = "forest_edge"
const LOCATION_LIOREN: String = "lioren"
const MAP_SHOP: String = "shop"
const MAP_GUILD: String = "guild"
const MAP_HOLLOW_BASIN: String = "hollow_basin"
const MAP_HOLLOW_LEDGE: String = "hollow_ledge"
const MAP_WORLD_LOCATIONS: Array[String] = [LOCATION_FOREST_EDGE, LOCATION_LIOREN, LOCATION_GROVE, LOCATION_HOLLOW, LOCATION_OUTPOST]
const MAP_CITY_LOCATIONS: Array[String] = [MAP_SHOP, MAP_GUILD]
const MAP_VISIT_PREFIX: String = "map_visited_"
const SHOP_CATALOG_PATH: String = "res://data/shop/cricket_twilight.json"
## Доступ к лавке открывает сцена ворот Лиорена; живёт в world_flags профиля,
## поэтому откатывается Печатью вместе с кошельком и инвентарём.
const WORLD_FLAG_LIOREN_SHOP_UNLOCKED: String = "lioren_shop_unlocked"
const MAX_ASTRAS := 9223372036854775807
const COPPER := "copper"
const SILVER := "silver"
const GOLD := "gold"
const COIN_TYPES: Array[String] = [COPPER, SILVER, GOLD]
const EXCHANGE_RATE: int = 100
const WORLD_FLAG_SHOP_INTRO_DONE: String = "shop_intro_done"
const WORLD_FLAG_SHOP_FIRST_SALE_DONE: String = "shop_first_sale_done"
const WORLD_FLAG_SHOP_FIRST_PURCHASE_DONE: String = "shop_first_purchase_done"
const WORLD_FLAG_SHOP_PURCHASE_BRIEFING_DONE: String = "shop_purchase_briefing_done"
const WORLD_FLAG_WANDERER_JACKET_PURCHASED: String = "wanderer_jacket_purchased"
const FIRST_GUILD_ORDER_ID: String = "guild_moon_flax"
const GUILD_LAST_CUE_ID: String = "DIA_GUILD_035"
const WORLD_FLAG_GUILD_VISIT: String = "guild_visit_active"
const WORLD_FLAG_GUILD_REGISTERED: String = "guild_registered"
const LOOT_PATHS: Dictionary = {
	"moss_slime": "res://data/loot/moss_slime.tres",
	"goblin_scout": "res://data/loot/goblin_scout.tres",
	# Испытание переиспользует обычную таблицу добычи гоблина (осознанное решение).
	TRIAL_ENEMY_ID: "res://data/loot/goblin_scout.tres",
}
const ROUTE_PATH: String = "res://data/route/forest_slice.json"

static var _route_definition_cache: Dictionary = {}
static var _grove_definition_cache: Dictionary = {}
static var _hollow_definition_cache: Dictionary = {}
static var _outpost_definition_cache: Dictionary = {}

var hero: CharacterState
var inventory: InventoryService
var checkpoints: CheckpointService
var current_enemy_id: String = ""
## Маршрут продвижения технического slice: {"route_id", "next_index", "completed"}.
## Данные узлов — в data/route/*.json; UI спрашивает у сессии, не считает сам.
var route_state: Dictionary = {}
## Монотонный счётчик попыток боя; сериализуется, откатывается с профилем.
var run_sequence: int = 0
## Устарело: с v3 награда живёт в pending_battle_result до получения. Поле
## остаётся только ради доставки legacy-сейвов v0/v1 и удалится с миграцией.
var pending_reward: Array[Dictionary] = []
## Durable результат выигранного, но ещё не полученного боя. RNG брошен один раз
## при создании; предметы попадают в inventory только через claim_battle_result.
var pending_battle_result: Dictionary = {}
var pending_story_reward: Dictionary = {}
## ID последнего принятого результата: повторный claim того же ID — no-op.
var last_claimed_result_id: String = ""
## Разовый визуальный эффект получения награды; не сериализуется, потребляется экраном Inventory.
var pending_receive_fx: bool = false
## Итог последнего claim'а для presentation; не сериализуется.
var last_settlement: Dictionary = {}
## Итог последней сделки лавки (kind/quantity/total/balance_after); не сериализуется.
var last_deal: Dictionary = {}
## Формат боя: полный auto (по умолчанию) или active (ручные атака и уклонение).
## Живёт вне откатываемого Checkpoint-профиля: переживает relaunch, новую игру и возвраты.
var combat_format: String = COMBAT_FORMAT_AUTO
var auto_speed: int = 1
var auto_ability: bool = true
var item_definitions: Dictionary = {}
var loot_generator: LootGenerator
var loot_rng: RandomNumberGenerator
var loot_seed: String = "path_of_reborn_blockout"
var wallet: Dictionary[String, int] = {COPPER: 0, SILVER: 0, GOLD: 0}
var echoes: int = 0
var claimed_echo_enemy_ids: Dictionary = {}
## Разовая meta-награда испытания; живёт вне откатываемого профиля Checkpoint,
## как и начисленное Эхо. Первый trial суммарно даёт +2, повтор после возврата +0.
var trial_echo_claimed: bool = false
var quest_flags: Dictionary = {}
var guild_order: Dictionary = {}
var npc_flags: Dictionary = {}
var world_flags: Dictionary = {}
var characters: Dictionary = {}
var familiars: Dictionary = {"owned": {}, "assignments": {}}
var story_rewards: Dictionary = {}
var seen_cue_ids: Dictionary = {}
var memory_flags: Dictionary = {}
var adaptation_nodes: Dictionary = {}
var techniques: Dictionary = {}
var enemy_journal: Dictionary = {}
var traces: int = 0
var play_tick: int = 0
var location_id: String = "forest_edge"
var in_combat: bool = false
var active_resolver: CombatResolver
var active_encounter_context: Dictionary = {}
var _selected_repeat: bool = false
var _run_token_sequence: int = 0
var _claim_in_progress: bool = false
var is_pursued: bool = false
var is_moving: bool = false
var awaiting_return: bool = false
## Глубина доменной транзакции (claim). Пока транзакция активна, GameRoot
## не сохраняет промежуточные состояния по внутренним inventory.changed.
var _transaction_depth: int = 0
## Settlement только за время жизни процесса: terminal event resolver'а
## испускается один раз, поэтому персистить ledger не нужно; при rollback
## счётчик run_sequence восстанавливается из профиля, незавершённых боёв нет.
var _settled_run_ids: Dictionary = {}
## Run, дошедшие до terminal event, и их исход: создание pending допустимо только
## для выигранного завершённого run — не раньше terminal event'а.
var _finished_run_contexts: Dictionary = {}
## «Когда-либо побеждён» — журнальная запись; определение маршрута она не делает.
var _beaten_encounter_ids: Dictionary = {}


func _init() -> void:
	for item_id: String in ITEM_PATHS:
		item_definitions[item_id] = load(ITEM_PATHS[item_id])
	loot_generator = LootGenerator.new()
	loot_rng = RandomNumberGenerator.new()
	new_game()

func new_game() -> void:
	_invalidate_active_resolver()
	_selected_repeat = false
	var hero_definition: ActorDefinition = load(ACTOR_PATHS["haruto"])
	hero = CharacterState.new(hero_definition)
	inventory = InventoryService.new(hero, item_definitions)
	var branch: Array[ItemInstance] = inventory.add(get_item_definition("broken_wanderer_branch"), 1)
	inventory.equip(branch[0].instance_id)
	current_enemy_id = ""
	route_state = _initial_route_state()
	run_sequence = 0
	_beaten_encounter_ids.clear()
	_settled_run_ids.clear()
	_finished_run_contexts.clear()
	pending_reward.clear()
	pending_battle_result = {}
	pending_story_reward = {}
	last_claimed_result_id = ""
	pending_receive_fx = false
	last_settlement = {}
	last_deal = {}
	wallet = {COPPER: 0, SILVER: 0, GOLD: 0}
	echoes = 0
	claimed_echo_enemy_ids.clear()
	trial_echo_claimed = false
	quest_flags.clear()
	guild_order.clear()
	npc_flags.clear()
	world_flags.clear()
	characters.clear()
	familiars = {"owned": {}, "assignments": {}}
	story_rewards.clear()
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
	# combat_format сознательно не сбрасывается: предпочтение переживает новую игру.
	set_loot_seed("path_of_reborn_blockout")
	checkpoints = CheckpointService.new(self)
	checkpoints.initialize()
	profile_changed.emit()

## Граница «пролог завершён, путь начался»: снимок «Первый след» фиксирует
## профиль уже с story-флагами пролога, чтобы возврат не отправлял Continue
## обратно в катсцену (route_for_continue смотрит prologue_completed).
func mark_path_started() -> void:
	if not world_flags.get("prologue_completed", false):
		return
	checkpoints.refresh_first_trace()

func set_loot_seed(seed_value: String) -> void:
	loot_seed = seed_value
	loot_rng.seed = seed_value.to_int() if seed_value.is_valid_int() else seed_value.hash()

## Публичная команда выбора встречи. Легальна только вне боя и без ожидающего
## результата; UI не может «выбрать» врага посреди боя или поверх pending.
func select_encounter(enemy_id: String, repeat: bool = false) -> bool:
	if in_combat or has_pending_reward() or awaiting_return or _claim_in_progress:
		return false
	if _encounter_context_for(enemy_id, repeat).is_empty():
		return false
	current_enemy_id = enemy_id
	_selected_repeat = repeat
	return true

func start_selected_combat() -> CombatResolver:
	return start_combat(current_enemy_id, _selected_repeat)

func select_random_repeat_encounter() -> bool:
	var candidates: Array[String] = route_repeat_enemy_ids()
	if candidates.is_empty():
		return false
	return select_encounter(candidates.pick_random(), true)

## Полное лечение перед боем — осознанная семантика slice (фиксация в доке);
## менять её отдельной задачей с балансом.
func start_combat(enemy_id: String, repeat: bool = false) -> CombatResolver:
	if in_combat or active_resolver != null or has_pending_reward() or awaiting_return or _claim_in_progress:
		return null
	var context: Dictionary = _encounter_context_for(enemy_id, repeat)
	if traces == 3 or context.is_empty():
		return null
	_invalidate_active_resolver()
	_selected_repeat = false
	current_enemy_id = enemy_id
	in_combat = true
	checkpoints.cancel()
	hero.restore_full_health()
	run_sequence += 1
	_run_token_sequence += 1
	var run_id: String = "run_%06d" % run_sequence
	context["run_id"] = run_id
	context["run_token"] = "attempt_%d" % _run_token_sequence
	context["combat_format"] = combat_format
	context["auto_speed"] = auto_speed if combat_format == COMBAT_FORMAT_AUTO else 1
	var enemy_definition: ActorDefinition = load(ACTOR_PATHS[enemy_id])
	var encounter: Dictionary = expedition_battle_node(context)
	var slots: Array = encounter.get("enemies", [])
	var first: Dictionary = slots[0].duplicate() if not slots.is_empty() else {}
	if context["encounter_mode"] == ENCOUNTER_GUILD_ORDER:
		enemy_definition = enemy_definition.duplicate()
		enemy_definition.max_hp = int(encounter["hp"])
		enemy_definition.strength = int(encounter["strength"])
	if context["encounter_mode"] == ENCOUNTER_REPEAT:
		var repeat_settings: Dictionary = route_definition()["repeat_enemies"][enemy_id]
		enemy_definition = _scaled_repeat_enemy(enemy_definition, int(repeat_settings["level"]))
		first["pollen_slow_ticks"] = int(repeat_settings.get("pollen_slow_ticks", 0))
	if encounter.has("noise_offset") and quest_flags.get("grove_noise", false):
		first["telegraph_offset"] = int(encounter["noise_offset"])
	if encounter.has("collapse_stun_ticks") and quest_flags.get(HOLLOW_COLLAPSED, false):
		first["initial_stun_ticks"] = int(encounter["collapse_stun_ticks"])
	var resolver := CombatResolver.new(hero, enemy_definition, run_id, first)
	for index: int in range(1, slots.size()):
		var slot: Dictionary = slots[index]
		var definition: ActorDefinition = load(ACTOR_PATHS[slot["actor_id"]])
		resolver.add_encounter_enemy(definition, slot)
	resolver.warden_pattern = encounter.get("warden_pattern", {})
	resolver.ally_warnings = PackedInt32Array(encounter.get("ally_warning_ticks", []))
	if quest_flags.get(GROVE_REPORTED, false):
		resolver.vulnerable_ability_bonus = float(grove_definition()["report"]["vulnerable_ability_multiplier"])
	if quest_flags.get(HOLLOW_TEMPO, false):
		var tempo: Dictionary = hollow_definition()["tempo"]
		resolver.tempo_window_ticks = int(tempo["window_ticks"])
		resolver.tempo_startup_reduction = int(tempo["startup_reduction"])
	resolver.run_token = context["run_token"]
	resolver.combat_format = combat_format
	resolver.auto_attack_enabled = combat_format == COMBAT_FORMAT_AUTO
	resolver.auto_ability_enabled = resolver.auto_attack_enabled and auto_ability
	resolver.auto_dodge_enabled = combat_format == COMBAT_FORMAT_AUTO
	active_resolver = resolver
	active_encounter_context = context.duplicate(true)
	resolver.finished.connect(_on_combat_finished.bind(resolver))
	return resolver

func retry_combat() -> CombatResolver:
	if not in_combat or active_resolver == null or not pending_battle_result.is_empty() or awaiting_return:
		return null
	var enemy_id: String = String(active_encounter_context.get("enemy_id", current_enemy_id))
	var repeat: bool = active_encounter_context.get("encounter_mode", "") == ENCOUNTER_REPEAT
	_invalidate_active_resolver()
	in_combat = false
	return start_combat(enemy_id, repeat)

## --- Формат боя ---

## Смена формата применяется со следующего боя; текущий resolver не трогаем
## (его cooldown/замах сохраняются до конца встречи).
func set_combat_format(format: String) -> bool:
	if format != COMBAT_FORMAT_AUTO and format != COMBAT_FORMAT_ACTIVE:
		return false
	if combat_format == format:
		return true
	combat_format = format
	combat_format_changed.emit(format)
	profile_changed.emit()
	return true

func set_auto_speed(speed: int) -> bool:
	if speed not in [1, 2]:
		return false
	if auto_speed == speed:
		return true
	auto_speed = speed
	auto_speed_changed.emit(speed)
	return true

func set_auto_ability(enabled: bool) -> void:
	if auto_ability != enabled:
		auto_ability = enabled
		auto_ability_changed.emit(enabled)

func combat_format_label() -> String:
	return "Автобой" if combat_format == COMBAT_FORMAT_AUTO else "Ручной бой"

func available_character_ids() -> Array[String]:
	var result: Array[String] = ["haruto"]
	for character_id: String in COMPANION_ACTOR_PATHS:
		if world_flags.get(character_id + "_joined", false):
			result.append(character_id)
	return result

func character_state(character_id: String = "haruto") -> CharacterState:
	if character_id == "haruto":
		return hero
	if not available_character_ids().has(character_id):
		return null
	_sync_companion(character_id)
	return characters.get(character_id)

func familiar_definition(familiar_id: String) -> FamiliarDefinition:
	return load(FAMILIAR_PATHS[familiar_id]) if FAMILIAR_PATHS.has(familiar_id) else null

func familiar_level(familiar_id: String) -> int:
	return int(familiars.get("owned", {}).get(familiar_id, 0))

func assigned_familiar(character_id: String) -> FamiliarDefinition:
	return familiar_definition(String(familiars.get("assignments", {}).get(character_id, "")))

func grant_familiar(familiar_id: String) -> bool:
	var definition: FamiliarDefinition = familiar_definition(familiar_id)
	if definition == null or familiar_level(familiar_id) > 0:
		return false
	familiars["owned"][familiar_id] = 1
	if not definition.bound_character_id.is_empty():
		familiars["assignments"][definition.bound_character_id] = familiar_id
	_apply_familiar_modifiers()
	profile_changed.emit()
	return true

func assign_familiar(character_id: String, familiar_id: String) -> bool:
	if in_combat or has_pending_reward() or awaiting_return or familiar_level(familiar_id) <= 0:
		return false
	var definition: FamiliarDefinition = familiar_definition(familiar_id)
	var owner: CharacterState = character_state(character_id)
	if owner == null:
		return false
	if character_id == "haruto":
		if not definition.bound_character_id.is_empty():
			return false
	elif definition.bound_character_id != character_id:
		return false
	familiars["assignments"][character_id] = familiar_id
	_apply_familiar_modifiers()
	profile_changed.emit()
	return true

func clear_familiar(character_id: String) -> bool:
	if character_id != "haruto" or in_combat or has_pending_reward() or awaiting_return or not familiars["assignments"].has(character_id):
		return false
	familiars["assignments"].erase(character_id)
	_apply_familiar_modifiers()
	profile_changed.emit()
	return true

func upgrade_familiar(character_id: String) -> bool:
	if character_id == "haruto" or in_combat or has_pending_reward() or awaiting_return:
		return false
	var definition: FamiliarDefinition = assigned_familiar(character_id)
	if definition == null or definition.bound_character_id != character_id:
		return false
	var level: int = familiar_level(definition.id)
	if level <= 0 or level >= definition.max_level:
		return false
	familiars["owned"][definition.id] = level + 1
	_apply_familiar_modifiers()
	profile_changed.emit()
	return true

func _sync_companion(character_id: String) -> void:
	if characters.has(character_id) or not COMPANION_ACTOR_PATHS.has(character_id):
		return
	var state := CharacterState.new(load(COMPANION_ACTOR_PATHS[character_id]))
	characters[character_id] = state
	inventory.register_character(character_id, state)
	for definition_path: String in FAMILIAR_PATHS.values():
		var definition: FamiliarDefinition = load(definition_path)
		if definition.bound_character_id == character_id and familiar_level(definition.id) <= 0:
			familiars["owned"][definition.id] = 1
			familiars["assignments"][character_id] = definition.id
	_apply_familiar_modifiers()

func _apply_familiar_modifiers() -> void:
	var states: Dictionary = {"haruto": hero}
	for character_id: String in characters:
		states[character_id] = characters[character_id]
	for character_id: String in states:
		var state: CharacterState = states[character_id]
		var source_id: String = "familiar:" + character_id
		var definition: FamiliarDefinition = assigned_familiar(character_id)
		if definition == null or familiar_level(definition.id) <= 0:
			state.remove_modifiers(source_id)
			continue
		var modifiers: Array[StatModifierDefinition] = []
		var level: int = familiar_level(definition.id)
		for group: Array in [definition.modifiers, definition.per_level_modifiers]:
			for template: StatModifierDefinition in group:
				var modifier := StatModifierDefinition.new()
				modifier.stat_id = template.stat_id
				modifier.amount = template.amount * (1 if group == definition.modifiers else maxi(0, level - 1))
				modifier.source_id = source_id
				modifiers.append(modifier)
		state.set_modifiers(source_id, modifiers)

## --- Маршрут ---

static func route_definition() -> Dictionary:
	if _route_definition_cache.is_empty():
		var file: FileAccess = FileAccess.open(ROUTE_PATH, FileAccess.READ)
		if file == null:
			return {"route_id": "forest_edge_slice", "nodes": []}
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
			return {"route_id": "forest_edge_slice", "nodes": []}
		_route_definition_cache = parser.data
	return _route_definition_cache

func route_nodes() -> Array:
	return route_definition().get("nodes", [])

func next_route_node() -> Dictionary:
	if route_state.get("completed", false):
		return {}
	var index: int = int(route_state.get("next_index", 0))
	var nodes: Array = route_nodes()
	if index < 0 or index >= nodes.size():
		return {}
	return nodes[index]

func route_completed() -> bool:
	return bool(route_state.get("completed", false))

func next_route_approach() -> String:
	if location_id != LOCATION_FOREST_EDGE or traces == 3 or awaiting_return or has_pending_reward():
		return ""
	match next_route_node().get("approach", ""):
		"first_slime":
			if not world_flags.get("first_slime_spotted", false):
				return "first_slime"
		"daijiro":
			if not world_flags.get("daijiro_intervened", false):
				return "daijiro_cart" if world_flags.get("daijiro_spotted", false) else "daijiro_lookout"
	return ""

func route_completion_label() -> String:
	return String(route_definition().get("completion_label", "Участок пройден"))

## Старые сохранения восстанавливают знакомых врагов по победам, Эху и
## уже пройденным узлам. Новые встречи записываются в журнал вне отката.
func route_repeat_enemy_ids() -> Array[String]:
	var result: Array[String] = []
	if location_id != LOCATION_FOREST_EDGE or in_combat or awaiting_return or has_pending_reward() or traces == 3 or _claim_in_progress:
		return result
	var repeat_enemies: Dictionary = route_definition().get("repeat_enemies", {})
	var nodes: Array = route_nodes()
	var limit: int = mini(int(route_state.get("next_index", 0)), nodes.size())
	for index: int in range(limit):
		var enemy_id: String = String(nodes[index].get("enemy_id", ""))
		if repeat_enemies.has(enemy_id) and not result.has(enemy_id):
			result.append(enemy_id)
	for enemy_id: String in repeat_enemies:
		var sighting_flag: String = repeat_enemies[enemy_id].get("seen_world_flag", "")
		if not result.has(enemy_id) and (
			enemy_journal.get(enemy_id, false) or _beaten_encounter_ids.get(enemy_id, false)
			or claimed_echo_enemy_ids.get(enemy_id, false) or world_flags.get(sighting_flag, false)
		):
			result.append(enemy_id)
	return result

func _scaled_repeat_enemy(definition: ActorDefinition, reference_level: int) -> ActorDefinition:
	var scaled: ActorDefinition = definition.duplicate()
	var level_delta: int = hero.level - reference_level
	var extra_strength: int = maxi(0, hero.strength - hero.definition.strength)
	var extra_hp: int = maxi(0, hero.max_hp - hero.definition.max_hp)
	var extra_defense: int = maxi(0, hero.defense - hero.definition.defense)
	scaled.max_hp = maxi(1, definition.max_hp + 2 * (level_delta + extra_strength))
	scaled.strength = maxi(1, definition.strength + floori(level_delta / 2.0)
		+ floori((extra_hp + 4 * extra_defense) / 12.0))
	return scaled

func _encounter_context_for(enemy_id: String, repeat: bool) -> Dictionary:
	if not _is_known_enemy(enemy_id):
		return {}
	if location_id == LOCATION_GUILD_ORDER:
		var stage: Dictionary = guild_order_stage()
		if repeat or stage.get("enemy_id", "") != enemy_id:
			return {}
		return {
			"enemy_id": enemy_id, "encounter_mode": ENCOUNTER_GUILD_ORDER,
			"route_id": guild_order["id"], "route_node_id": str(int(guild_order["cleared"])),
			"order_total": int(guild_order["total"]),
		}
	if location_id == LOCATION_GROVE:
		var grove: Dictionary = grove_node(grove_stage())
		if repeat or String(grove.get("enemy_id", "")) != enemy_id:
			return {}
		if enemy_id == "dust_moth" and not seen_cue_ids.has("DIA_GROVE_011"):
			return {}
		return {"enemy_id": enemy_id, "encounter_mode": ENCOUNTER_GROVE, "route_id": LOCATION_GROVE, "route_node_id": grove["node_id"]}
	if location_id in [LOCATION_HOLLOW, LOCATION_OUTPOST]:
		var at_outpost: bool = location_id == LOCATION_OUTPOST
		var stage: String = outpost_stage() if at_outpost else hollow_stage()
		var node: Dictionary = outpost_node(stage) if at_outpost else hollow_node(stage)
		var prerequisite: String = HOLLOW_REPORTED if at_outpost else GROVE_REPORTED
		if repeat or not quest_flags.get(prerequisite, false) or node.get("enemy_id", "") != enemy_id:
			return {}
		if not seen_cue_ids.has_all(node.get("cues", [])):
			return {}
		if stage == "elite" and not seen_cue_ids.has("DIA_HOLLOW_009"):
			return {}
		return {"enemy_id": enemy_id, "encounter_mode": ENCOUNTER_OUTPOST if at_outpost else ENCOUNTER_HOLLOW, "route_id": location_id, "route_node_id": stage}
	var route_id: String = String(route_definition().get("route_id", ""))
	var node: Dictionary = next_route_node()
	if not repeat and not node.is_empty() and String(node.get("enemy_id", "")) == enemy_id:
		return {
			"enemy_id": enemy_id,
			"encounter_mode": ENCOUNTER_ROUTE,
			"route_id": route_id,
			"route_node_id": String(node.get("node_id", "")),
		}
	if not repeat and enemy_id == TRIAL_ENEMY_ID:
		if not trial_available():
			return {}
		return {"enemy_id": enemy_id, "encounter_mode": ENCOUNTER_TRIAL, "route_id": route_id, "route_node_id": ""}
	if enemy_id in route_repeat_enemy_ids():
		return {"enemy_id": enemy_id, "encounter_mode": ENCOUNTER_REPEAT, "route_id": route_id, "route_node_id": ""}
	return {}

## --- Испытание ---

## Добровольное испытание открывается после учебного двухузлового участка.
func trial_available() -> bool:
	return route_completed()

func trial_encounter_available() -> bool:
	return location_id == LOCATION_FOREST_EDGE and trial_available() and not in_combat and not awaiting_return and not has_pending_reward() and traces < 3 and not _claim_in_progress

## --- Settlement: создание pending ---

## UI не вызывает это: resolver сам шлёт terminal event, сессия один раз
## создаёт durable pending-result. Повторный finished того же run — no-op;
## inventory/XP/route здесь не трогаются — это происходит в claim.
func settle_combat(run_id: String, enemy_id: String) -> bool:
	if run_id.is_empty() or enemy_id.is_empty() or _settled_run_ids.has(run_id) or has_pending_reward():
		return false
	var context: Variant = _finished_run_contexts.get(run_id, null)
	if typeof(context) != TYPE_DICTIONARY or String(context.get("enemy_id", "")) != enemy_id:
		return false
	var expedition: Dictionary = expedition_battle_node(context)
	var repeat_settings: Dictionary = {}
	if context["encounter_mode"] == ENCOUNTER_REPEAT:
		repeat_settings = route_definition().get("repeat_enemies", {}).get(enemy_id, {})
	if expedition.is_empty() and repeat_settings.is_empty() and not LOOT_PATHS.has(enemy_id):
		return false
	_settled_run_ids[run_id] = true
	var enemy_definition: ActorDefinition = load(ACTOR_PATHS[enemy_id])
	var rewards: Array = expedition.get("rewards", []).duplicate()
	var echo_available: bool = false
	if expedition.is_empty():
		if LOOT_PATHS.has(enemy_id):
			rewards = loot_generator.generate(load(LOOT_PATHS[enemy_id]), loot_rng)
		echo_available = not claimed_echo_enemy_ids.has(enemy_id)
	else:
		for slot: Dictionary in expedition["enemies"]:
			echo_available = echo_available or not claimed_echo_enemy_ids.has(slot["actor_id"])
	if context["encounter_mode"] == ENCOUNTER_GUILD_ORDER:
		var order: Dictionary = GuildOrders.definition(context["route_id"])
		rewards.append_array(GuildOrders.bonus_loot(order["rank"], int(context["route_node_id"]), int(context["order_total"]), loot_rng))
	elif EXPEDITION_ROUTES.has(context["encounter_mode"]):
		var stages: Dictionary = story_order(context["route_id"])
		var index: int = stages["nodes"].find(context["route_node_id"])
		if index >= 0:
			rewards.append_array(GuildOrders.bonus_loot(stages["rank"], index, stages["nodes"].size(), loot_rng))
	if String(context.get("encounter_mode", "")) == ENCOUNTER_ROUTE:
		for node: Dictionary in route_nodes():
			if String(node.get("node_id", "")) == String(context.get("route_node_id", "")):
				rewards.append_array(node.get("first_clear_rewards", []))
				break
	var items: Array[Dictionary] = []
	for reward: Dictionary in rewards:
		var definition: ItemDefinition = get_item_definition(reward.get("item_id", ""))
		if definition == null:
			continue
		items.append({
			"entry_id": "entry_%06d" % (items.size() + 1),
			"item_id": definition.id,
			"quantity": int(reward.get("quantity", 0)),
			"aspect_id": String(reward.get("aspect_id", "")),
			"slot_id": definition.slot_id,
			"level": maxi(1, int(reward.get("level", definition.level))),
			"sale_price_copper": maxi(0, int(reward.get("sale_price_copper", definition.sale_price_copper))),
			"sellable": bool(reward.get("sellable", definition.sellable)),
		})
	pending_battle_result = {
		"result_id": "%s_result" % run_id,
		"run_id": run_id,
		"run_token": String(context.get("run_token", "")),
		"enemy_id": enemy_id,
		"encounter_mode": String(context.get("encounter_mode", "")),
		"route_id": String(context.get("route_id", "")),
		"route_node_id": String(context.get("route_node_id", "")),
		"items": items,
		"choices": {},
		"xp": int(expedition.get("xp", repeat_settings.get("xp", enemy_definition.xp_reward))),
		"echo_gained": echo_available,
		"trial_echo_gained": enemy_id == TRIAL_ENEMY_ID and not trial_echo_claimed,
		"loot_seed": loot_seed,
		"loot_state": str(loot_rng.state),
	}
	if context["encounter_mode"] == ENCOUNTER_GUILD_ORDER:
		pending_battle_result["order_total"] = context["order_total"]
	profile_changed.emit()
	return true

## --- Settlement: получение (claim) ---

## Одно новое намеренное действие игрока получает результат ровно один раз:
## весь батч (предметы, XP, route, журнал, эхо) применяется внутри транзакции,
## сохранение промежуточных состояний заблокировано. Экипировка применяет
## подтверждённые выборы; неизменённые находки остаются в общей сумке.
func claim_battle_result(result_id: String) -> bool:
	if _claim_in_progress or result_id.is_empty() or pending_battle_result.is_empty() or awaiting_return or not reward_choices_complete():
		return false
	if String(pending_battle_result.get("result_id", "")) != result_id or not is_valid_pending_battle_result(pending_battle_result):
		return false
	if not expedition_battle_matches(pending_battle_result, location_id, quest_flags, npc_flags, guild_order):
		return false
	_claim_in_progress = true
	_transaction_depth += 1
	var enemy_id: String = String(pending_battle_result.get("enemy_id", ""))
	var level_before: int = hero.level
	var items: Array[Dictionary] = []
	for reward: Dictionary in pending_battle_result.get("items", []):
		var definition: ItemDefinition = get_item_definition(reward.get("item_id", ""))
		if definition == null:
			continue
		var affected: Array[ItemInstance] = inventory.add(
			definition,
			int(reward.get("quantity", 0)),
			String(reward.get("aspect_id", "")),
			{
				"level": int(reward.get("level", definition.level)),
				"sale_price_copper": int(reward.get("sale_price_copper", definition.sale_price_copper)),
				"sellable": bool(reward.get("sellable", definition.sellable)),
			}
		)
		var instance_ids: Array[String] = []
		for item: ItemInstance in affected:
			instance_ids.append(item.instance_id)
		var choice: Dictionary = pending_battle_result.get("choices", {}).get(reward.get("entry_id", ""), {"action": "store"})
		if choice.get("action", "store") == "equip" and not instance_ids.is_empty():
			inventory.equip(instance_ids[0])
		items.append({
			"entry_id": String(reward.get("entry_id", "")),
			"action": String(choice.get("action", "store")),
			"item_id": definition.id,
			"quantity": int(reward.get("quantity", 0)),
			"aspect_id": String(reward.get("aspect_id", "")),
			"slot_id": definition.slot_id,
			"instance_ids": instance_ids,
		})
	hero.gain_xp(int(pending_battle_result.get("xp", 0)))
	var echo_gained: bool = false
	var encounter_species: Array[String] = [enemy_id]
	for slot: Dictionary in expedition_battle_node(pending_battle_result).get("enemies", []):
		var species: String = String(slot["actor_id"])
		if not encounter_species.has(species):
			encounter_species.append(species)
	for species: String in encounter_species:
		_beaten_encounter_ids[species] = true
		if bool(pending_battle_result["echo_gained"]) and not claimed_echo_enemy_ids.has(species):
			claimed_echo_enemy_ids[species] = true
			echoes += 1
			echo_gained = true
	var trial_echo_gained: bool = false
	if bool(pending_battle_result.get("trial_echo_gained", false)) and not trial_echo_claimed:
		trial_echo_claimed = true
		echoes += 1
		trial_echo_gained = true
	var route_advanced: bool = _advance_route(pending_battle_result)
	if pending_battle_result.get("encounter_mode", "") == ENCOUNTER_ROUTE and enemy_id == "goblin_scout":
		world_flags["daijiro_scout_defeated"] = true
	# Журнал побед — внутри транзакции, до единственного итогового сохранения.
	last_settlement = {
		"result_id": result_id,
		"run_id": String(pending_battle_result.get("run_id", "")),
		"enemy_id": enemy_id,
		"encounter_mode": String(pending_battle_result.get("encounter_mode", "")),
		"route_node_id": String(pending_battle_result.get("route_node_id", "")),
		"won": true,
		"xp": int(pending_battle_result.get("xp", 0)),
		"levels_gained": hero.level - level_before,
		"items": items,
		"echo_gained": echo_gained,
		"trial_echo_gained": trial_echo_gained,
		"route_advanced": route_advanced,
	}
	pending_receive_fx = not items.is_empty()
	pending_battle_result = {}
	last_claimed_result_id = result_id
	_transaction_depth -= 1
	_claim_in_progress = false
	profile_changed.emit()
	battle_result_claimed.emit(last_settlement)
	return true

func publish_battle_result_claimed() -> void:
	if last_settlement.is_empty():
		return
	battle_result_claimed.emit(last_settlement)

func choose_battle_reward(entry_id: String, action: String) -> bool:
	return _choose_reward(pending_battle_result, entry_id, action)

func choose_story_reward(entry_id: String, action: String) -> bool:
	return _choose_reward(pending_story_reward, entry_id, action)

func _choose_reward(result: Dictionary, entry_id: String, action: String) -> bool:
	if in_combat or awaiting_return or _claim_in_progress or action not in ["store", "equip"]:
		return false
	for entry: Dictionary in result.get("items", []):
		if String(entry.get("entry_id", "")) != entry_id:
			continue
		var definition: ItemDefinition = get_item_definition(String(entry.get("item_id", "")))
		if action == "equip" and (definition == null or definition.slot_id.is_empty()):
			return false
		var result_id: String = String(result.get("result_id", result.get("reward_id", "")))
		result["choices"][entry_id] = {"result_id": result_id, "entry_id": entry_id, "action": action}
		profile_changed.emit()
		return true
	return false

func reward_choices_complete(story: bool = false) -> bool:
	var result: Dictionary = pending_story_reward if story else pending_battle_result
	if result.is_empty():
		return false
	for entry: Dictionary in result.get("items", []):
		if not result.get("choices", {}).has(entry.get("entry_id", "")):
			return false
	return true

func prepare_daijiro_sword_reward() -> bool:
	if (
		in_combat
		or awaiting_return
		or has_pending_reward()
		or _claim_in_progress
		or story_rewards.has(DAIJIRO_SWORD_REWARD_ID)
		or not world_flags.get("daijiro_intervened", false)
		or not world_flags.get("daijiro_scout_defeated", false)
		or not world_flags.get("daijiro_introduction_completed", false)
	):
		return false
	var definition: ItemDefinition = get_item_definition("training_sword")
	pending_story_reward = {
		"reward_id": DAIJIRO_SWORD_REWARD_ID,
		"items": [{
			"entry_id": "daijiro_sword_01",
			"item_id": definition.id,
			"quantity": 1,
			"aspect_id": "",
			"slot_id": definition.slot_id,
			"level": definition.level,
			"sale_price_copper": definition.sale_price_copper,
			"sellable": definition.sellable,
		}],
		"choices": {},
	}
	profile_changed.emit()
	return true

func claim_story_reward(reward_id: String) -> bool:
	if _claim_in_progress or awaiting_return or in_combat or pending_story_reward.is_empty():
		return false
	if String(pending_story_reward.get("reward_id", "")) != reward_id or story_rewards.has(reward_id):
		return false
	_claim_in_progress = true
	_transaction_depth += 1
	var delivered: Array[Dictionary] = []
	for reward: Dictionary in pending_story_reward.get("items", []):
		var definition: ItemDefinition = get_item_definition(String(reward.get("item_id", "")))
		if definition == null:
			_transaction_depth -= 1
			_claim_in_progress = false
			return false
		var affected: Array[ItemInstance] = inventory.add(definition, int(reward["quantity"]), String(reward["aspect_id"]), {
			"level": int(reward["level"]),
			"sale_price_copper": int(reward["sale_price_copper"]),
			"sellable": bool(reward["sellable"]),
		})
		var instance_ids: Array[String] = []
		for item: ItemInstance in affected:
			instance_ids.append(item.instance_id)
		var choice: Dictionary = pending_story_reward["choices"].get(reward["entry_id"], {"action": "store"})
		if choice.get("action", "store") == "equip" and not instance_ids.is_empty():
			inventory.equip(instance_ids[0])
		delivered.append({"entry_id": reward["entry_id"], "item_id": definition.id, "quantity": int(reward["quantity"]), "instance_ids": instance_ids, "action": choice.get("action", "store")})
	story_rewards[reward_id] = true
	pending_story_reward = {}
	pending_receive_fx = true
	last_settlement = {"result_id": reward_id, "story_reward": true, "items": delivered}
	_transaction_depth -= 1
	_claim_in_progress = false
	profile_changed.emit()
	story_reward_claimed.emit(last_settlement)
	return true

func current_combat_format() -> String:
	return String(active_encounter_context.get("combat_format", combat_format))

func has_pending_battle_result() -> bool:
	return not pending_battle_result.is_empty()

func has_pending_reward() -> bool:
	return not pending_battle_result.is_empty() or not pending_story_reward.is_empty()

func is_transaction_active() -> bool:
	return _transaction_depth > 0

## Доменная экипировка конкретного предмета (toast «Надеть»).
func equip_item(instance_id: String, character_id: String = "haruto") -> bool:
	if in_combat or awaiting_return or has_pending_reward() or _claim_in_progress:
		return false
	if not inventory.equip(instance_id, character_id):
		return false
	profile_changed.emit()
	return true

func unequip_item(slot_id: String, character_id: String = "haruto") -> bool:
	if in_combat or awaiting_return or has_pending_reward() or _claim_in_progress:
		return false
	if not inventory.unequip(slot_id, character_id):
		return false
	profile_changed.emit()
	return true

## Игрок сдаётся через паузу: по цене возврата, без автовыбора точки.
func abandon_combat() -> void:
	if not in_combat:
		return
	_remember_encounter_enemies(active_resolver)
	_invalidate_active_resolver()
	in_combat = false
	awaiting_return = true
	profile_changed.emit()

static func trade_total(unit_price: int, quantity: int) -> int:
	@warning_ignore("integer_division")
	if unit_price <= 0 or quantity <= 0 or unit_price > MAX_ASTRAS / quantity:
		return 0
	return unit_price * quantity

func sell_item(instance_id: String, quantity: int = 1, expected_price: int = -1, expected_stock: int = -1) -> bool:
	if in_combat or awaiting_return or has_pending_reward() or _claim_in_progress or quantity <= 0:
		return false
	var item: ItemInstance = inventory.get_item(instance_id)
	if item == null or not item.sellable or item.quantity < quantity:
		return false
	if inventory.is_equipped(instance_id):
		return false
	if (expected_price >= 0 and item.sale_price_copper != expected_price) or (expected_stock >= 0 and item.quantity != expected_stock):
		return false
	var total: int = trade_total(item.sale_price_copper, quantity)
	if total <= 0 or wallet[COPPER] > MAX_ASTRAS - total:
		return false
	if not inventory.remove(instance_id, quantity):
		return false
	wallet[COPPER] += total
	if not bool(world_flags.get(WORLD_FLAG_SHOP_FIRST_SALE_DONE, false)):
		world_flags[WORLD_FLAG_SHOP_FIRST_SALE_DONE] = true
	var sold_definition: ItemDefinition = get_item_definition(item.definition_id)
	last_deal = {
		"kind": "sell",
		"instance_id": instance_id,
		"item_id": item.definition_id,
		"display_name": sold_definition.display_name if sold_definition != null else item.definition_id,
		"quantity": quantity,
		"unit_price_copper": item.sale_price_copper,
		"total_copper": total,
		"balance_after": wallet[COPPER],
	}
	profile_changed.emit()
	return true

## --- Лавка «Сверчок и Сумрак» ---

## Базовое перемещение между Тропой и Лиореном. Карта проверяет сюжетный доступ.
func travel_to(location_id: String) -> bool:
	if in_combat or has_pending_reward() or awaiting_return or _claim_in_progress:
		return false
	if location_id not in [LOCATION_FOREST_EDGE, LOCATION_LIOREN]:
		return false
	if self.location_id in EXPEDITION_LOCATIONS:
		return false
	if location_id == self.location_id:
		return true
	if location_id == LOCATION_FOREST_EDGE and traces == 3:
		return false
	record_map_visit(self.location_id)
	self.location_id = location_id
	record_map_visit(location_id)
	profile_changed.emit()
	return true

func record_map_visit(destination: String) -> void:
	memory_flags[MAP_VISIT_PREFIX + destination] = true

func has_visited_map_location(destination: String) -> bool:
	if destination == location_id or memory_flags.get(MAP_VISIT_PREFIX + destination, false):
		return true
	# Recover visits from progress recorded before the map kept its own history.
	match destination:
		LOCATION_FOREST_EDGE:
			return true
		LOCATION_LIOREN:
			return shop_access_unlocked() or seen_cue_ids.has("DIA_CITY_001")
		LOCATION_GROVE:
			return seen_cue_ids.has("DIA_GROVE_001") or quest_flags.get(GROVE_HOUNDS_WON, false)
		LOCATION_HOLLOW:
			return quest_flags.get(HOLLOW_STARTED, false) or seen_cue_ids.has("DIA_HOLLOW_021")
		LOCATION_OUTPOST:
			return seen_cue_ids.has("DIA_AKARI_001") or quest_flags.get(OUTPOST_BOWL, false)
		MAP_SHOP:
			return seen_cue_ids.has("DIA_SHOP_001") or world_flags.get(WORLD_FLAG_SHOP_INTRO_DONE, false) or world_flags.get(WORLD_FLAG_SHOP_FIRST_PURCHASE_DONE, false)
		MAP_GUILD:
			return guild_visit_active() or seen_cue_ids.has("DIA_GUILD_001") or not guild_rank().is_empty()
		MAP_HOLLOW_LEDGE:
			return (location_id == LOCATION_HOLLOW and hollow_stage() == "ledge") or quest_flags.get(HOLLOW_UPPER_MARKER, false)
		MAP_HOLLOW_BASIN:
			return quest_flags.get(HOLLOW_ELITE_ENTERED, false) or quest_flags.get(HOLLOW_ELITE_WON, false) or quest_flags.get(HOLLOW_RETREATED, false)
	return false

func first_unvisited_map_route(city_map: bool) -> String:
	var destinations: Array[String] = MAP_CITY_LOCATIONS if city_map else MAP_WORLD_LOCATIONS
	if not city_map and location_id == LOCATION_HOLLOW:
		destinations = [MAP_HOLLOW_BASIN]
	for destination: String in destinations:
		if not has_visited_map_location(destination) and map_travel_blocker(destination).is_empty():
			return destination
	return ""

func map_travel_blocker(destination: String) -> String:
	if destination == location_id:
		return "current"
	if destination == MAP_HOLLOW_BASIN and location_id == LOCATION_HOLLOW and hollow_stage() == "elite":
		return "current"
	if destination == MAP_HOLLOW_LEDGE and location_id == LOCATION_HOLLOW and hollow_stage() == "ledge":
		return "current"
	if in_combat or has_pending_reward() or awaiting_return or _claim_in_progress:
		return "busy"
	if checkpoints.channel_active or checkpoints.has_pending_completion():
		return "checkpoint"
	if destination == LOCATION_LIOREN:
		if location_id == LOCATION_FOREST_EDGE and not story_rewards.has(DAIJIRO_SWORD_REWARD_ID):
			return "daijiro"
		if location_id == LOCATION_HOLLOW and hollow_stage() == "elite":
			return "via_ledge"
		return ""
	if destination == MAP_SHOP:
		return "" if can_trade() else "gates"
	if destination == MAP_GUILD:
		return "" if can_visit_guild() else "merchant"
	if destination == MAP_HOLLOW_LEDGE:
		return "" if location_id == LOCATION_HOLLOW and hollow_stage() == "elite" else "unavailable"
	if traces >= 3:
		return "rest"
	if destination == MAP_HOLLOW_BASIN:
		if location_id == LOCATION_HOLLOW and hollow_stage() == "ledge" and quest_flags.get(HOLLOW_CLOTH, false) and not quest_flags.get(HOLLOW_ELITE_WON, false):
			return ""
		return "unavailable"
	if location_id != LOCATION_LIOREN:
		return "via_lioren"
	match destination:
		LOCATION_FOREST_EDGE:
			return ""
		LOCATION_GROVE:
			return "" if can_enter_grove() else "registration"
		LOCATION_HOLLOW:
			return "" if can_enter_hollow() else "grove_report"
		LOCATION_OUTPOST:
			if quest_flags.get(OUTPOST_ALLIANCE, false):
				return "completed"
			return "" if can_enter_outpost() else "hollow_report"
		_:
			return "unavailable"

## Выполняется GameRoot над кандидатом сохранения после выбора пункта карты.
func apply_map_travel(destination: String) -> bool:
	if not map_travel_blocker(destination).is_empty():
		return false
	match destination:
		LOCATION_LIOREN:
			if location_id in EXPEDITION_LOCATIONS:
				return apply_expedition_command("leave", location_id)
			return travel_to(destination)
		LOCATION_FOREST_EDGE:
			world_flags.erase(WORLD_FLAG_GUILD_VISIT)
			return travel_to(destination)
		LOCATION_GROVE, LOCATION_HOLLOW, LOCATION_OUTPOST:
			return apply_expedition_command("enter", destination)
		MAP_HOLLOW_BASIN:
			return apply_hollow_command("descend")
		MAP_HOLLOW_LEDGE:
			return apply_hollow_command("retreat")
		MAP_SHOP:
			record_map_visit(destination)
			return true
		MAP_GUILD:
			set_guild_visit_active(true)
			return guild_visit_active()
		_:
			return false

func apply_expedition_command(command: String, route_id: String) -> bool:
	match route_id:
		LOCATION_GROVE: return apply_grove_command(command)
		LOCATION_HOLLOW: return apply_hollow_command(command)
		LOCATION_OUTPOST: return apply_outpost_command(command)
		_: return false

func shop_access_unlocked() -> bool:
	return bool(world_flags.get(WORLD_FLAG_LIOREN_SHOP_UNLOCKED, false))

func should_show_lioren_gates() -> bool:
	return location_id == LOCATION_LIOREN and story_rewards.has(DAIJIRO_SWORD_REWARD_ID) and not shop_access_unlocked()

func can_trade() -> bool:
	return location_id == LOCATION_LIOREN and shop_access_unlocked() and not in_combat and not awaiting_return and not has_pending_reward()

func can_visit_guild() -> bool:
	return can_trade() and world_flags.get(WORLD_FLAG_SHOP_PURCHASE_BRIEFING_DONE, false) == true

func guild_visit_active() -> bool:
	return can_visit_guild() and world_flags.get(WORLD_FLAG_GUILD_VISIT, false) == true

func set_guild_visit_active(active: bool) -> void:
	if not can_visit_guild() or active == guild_visit_active():
		return
	if active:
		world_flags[WORLD_FLAG_GUILD_VISIT] = true
		record_map_visit(MAP_GUILD)
	else:
		world_flags.erase(WORLD_FLAG_GUILD_VISIT)
	profile_changed.emit()

func guild_rank() -> String:
	return "E" if world_flags.get(WORLD_FLAG_GUILD_REGISTERED, false) == true else ""

func guild_order_is_completed(order_id: String) -> bool:
	return quest_flags.get("guild_order_completed_" + order_id, false)

func guild_order_is_unlocked(order_id: String) -> bool:
	var order: Dictionary = GuildOrders.definition(order_id)
	if guild_rank().is_empty() or order.is_empty():
		return false
	var index: int = GuildOrders.RANKS.find(order["rank"])
	if index == 0:
		return true
	var previous_rank: String = GuildOrders.RANKS[index - 1]
	for previous_id: String in GuildOrders.data()["orders"]:
		if GuildOrders.definition(previous_id)["rank"] == previous_rank and guild_order_is_completed(previous_id):
			return true
	return false

func guild_order_stage() -> Dictionary:
	if guild_order.is_empty():
		return {}
	return GuildOrders.stage(guild_order["id"], int(guild_order["cleared"]), int(guild_order["total"]))

func guild_order_location() -> String:
	return GuildOrders.order_type(GuildOrders.definition(guild_order.get("id", ""))).get("location", LOCATION_FOREST_EDGE)

func apply_guild_order_command(command: String, order_id: String = "") -> bool:
	if in_combat or has_pending_reward() or awaiting_return or checkpoints.channel_active or checkpoints.has_pending_completion():
		return false
	if command == "leave":
		if location_id != LOCATION_GUILD_ORDER:
			return false
		location_id = LOCATION_LIOREN
		world_flags[WORLD_FLAG_GUILD_VISIT] = true
		return true
	if not guild_visit_active():
		return false
	if command == "accept":
		if not guild_order.is_empty() or not guild_order_is_unlocked(order_id) or guild_order_is_completed(order_id):
			return false
		var rules: Dictionary = GuildOrders.rank_rules(GuildOrders.definition(order_id)["rank"])
		guild_order = {"id": order_id, "total": loot_rng.randi_range(int(rules["min"]), int(rules["max"])), "cleared": 0}
		return true
	if guild_order.is_empty() or guild_order["id"] != order_id:
		return false
	match command:
		"depart":
			if traces >= 3 or guild_order_stage().is_empty():
				return false
			location_id = LOCATION_GUILD_ORDER
			world_flags.erase(WORLD_FLAG_GUILD_VISIT)
		"report":
			if not guild_order_stage().is_empty():
				return false
			var order: Dictionary = GuildOrders.definition(order_id)
			var reward: Dictionary = GuildOrders.rank_rules(order["rank"])
			var copper: int = int(reward["copper"])
			if wallet[COPPER] > MAX_ASTRAS - copper:
				return false
			var gear: ItemDefinition = get_item_definition(GuildOrders.order_type(order)["reward"])
			inventory.add(gear, 1, "", {"level": int(reward["level"])})
			wallet[COPPER] += copper
			hero.gain_xp(int(reward["xp"]))
			quest_flags["guild_order_completed_" + order_id] = true
			guild_order = {}
		_:
			return false
	return true

func story_order(location: String) -> Dictionary:
	var route: Dictionary
	var mode: String
	match location:
		LOCATION_GROVE:
			route = grove_definition()
			mode = ENCOUNTER_GROVE
		LOCATION_HOLLOW:
			route = hollow_definition()
			mode = ENCOUNTER_HOLLOW
		LOCATION_OUTPOST:
			route = outpost_definition()
			mode = ENCOUNTER_OUTPOST
		_: return {}
	var order: Dictionary = route["order"]
	var nodes: Array = _outpost_order_nodes(quest_flags) if location == LOCATION_OUTPOST else order["nodes"]
	var cleared: int = 0
	for node_id: String in nodes:
		var node: Dictionary = expedition_battle_node({"encounter_mode": mode, "route_node_id": node_id})
		if quest_flags.get(node["cleared_flag"], false) or (node_id == "upper_guard" and quest_flags.get(HOLLOW_UPPER_MARKER, false)):
			cleared += 1
	return {"rank": order["rank"], "nodes": nodes, "cleared": cleared, "silver": int(route["report"]["silver"])}

func can_register_with_guild() -> bool:
	return guild_visit_active() and guild_rank().is_empty() and seen_cue_ids.has(GUILD_LAST_CUE_ID)

func register_with_guild() -> bool:
	if not can_register_with_guild() or checkpoints.channel_active:
		return false
	world_flags[WORLD_FLAG_GUILD_REGISTERED] = true
	quest_flags[FIRST_GUILD_ORDER_ID] = true
	profile_changed.emit()
	return true

static func grove_definition() -> Dictionary:
	if _grove_definition_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GROVE_ROUTE_PATH))
		if parsed is Dictionary:
			_grove_definition_cache = parsed
	return _grove_definition_cache

static func grove_node(node_id: String) -> Dictionary:
	for node: Dictionary in grove_definition().get("nodes", []):
		if node["node_id"] == node_id:
			return node
	return {}

func grove_stage() -> String:
	return grove_stage_for(quest_flags, npc_flags)

static func grove_stage_for(quests: Dictionary, npcs: Dictionary) -> String:
	if not quests.get("grove_approached", false):
		return "approach"
	if not quests.get(GROVE_HOUNDS_WON, false):
		return "hound_pair"
	for choice: String in GROVE_KENTA_CHOICES:
		if npcs.get(choice, false):
			return "clearing" if quests.get(GROVE_POLLEN_WON, false) else "pollen_pair"
	return "root_bridge"

func battle_echo_reward(result: Dictionary) -> int:
	var node: Dictionary = expedition_battle_node(result)
	if node.is_empty():
		return int(result.get("echo_gained", false)) + int(result.get("trial_echo_gained", false))
	if not result.get("echo_gained", false):
		return 0
	var new_species: Dictionary = {}
	for slot: Dictionary in node.get("enemies", []):
		if not claimed_echo_enemy_ids.has(slot["actor_id"]):
			new_species[slot["actor_id"]] = true
	return new_species.size()

func grove_kenta_outcome() -> String:
	for choice: String in GROVE_KENTA_CHOICES:
		if npc_flags.get(choice, false):
			return choice
	return ""

func grove_bandage() -> ItemInstance:
	for item: ItemInstance in inventory.filter("consumable"):
		if item.definition_id == GROVE_BANDAGE:
			return item
	return null

func can_enter_grove() -> bool:
	return can_visit_guild() and guild_rank() == "E" and quest_flags.get(FIRST_GUILD_ORDER_ID, false) and traces < 3 and not checkpoints.channel_active

func can_report_grove() -> bool:
	return guild_visit_active() and guild_rank() == "E" and quest_flags.get(GROVE_FLAX, false) and quest_flags.get(GROVE_MARKER, false) and not quest_flags.get(GROVE_REPORTED, false)

## GameRoot executes this on a copy and publishes only after SaveService commits.
func apply_grove_command(command: String) -> bool:
	if in_combat or has_pending_reward() or awaiting_return or checkpoints.channel_active:
		return false
	if command == "enter":
		if not can_enter_grove():
			return false
		location_id = LOCATION_GROVE
		record_map_visit(LOCATION_GROVE)
		record_map_visit(LOCATION_LIOREN)
		world_flags.erase(WORLD_FLAG_GUILD_VISIT)
		return true
	if command == "report":
		if not can_report_grove() or not seen_cue_ids.has("DIA_GROVE_021"):
			return false
		var reward: Dictionary = grove_definition()["report"]
		var silver: int = int(reward["silver"])
		if wallet[SILVER] > MAX_ASTRAS - silver:
			return false
		var previous_level: int = hero.level
		hero.gain_xp(int(reward["xp"]))
		wallet[SILVER] += silver
		if not memory_flags.get(GROVE_ECHOES_GRANTED, false):
			echoes += int(reward["echoes"])
			memory_flags[GROVE_ECHOES_GRANTED] = true
		quest_flags[GROVE_REPORTED] = true
		if previous_level < 3 and hero.level == 3:
			quest_flags[GROVE_LEVEL_THREE] = true
		return true
	if location_id != LOCATION_GROVE or traces >= 3:
		return false
	var stage: String = grove_stage()
	match command:
		"decline_point":
			if stage != "clearing" or world_flags.get(GROVE_SEALED, false) or world_flags.get(GROVE_DECLINED_SEAL, false):
				return false
			world_flags[GROVE_DECLINED_SEAL] = true
		"leave":
			if stage == "clearing" and not world_flags.get(GROVE_SEALED, false):
				if not world_flags.get(GROVE_DECLINED_SEAL, false) or not seen_cue_ids.has("DIA_GROVE_015"):
					return false
			location_id = LOCATION_LIOREN
			world_flags.erase(GROVE_DECLINED_SEAL)
		"approach", "noise":
			if stage != "approach" or not seen_cue_ids.has("DIA_GROVE_004"):
				return false
			quest_flags["grove_approached"] = true
			if command == "noise":
				quest_flags["grove_noise"] = true
		"flax", "marker":
			var flag: String = GROVE_FLAX if command == "flax" else GROVE_MARKER
			if stage != "clearing" or quest_flags.get(flag, false):
				return false
			quest_flags[flag] = true
		_:
			if command not in GROVE_KENTA_CHOICES or stage != "root_bridge" or not seen_cue_ids.has("DIA_GROVE_007"):
				return false
			if command == "grove_kenta_bandage":
				var bandage: ItemInstance = grove_bandage()
				if bandage == null or not inventory.remove(bandage.instance_id, 1):
					return false
			npc_flags[command] = true
			if command != "grove_kenta_hint":
				npc_flags["grove_kenta_trust"] = true
	return true

static func hollow_definition() -> Dictionary:
	if _hollow_definition_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/route/blue_hollow.json"))
		if parsed is Dictionary:
			_hollow_definition_cache = parsed
	return _hollow_definition_cache

static func hollow_node(node_id: String) -> Dictionary:
	return hollow_definition().get("nodes", {}).get(node_id, {})

func hollow_stage() -> String:
	return hollow_stage_for(quest_flags)

static func hollow_stage_for(quests: Dictionary) -> String:
	if not quests.get(HOLLOW_SHIELDBACK_WON, false):
		return "river"
	if not quests.get(HOLLOW_WATER_MARKER, false):
		return "water_marker"
	if not quests.get(HOLLOW_SHELF_WON, false):
		return "shelf"
	if not quests.get(HOLLOW_UPPER_MARKER, false) and not quests.get("hollow_upper_guard_won", false):
		return "upper_guard"
	if not quests.get(HOLLOW_UPPER_MARKER, false):
		return "upper_marker"
	if quests.get(HOLLOW_ELITE_ENTERED, false) and not quests.get(HOLLOW_ELITE_WON, false):
		return "elite"
	return "ledge"

static func outpost_definition() -> Dictionary:
	if _outpost_definition_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/route/winds_edge.json"))
		if parsed is Dictionary:
			_outpost_definition_cache = parsed
	return _outpost_definition_cache

static func outpost_node(node_id: String) -> Dictionary:
	return outpost_definition().get("nodes", {}).get(node_id, {})

func outpost_stage() -> String:
	return outpost_stage_for(quest_flags)

static func outpost_stage_for(quests: Dictionary) -> String:
	if not quests.get(OUTPOST_BOWL, false):
		return "bowl"
	if not quests.get(OUTPOST_SEAL, false):
		return "seal"
	for node_id: String in _outpost_order_nodes(quests):
		if not quests.get(outpost_node(node_id)["cleared_flag"], false):
			return node_id
	if not quests.get(OUTPOST_ALLIANCE, false):
		return "alliance"
	return "return"

static func _outpost_order_nodes(quests: Dictionary) -> Array:
	var nodes: Array = outpost_definition()["order"]["nodes"]
	# Profiles that already touched the signal before the update keep their pending battles.
	if quests.get(OUTPOST_SEAL, false) and not quests.get("outpost_patrol_route", false):
		return [nodes.front(), nodes.back()]
	return nodes

func can_enter_outpost() -> bool:
	return can_visit_guild() and guild_rank() == "E" and quest_flags.get(HOLLOW_REPORTED, false) and not quest_flags.get(OUTPOST_ALLIANCE, false) and traces < 3

func can_report_outpost() -> bool:
	return guild_visit_active() and guild_rank() == "E" and quest_flags.get(OUTPOST_ALLIANCE, false) and not quest_flags.get(OUTPOST_REPORTED, false)

func apply_outpost_command(command: String) -> bool:
	if in_combat or has_pending_reward() or awaiting_return or checkpoints.channel_active:
		return false
	match command:
		"enter":
			if not can_enter_outpost() or not seen_cue_ids.has(OUTPOST_ORDER_CUE):
				return false
			location_id = LOCATION_OUTPOST
			record_map_visit(LOCATION_OUTPOST)
			record_map_visit(LOCATION_LIOREN)
			world_flags.erase(WORLD_FLAG_GUILD_VISIT)
			return true
		"report":
			if not can_report_outpost() or not seen_cue_ids.has_all(outpost_definition()["report_cues"]):
				return false
			var report: Dictionary = outpost_definition()["report"]
			var silver: int = int(report["silver"])
			if wallet[SILVER] > MAX_ASTRAS - silver:
				return false
			wallet[SILVER] += silver
			if not memory_flags.get(OUTPOST_ECHOES_GRANTED, false):
				echoes += int(report["echoes"])
				memory_flags[OUTPOST_ECHOES_GRANTED] = true
			quest_flags[OUTPOST_REPORTED] = true
			return true
		"finish":
			if not guild_visit_active() or not quest_flags.get(OUTPOST_REPORTED, false) or quest_flags.get(OUTPOST_FINISHED, false):
				return false
			if not seen_cue_ids.has_all(outpost_definition()["epilogue_cues"]):
				return false
			quest_flags[OUTPOST_FINISHED] = true
			return true
	if location_id != LOCATION_OUTPOST or not quest_flags.get(HOLLOW_REPORTED, false):
		return false
	if command == "leave":
		location_id = LOCATION_LIOREN
		return true
	if traces >= 3 or command != outpost_stage():
		return false
	match command:
		"bowl":
			quest_flags[OUTPOST_BOWL] = true
		"seal":
			quest_flags[OUTPOST_SEAL] = true
			quest_flags["outpost_patrol_route"] = true
		"alliance":
			if not seen_cue_ids.has_all(outpost_node("alliance")["cues"]):
				return false
			quest_flags[OUTPOST_ALLIANCE] = true
		_:
			return false
	return true

static func expedition_battle_node(context: Dictionary) -> Dictionary:
	var node_id: String = String(context.get("route_node_id", ""))
	match context.get("encounter_mode", ""):
		ENCOUNTER_GROVE: return grove_node(node_id)
		ENCOUNTER_HOLLOW: return hollow_node(node_id)
		ENCOUNTER_OUTPOST: return outpost_node(node_id)
		ENCOUNTER_GUILD_ORDER: return GuildOrders.stage(context["route_id"], int(node_id), int(context["order_total"]))
		_: return {}

static func expedition_battle_matches(result: Dictionary, location: String, quests: Dictionary, npcs: Dictionary, order: Dictionary = {}) -> bool:
	match result["encounter_mode"]:
		ENCOUNTER_GROVE:
			return location == LOCATION_GROVE and result["route_node_id"] == grove_stage_for(quests, npcs)
		ENCOUNTER_HOLLOW:
			return location == LOCATION_HOLLOW and quests.get(GROVE_REPORTED, false) and result["route_node_id"] == hollow_stage_for(quests)
		ENCOUNTER_OUTPOST:
			return location == LOCATION_OUTPOST and quests.get(HOLLOW_REPORTED, false) and result["route_node_id"] == outpost_stage_for(quests)
		ENCOUNTER_GUILD_ORDER:
			return location == LOCATION_GUILD_ORDER and result["route_id"] == order.get("id") and result["route_node_id"] == str(int(order.get("cleared", -1))) and int(result["order_total"]) == int(order.get("total", 0))
		_:
			return true

func can_enter_hollow() -> bool:
	return can_visit_guild() and guild_rank() == "E" and quest_flags.get(GROVE_REPORTED, false) and traces < 3 and not checkpoints.channel_active

func can_report_hollow() -> bool:
	return guild_visit_active() and guild_rank() == "E" and quest_flags.get(GROVE_REPORTED, false) and quest_flags.get(HOLLOW_WATER_MARKER, false) and quest_flags.get(HOLLOW_UPPER_MARKER, false) and quest_flags.get(HOLLOW_CLOTH, false) and not quest_flags.get(HOLLOW_REPORTED, false)

func can_place_expedition_checkpoint() -> bool:
	if location_id == LOCATION_GROVE:
		return grove_stage() == "clearing"
	if location_id == LOCATION_HOLLOW:
		return hollow_stage() in ["shelf", "upper_guard", "ledge"]
	if location_id == LOCATION_OUTPOST:
		return outpost_stage() in ["bowl", "gate_patrol", "stairs_patrol", "tower_patrol", "warden", "alliance", "return"]
	return true

## Сюжетные команды Оврага проходят через ту же запись кандидата, что и Роща.
func apply_hollow_command(command: String) -> bool:
	if in_combat or has_pending_reward() or awaiting_return or checkpoints.channel_active:
		return false
	if command == "enter":
		if not can_enter_hollow() or not seen_cue_ids.has("DIA_HOLLOW_004"):
			return false
		location_id = LOCATION_HOLLOW
		record_map_visit(LOCATION_HOLLOW)
		record_map_visit(LOCATION_LIOREN)
		quest_flags[HOLLOW_STARTED] = true
		world_flags.erase(WORLD_FLAG_GUILD_VISIT)
		return true
	if command == "report":
		if not can_report_hollow() or not seen_cue_ids.has("DIA_HOLLOW_018"):
			return false
		var reward: Dictionary = hollow_definition()["report"]
		var silver: int = int(reward["silver"])
		if wallet[SILVER] > MAX_ASTRAS - silver:
			return false
		var previous_level: int = hero.level
		hero.gain_xp(int(reward["xp"]))
		wallet[SILVER] += silver
		if not memory_flags.get(HOLLOW_ECHOES_GRANTED, false):
			echoes += int(reward["echoes"])
			memory_flags[HOLLOW_ECHOES_GRANTED] = true
		quest_flags[HOLLOW_REPORTED] = true
		if previous_level < 4 and hero.level == 4:
			quest_flags[HOLLOW_LEVEL_FOUR] = true
		return true
	if location_id != LOCATION_HOLLOW or not quest_flags.get(GROVE_REPORTED, false):
		return false
	if command == "leave":
		location_id = LOCATION_LIOREN
		quest_flags.erase(HOLLOW_ELITE_ENTERED)
		return true
	var stage: String = hollow_stage()
	if command == "retreat":
		if stage != "elite":
			return false
		quest_flags.erase(HOLLOW_ELITE_ENTERED)
		quest_flags[HOLLOW_RETREATED] = true
		record_map_visit(MAP_HOLLOW_LEDGE)
		return true
	if traces >= 3:
		return false
	match command:
		"water_marker":
			if stage != "water_marker":
				return false
			var reward: Dictionary = hollow_definition()["water_marker_reward"]
			var definition: ItemDefinition = get_item_definition(reward["item_id"])
			inventory.add(definition, int(reward["quantity"]), reward["aspect_id"], reward)
			quest_flags[HOLLOW_WATER_MARKER] = true
		"collapse":
			if stage != "shelf" or quest_flags.get(HOLLOW_COLLAPSED, false) or not seen_cue_ids.has("DIA_HOLLOW_006"):
				return false
			quest_flags[HOLLOW_COLLAPSED] = true
		"upper_marker":
			if stage != "upper_marker" or not seen_cue_ids.has("DIA_HOLLOW_021"):
				return false
			quest_flags[HOLLOW_UPPER_MARKER] = true
			record_map_visit(MAP_HOLLOW_LEDGE)
		"cloth":
			if stage != "ledge" or quest_flags.get(HOLLOW_CLOTH, false) or not seen_cue_ids.has("DIA_HOLLOW_007"):
				return false
			quest_flags[HOLLOW_CLOTH] = true
		"descend":
			if stage != "ledge" or not quest_flags.get(HOLLOW_CLOTH, false) or quest_flags.get(HOLLOW_ELITE_WON, false):
				return false
			quest_flags[HOLLOW_ELITE_ENTERED] = true
			record_map_visit(MAP_HOLLOW_BASIN)
		_:
			return false
	return true

func coin_exchange_quote(from_coin: String, to_coin: String) -> Dictionary:
	var from_index: int = COIN_TYPES.find(from_coin)
	var to_index: int = COIN_TYPES.find(to_coin)
	if from_index < 0 or to_index < 0 or absi(from_index - to_index) != 1:
		return {}
	var spend: int = EXCHANGE_RATE if from_index < to_index else 1
	var receive: int = 1 if from_index < to_index else EXCHANGE_RATE
	var from_balance: int = wallet[from_coin]
	var to_balance: int = wallet[to_coin]
	@warning_ignore("integer_division")
	var max_quantity: int = mini(from_balance / spend, (MAX_ASTRAS - to_balance) / receive)
	return {
		"spend": spend,
		"receive": receive,
		"from_balance": from_balance,
		"to_balance": to_balance,
		"max_quantity": max_quantity,
	}

func exchange_coins(from_coin: String, to_coin: String, quantity: int, expected_quote: Dictionary) -> bool:
	if not can_trade() or _claim_in_progress or checkpoints.channel_active or quantity < 1:
		return false
	var quote: Dictionary = coin_exchange_quote(from_coin, to_coin)
	if quote.is_empty() or quote != expected_quote or quantity > int(quote["max_quantity"]):
		return false
	var spent: int = int(quote["spend"]) * quantity
	var received: int = int(quote["receive"]) * quantity
	wallet[from_coin] -= spent
	wallet[to_coin] += received
	last_deal = {
		"kind": "exchange",
		"from_coin": from_coin,
		"to_coin": to_coin,
		"spent": spent,
		"received": received,
	}
	profile_changed.emit()
	return true

static var _shop_catalog_cache: Dictionary = {}

static func shop_catalog() -> Dictionary:
	if _shop_catalog_cache.is_empty():
		var file: FileAccess = FileAccess.open(SHOP_CATALOG_PATH, FileAccess.READ)
		if file == null:
			return {"shop_id": "cricket_twilight", "offers": []}
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
			_shop_catalog_cache = {"shop_id": "cricket_twilight", "offers": []}
		else:
			_shop_catalog_cache = parser.data
	return _shop_catalog_cache

## Живой список предложений: статика каталога + состояние из флагов профиля.
## remaining == -1 — без лимита; sold_out пересчитывается из once_flag, поэтому
## откат Печатью восстанавливает одноразовое предложение сам.
func shop_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for offer: Variant in shop_catalog().get("offers", []):
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		var offer_id: String = String(offer.get("offer_id", ""))
		var definition: ItemDefinition = get_item_definition(String(offer.get("item_id", "")))
		if offer_id.is_empty() or definition == null:
			continue
		var once_flag: String = String(offer.get("once_flag", ""))
		var limit: int = maxi(0, int(offer.get("purchase_limit", 0)))
		var remaining: int = -1
		if limit > 0:
			remaining = limit - (1 if not once_flag.is_empty() and bool(world_flags.get(once_flag, false)) else 0)
		offers.append({
			"offer_id": offer_id,
			"item_id": definition.id,
			"display_name": definition.display_name,
			"price_copper": maxi(0, int(offer.get("price_copper", definition.sale_price_copper))),
			"purchase_limit": limit,
			"remaining": remaining,
			"sold_out": remaining == 0,
			"once_flag": once_flag,
		})
	return offers

## Покупка по предложению каталога. Одна сделка — один проход: проверки,
## списание и выдача идут внутри транзакции, вехи пишутся вместе со сделкой.
func equipment_upgrade_quote(instance_id: String) -> Dictionary:
	if not can_trade() or guild_rank().is_empty():
		return {}
	var item: ItemInstance = inventory.get_item(instance_id)
	if item == null or item.level >= GuildOrders.RANKS.size():
		return {}
	var definition: ItemDefinition = get_item_definition(item.definition_id)
	if definition.slot_id.is_empty() or definition.modifiers.is_empty():
		return {}
	return {"id": instance_id, "level": item.level, "price": 12 * item.level * item.level}

func upgrade_equipment(quote: Dictionary) -> bool:
	if quote.is_empty() or quote != equipment_upgrade_quote(quote.get("id", "")):
		return false
	var price: int = quote["price"]
	if checkpoints.channel_active or wallet[COPPER] < price:
		return false
	wallet[COPPER] -= price
	inventory.upgrade_equipment(quote["id"], int(quote["level"]) + 1)
	profile_changed.emit()
	return true

func buy_item(offer_id: String, quantity: int = 1, expected_price: int = -1) -> bool:
	if in_combat or awaiting_return or has_pending_reward() or _claim_in_progress or quantity <= 0:
		return false
	if not shop_access_unlocked():
		return false
	var offer: Dictionary = {}
	for candidate: Dictionary in shop_offers():
		if String(candidate.get("offer_id", "")) == offer_id:
			offer = candidate
			break
	if offer.is_empty() or bool(offer.get("sold_out", false)):
		return false
	if int(offer.get("remaining", -1)) >= 0 and quantity > int(offer["remaining"]):
		return false
	var definition: ItemDefinition = get_item_definition(String(offer.get("item_id", "")))
	if definition == null:
		return false
	var price: int = int(offer.get("price_copper", 0))
	if expected_price >= 0 and price != expected_price:
		return false
	var total: int = trade_total(price, quantity)
	if total <= 0 or wallet[COPPER] < total:
		return false
	_claim_in_progress = true
	_transaction_depth += 1
	wallet[COPPER] -= total
	var affected: Array[ItemInstance] = inventory.add(definition, quantity)
	var instance_ids: Array[String] = []
	for item: ItemInstance in affected:
		instance_ids.append(item.instance_id)
	var once_flag: String = String(offer.get("once_flag", ""))
	if not once_flag.is_empty():
		world_flags[once_flag] = true
	if not bool(world_flags.get(WORLD_FLAG_SHOP_FIRST_PURCHASE_DONE, false)):
		world_flags[WORLD_FLAG_SHOP_FIRST_PURCHASE_DONE] = true
	last_deal = {
		"kind": "buy",
		"offer_id": offer_id,
		"item_id": definition.id,
		"display_name": definition.display_name,
		"quantity": quantity,
		"unit_price_copper": price,
		"total_copper": total,
		"instance_ids": instance_ids,
		"balance_after": wallet[COPPER],
	}
	_transaction_depth -= 1
	_claim_in_progress = false
	profile_changed.emit()
	return true

func get_item_definition(item_id: String) -> ItemDefinition:
	return item_definitions.get(item_id)

func choose_upgrade(upgrade_id: String, character_id: String = "haruto") -> bool:
	if in_combat or awaiting_return or has_pending_reward() or _claim_in_progress:
		return false
	var state: CharacterState = character_state(character_id)
	if state == null or not state.choose_upgrade(upgrade_id):
		return false
	profile_changed.emit()
	return true

func apply_state_dto(dto: Dictionary) -> void:
	_invalidate_active_resolver()
	_selected_repeat = false
	_claim_in_progress = false
	var meta: Dictionary = dto["meta"]
	traces = int(meta["traces"])
	apply_profile_dto(dto["profile"])
	echoes = int(meta["echoes"])
	claimed_echo_enemy_ids = meta["claimed_echo_enemy_ids"].duplicate(true)
	trial_echo_claimed = bool(meta.get("trial_echo_claimed", false))
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
	pending_battle_result = dto.get("pending_battle_result", {}).duplicate(true)
	if not pending_battle_result.is_empty() and not is_valid_pending_battle_result(pending_battle_result):
		pending_battle_result = {}
	pending_story_reward = dto.get("pending_story_reward", {}).duplicate(true)
	in_combat = false
	is_pursued = false
	is_moving = false
	# Формат боя живёт вне профиля и вне Checkpoint: загружаем из save DTO,
	# некорректное значение даёт default auto.
	var loaded_format: String = String(dto.get("combat_format", COMBAT_FORMAT_AUTO))
	combat_format = loaded_format if loaded_format in [COMBAT_FORMAT_AUTO, COMBAT_FORMAT_ACTIVE] else COMBAT_FORMAT_AUTO
	_deliver_legacy_pending_rewards()
	checkpoints.apply_dto(dto["checkpoints"])
	profile_changed.emit()

func capture_profile_dto() -> Dictionary:
	return {
		"hero": hero.capture_dto(),
		"inventory": inventory.capture_dto(),
		# JSON parses numbers as floats. Strings keep every coin at int64 precision.
		"wallet": {COPPER: str(wallet[COPPER]), SILVER: str(wallet[SILVER]), GOLD: str(wallet[GOLD])},
		"quest_flags": quest_flags.duplicate(true),
		"guild_order": guild_order.duplicate(true),
		"npc_flags": npc_flags.duplicate(true),
		"world_flags": world_flags.duplicate(true),
		"completed_encounter_ids": completed_encounter_ids().duplicate(true),
		"route_state": route_state.duplicate(true),
		"run_sequence": run_sequence,
		"play_tick": play_tick,
		"last_claimed_result_id": last_claimed_result_id,
		"characters": _capture_characters(),
		"familiars": familiars.duplicate(true),
		"story_rewards": story_rewards.duplicate(true),
	}

func _capture_characters() -> Dictionary:
	var result: Dictionary = {}
	for character_id: String in characters:
		result[character_id] = characters[character_id].capture_dto()
	return result

func apply_profile_dto(dto: Dictionary) -> void:
	_invalidate_active_resolver()
	_selected_repeat = false
	in_combat = false
	hero = CharacterState.new(load(ACTOR_PATHS["haruto"]))
	inventory = InventoryService.new(hero, item_definitions)
	characters = {}
	familiars = dto.get("familiars", {"owned": {}, "assignments": {}}).duplicate(true)
	story_rewards = dto.get("story_rewards", {}).duplicate(true)
	var saved_wallet: Dictionary = dto.get("wallet", {})
	for coin: String in COIN_TYPES:
		wallet[coin] = maxi(0, int(saved_wallet.get(coin, "0")))
	quest_flags = dto.get("quest_flags", {}).duplicate(true)
	guild_order = dto.get("guild_order", {}).duplicate(true)
	npc_flags = dto.get("npc_flags", {}).duplicate(true)
	world_flags = dto.get("world_flags", {}).duplicate(true)
	for character_id: String in available_character_ids():
		if character_id == "haruto":
			continue
		_sync_companion(character_id)
		if dto.get("characters", {}).has(character_id):
			characters[character_id].apply_dto(dto["characters"][character_id])
	inventory.apply_dto(dto.get("inventory", {}))
	hero.set_void_traces(traces)
	hero.apply_dto(dto.get("hero", {}))
	_apply_familiar_modifiers()
	_beaten_encounter_ids = dto.get("completed_encounter_ids", {}).duplicate(true)
	route_state = dto.get("route_state", {}).duplicate(true)
	if route_state.is_empty():
		# Legacy v1 без поля маршрута: честно выводим пройденные узлы из журнала.
		route_state = _derive_route_state(_beaten_encounter_ids)
	elif not is_valid_route_state(route_state):
		# Невалидное непустое состояние не применяем частично: безопасная замена.
		route_state = _derive_route_state(_beaten_encounter_ids)
	run_sequence = maxi(0, int(dto.get("run_sequence", 0)))
	play_tick = maxi(0, int(dto.get("play_tick", 0)))
	pending_reward.clear()
	last_settlement = {}
	last_deal = {}
	last_claimed_result_id = String(dto.get("last_claimed_result_id", ""))
	_settled_run_ids.clear()
	_finished_run_contexts.clear()
	pending_receive_fx = false

func completed_encounter_ids() -> Dictionary:
	return _beaten_encounter_ids

func _on_combat_finished(won: bool, resolver: CombatResolver) -> void:
	if resolver == null or resolver != active_resolver or not resolver.is_active:
		return
	_remember_encounter_enemies(resolver)
	var context: Dictionary = active_encounter_context.duplicate(true)
	var run_id: String = String(context.get("run_id", ""))
	var enemy_id: String = String(context.get("enemy_id", ""))
	if won:
		_finished_run_contexts[run_id] = context
	_invalidate_active_resolver()
	in_combat = false
	if won:
		settle_combat(run_id, enemy_id)
	else:
		awaiting_return = true
		profile_changed.emit()

func _remember_encounter_enemies(resolver: CombatResolver) -> void:
	for slot: CombatResolver.EnemySlot in resolver.enemy_slots:
		if not slot.dormant:
			enemy_journal[slot.actor.definition.id] = true

func _invalidate_active_resolver() -> void:
	if active_resolver != null:
		active_resolver.invalidate()
	active_resolver = null
	active_encounter_context = {}

func _advance_route(result: Dictionary) -> bool:
	if result["encounter_mode"] == ENCOUNTER_GUILD_ORDER:
		guild_order["cleared"] = int(guild_order["cleared"]) + 1
		return true
	if EXPEDITION_ROUTES.has(result["encounter_mode"]):
		var node: Dictionary = expedition_battle_node(result)
		if not expedition_battle_matches(result, location_id, quest_flags, npc_flags):
			return false
		quest_flags[node["cleared_flag"]] = true
		if result["encounter_mode"] == ENCOUNTER_HOLLOW:
			if node["cleared_flag"] == HOLLOW_SHELF_WON:
				quest_flags[HOLLOW_TEMPO] = true
			if node["cleared_flag"] == HOLLOW_ELITE_WON:
				quest_flags.erase(HOLLOW_ELITE_ENTERED)
		return true
	if result.get("encounter_mode", "") != ENCOUNTER_ROUTE or route_state.get("completed", false):
		return false
	if String(result.get("route_id", "")) != String(route_state.get("route_id", "")):
		return false
	var nodes: Array = route_nodes()
	var index: int = int(route_state.get("next_index", 0))
	if index < 0 or index >= nodes.size():
		return false
	var node: Dictionary = nodes[index]
	if String(node.get("node_id", "")) != String(result.get("route_node_id", "")) or String(node.get("enemy_id", "")) != String(result.get("enemy_id", "")):
		return false
	index += 1
	route_state["next_index"] = index
	route_state["completed"] = index >= nodes.size()
	return true

func _is_known_enemy(enemy_id: String) -> bool:
	return ACTOR_PATHS.has(enemy_id) and enemy_id != "haruto"

## Строгая валидация маршрута: известный route_id, целый индекс 0…N и
## согласованность completed. Общая политика для профиля и Checkpoint-снимков.
static func is_valid_route_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	if typeof(state.get("route_id", null)) != TYPE_STRING or String(state["route_id"]).is_empty():
		return false
	if typeof(state.get("completed", null)) != TYPE_BOOL:
		return false
	if not _is_intlike_number(state.get("next_index", null)):
		return false
	var nodes: Array = route_definition().get("nodes", [])
	if String(state["route_id"]) != String(route_definition().get("route_id", "")):
		return false
	var index: int = int(state["next_index"])
	if index < 0 or index > nodes.size():
		return false
	if bool(state["completed"]) != (index >= nodes.size()):
		return false
	return true

## Допустимая форма pending-result; неизвестный DTO отвергается целиком.
static func is_valid_pending_battle_result(result: Dictionary) -> bool:
	if result.is_empty():
		return false
	if typeof(result.get("choices", null)) != TYPE_DICTIONARY:
		return false
	if typeof(result.get("result_id", null)) != TYPE_STRING or String(result["result_id"]).is_empty():
		return false
	if typeof(result.get("run_id", null)) != TYPE_STRING or String(result["run_id"]).is_empty():
		return false
	if result.has("run_token") and typeof(result["run_token"]) != TYPE_STRING:
		return false
	if typeof(result.get("enemy_id", null)) != TYPE_STRING or not GameSession.ACTOR_PATHS.has(result["enemy_id"]) or result["enemy_id"] == "haruto":
		return false
	if typeof(result.get("encounter_mode", null)) != TYPE_STRING:
		return false
	if typeof(result.get("route_node_id", null)) != TYPE_STRING or typeof(result.get("route_id", null)) != TYPE_STRING:
		return false
	var enemy_id: String = String(result["enemy_id"])
	var mode: String = String(result["encounter_mode"])
	var is_expedition: bool = EXPEDITION_ROUTES.has(mode)
	if mode == ENCOUNTER_GUILD_ORDER:
		var index_text: String = result["route_node_id"]
		var progress: Dictionary = {"id": result["route_id"], "total": result.get("order_total"), "cleared": int(index_text)}
		if not index_text.is_valid_int() or not GuildOrders.valid_progress(progress) or expedition_battle_node(result).get("enemy_id", "") != enemy_id:
			return false
	elif is_expedition:
		var expected_route: String = EXPEDITION_ROUTES[mode]
		if result["route_id"] != expected_route or expedition_battle_node(result).get("enemy_id", "") != enemy_id:
			return false
	else:
		if result["route_id"] != route_definition().get("route_id", ""):
			return false
		match mode:
			ENCOUNTER_REPEAT:
				if not route_definition().get("repeat_enemies", {}).has(enemy_id):
					return false
			ENCOUNTER_ROUTE, ENCOUNTER_TRIAL:
				if not LOOT_PATHS.has(enemy_id):
					return false
			_:
				return false
	if mode == ENCOUNTER_TRIAL and enemy_id != TRIAL_ENEMY_ID:
		return false
	if mode != ENCOUNTER_TRIAL and enemy_id == TRIAL_ENEMY_ID:
		return false
	if mode == ENCOUNTER_ROUTE:
		var matching_node: bool = false
		for node: Dictionary in route_definition().get("nodes", []):
			if String(node.get("node_id", "")) == String(result["route_node_id"]) and String(node.get("enemy_id", "")) == enemy_id:
				matching_node = true
				break
		if not matching_node:
			return false
	elif not is_expedition and mode != ENCOUNTER_GUILD_ORDER and not String(result["route_node_id"]).is_empty():
		return false
	if typeof(result.get("xp", null)) == TYPE_NIL or not _is_intlike_number(result["xp"]) or int(result["xp"]) < 0:
		return false
	if typeof(result.get("echo_gained", null)) != TYPE_BOOL or typeof(result.get("trial_echo_gained", null)) != TYPE_BOOL:
		return false
	if typeof(result.get("loot_seed", null)) != TYPE_STRING or typeof(result.get("loot_state", null)) != TYPE_STRING:
		return false
	if not String(result["loot_state"]).is_valid_int():
		return false
	if typeof(result.get("items", null)) != TYPE_ARRAY:
		return false
	for entry: Variant in result["items"]:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		if typeof(entry.get("item_id", null)) != TYPE_STRING or not GameSession.ITEM_PATHS.has(entry["item_id"]):
			return false
		if not _is_intlike_number(entry.get("quantity", null)) or int(entry["quantity"]) < 1:
			return false
		if typeof(entry.get("aspect_id", null)) != TYPE_STRING or typeof(entry.get("slot_id", null)) != TYPE_STRING:
			return false
		if typeof(entry.get("entry_id", null)) != TYPE_STRING or String(entry["entry_id"]).is_empty():
			return false
		if not _is_intlike_number(entry.get("level", null)) or int(entry["level"]) < 1 or not _is_intlike_number(entry.get("sale_price_copper", null)) or int(entry["sale_price_copper"]) < 0 or typeof(entry.get("sellable", null)) != TYPE_BOOL:
			return false
		var definition: ItemDefinition = load(GameSession.ITEM_PATHS[entry["item_id"]])
		if String(entry["slot_id"]) != definition.slot_id:
			return false
		if result["choices"].has(entry["entry_id"]):
			var choice: Variant = result["choices"][entry["entry_id"]]
			if typeof(choice) != TYPE_DICTIONARY or choice.get("result_id", "") != result["result_id"] or choice.get("action", "") not in ["store", "equip"]:
				return false
			if choice["action"] == "equip" and definition.slot_id.is_empty():
				return false
	return true

static func _is_intlike_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == floorf(float(value))

## Честная производная для сейвов v1: сколько узлов маршрута уже пройдено.
func _derive_route_state(beaten: Dictionary) -> Dictionary:
	var state: Dictionary = _initial_route_state()
	var index: int = 0
	if beaten.has("goblin_scout"):
		index = route_nodes().size()
	elif world_flags.get("daijiro_intervened", false):
		index = 2
	elif beaten.has("moss_slime"):
		index = 1
	state["next_index"] = index
	state["completed"] = index >= route_nodes().size()
	return state

func _initial_route_state() -> Dictionary:
	return {
		"route_id": String(route_definition().get("route_id", "forest_edge_slice")),
		"next_index": 0,
		"completed": false,
	}

## Единственный идемпотентный путь доставки наград старого формата:
## v1 начислял XP сразу, поэтому здесь только предметы, без повторного XP.
func _deliver_legacy_pending_rewards() -> void:
	if pending_reward.is_empty():
		return
	for reward: Dictionary in pending_reward:
		var definition: ItemDefinition = get_item_definition(reward.get("item_id", ""))
		if definition == null:
			continue
		inventory.add(
			definition,
			int(reward.get("quantity", 0)),
			String(reward.get("aspect_id", ""))
		)
	pending_reward.clear()
	pending_receive_fx = true
