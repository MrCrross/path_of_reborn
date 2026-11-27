extends RefCounted

## Shared card format for pending combat loot and story gifts. The persisted
## result may contain partial choices until the player confirms every card.
static func make_entry(entry_id: String, definition: ItemDefinition, reward: Dictionary) -> Dictionary:
	return {
		"entry_id": entry_id,
		"item_id": definition.id,
		"quantity": int(reward["quantity"]),
		"aspect_id": String(reward.get("aspect_id", "")),
		"slot_id": definition.slot_id,
		"level": maxi(1, int(reward.get("level", definition.level))),
		"sale_price_copper": maxi(0, int(reward.get("sale_price_copper", definition.sale_price_copper))),
		"sellable": bool(reward.get("sellable", definition.sellable)),
	}

static func valid_cards(result: Dictionary, result_id: String, item_paths: Dictionary) -> bool:
	if result_id.is_empty() or not result.get("items") is Array or not result.get("choices") is Dictionary:
		return false
	var choices: Dictionary = result["choices"]
	var entry_ids: Dictionary = {}
	for entry: Variant in result["items"]:
		if not entry is Dictionary or not entry.get("entry_id") is String or entry["entry_id"].is_empty():
			return false
		var entry_id: String = entry["entry_id"]
		if entry_ids.has(entry_id) or not item_paths.has(entry.get("item_id")):
			return false
		var definition: ItemDefinition = load(item_paths[entry["item_id"]])
		if definition == null or entry.get("slot_id") != definition.slot_id:
			return false
		if not entry.get("aspect_id") is String or not entry.get("sellable") is bool:
			return false
		if not _integer_at_least(entry.get("quantity"), 1) or not _integer_at_least(entry.get("level"), 1) or not _integer_at_least(entry.get("sale_price_copper"), 0):
			return false
		entry_ids[entry_id] = true
		if choices.has(entry_id):
			var choice: Variant = choices[entry_id]
			if not choice is Dictionary or choice.get("result_id") != result_id or choice.get("entry_id") != entry_id:
				return false
			if choice.get("action") not in ["store", "equip"] or (choice["action"] == "equip" and definition.slot_id.is_empty()):
				return false
	return entry_ids.has_all(choices.keys())

## Both claim commands validate the complete batch before changing inventory.
static func deliver(result: Dictionary, inventory: InventoryService) -> Array[Dictionary]:
	var delivered: Array[Dictionary] = []
	for entry: Dictionary in result["items"]:
		var definition: ItemDefinition = inventory.get_definition(entry["item_id"])
		var instances: Array[ItemInstance] = inventory.add(definition, int(entry["quantity"]), entry["aspect_id"], entry)
		var instance_ids: Array[String] = []
		for item: ItemInstance in instances:
			instance_ids.append(item.instance_id)
		var action: String = result["choices"][entry["entry_id"]]["action"]
		if action == "equip":
			inventory.equip(instance_ids[0])
		delivered.append({
			"entry_id": entry["entry_id"], "action": action, "item_id": definition.id,
			"quantity": int(entry["quantity"]), "aspect_id": entry["aspect_id"],
			"slot_id": definition.slot_id, "instance_ids": instance_ids,
		})
	return delivered

static func _integer_at_least(value: Variant, minimum: int) -> bool:
	if value is int:
		return value >= minimum
	return value is float and is_finite(value) and value == floorf(value) and value >= minimum and value < 9223372036854775808.0
