class_name InventoryService
extends RefCounted

signal changed

var items: Array[ItemInstance] = []
var equipment: Dictionary = {}
var next_serial: int = 1

var _hero: CharacterState
var _definitions: Dictionary

func _init(hero: CharacterState, definitions: Dictionary) -> void:
	_hero = hero
	_definitions = definitions

func add(definition: ItemDefinition, quantity: int, aspect_id: String = "") -> Array[ItemInstance]:
	var affected: Array[ItemInstance] = []
	if definition.id.is_empty() or quantity <= 0 or definition.stack_limit <= 0:
		return affected
	var remaining: int = quantity
	while remaining > 0:
		var stack: ItemInstance = _find_stack(definition.id, aspect_id, definition.stack_limit)
		if stack == null:
			stack = ItemInstance.new()
			stack.instance_id = "item_%06d" % next_serial
			stack.definition_id = definition.id
			stack.aspect_id = aspect_id
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
	if not definition.slot_id.is_empty() and equipment.get(definition.slot_id, "") == instance_id:
		unequip(definition.slot_id)
	item.quantity -= quantity
	if item.quantity == 0:
		items.erase(item)
	changed.emit()
	return true

func equip(instance_id: String) -> bool:
	var item: ItemInstance = get_item(instance_id)
	if item == null:
		return false
	var definition: ItemDefinition = get_definition(item.definition_id)
	if definition.slot_id.is_empty():
		return false
	if equipment.get(definition.slot_id, "") == instance_id:
		return true
	if equipment.has(definition.slot_id):
		unequip(definition.slot_id)
	equipment[definition.slot_id] = instance_id
	_hero.set_modifiers(instance_id, definition.modifiers)
	changed.emit()
	return true

func unequip(slot_id: String) -> bool:
	if not equipment.has(slot_id):
		return false
	var instance_id: String = equipment[slot_id]
	equipment.erase(slot_id)
	_hero.remove_modifiers(instance_id)
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

func is_equipped(instance_id: String) -> bool:
	var item: ItemInstance = get_item(instance_id)
	if item == null:
		return false
	var definition: ItemDefinition = get_definition(item.definition_id)
	return equipment.get(definition.slot_id, "") == instance_id

func capture_dto() -> Dictionary:
	var item_dtos: Array[Dictionary] = []
	for item: ItemInstance in items:
		item_dtos.append(item.capture_dto())
	return {
		"items": item_dtos,
		"equipment": equipment.duplicate(),
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
		restored_items.append(item)
		ids[instance_id] = true
	var restored_equipment: Dictionary = dto.get("equipment", {}).duplicate()
	for slot_id: String in restored_equipment:
		var instance_id: String = restored_equipment[slot_id]
		var item: ItemInstance = null
		for candidate: ItemInstance in restored_items:
			if candidate.instance_id == instance_id:
				item = candidate
				break
		if item == null or get_definition(item.definition_id).slot_id != slot_id:
			return false
	_hero.clear_modifiers()
	items = restored_items
	equipment = restored_equipment
	next_serial = maxi(1, int(dto.get("next_serial", 1)))
	for slot_id: String in equipment:
		var instance_id: String = equipment[slot_id]
		var item: ItemInstance = get_item(instance_id)
		_hero.set_modifiers(instance_id, get_definition(item.definition_id).modifiers)
	changed.emit()
	return true

func _find_stack(definition_id: String, aspect_id: String, stack_limit: int) -> ItemInstance:
	if stack_limit <= 1:
		return null
	for item: ItemInstance in items:
		if item.definition_id == definition_id and item.aspect_id == aspect_id and item.quantity < stack_limit:
			return item
	return null
