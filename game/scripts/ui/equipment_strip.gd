class_name EquipmentStrip
extends PanelContainer

signal item_requested(instance_id: String)
signal empty_slot_requested(slot_id: String)
signal familiar_requested(character_id: String)

const SLOT_IDS: Array[String] = ["helmet", "armor", "weapon", "boots", "shoulders", "familiar", "charm", "ring"]
const SLOT_SIZE := Vector2(34, 24)
const LEFT_SLOTS: Array[String] = ["helmet", "armor", "shoulders", "boots"]
const RIGHT_SLOTS: Array[String] = ["weapon", "charm", "ring", "familiar"]
const INVENTORY_TILE_BRIGHTNESS := {
	&"normal": 1.0,
	&"hover": 1.16,
	&"pressed": 0.76,
	&"disabled": 0.56,
}

var session: GameSession
var display_mode: String = "inventory"
var character_id: String = "haruto"
var slot_buttons: Dictionary = {}
var portrait: TextureRect
var suppressed: bool = false

var _observed_inventory: InventoryService
var _empty_icons: Dictionary[String, Texture2D] = {}
var _built: bool = false

func configure(game_session: GameSession, mode: String = "inventory", selected_character_id: String = "haruto") -> void:
	session = game_session
	display_mode = mode
	character_id = selected_character_id
	if is_inside_tree():
		_build()
		_bind()
		refresh()

func set_character(value: String) -> void:
	character_id = value
	refresh()

func set_suppressed(value: bool) -> void:
	suppressed = value
	refresh()

func _ready() -> void:
	if session != null:
		_build()
		_bind()
		refresh()

func _build() -> void:
	if _built:
		return
	_built = true
	if display_mode == "characters":
		_build_portrait_layout()
		return
	theme_type_variation = &"EquipmentPanel" if display_mode == "inventory" else &"HudPanel"
	if display_mode == "combat":
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 2)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)
	if display_mode == "inventory":
		var heading := Label.new()
		heading.text = "Комплект"
		heading.add_theme_font_size_override("font_size", 8)
		heading.add_theme_color_override("font_color", AppTheme.COLOR_ACCENT_TEXT)
		column.add_child(heading)
	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	column.add_child(grid)
	for slot_id: String in SLOT_IDS:
		_add_slot(grid, slot_id, SLOT_SIZE)

func _build_portrait_layout() -> void:
	theme_type_variation = &"ArenaPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	for slot_id: String in LEFT_SLOTS:
		_add_slot(left, slot_id, Vector2(28, 27))
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(portrait)
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	for slot_id: String in RIGHT_SLOTS:
		_add_slot(right, slot_id, Vector2(28, 27))

func _add_slot(parent: Container, slot_id: String, extent: Vector2) -> void:
	if display_mode != "inventory":
		_empty_icons[slot_id] = ArtMap.texture(ArtMap.EMPTY_SLOT_ICONS[slot_id])
	var button := Button.new()
	button.name = "Slot_" + slot_id
	button.custom_minimum_size = extent
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 20)
	if display_mode == "inventory":
		UiIcons.tint(button, Color.WHITE)
	if display_mode == "combat":
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		button.pressed.connect(_on_slot_pressed.bind(slot_id))
	parent.add_child(button)
	var badge := Label.new()
	badge.name = "LevelBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 6)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	badge.offset_right = -2
	badge.offset_top = -9
	badge.hide()
	slot_buttons[slot_id] = button

func _bind() -> void:
	if session == null:
		return
	if not session.profile_changed.is_connected(_on_profile_changed):
		session.profile_changed.connect(_on_profile_changed)
	_connect_inventory()

func _connect_inventory() -> void:
	if _observed_inventory == session.inventory:
		return
	if _observed_inventory != null and _observed_inventory.changed.is_connected(refresh):
		_observed_inventory.changed.disconnect(refresh)
	_observed_inventory = session.inventory
	if not _observed_inventory.changed.is_connected(refresh):
		_observed_inventory.changed.connect(refresh)

func _exit_tree() -> void:
	if _observed_inventory != null and _observed_inventory.changed.is_connected(refresh):
		_observed_inventory.changed.disconnect(refresh)
	if session != null and session.profile_changed.is_connected(_on_profile_changed):
		session.profile_changed.disconnect(_on_profile_changed)

func _on_profile_changed() -> void:
	_connect_inventory()
	refresh()

func refresh() -> void:
	if not _built or session == null:
		return
	for slot_id: String in SLOT_IDS:
		var button: Button = slot_buttons[slot_id]
		var badge: Label = button.get_node("LevelBadge")
		if slot_id == "familiar":
			_refresh_familiar(button, badge)
			continue
		var data: Dictionary = EquipmentModel.slot(session, slot_id, character_id)
		var item: ItemInstance = data["item"]
		var definition: ItemDefinition = data["definition"]
		if item != null and definition != null:
			_set_slot_icon(button, slot_id, data["icon"])
			badge.text = str(item.level)
			badge.show()
			button.tooltip_text = "%s: %s · Ур.%d · Надето" % [data["slot_label"], definition.display_name, item.level]
		else:
			badge.hide()
			_set_slot_icon(button, slot_id)
			button.tooltip_text = "%s: Пусто" % data["slot_label"]
		button.accessibility_name = button.tooltip_text
	visible = not suppressed

func _refresh_familiar(button: Button, badge: Label) -> void:
	var definition: FamiliarDefinition = session.assigned_familiar(character_id)
	badge.visible = definition != null
	if definition == null:
		_set_slot_icon(button, "familiar")
		button.tooltip_text = "Фамильяр: Пусто"
	else:
		_set_slot_icon(button, "familiar", ArtMap.item_icon("echo_crystal", "moss"))
		var level: int = session.familiar_level(definition.id)
		badge.text = str(level)
		button.tooltip_text = "Фамильяр: %s · Ур.%d" % [definition.display_name, level]
	button.accessibility_name = button.tooltip_text

func _set_slot_icon(button: Button, slot_id: String, item_icon: Texture2D = null) -> void:
	if display_mode == "inventory":
		var path: String = ArtMap.INVENTORY_SLOT_TILES[slot_id]
		if item_icon != null:
			path = ArtMap.INVENTORY_WEAPON_PLATE if slot_id == "weapon" else ArtMap.INVENTORY_SLOT_PLATE
		_set_inventory_tile(button, path)
		button.icon = item_icon
		return
	button.icon = item_icon if item_icon != null else _empty_icons[slot_id]
	UiIcons.tint(button, Color.WHITE if item_icon != null else Color(1.0, 1.0, 1.0, 0.86))

func _set_inventory_tile(button: Button, path: String) -> void:
	var tile: Texture2D = ArtMap.texture(path)
	var current := button.get_theme_stylebox("normal") as StyleBoxTexture
	if current != null and current.texture == tile:
		return
	for state: StringName in INVENTORY_TILE_BRIGHTNESS:
		var brightness: float = INVENTORY_TILE_BRIGHTNESS[state]
		var style := StyleBoxTexture.new()
		style.texture = tile
		style.modulate_color = Color(brightness, brightness, brightness)
		style.set_content_margin_all(2.0)
		button.add_theme_stylebox_override(state, style)

func _on_slot_pressed(slot_id: String) -> void:
	if slot_id == "familiar":
		familiar_requested.emit(character_id)
		return
	var data: Dictionary = EquipmentModel.slot(session, slot_id, character_id)
	if data["item"] == null:
		empty_slot_requested.emit(slot_id)
	else:
		item_requested.emit(String(data["instance_id"]))
