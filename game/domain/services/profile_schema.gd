extends RefCounted

## Versioned profile DTOs are migrated on a deep copy, then validated before
## any live session or Checkpoint state is replaced.
const CURRENT_VERSION: int = 7

static func migrate(source: Dictionary) -> Dictionary:
	var dto: Dictionary = source.duplicate(true)
	if not _is_intlike(dto.get("schema_version")):
		return {}
	var version: int = int(dto["schema_version"])
	if version > CURRENT_VERSION or version < 0:
		return {}
	while version < CURRENT_VERSION:
		match version:
			0:
				if not dto.has("loot_seed") or not dto.has("loot_state"):
					return {}
				dto["loot"] = {"seed": dto["loot_seed"], "state": dto["loot_state"]}
				dto.erase("loot_seed")
				dto.erase("loot_state")
			1:
				# v2: маршрут и счётчик попыток боя живут в профиле.
				# Значения по умолчанию; GameSession при загрузке честно
				# выводит маршрут из completed_encounter_ids, если поле пустое.
				if not _add_legacy_route(dto.get("profile")) or not _migrate_checkpoint_profiles(dto.get("checkpoints"), _add_legacy_route):
					return {}
			2:
				# v3: двухэтапная награда и формат боя. Важно: награды v2 уже
				# выданы в инвентарь — их НЕЛЬЗЯ превращать в новый pending
				# (иначе повторная выдача). Старый сейв просто получает пустой
				# pending и default-формат; pending_reward legacy сохраняется.
				if typeof(dto.get("profile")) != TYPE_DICTIONARY:
					return {}
				var v3_profile: Dictionary = dto["profile"]
				if not v3_profile.has("pending_battle_result"):
					v3_profile["pending_battle_result"] = {}
				if not v3_profile.has("last_claimed_result_id"):
					v3_profile["last_claimed_result_id"] = ""
				if not v3_profile.has("trial_echo_claimed"):
					v3_profile["trial_echo_claimed"] = false
				if not dto.has("pending_battle_result"):
					dto["pending_battle_result"] = {}
				if not dto.has("combat_format"):
					dto["combat_format"] = GameSession.COMBAT_FORMAT_AUTO
			3:
				if not _migrate_v3_to_v4(dto):
					return {}
			4:
				if not _migrate_v4_to_v5(dto):
					return {}
			5:
				if not _migrate_v5_to_v6(dto):
					return {}
			6:
				if not _migrate_v6_to_v7(dto):
					return {}
			_:
				return {}
		version += 1
		dto["schema_version"] = version
	return dto

static func _add_legacy_route(profile: Variant) -> bool:
	if not profile is Dictionary:
		return false
	profile.get_or_add("route_state", {})
	profile.get_or_add("run_sequence", 0)
	return true

## Every profile-bearing snapshot follows the same migration as the live
## profile. An incomplete snapshot invalidates the entire candidate document.
static func _migrate_checkpoint_profiles(checkpoints: Variant, migrate_profile: Callable) -> bool:
	if not checkpoints is Dictionary or not checkpoints.get("manual_snapshots") is Array:
		return false
	var pending: Variant = checkpoints.get("pending_completion", {})
	if not pending is Dictionary:
		return false
	var snapshots: Array = [checkpoints.get("first_trace_snapshot")]
	snapshots.append_array(checkpoints["manual_snapshots"])
	if not pending.is_empty():
		snapshots.append(pending)
	for snapshot: Variant in snapshots:
		if not snapshot is Dictionary or not snapshot.get("profile") is Dictionary or not migrate_profile.call(snapshot["profile"]):
			return false
	return true

static func _migrate_v6_to_v7(dto: Dictionary) -> bool:
	if not _migrate_copper_wallet(dto.get("profile")):
		return false
	if typeof(dto.get("pending_battle_result")) != TYPE_DICTIONARY or typeof(dto.get("checkpoints")) != TYPE_DICTIONARY:
		return false
	var pending_items: Variant = dto["pending_battle_result"].get("items", [])
	if typeof(pending_items) != TYPE_ARRAY:
		return false
	_reprice_echo_crystals(pending_items, "item_id")
	return _migrate_checkpoint_profiles(dto["checkpoints"], _migrate_copper_wallet)

