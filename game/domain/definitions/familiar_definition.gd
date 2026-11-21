class_name FamiliarDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var bound_character_id: String = ""
@export var max_level: int = 3
@export var modifiers: Array[StatModifierDefinition] = []
@export var per_level_modifiers: Array[StatModifierDefinition] = []
