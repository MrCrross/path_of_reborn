extends Control

signal navigate_requested(destination: String)

const STAT_LABELS: Dictionary[String, String] = {
	"max_hp": "Макс. HP",
	"strength": "Сила",
	"defense": "Защита",
	"mana": "Мана",
}
const SLOT_LABELS: Dictionary[String, String] = {
	"weapon": "Оружие",
	"charm": "Оберег",
}

var session: GameSession

@onready var reward_text: Label = %RewardText
@onready var comparison_text: Label = %ComparisonText
@onready var equip_button: Button = %EquipButton

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	_refresh()
	if equip_button.disabled:
		%InventoryButton.grab_focus()
	else:
		equip_button.grab_focus()

func _on_inventory_pressed() -> void:
	if session.claim_reward(false):
		navigate_requested.emit("inventory")

func _on_equip_pressed() -> void:
	if session.claim_reward(true):
		navigate_requested.emit("inventory")

func _refresh() -> void:
	var lines: Array[String] = []
	var reward_equipment: Dictionary[String, ItemDefinition] = {}
	for reward: Dictionary in session.pending_reward:
		var definition: ItemDefinition = session.get_item_definition(reward.get("item_id", ""))
		if definition == null:
			continue
		var quantity: int = int(reward.get("quantity", 0))
		var line: String = "%s ×%d\n%s" % [definition.display_name, quantity, definition.rarity_id]
		var aspect_id: String = reward.get("aspect_id", "")
		if not aspect_id.is_empty():
			line += " · аспект: %s" % aspect_id
		lines.append(line)
		if not definition.slot_id.is_empty() and quantity > 0:
			reward_equipment[definition.slot_id] = definition
	reward_text.text = "\n\n".join(lines) if not lines.is_empty() else "Награда уже принята."
	equip_button.disabled = reward_equipment.is_empty()
	if equip_button.disabled:
		comparison_text.text = "Этот предмет хранится в инвентаре и не надевается."
	else:
		comparison_text.text = _comparison(reward_equipment)

func _comparison(reward_equipment: Dictionary[String, ItemDefinition]) -> String:
	var lines: Array[String] = []
	var replaced_sources: Array[String] = []
	var added_modifiers: Array[StatModifierDefinition] = []
	for slot_id: String in reward_equipment:
		var equipped_id: String = session.inventory.equipment.get(slot_id, "")
		var equipped: ItemInstance = session.inventory.get_item(equipped_id)
		var equipped_name: String = "пусто"
		if equipped != null:
			replaced_sources.append(equipped_id)
			equipped_name = session.get_item_definition(equipped.definition_id).display_name
		lines.append("%s · %s" % [SLOT_LABELS.get(slot_id, slot_id), equipped_name])
		added_modifiers.append_array(reward_equipment[slot_id].modifiers)
	var preview: Dictionary[String, int] = session.hero.preview_stats(replaced_sources, added_modifiers)
	var has_changes: bool = false
	for stat_id: String in STAT_LABELS:
		var current: int = session.hero.get(stat_id)
		if current != preview[stat_id]:
			has_changes = true
			lines.append("%s %d → %d" % [STAT_LABELS[stat_id], current, preview[stat_id]])
	if not has_changes:
		lines.append("Характеристики сохранятся.")
	return "\n".join(lines)