static func _migrate_copper_wallet(profile: Variant) -> bool:
	if typeof(profile) != TYPE_DICTIONARY or typeof(profile.get("inventory")) != TYPE_DICTIONARY:
		return false
	var copper: Variant = profile.get("currency")
	if not _nonnegative(copper) or float(copper) > float(GameSession.MAX_ASTRAS):
		return false
	# В старом числовом формате JSON округлял верхнюю границу до 2^63.
	var at_legacy_limit: bool = typeof(copper) == TYPE_FLOAT and copper == float(GameSession.MAX_ASTRAS)
	var amount: int = GameSession.MAX_ASTRAS if at_legacy_limit else int(copper)
	profile["wallet"] = {GameSession.COPPER: str(amount), GameSession.SILVER: "0", GameSession.GOLD: "0"}
	profile.erase("currency")
	var items: Variant = profile["inventory"].get("items")
	if typeof(items) != TYPE_ARRAY:
		return false
	_reprice_echo_crystals(items, "definition_id")
	return true

static func _reprice_echo_crystals(items: Array, id_key: String) -> void:
	for item: Variant in items:
		if typeof(item) == TYPE_DICTIONARY and item.get(id_key) == "echo_crystal" and item.get("sale_price_copper") == 2000:
			item["sale_price_copper"] = 20

## The new slime sits between the two old nodes. Keep profiles and Checkpoint
## snapshots already at the cart on the goblin node, including pending victories.
static func _migrate_v5_to_v6(dto: Dictionary) -> bool:
	if typeof(dto.get("checkpoints")) != TYPE_DICTIONARY or typeof(dto.get("pending_battle_result")) != TYPE_DICTIONARY:
		return false
	var pending: Dictionary = dto["pending_battle_result"]
	var at_cart: bool = pending.get("route_node_id", "") == "forest_edge_goblin"
	if not _migrate_forest_route(dto.get("profile"), at_cart):
		return false
	return _migrate_checkpoint_profiles(dto["checkpoints"], _migrate_forest_route)

static func _migrate_forest_route(profile: Variant, pending_goblin: bool = false) -> bool:
	if typeof(profile) != TYPE_DICTIONARY or typeof(profile.get("route_state")) != TYPE_DICTIONARY or typeof(profile.get("world_flags")) != TYPE_DICTIONARY:
		return false
	var route: Dictionary = profile["route_state"]
	if route.is_empty():
		if pending_goblin:
			profile["route_state"] = {"route_id": "forest_edge_slice", "next_index": 2, "completed": false}
		return true
	var index: Variant = route.get("next_index")
	if route.get("route_id", "") != "forest_edge_slice" or not _is_intlike(index) or int(index) not in [0, 1, 2] or route.get("completed") != (int(index) == 2):
		return false
	if int(index) == 2:
		route["next_index"] = 3
	elif int(index) == 1 and (pending_goblin or profile["world_flags"].get("daijiro_intervened", false)):
		route["next_index"] = 2
	return true

static func _migrate_v3_to_v4(dto: Dictionary) -> bool:
	if typeof(dto.get("profile")) != TYPE_DICTIONARY or typeof(dto.get("meta")) != TYPE_DICTIONARY or typeof(dto.get("checkpoints")) != TYPE_DICTIONARY:
		return false
	var profile: Dictionary = dto["profile"]
	var meta: Dictionary = dto["meta"]
	var profile_pending: Variant = profile.get("pending_battle_result", {})
	var root_pending: Variant = dto.get("pending_battle_result", {})
	if typeof(profile_pending) != TYPE_DICTIONARY or typeof(root_pending) != TYPE_DICTIONARY:
		return false
	# The v3 runtime read the profile copy first. Card fields absent in that
	# version are supplied by v4 → v5 and checked after all migrations.
	var pending: Dictionary = root_pending if profile_pending.is_empty() else profile_pending
	if not pending.is_empty() and not pending.has("route_id"):
		pending["route_id"] = GameSession.route_definition()["route_id"]
	dto["pending_battle_result"] = pending
	profile.erase("pending_battle_result")
	var profile_trial: Variant = profile.get("trial_echo_claimed", false)
	var meta_trial: Variant = meta.get("trial_echo_claimed", false)
	if typeof(profile_trial) != TYPE_BOOL or typeof(meta_trial) != TYPE_BOOL:
		return false
	meta["trial_echo_claimed"] = bool(profile_trial) or bool(meta_trial)
	profile.erase("trial_echo_claimed")
	return _migrate_checkpoint_profiles(dto["checkpoints"], _migrate_v3_snapshot_profile)

