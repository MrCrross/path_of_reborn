class_name InventoryService
extends RefCounted

signal changed

var items: Array[ItemInstance] = []
var equipment: Dictionary = {}
var character_equipment: Dictionary = {}
var next_serial: int = 1

var _hero: CharacterState
var _definitions: Dictionary
var _characters: Dictionary = {}

func _init(hero: CharacterState, definitions: Dictionary) -> void:
	_hero = hero
	_definitions = definitions
	_characters["haruto"] = hero

func register_character(character_id: String, state: CharacterState) -> bool:
	if character_id.is_empty() or state == null:
		return false
	_characters[character_id] = state
	if character_id != "haruto" and not character_equipment.has(character_id):
		character_equipment[character_id] = {}
	return true

func character_state(character_id: String = "haruto") -> CharacterState:
	return _characters.get(character_id)

func equipment_for(character_id: String = "haruto") -> Dictionary:
	return equipment if character_id == "haruto" else character_equipment.get(character_id, {})

func add(definition: ItemDefinition, quantity: int, aspect_id: String = "", properties: Dictionary = {}) -> Array[ItemInstance]:
	var affected: Array[ItemInstance] = []
	if definition.id.is_empty() or quantity <= 0 or definition.stack_limit <= 0:
		return affected
	var level: int = maxi(1, int(properties.get("level", definition.level)))
	var sale_price_copper: int = maxi(0, int(properties.get("sale_price_copper", definition.sale_price_copper)))
	var sellable: bool = bool(properties.get("sellable", definition.sellable))
	var remaining: int = quantity
	while remaining > 0:
		var stack: ItemInstance = _find_stack(definition.id, aspect_id, level, sale_price_copper, sellable, definition.stack_limit)
		if stack == null:
			stack = ItemInstance.new()
			stack.instance_id = "item_%06d" % next_serial
			stack.definition_id = definition.id
			stack.aspect_id = aspect_id
			stack.level = level
			stack.sale_price_copper = sale_price_copper
			stack.sellable = sellable
			stack.quantity = 0
			next_serial += 1
			items.append(stack)
		var amount: int = mini(remaining, definition.stack_limit - stack.quantity)
		stack.quantity += amount
		remaining -= amount
		if not affected.has(stack):
			affected.append(stack)
	changed.emit()
	return affected

func remove(instance_id: String, quantity: int = 1) -> bool:
	var item: ItemInstance = get_item(instance_id)
	if item == null or quantity <= 0 or item.quantity < quantity:
		return false
	var definition: ItemDefinition = get_definition(item.definition_id)
	var owner_id: String = _owner_for_instance(instance_id)
	if not definition.slot_id.is_empty() and not owner_id.is_empty():
		unequip(definition.slot_id, owner_id)
	item.quantity -= quantity
	if item.quantity == 0:
		items.erase(item)
	changed.emit()
	return true

func equip(instance_id: String, character_id: String = "haruto") -> bool:
	var item: ItemInstance = get_item(instance_id)
	var state: CharacterState = character_state(character_id)
	if item == null or state == null:
		return false
	var definition: ItemDefinition = get_definition(item.definition_id)
	if definition.slot_id.is_empty():
		return false
	var slots: Dictionary = equipment_for(character_id)
	if slots.get(definition.slot_id, "") == instance_id:
		return true
	var previous_owner: String = _owner_for_instance(instance_id)
	if not previous_owner.is_empty():
		unequip(definition.slot_id, previous_owner)
	if slots.has(definition.slot_id):
		unequip(definition.slot_id, character_id)
	slots[definition.slot_id] = instance_id
	if character_id != "haruto":
		character_equipment[character_id] = slots
	state.set_modifiers(instance_id, definition.modifiers)
	changed.emit()
	return true

func unequip(slot_id: String, character_id: String = "haruto") -> bool:
	var slots: Dictionary = equipment_for(character_id)
	var state: CharacterState = character_state(character_id)
	if state == null or not slots.has(slot_id):
		return false
	var instance_id: String = slots[slot_id]
	slots.erase(slot_id)
	state.remove_modifiers(instance_id)
	changed.emit()
	return true

func filter(type_id: String = "") -> Array[ItemInstance]:
	var filtered: Array[ItemInstance] = []
	for item: ItemInstance in items:
		var definition: ItemDefinition = get_definition(item.definition_id)
		if type_id.is_empty() or definition.type_id == type_id:
			filtered.append(item)
	return filtered

func get_item(instance_id: String) -> ItemInstance:
	for item: ItemInstance in items:
		if item.instance_id == instance_id:
			return item
	return null

