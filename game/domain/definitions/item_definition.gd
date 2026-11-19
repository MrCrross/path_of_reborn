class_name ItemDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var rarity_id: String = "common"
@export var type_id: String = "material"
@export var slot_id: String = ""
@export var aspect_id: String = ""
@export var stack_limit: int = 1
@export var modifiers: Array[StatModifierDefinition] = []