static func _migrate_v3_snapshot_profile(profile: Dictionary) -> bool:
	var pending: Variant = profile.get("pending_battle_result", {})
	if typeof(pending) != TYPE_DICTIONARY or not pending.is_empty():
		return false
	profile.erase("pending_battle_result")
	profile.erase("trial_echo_claimed")
	return true

static func _migrate_v4_to_v5(dto: Dictionary) -> bool:
	if typeof(dto.get("profile")) != TYPE_DICTIONARY or typeof(dto.get("checkpoints")) != TYPE_DICTIONARY:
		return false
	if not _migrate_v4_profile(dto["profile"]):
		return false
	if typeof(dto.get("pending_battle_result")) != TYPE_DICTIONARY:
		return false
	if not _migrate_v4_pending(dto["pending_battle_result"]):
		return false
	dto["pending_story_reward"] = {}
	return _migrate_checkpoint_profiles(dto["checkpoints"], _migrate_v4_profile)

static func _migrate_v4_profile(profile: Dictionary) -> bool:
	if typeof(profile.get("inventory")) != TYPE_DICTIONARY:
		return false
	var inventory: Dictionary = profile["inventory"]
	if typeof(inventory.get("items")) != TYPE_ARRAY:
		return false
	for item: Variant in inventory["items"]:
		if typeof(item) != TYPE_DICTIONARY:
			return false
		var definition_id: String = String(item.get("definition_id", ""))
		if not GameSession.ITEM_PATHS.has(definition_id):
			return false
		var definition: ItemDefinition = load(GameSession.ITEM_PATHS[definition_id])
		if definition == null:
			return false
		item["level"] = definition.level
		item["sale_price_copper"] = definition.sale_price_copper
		item["sellable"] = definition.sellable
	inventory["character_equipment"] = {}
	profile["characters"] = {}
	profile["familiars"] = {"owned": {}, "assignments": {}}
	profile["story_rewards"] = {}
	return true

static func _migrate_v4_pending(result: Dictionary) -> bool:
	if result.is_empty():
		return true
	if not result.get("items") is Array:
		return false
	result["choices"] = {}
	var items: Array = result["items"]
	for index: int in range(items.size()):
		if typeof(items[index]) != TYPE_DICTIONARY:
			return false
		var entry: Dictionary = items[index]
		var item_id: String = String(entry.get("item_id", ""))
		if not GameSession.ITEM_PATHS.has(item_id):
			return false
		var definition: ItemDefinition = load(GameSession.ITEM_PATHS[item_id])
		if definition == null:
			return false
		entry["entry_id"] = "entry_%06d" % (index + 1)
		entry["level"] = definition.level
		entry["sale_price_copper"] = definition.sale_price_copper
		entry["sellable"] = definition.sellable
	return true

