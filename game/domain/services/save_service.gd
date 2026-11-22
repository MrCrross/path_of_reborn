class_name SaveService
extends RefCounted

const CURRENT_VERSION: int = 7
const DEFAULT_PATH: String = "user://profile.json"

var last_error: String = ""
var loaded_from_backup: bool = false

func capture(session: GameSession) -> Dictionary:
	return {
		"schema_version": CURRENT_VERSION,
		"profile": session.capture_profile_dto(),
		"meta": {
			"echoes": session.echoes,
			"claimed_echo_enemy_ids": session.claimed_echo_enemy_ids.duplicate(true),
			"seen_cue_ids": session.seen_cue_ids.duplicate(true),
			"memory_flags": session.memory_flags.duplicate(true),
			"adaptation_nodes": session.adaptation_nodes.duplicate(true),
			"techniques": session.techniques.duplicate(true),
			"enemy_journal": session.enemy_journal.duplicate(true),
			"traces": session.traces,
			"trial_echo_claimed": session.trial_echo_claimed,
		},
		"checkpoints": session.checkpoints.capture_dto(),
		"location_id": session.location_id,
		"current_enemy_id": session.current_enemy_id,
		"pending_reward": session.pending_reward.duplicate(true),
		"pending_battle_result": session.pending_battle_result.duplicate(true),
		"pending_story_reward": session.pending_story_reward.duplicate(true),
		"combat_format": session.combat_format,
		"loot": {
			"seed": session.loot_seed,
			"state": str(session.loot_rng.state),
		},
		"awaiting_return": session.awaiting_return,
	}

