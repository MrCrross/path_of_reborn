class_name GameSession
extends RefCounted

signal profile_changed
signal combat_format_changed(format: String)
signal auto_speed_changed(speed: int)
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

const ACTOR_PATHS: Dictionary = {
	"haruto": "res://data/actors/haruto.tres",
	"moss_slime": "res://data/actors/moss_slime.tres",
	"goblin_scout": "res://data/actors/goblin_scout.tres",
	TRIAL_ENEMY_ID: "res://data/actors/goblin_trial.tres",
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
}
const LOCATION_FOREST_EDGE: String = "forest_edge"
const LOCATION_LIOREN: String = "lioren"
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
const LOOT_PATHS: Dictionary = {
	"moss_slime": "res://data/loot/moss_slime.tres",
	"goblin_scout": "res://data/loot/goblin_scout.tres",
	# Испытание переиспользует обычную таблицу добычи гоблина (осознанное решение).
	TRIAL_ENEMY_ID: "res://data/loot/goblin_scout.tres",
}
const ROUTE_PATH: String = "res://data/route/forest_slice.json"

static var _route_definition_cache: Dictionary = {}

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
	var resolver := CombatResolver.new(hero, enemy_definition, run_id)
	resolver.run_token = context["run_token"]
	resolver.combat_format = combat_format
	resolver.auto_attack_enabled = combat_format == COMBAT_FORMAT_AUTO
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

## Повторяемые враги — узлы, которые уже пройдены (индекс < next_index).
func route_repeat_enemy_ids() -> Array[String]:
	var result: Array[String] = []
	var nodes: Array = route_nodes()
	var limit: int = mini(int(route_state.get("next_index", 0)), nodes.size())
	for index: int in range(limit):
		var enemy_id: String = String(nodes[index].get("enemy_id", ""))
		if not enemy_id.is_empty() and not result.has(enemy_id):
			result.append(enemy_id)
	return result

func _encounter_context_for(enemy_id: String, repeat: bool) -> Dictionary:
	if not _is_known_enemy(enemy_id):
		return {}
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
	return trial_available() and not in_combat and not awaiting_return and not has_pending_reward() and traces < 3 and not _claim_in_progress

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
	if not LOOT_PATHS.has(enemy_id):
		return false
	_settled_run_ids[run_id] = true
	var enemy_definition: ActorDefinition = load(ACTOR_PATHS[enemy_id])
	var rewards: Array = loot_generator.generate(load(LOOT_PATHS[enemy_id]), loot_rng).duplicate(true)
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
		"xp": enemy_definition.xp_reward,
		"echo_gained": not claimed_echo_enemy_ids.has(enemy_id),
		"trial_echo_gained": enemy_id == TRIAL_ENEMY_ID and not trial_echo_claimed,
		"loot_seed": loot_seed,
		"loot_state": str(loot_rng.state),
	}
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
	if bool(pending_battle_result.get("echo_gained", false)) and not claimed_echo_enemy_ids.has(enemy_id):
		claimed_echo_enemy_ids[enemy_id] = true
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
	_beaten_encounter_ids[enemy_id] = true
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

## Переход между открытыми точками маршрута. Не отменяет канал Печати и не
## лечит: это перемещение, а не возврат. Доступность точек решает UI по флагам.
func travel_to(location_id: String) -> bool:
	if in_combat or has_pending_reward() or awaiting_return or _claim_in_progress:
		return false
	if location_id != LOCATION_FOREST_EDGE and location_id != LOCATION_LIOREN:
		return false
	if location_id == self.location_id:
		return true
	if location_id == LOCATION_FOREST_EDGE and traces == 3:
		return false
	self.location_id = location_id
	profile_changed.emit()
	return true

func shop_access_unlocked() -> bool:
	return bool(world_flags.get(WORLD_FLAG_LIOREN_SHOP_UNLOCKED, false))

func can_trade() -> bool:
	return location_id == LOCATION_LIOREN and shop_access_unlocked() and not in_combat and not awaiting_return and not has_pending_reward()

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

func _invalidate_active_resolver() -> void:
	if active_resolver != null:
		active_resolver.invalidate()
	active_resolver = null
	active_encounter_context = {}

func _advance_route(result: Dictionary) -> bool:
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
	if typeof(result.get("encounter_mode", null)) != TYPE_STRING or result["encounter_mode"] not in [ENCOUNTER_ROUTE, ENCOUNTER_REPEAT, ENCOUNTER_TRIAL]:
		return false
	if typeof(result.get("route_node_id", null)) != TYPE_STRING or typeof(result.get("route_id", null)) != TYPE_STRING:
		return false
	if String(result["route_id"]) != String(route_definition().get("route_id", "")):
		return false
	var enemy_id: String = String(result["enemy_id"])
	var mode: String = String(result["encounter_mode"])
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
	elif not String(result["route_node_id"]).is_empty():
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