static func validate(dto: Dictionary) -> bool:
	if not _has_keys(dto, ["schema_version", "profile", "meta", "checkpoints", "location_id", "current_enemy_id", "pending_reward", "pending_battle_result", "pending_story_reward", "combat_format", "loot", "awaiting_return"]):
		return false
	if not _is_intlike(dto["schema_version"]) or int(dto["schema_version"]) != CURRENT_VERSION or typeof(dto["awaiting_return"]) != TYPE_BOOL:
		return false
	if typeof(dto["location_id"]) != TYPE_STRING or dto["location_id"].is_empty():
		return false
	if typeof(dto["current_enemy_id"]) != TYPE_STRING:
		return false
	if not dto["current_enemy_id"].is_empty() and not GameSession.ACTOR_PATHS.has(dto["current_enemy_id"]):
		return false
	if typeof(dto["combat_format"]) != TYPE_STRING or dto["combat_format"] not in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE]:
		return false
	if not _valid_profile(dto["profile"]) or not _valid_meta(dto["meta"]) or not _valid_checkpoints(dto["checkpoints"]):
		return false
	if dto["location_id"] == GameSession.LOCATION_GUILD_ORDER and dto["profile"].get("guild_order", {}).is_empty():
		return false
	if typeof(dto["loot"]) != TYPE_DICTIONARY or not _has_keys(dto["loot"], ["seed", "state"]):
		return false
	if typeof(dto["loot"]["seed"]) != TYPE_STRING or typeof(dto["loot"]["state"]) != TYPE_STRING or not dto["loot"]["state"].is_valid_int():
		return false
	if typeof(dto["pending_battle_result"]) != TYPE_DICTIONARY:
		return false
	var battle: Dictionary = dto["pending_battle_result"]
	var profile: Dictionary = dto["profile"]
	if not battle.is_empty():
		if not GameSession.is_valid_pending_battle_result(battle):
			return false
		if profile.get("last_claimed_result_id") == battle["result_id"]:
			return false
		if not GameSession.expedition_battle_matches(battle, dto["location_id"], profile["quest_flags"], profile["npc_flags"], profile.get("guild_order", {})):
			return false
	if not _valid_story_reward(dto["pending_story_reward"]):
		return false
	var gift: Dictionary = dto["pending_story_reward"]
	if not gift.is_empty() and profile["story_rewards"].has(gift["reward_id"]):
		return false
	if dto["awaiting_return"] and (not dto["pending_battle_result"].is_empty() or not dto["pending_story_reward"].is_empty()):
		return false
	if not dto["pending_battle_result"].is_empty() and not dto["pending_story_reward"].is_empty():
		return false
	return _valid_rewards(dto["pending_reward"])

static func _valid_profile(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["hero", "inventory", "wallet", "quest_flags", "npc_flags", "world_flags", "completed_encounter_ids", "play_tick", "characters", "familiars", "story_rewards"]):
		return false
	if not _valid_wallet(dto["wallet"]) or not _nonnegative(dto["play_tick"]):
		return false
	var order: Variant = dto.get("guild_order", {})
	if not GuildOrders.valid_progress(order):
		return false
	if dto.has("run_sequence") and not _nonnegative(dto["run_sequence"]):
		return false
	if dto.has("pending_battle_result") or dto.has("trial_echo_claimed"):
		return false
	if dto.has("last_claimed_result_id") and typeof(dto["last_claimed_result_id"]) != TYPE_STRING:
		return false
	# Маршрут: пустое состояние — отдельный legacy-случай (выводится из журнала
	# при apply); непустое обязано быть полностью валидным, без частичного применения.
	if not dto.has("route_state") or typeof(dto["route_state"]) != TYPE_DICTIONARY:
		return false
	var route_state: Dictionary = dto["route_state"]
	if not route_state.is_empty() and not GameSession.is_valid_route_state(route_state):
		return false
	for key: String in ["quest_flags", "npc_flags", "world_flags", "completed_encounter_ids", "story_rewards"]:
		if not _valid_flag_map(dto[key]):
			return false
	if not order.is_empty() and (not dto["world_flags"].get(GameSession.WORLD_FLAG_GUILD_REGISTERED, false) or dto["quest_flags"].get("guild_order_completed_" + order["id"], false)):
		return false
	if typeof(dto["characters"]) != TYPE_DICTIONARY:
		return false
	for character_id: Variant in dto["characters"]:
		if typeof(character_id) != TYPE_STRING or not GameSession.COMPANION_ACTOR_PATHS.has(character_id) or not _valid_hero(dto["characters"][character_id]):
			return false
	if not _valid_familiars(dto["familiars"]) or not _valid_inventory(dto["inventory"]):
		return false
	for character_id: Variant in dto["inventory"].get("character_equipment", {}):
		if not dto["characters"].has(character_id):
			return false
	return _valid_hero(dto["hero"])