func get_definition(definition_id: String) -> ItemDefinition:
	return _definitions.get(definition_id)

func is_equipped(instance_id: String, character_id: String = "") -> bool:
	var item: ItemInstance = get_item(instance_id)
	if item == null:
		return false
	if not character_id.is_empty():
		return equipment_for(character_id).get(get_definition(item.definition_id).slot_id, "") == instance_id
	return not _owner_for_instance(instance_id).is_empty()

func capture_dto() -> Dictionary:
	var item_dtos: Array[Dictionary] = []
	for item: ItemInstance in items:
		item_dtos.append(item.capture_dto())
	return {
		"items": item_dtos,
		"equipment": equipment.duplicate(),
		"character_equipment": character_equipment.duplicate(true),
		"next_serial": next_serial,
	}

func apply_dto(dto: Dictionary) -> bool:
	var restored_items: Array[ItemInstance] = []
	var ids: Dictionary = {}
	for entry: Dictionary in dto.get("items", []):
		var definition_id: String = entry.get("definition_id", "")
		var instance_id: String = entry.get("instance_id", "")
		var definition: ItemDefinition = get_definition(definition_id)
		var quantity: int = int(entry.get("quantity", 0))
		if definition == null or instance_id.is_empty() or ids.has(instance_id):
			return false
		if quantity <= 0 or quantity > definition.stack_limit:
			return false
		var item := ItemInstance.new()
		item.instance_id = instance_id
		item.definition_id = definition_id
		item.quantity = quantity
		item.aspect_id = String(entry.get("aspect_id", ""))
		item.secured = bool(entry.get("secured", false))
		item.level = maxi(1, int(entry.get("level", definition.level)))
		item.sale_price_copper = maxi(0, int(entry.get("sale_price_copper", definition.sale_price_copper)))
		item.sellable = bool(entry.get("sellable", definition.sellable))
		restored_items.append(item)
		ids[instance_id] = true
	var restored_equipment: Dictionary = dto.get("equipment", {}).duplicate()
	var restored_character_equipment: Dictionary = dto.get("character_equipment", {}).duplicate(true)
	if not _valid_equipment_map(restored_equipment, restored_items, "haruto"):
		return false
	for character_id: String in restored_character_equipment:
		if character_id == "haruto" or not _characters.has(character_id):
			return false
		if not _valid_equipment_map(restored_character_equipment[character_id], restored_items, character_id):
			return false
	for state: CharacterState in _characters.values():
		state.clear_modifiers()
	items = restored_items
	equipment = restored_equipment
	character_equipment = restored_character_equipment
	next_serial = maxi(1, int(dto.get("next_serial", 1)))
	_apply_modifiers(equipment, "haruto")
	for character_id: String in character_equipment:
		_apply_modifiers(character_equipment[character_id], character_id)
	changed.emit()
	return true

func _valid_equipment_map(slots: Variant, restored_items: Array[ItemInstance], character_id: String) -> bool:
	if typeof(slots) != TYPE_DICTIONARY or not _characters.has(character_id):
		return false
	for slot_id: String in slots:
		var instance_id: String = String(slots[slot_id])
		var item: ItemInstance = null
		for candidate: ItemInstance in restored_items:
			if candidate.instance_id == instance_id:
				item = candidate
				break
		if item == null or get_definition(item.definition_id).slot_id != slot_id:
			return false
	return true

func _apply_modifiers(slots: Dictionary, character_id: String) -> void:
	var state: CharacterState = character_state(character_id)
	for slot_id: String in slots:
		var item: ItemInstance = get_item(String(slots[slot_id]))
		state.set_modifiers(item.instance_id, get_definition(item.definition_id).modifiers)

func _owner_for_instance(instance_id: String) -> String:
	var item: ItemInstance = get_item(instance_id)
	if item == null:
		return ""
	var slot_id: String = get_definition(item.definition_id).slot_id
	for character_id: String in _characters:
		if equipment_for(character_id).get(slot_id, "") == instance_id:
			return character_id
	return ""

func _find_stack(definition_id: String, aspect_id: String, level: int, sale_price_copper: int, sellable: bool, stack_limit: int) -> ItemInstance:
	if stack_limit <= 1:
		return null
	for item: ItemInstance in items:
		if (
			item.definition_id == definition_id
			and item.aspect_id == aspect_id
			and item.level == level
			and item.sale_price_copper == sale_price_copper
			and item.sellable == sellable
			and item.quantity < stack_limit
		):
			return item
	return null
