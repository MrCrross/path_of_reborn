class_name EquipmentModel
extends RefCounted

static func slot(session: GameSession, slot_id: String, character_id: String = "haruto") -> Dictionary:
	var instance_id: String = String(session.inventory.equipment_for(character_id).get(slot_id, ""))
	var item: ItemInstance = session.inventory.get_item(instance_id)
	var definition: ItemDefinition = null if item == null else session.get_item_definition(item.definition_id)
	return {
		"slot_id": slot_id,
		"slot_label": UiText.slot(slot_id),
		"character_id": character_id,
		"instance_id": instance_id,
		"item": item,
		"definition": definition,
		"icon": null if item == null else ArtMap.item_icon(item.definition_id, item.aspect_id),
	}

static func for_instance(session: GameSession, instance_id: String, character_id: String = "haruto") -> Dictionary:
	var item: ItemInstance = session.inventory.get_item(instance_id)
	if item == null:
		return {}
	return _details(session, item, session.get_item_definition(item.definition_id), item.aspect_id, item.quantity, character_id, {
		"level": item.level,
		"sale_price_copper": item.sale_price_copper,
		"sellable": item.sellable,
	})

static func for_reward(session: GameSession, item_id: String, aspect_id: String, quantity: int = 1, reward: Dictionary = {}, character_id: String = "haruto") -> Dictionary:
	var definition: ItemDefinition = session.get_item_definition(item_id)
	if definition == null:
		return {}
	return _details(session, null, definition, aspect_id, quantity, character_id, reward)

static func _details(session: GameSession, item: ItemInstance, definition: ItemDefinition, aspect_id: String, quantity: int, character_id: String, properties: Dictionary) -> Dictionary:
	var equipped: bool = item != null and session.inventory.is_equipped(item.instance_id, character_id)
	var current: Dictionary = slot(session, definition.slot_id, character_id) if not definition.slot_id.is_empty() else {}
	var current_item: ItemInstance = current.get("item")
	var removed: Array[String] = []
	if current_item != null:
		removed.append(current_item.instance_id)
	var deltas: Array[Dictionary] = []
	var state: CharacterState = session.inventory.character_state(character_id)
	if not definition.slot_id.is_empty() and current_item != null and state != null and not (item != null and current_item.instance_id == item.instance_id):
		var preview: Dictionary[String, int] = state.preview_stats(removed, definition.modifiers)
		var compared_stats: Dictionary = {}
		var current_definition: ItemDefinition = current.get("definition")
		if current_definition != null:
			for modifier: StatModifierDefinition in current_definition.modifiers:
				compared_stats[modifier.stat_id] = true
		for modifier: StatModifierDefinition in definition.modifiers:
			compared_stats[modifier.stat_id] = true
		for stat_id: String in UiText.STAT_LABELS:
			if not compared_stats.has(stat_id):
				continue
			var before: int = int(state.get(stat_id))
			var after: int = int(preview.get(stat_id, before))
			deltas.append({"stat_id": stat_id, "label": UiText.stat(stat_id), "before": before, "after": after})
	var bonuses: Array[Dictionary] = []
	for modifier: StatModifierDefinition in definition.modifiers:
		bonuses.append({"stat_id": modifier.stat_id, "label": UiText.stat(modifier.stat_id), "amount": modifier.amount})
	return {
		"item": item,
		"instance_id": "" if item == null else item.instance_id,
		"definition": definition,
		"character_id": character_id,
		"aspect_id": aspect_id,
		"quantity": quantity,
		"level": int(properties.get("level", item.level if item != null else definition.level)),
		"sale_price_copper": int(properties.get("sale_price_copper", item.sale_price_copper if item != null else definition.sale_price_copper)),
		"sellable": bool(properties.get("sellable", item.sellable if item != null else definition.sellable)),
		"secured": item != null and item.secured,
		"slot_id": definition.slot_id,
		"equipped": equipped,
		"icon": ArtMap.item_icon(definition.id, aspect_id),
		"current_item": current_item,
		"current_definition": current.get("definition"),
		"current_instance_id": String(current.get("instance_id", "")),
		"current_icon": current.get("icon"),
		"same_item": current_item != null and item != null and current_item.instance_id == item.instance_id,
		"deltas": deltas,
		"bonuses": bonuses,
	}