static func _valid_wallet(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != GameSession.COIN_TYPES.size():
		return false
	for coin: String in GameSession.COIN_TYPES:
		var amount: Variant = value.get(coin)
		if typeof(amount) != TYPE_STRING or not amount.is_valid_int() or int(amount) < 0 or str(int(amount)) != amount:
			return false
	return true

static func _valid_familiars(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["owned", "assignments"]):
		return false
	if typeof(dto["owned"]) != TYPE_DICTIONARY or typeof(dto["assignments"]) != TYPE_DICTIONARY:
		return false
	for familiar_id: Variant in dto["owned"]:
		if typeof(familiar_id) != TYPE_STRING or not GameSession.FAMILIAR_PATHS.has(familiar_id):
			return false
		var level: Variant = dto["owned"][familiar_id]
		if level is Dictionary:
			level = level.get("level")
		var definition: FamiliarDefinition = load(GameSession.FAMILIAR_PATHS[familiar_id])
		if not _is_intlike(level) or level < 1 or level > definition.max_level:
			return false
	for character_id: Variant in dto["assignments"]:
		if typeof(character_id) != TYPE_STRING or typeof(dto["assignments"][character_id]) != TYPE_STRING:
			return false
		var familiar_id: String = dto["assignments"][character_id]
		if not dto["owned"].has(familiar_id):
			return false
		var familiar: FamiliarDefinition = load(GameSession.FAMILIAR_PATHS[familiar_id])
		var owner: String = "haruto" if familiar.bound_character_id.is_empty() else familiar.bound_character_id
		if character_id != owner:
			return false
	return true

static func _valid_hero(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["level", "experience", "pending_upgrade_choices", "current_hp", "strength_upgrades", "max_hp_upgrades"]):
		return false
	for key: String in ["level", "experience", "pending_upgrade_choices", "current_hp", "strength_upgrades", "max_hp_upgrades"]:
		if not _nonnegative(dto[key]):
			return false
	return int(dto["level"]) >= 1

static func _valid_inventory(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["items", "equipment", "character_equipment", "next_serial"]):
		return false
	if typeof(dto["items"]) != TYPE_ARRAY or typeof(dto["equipment"]) != TYPE_DICTIONARY or typeof(dto["character_equipment"]) != TYPE_DICTIONARY or not _nonnegative(dto["next_serial"]) or int(dto["next_serial"]) < 1:
		return false
	var ids: Dictionary = {}
	for entry: Variant in dto["items"]:
		if typeof(entry) != TYPE_DICTIONARY or not _has_keys(entry, ["instance_id", "definition_id", "quantity", "aspect_id", "secured", "level", "sale_price_copper", "sellable"]):
			return false
		if typeof(entry["instance_id"]) != TYPE_STRING or entry["instance_id"].is_empty() or ids.has(entry["instance_id"]):
			return false
		if typeof(entry["definition_id"]) != TYPE_STRING or not GameSession.ITEM_PATHS.has(entry["definition_id"]):
			return false
		var definition: ItemDefinition = load(GameSession.ITEM_PATHS[entry["definition_id"]])
		if not _nonnegative(entry["quantity"]) or int(entry["quantity"]) < 1 or int(entry["quantity"]) > definition.stack_limit:
			return false
		if typeof(entry["aspect_id"]) != TYPE_STRING or typeof(entry["secured"]) != TYPE_BOOL or typeof(entry["sellable"]) != TYPE_BOOL:
			return false
		if not _nonnegative(entry["level"]) or int(entry["level"]) < 1 or not _nonnegative(entry["sale_price_copper"]):
			return false
		ids[entry["instance_id"]] = entry
	var equipped_ids: Dictionary = {}
	if not _valid_equipment_slots(dto["equipment"], ids, equipped_ids):
		return false
	for character_id: Variant in dto["character_equipment"]:
		if typeof(character_id) != TYPE_STRING or character_id == "haruto" or not _valid_equipment_slots(dto["character_equipment"][character_id], ids, equipped_ids):
			return false
	return true

static func _valid_equipment_slots(slots: Variant, ids: Dictionary, equipped_ids: Dictionary) -> bool:
	if typeof(slots) != TYPE_DICTIONARY:
		return false
	for slot_id: Variant in slots:
		if typeof(slot_id) != TYPE_STRING or typeof(slots[slot_id]) != TYPE_STRING:
			return false
		var instance_id: String = slots[slot_id]
		if not ids.has(instance_id) or equipped_ids.has(instance_id):
			return false
		var definition: ItemDefinition = load(GameSession.ITEM_PATHS[ids[instance_id]["definition_id"]])
		if definition.slot_id != slot_id:
			return false
		equipped_ids[instance_id] = true
	return true

static func _valid_meta(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["echoes", "claimed_echo_enemy_ids", "seen_cue_ids", "memory_flags", "adaptation_nodes", "techniques", "enemy_journal", "traces", "trial_echo_claimed"]):
		return false
	if not _nonnegative(dto["echoes"]) or not _nonnegative(dto["traces"]) or int(dto["traces"]) > 3 or typeof(dto["trial_echo_claimed"]) != TYPE_BOOL:
		return false
	for key: String in ["claimed_echo_enemy_ids", "seen_cue_ids", "memory_flags", "adaptation_nodes", "techniques", "enemy_journal"]:
		if not _valid_flag_map(dto[key]):
			return false
	return true

static func _valid_checkpoints(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["manual_snapshots", "first_trace_snapshot", "first_trace_available", "sequence"]):
		return false
	if typeof(dto["manual_snapshots"]) != TYPE_ARRAY or dto["manual_snapshots"].size() > CheckpointService.MANUAL_LIMIT:
		return false
	if typeof(dto["first_trace_available"]) != TYPE_BOOL or not _nonnegative(dto["sequence"]):
		return false
	if not _valid_snapshot(dto["first_trace_snapshot"]):
		return false
	# staged-завершение канала (аддитивное поле v4): либо отсутствует/пусто,
	# либо обязано быть валидным снимком — неполные данные не принимаем.
	var pending: Variant = dto.get("pending_completion", {})
	if typeof(pending) != TYPE_DICTIONARY:
		return false
	if not pending.is_empty() and not _valid_snapshot(pending):
		return false
	var ids: Dictionary = {}
	for snapshot: Variant in dto["manual_snapshots"]:
		if not _valid_snapshot(snapshot) or ids.has(snapshot["checkpoint_id"]):
			return false
		ids[snapshot["checkpoint_id"]] = true
	return true

static func _valid_snapshot(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["checkpoint_id", "sequence", "location_id", "profile"]):
		return false
	return (
		typeof(dto["checkpoint_id"]) == TYPE_STRING
		and not dto["checkpoint_id"].is_empty()
		and _nonnegative(dto["sequence"])
		and typeof(dto["location_id"]) == TYPE_STRING
		and not dto["location_id"].is_empty()
		and _valid_profile(dto["profile"])
		and (dto["location_id"] != GameSession.LOCATION_GUILD_ORDER or not dto["profile"].get("guild_order", {}).is_empty())
	)

static func _valid_story_reward(reward: Variant) -> bool:
	return reward is Dictionary and (reward.is_empty() or GameSession.is_valid_story_reward(reward))

static func _valid_rewards(rewards: Variant) -> bool:
	if typeof(rewards) != TYPE_ARRAY:
		return false
	for reward: Variant in rewards:
		if typeof(reward) != TYPE_DICTIONARY or not _has_keys(reward, ["item_id", "quantity", "aspect_id"]):
			return false
		if typeof(reward["item_id"]) != TYPE_STRING or not GameSession.ITEM_PATHS.has(reward["item_id"]):
			return false
		if not _nonnegative(reward["quantity"]) or int(reward["quantity"]) < 1 or typeof(reward["aspect_id"]) != TYPE_STRING:
			return false
	return true

static func _valid_flag_map(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or typeof(value[key]) not in [TYPE_BOOL, TYPE_STRING, TYPE_INT, TYPE_FLOAT]:
			return false
	return true

static func _has_keys(dto: Variant, keys: Array) -> bool:
	if typeof(dto) != TYPE_DICTIONARY:
		return false
	for key: String in keys:
		if not dto.has(key):
			return false
	return true

static func _is_intlike(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value))

static func _nonnegative(value: Variant) -> bool:
	return _is_intlike(value) and float(value) >= 0.0

static func normalize_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
		return int(value)
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for entry: Variant in value:
			result.append(normalize_numbers(entry))
		return result
	if typeof(value) == TYPE_DICTIONARY:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = normalize_numbers(value[key])
		return result
	return value