func save(session: GameSession, path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	if not path.begins_with("user://"):
		return _fail("Путь сохранения должен находиться в user://")
	if session.in_combat or session.checkpoints.channel_active or session.is_transaction_active():
		return _fail("Сохранение возможно только вне боя, фиксации и транзакции награды")
	var dto: Dictionary = capture(session)
	if not validate(dto):
		return _fail("Состояние не прошло проверку сохранения")
	return _write_dto(dto, path)

func save_combat_format(format: String, path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	if not path.begins_with("user://"):
		return _fail("Путь сохранения должен находиться в user://")
	if format not in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE]:
		return _fail("Неизвестный формат боя")
	var result: Dictionary = _read_dto(path)
	if not result["ok"]:
		result = _read_dto(path + ".bak")
	if not result["ok"]:
		return _fail("Нет сохранённого профиля для настройки боя")
	var dto: Dictionary = result["data"]
	dto["combat_format"] = format
	if not validate(dto):
		return _fail("Профиль не прошёл проверку настройки боя")
	return _write_dto(dto, path)

func _write_dto(dto: Dictionary, path: String) -> bool:
	var base_dir: String = path.get_base_dir()
	var make_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	if make_error != OK:
		return _fail("Не удалось создать каталог профиля: %s" % error_string(make_error))
	var temp_path: String = path + ".tmp"
	var backup_path: String = path + ".bak"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("Не удалось открыть временный файл: %s" % error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(dto, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		_remove_file(temp_path)
		return _fail("Не удалось записать профиль: %s" % error_string(write_error))
	if FileAccess.file_exists(path) and _read_dto(path)["ok"]:
		var copy_error: Error = DirAccess.copy_absolute(
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(backup_path)
		)
		if copy_error != OK:
			_remove_file(temp_path)
			return _fail("Не удалось обновить резервную копию: %s" % error_string(copy_error))
	var rename_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(path)
	)
	if rename_error != OK:
		_remove_file(temp_path)
		return _fail("Не удалось заменить профиль: %s" % error_string(rename_error))
	return true

func load_into(session: GameSession, path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	loaded_from_backup = false
	var result: Dictionary = _read_dto(path)
	if not result["ok"]:
		result = _read_dto(path + ".bak")
		loaded_from_backup = result["ok"]
	if not result["ok"]:
		if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
			last_error = ""
		else:
			last_error = "Профиль повреждён или имеет неподдерживаемую версию"
		return false
	session.apply_state_dto(result["data"])
	return true

func peek_combat_format(path: String = DEFAULT_PATH) -> String:
	var result: Dictionary = _read_dto(path)
	if not result["ok"]:
		result = _read_dto(path + ".bak")
	return String(result["data"].get("combat_format", GameSession.COMBAT_FORMAT_AUTO)) if result["ok"] else GameSession.COMBAT_FORMAT_AUTO

func has_profile(path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	if _read_dto(path)["ok"] or _read_dto(path + ".bak")["ok"]:
		return true
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
		last_error = "Профиль повреждён или имеет неподдерживаемую версию"
	return false

func migrate(source: Dictionary) -> Dictionary:
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
				if typeof(dto.get("profile")) != TYPE_DICTIONARY:
					return {}
				var profile: Dictionary = dto["profile"]
				if not profile.has("route_state"):
					profile["route_state"] = {}
				if not profile.has("run_sequence"):
					profile["run_sequence"] = 0
				if typeof(dto.get("checkpoints")) != TYPE_DICTIONARY:
					return {}
				var checkpoints: Dictionary = dto["checkpoints"]
				var snapshots: Array = [checkpoints.get("first_trace_snapshot", {})]
				if typeof(checkpoints.get("manual_snapshots")) != TYPE_ARRAY:
					return {}
				snapshots.append_array(checkpoints["manual_snapshots"])
				for snapshot: Variant in snapshots:
					if typeof(snapshot) != TYPE_DICTIONARY or typeof(snapshot.get("profile")) != TYPE_DICTIONARY:
						return {}
					if not snapshot["profile"].has("route_state"):
						snapshot["profile"]["route_state"] = {}
					if not snapshot["profile"].has("run_sequence"):
						snapshot["profile"]["run_sequence"] = 0
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

func _migrate_v6_to_v7(dto: Dictionary) -> bool:
	if not _migrate_copper_wallet(dto.get("profile")):
		return false
	if typeof(dto.get("pending_battle_result")) != TYPE_DICTIONARY or typeof(dto.get("checkpoints")) != TYPE_DICTIONARY:
		return false
	var pending_items: Variant = dto["pending_battle_result"].get("items", [])
	if typeof(pending_items) != TYPE_ARRAY:
		return false
	_reprice_echo_crystals(pending_items, "item_id")
	var checkpoints: Dictionary = dto["checkpoints"]
	if typeof(checkpoints.get("manual_snapshots")) != TYPE_ARRAY or typeof(checkpoints.get("pending_completion", {})) != TYPE_DICTIONARY:
		return false
	var snapshots: Array = [checkpoints.get("first_trace_snapshot")]
	snapshots.append_array(checkpoints["manual_snapshots"])
	var pending_completion: Dictionary = checkpoints.get("pending_completion", {})
	if not pending_completion.is_empty():
		snapshots.append(pending_completion)
	for snapshot: Variant in snapshots:
		if typeof(snapshot) != TYPE_DICTIONARY or not _migrate_copper_wallet(snapshot.get("profile")):
			return false
	return true

func _migrate_copper_wallet(profile: Variant) -> bool:
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

func _reprice_echo_crystals(items: Array, id_key: String) -> void:
	for item: Variant in items:
		if typeof(item) == TYPE_DICTIONARY and item.get(id_key) == "echo_crystal" and item.get("sale_price_copper") == 2000:
			item["sale_price_copper"] = 20

## The new slime sits between the two old nodes. Keep profiles and Checkpoint
## snapshots already at the cart on the goblin node, including pending victories.
func _migrate_v5_to_v6(dto: Dictionary) -> bool:
	if typeof(dto.get("checkpoints")) != TYPE_DICTIONARY or typeof(dto.get("pending_battle_result")) != TYPE_DICTIONARY:
		return false
	var pending: Dictionary = dto["pending_battle_result"]
	var at_cart: bool = pending.get("route_node_id", "") == "forest_edge_goblin"
	if not _migrate_forest_route(dto.get("profile"), at_cart):
		return false
	var checkpoints: Dictionary = dto["checkpoints"]
	if typeof(checkpoints.get("manual_snapshots")) != TYPE_ARRAY or typeof(checkpoints.get("pending_completion", {})) != TYPE_DICTIONARY:
		return false
	var snapshots: Array = [checkpoints.get("first_trace_snapshot")]
	snapshots.append_array(checkpoints["manual_snapshots"])
	var pending_completion: Dictionary = checkpoints.get("pending_completion", {})
	if not pending_completion.is_empty():
		snapshots.append(pending_completion)
	for snapshot: Variant in snapshots:
		if typeof(snapshot) != TYPE_DICTIONARY or not _migrate_forest_route(snapshot.get("profile")):
			return false
	return true

func _migrate_forest_route(profile: Variant, pending_goblin: bool = false) -> bool:
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

func _migrate_v3_to_v4(dto: Dictionary) -> bool:
	if typeof(dto.get("profile")) != TYPE_DICTIONARY or typeof(dto.get("meta")) != TYPE_DICTIONARY or typeof(dto.get("checkpoints")) != TYPE_DICTIONARY:
		return false
	var profile: Dictionary = dto["profile"]
	var meta: Dictionary = dto["meta"]
	var profile_pending: Variant = profile.get("pending_battle_result", {})
	var root_pending: Variant = dto.get("pending_battle_result", {})
	if typeof(profile_pending) != TYPE_DICTIONARY or typeof(root_pending) != TYPE_DICTIONARY:
		return false
	profile_pending = _normalize_v3_pending(profile_pending)
	root_pending = _normalize_v3_pending(root_pending)
	if not profile_pending.is_empty():
		if not GameSession.is_valid_pending_battle_result(profile_pending):
			return false
		dto["pending_battle_result"] = profile_pending
	elif not root_pending.is_empty():
		if not GameSession.is_valid_pending_battle_result(root_pending):
			return false
		dto["pending_battle_result"] = root_pending
	else:
		dto["pending_battle_result"] = {}
	profile.erase("pending_battle_result")
	var profile_trial: Variant = profile.get("trial_echo_claimed", false)
	var meta_trial: Variant = meta.get("trial_echo_claimed", false)
	if typeof(profile_trial) != TYPE_BOOL or typeof(meta_trial) != TYPE_BOOL:
		return false
	meta["trial_echo_claimed"] = bool(profile_trial) or bool(meta_trial)
	profile.erase("trial_echo_claimed")
	var checkpoints: Dictionary = dto["checkpoints"]
	if not _migrate_v3_snapshot(checkpoints.get("first_trace_snapshot", null)):
		return false
	if typeof(checkpoints.get("manual_snapshots")) != TYPE_ARRAY:
		return false
	for snapshot: Variant in checkpoints["manual_snapshots"]:
		if not _migrate_v3_snapshot(snapshot):
			return false
	return true

func _normalize_v3_pending(pending: Dictionary) -> Dictionary:
	var result: Dictionary = pending.duplicate(true)
	if not result.is_empty() and not result.has("route_id"):
		result["route_id"] = String(GameSession.route_definition().get("route_id", ""))
	return result

func _migrate_v3_snapshot(snapshot: Variant) -> bool:
	if typeof(snapshot) != TYPE_DICTIONARY or typeof(snapshot.get("profile")) != TYPE_DICTIONARY:
		return false
	var profile: Dictionary = snapshot["profile"]
	var pending: Variant = profile.get("pending_battle_result", {})
	if typeof(pending) != TYPE_DICTIONARY or not pending.is_empty():
		return false
	profile.erase("pending_battle_result")
	profile.erase("trial_echo_claimed")
	return true

func _migrate_v4_to_v5(dto: Dictionary) -> bool:
	if typeof(dto.get("profile")) != TYPE_DICTIONARY or typeof(dto.get("checkpoints")) != TYPE_DICTIONARY:
		return false
	if not _migrate_v4_profile(dto["profile"]):
		return false
	if typeof(dto.get("pending_battle_result")) != TYPE_DICTIONARY:
		return false
	dto["pending_battle_result"] = _migrate_v4_pending(dto["pending_battle_result"])
	if dto["pending_battle_result"].is_empty() and not dto["pending_battle_result"] == {}:
		return false
	dto["pending_story_reward"] = {}
	var checkpoints: Dictionary = dto["checkpoints"]
	for snapshot: Variant in [checkpoints.get("first_trace_snapshot", {})]:
		if not _migrate_v4_snapshot(snapshot):
			return false
	if typeof(checkpoints.get("manual_snapshots")) != TYPE_ARRAY:
		return false
	for snapshot: Variant in checkpoints["manual_snapshots"]:
		if not _migrate_v4_snapshot(snapshot):
			return false
	var pending_completion: Variant = checkpoints.get("pending_completion", {})
	if not pending_completion.is_empty() and not _migrate_v4_snapshot(pending_completion):
		return false
	return true

func _migrate_v4_snapshot(snapshot: Variant) -> bool:
	return typeof(snapshot) == TYPE_DICTIONARY and typeof(snapshot.get("profile")) == TYPE_DICTIONARY and _migrate_v4_profile(snapshot["profile"])

func _migrate_v4_profile(profile: Dictionary) -> bool:
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

func _migrate_v4_pending(pending: Dictionary) -> Dictionary:
	var result: Dictionary = pending.duplicate(true)
	if result.is_empty():
		return result
	result["choices"] = {}
	var items: Array = result.get("items", [])
	for index: int in range(items.size()):
		if typeof(items[index]) != TYPE_DICTIONARY:
			return {"invalid": true}
		var entry: Dictionary = items[index]
		var item_id: String = String(entry.get("item_id", ""))
		if not GameSession.ITEM_PATHS.has(item_id):
			return {"invalid": true}
		var definition: ItemDefinition = load(GameSession.ITEM_PATHS[item_id])
		if definition == null:
			return {"invalid": true}
		entry["entry_id"] = "entry_%06d" % (index + 1)
		entry["level"] = definition.level
		entry["sale_price_copper"] = definition.sale_price_copper
		entry["sellable"] = definition.sellable
	return result

func validate(dto: Dictionary) -> bool:
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
	if typeof(dto["loot"]) != TYPE_DICTIONARY or not _has_keys(dto["loot"], ["seed", "state"]):
		return false
	if typeof(dto["loot"]["seed"]) != TYPE_STRING or typeof(dto["loot"]["state"]) != TYPE_STRING or not dto["loot"]["state"].is_valid_int():
		return false
	if typeof(dto["pending_battle_result"]) != TYPE_DICTIONARY:
		return false
	if not dto["pending_battle_result"].is_empty() and not GameSession.is_valid_pending_battle_result(dto["pending_battle_result"]):
		return false
	if not _valid_story_reward(dto["pending_story_reward"]):
		return false
	if dto["awaiting_return"] and (not dto["pending_battle_result"].is_empty() or not dto["pending_story_reward"].is_empty()):
		return false
	if not dto["pending_battle_result"].is_empty() and not dto["pending_story_reward"].is_empty():
		return false
	return _valid_rewards(dto["pending_reward"])

func _read_dto(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}}
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK:
		return {"ok": false, "data": {}}
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}}
	var dto: Dictionary = migrate(parser.data)
	if dto.is_empty() or not validate(dto):
		return {"ok": false, "data": {}}
	return {"ok": true, "data": _normalize_numbers(dto)}

func _valid_profile(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["hero", "inventory", "wallet", "quest_flags", "npc_flags", "world_flags", "completed_encounter_ids", "play_tick", "characters", "familiars", "story_rewards"]):
		return false
	if not _valid_wallet(dto["wallet"]) or not _nonnegative(dto["play_tick"]):
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
	if typeof(dto["characters"]) != TYPE_DICTIONARY:
		return false
	for character_id: Variant in dto["characters"]:
		if typeof(character_id) != TYPE_STRING or not GameSession.COMPANION_ACTOR_PATHS.has(character_id) or not _valid_hero(dto["characters"][character_id]):
			return false
	if not _valid_familiars(dto["familiars"]):
		return false
	for character_id: Variant in dto["inventory"].get("character_equipment", {}):
		if not dto["characters"].has(character_id):
			return false
	return _valid_hero(dto["hero"]) and _valid_inventory(dto["inventory"])

func _valid_wallet(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != GameSession.COIN_TYPES.size():
		return false
	for coin: String in GameSession.COIN_TYPES:
		var amount: Variant = value.get(coin)
		if typeof(amount) != TYPE_STRING or not amount.is_valid_int() or int(amount) < 0 or str(int(amount)) != amount:
			return false
	return true

func _valid_familiars(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["owned", "assignments"]):
		return false
	if typeof(dto["owned"]) != TYPE_DICTIONARY or typeof(dto["assignments"]) != TYPE_DICTIONARY:
		return false
	for familiar_id: Variant in dto["owned"]:
		if typeof(familiar_id) != TYPE_STRING or not GameSession.FAMILIAR_PATHS.has(familiar_id):
			return false
		var state: Variant = dto["owned"][familiar_id]
		if typeof(state) != TYPE_DICTIONARY or not _nonnegative(state.get("level")) or int(state["level"]) < 1:
			return false
	for character_id: Variant in dto["assignments"]:
		if typeof(character_id) != TYPE_STRING or typeof(dto["assignments"][character_id]) != TYPE_STRING:
			return false
		if not dto["owned"].has(dto["assignments"][character_id]):
			return false
	return true

func _valid_hero(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["level", "experience", "pending_upgrade_choices", "current_hp", "strength_upgrades", "max_hp_upgrades"]):
		return false
	for key: String in ["level", "experience", "pending_upgrade_choices", "current_hp", "strength_upgrades", "max_hp_upgrades"]:
		if not _nonnegative(dto[key]):
			return false
	return int(dto["level"]) >= 1

func _valid_inventory(dto: Variant) -> bool:
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

func _valid_equipment_slots(slots: Variant, ids: Dictionary, equipped_ids: Dictionary) -> bool:
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

func _valid_meta(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["echoes", "claimed_echo_enemy_ids", "seen_cue_ids", "memory_flags", "adaptation_nodes", "techniques", "enemy_journal", "traces", "trial_echo_claimed"]):
		return false
	if not _nonnegative(dto["echoes"]) or not _nonnegative(dto["traces"]) or int(dto["traces"]) > 3 or typeof(dto["trial_echo_claimed"]) != TYPE_BOOL:
		return false
	for key: String in ["claimed_echo_enemy_ids", "seen_cue_ids", "memory_flags", "adaptation_nodes", "techniques", "enemy_journal"]:
		if not _valid_flag_map(dto[key]):
			return false
	return true

func _valid_checkpoints(dto: Variant) -> bool:
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

func _valid_snapshot(dto: Variant) -> bool:
	if typeof(dto) != TYPE_DICTIONARY or not _has_keys(dto, ["checkpoint_id", "sequence", "location_id", "profile"]):
		return false
	return (
		typeof(dto["checkpoint_id"]) == TYPE_STRING
		and not dto["checkpoint_id"].is_empty()
		and _nonnegative(dto["sequence"])
		and typeof(dto["location_id"]) == TYPE_STRING
		and not dto["location_id"].is_empty()
		and _valid_profile(dto["profile"])
	)

func _valid_story_reward(reward: Variant) -> bool:
	if typeof(reward) != TYPE_DICTIONARY:
		return false
	if reward.is_empty():
		return true
	if not _has_keys(reward, ["reward_id", "items", "choices"]):
		return false
	if typeof(reward["reward_id"]) != TYPE_STRING or reward["reward_id"].is_empty() or typeof(reward["choices"]) != TYPE_DICTIONARY:
		return false
	if typeof(reward["items"]) != TYPE_ARRAY or reward["items"].is_empty():
		return false
	var entry_ids: Dictionary = {}
	for entry: Variant in reward["items"]:
		if not _valid_reward_entry(entry):
			return false
		if entry_ids.has(entry["entry_id"]):
			return false
		entry_ids[entry["entry_id"]] = true
	return true

func _valid_reward_entry(entry: Variant) -> bool:
	if typeof(entry) != TYPE_DICTIONARY or not _has_keys(entry, ["entry_id", "item_id", "quantity", "aspect_id", "slot_id", "level", "sale_price_copper", "sellable"]):
		return false
	if typeof(entry["entry_id"]) != TYPE_STRING or entry["entry_id"].is_empty():
		return false
	if typeof(entry["item_id"]) != TYPE_STRING or not GameSession.ITEM_PATHS.has(entry["item_id"]):
		return false
	var definition: ItemDefinition = load(GameSession.ITEM_PATHS[entry["item_id"]])
	if typeof(entry["aspect_id"]) != TYPE_STRING or entry["slot_id"] != definition.slot_id or typeof(entry["sellable"]) != TYPE_BOOL:
		return false
	return _nonnegative(entry["quantity"]) and int(entry["quantity"]) >= 1 and _nonnegative(entry["level"]) and int(entry["level"]) >= 1 and _nonnegative(entry["sale_price_copper"])

func _valid_rewards(rewards: Variant) -> bool:
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

func _valid_flag_map(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or typeof(value[key]) not in [TYPE_BOOL, TYPE_STRING, TYPE_INT, TYPE_FLOAT]:
			return false
	return true

func _has_keys(dto: Variant, keys: Array) -> bool:
	if typeof(dto) != TYPE_DICTIONARY:
		return false
	for key: String in keys:
		if not dto.has(key):
			return false
	return true

func _is_intlike(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value))

func _nonnegative(value: Variant) -> bool:
	return _is_intlike(value) and float(value) >= 0.0

func _normalize_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
		return int(value)
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for entry: Variant in value:
			result.append(_normalize_numbers(entry))
		return result
	if typeof(value) == TYPE_DICTIONARY:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _normalize_numbers(value[key])
		return result
	return value

func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _fail(message: String) -> bool:
	last_error = message
	return false
