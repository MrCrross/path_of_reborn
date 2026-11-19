extends Control

signal navigate_requested(destination: String)

var session: GameSession
var filter_id: String = ""

@onready var stats_text: Label = %StatsText
@onready var upgrade_row: HBoxContainer = %UpgradeRow
@onready var strength_upgrade: Button = %StrengthUpgrade
@onready var hp_upgrade: Button = %HpUpgrade
@onready var type_filter: OptionButton = %TypeFilter
@onready var items_list: VBoxContainer = %ItemsList
@onready var back_button: Button = %BackButton

func configure(game_session: GameSession) -> void:
	session = game_session

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	type_filter.add_item("Все типы")
	type_filter.add_item("Оружие")
	type_filter.add_item("Обереги")
	type_filter.add_item("Материалы")
	type_filter.add_item("Кристаллы Эха")
	_refresh()
	back_button.grab_focus()

func _on_filter_selected(index: int) -> void:
	filter_id = ["", "weapon", "charm", "material", "echo"][index]
	_refresh()

func _on_item_pressed(instance_id: String) -> void:
	var item: ItemInstance = session.inventory.get_item(instance_id)
	if item == null:
		return
	var definition: ItemDefinition = session.get_item_definition(item.definition_id)
	if session.inventory.is_equipped(instance_id):
		session.inventory.unequip(definition.slot_id)
	else:
		session.inventory.equip(instance_id)
	_refresh()

func _on_back_pressed() -> void:
	navigate_requested.emit("world")

func _on_strength_upgrade_pressed() -> void:
	if session.choose_upgrade("strength"):
		_refresh()

func _on_hp_upgrade_pressed() -> void:
	if session.choose_upgrade("max_hp"):
		_refresh()

func _refresh() -> void:
	upgrade_row.visible = session.hero.pending_upgrade_choices > 0
	strength_upgrade.text = "Сила +%d (%d)" % [session.hero.definition.strength_upgrade_amount, session.hero.pending_upgrade_choices]
	hp_upgrade.text = "HP +%d" % session.hero.definition.max_hp_upgrade_amount
	stats_text.text = "HP %d/%d · Сила %d\nЗащита %d · Мана %d" % [
		session.hero.current_hp,
		session.hero.max_hp,
		session.hero.strength,
		session.hero.defense,
		session.hero.mana,
	]
	for child: Node in items_list.get_children():
		items_list.remove_child(child)
		child.queue_free()
	for item: ItemInstance in session.inventory.filter(filter_id):
		var definition: ItemDefinition = session.get_item_definition(item.definition_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 34)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 10)
		var equipped_mark: String = "[надет] " if session.inventory.is_equipped(item.instance_id) else ""
		button.text = "%s%s ×%d\n%s" % [equipped_mark, definition.display_name, item.quantity, definition.rarity_id]
		if not item.aspect_id.is_empty():
			button.text += " · %s" % item.aspect_id
		button.disabled = definition.slot_id.is_empty()
		button.pressed.connect(_on_item_pressed.bind(item.instance_id))
		items_list.add_child(button)
	if items_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Пусто"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		items_list.add_child(empty)
