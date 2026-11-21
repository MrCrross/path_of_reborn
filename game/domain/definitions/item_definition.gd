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
@export var level: int = 1
@export var sale_price_copper: int = 0
@export var sellable: bool = false
@export var lower_is_better_stats: Array[String] = []
@export var modifiers: Array[StatModifierDefinition] = []
