extends Control

signal navigate_requested(destination: String)

const HERO_ID := "haruto"
const HERO_ART_REGION := Rect2(14, 72, 750, 1288)

var session: GameSession
var selected_character_id: String = ""
var catalog_buttons: Dictionary[String, Button] = {}

var _open_hero_on_ready: bool = false
var _hero_art: AtlasTexture
var _focus_guard := ModalFocus.new()

@onready var back_button: Button = %BackButton
@onready var catalog: ScrollContainer = %Catalog
@onready var profile: ScrollContainer = %Profile
@onready var stats_label: Label = %Stats
@onready var upgrade_row: HBoxContainer = %UpgradeRow
@onready var strength_upgrade: Button = %StrengthUpgrade
@onready var hp_upgrade: Button = %HpUpgrade
@onready var familiar_option: OptionButton = %FamiliarOption
@onready var familiar_button: Button = %FamiliarButton
@onready var equipment_strip: EquipmentStrip = %EquipmentStrip
@onready var details_layer: Control = %ItemDetailsLayer
@onready var details_view: ItemDetailsView = %ItemDetails

func configure(game_session: GameSession, open_hero: bool = false) -> void:
	session = game_session
	_open_hero_on_ready = open_hero

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	_hero_art = AtlasTexture.new()
	_hero_art.atlas = ArtMap.texture(ArtMap.HERO_EXILED_STILL)
	_hero_art.region = HERO_ART_REGION
	_hero_art.filter_clip = true
	UiIcons.apply(back_button, "back", "К пути")
	back_button.pressed.connect(handle_back)
	for label: Label in [%TotalPower, %Power, %NextLevel, %UpgradeCount]:
		label.add_theme_color_override("font_color", AppTheme.COLOR_ACCENT)
	for label: Label in [%RosterCount, %Experience, %SlotHint, %FamiliarStatus]:
		label.add_theme_color_override("font_color", AppTheme.COLOR_TEXT_DIM)
	equipment_strip.configure(session, "characters")
	equipment_strip.item_requested.connect(_open_details)
	equipment_strip.empty_slot_requested.connect(_on_empty_slot)
	equipment_strip.familiar_requested.connect(_show_familiar)
	details_view.configure(session, true)
	details_view.close_requested.connect(_close_details)
	details_view.action_requested.connect(_on_item_action)
	$ItemDetailsLayer/Dim.gui_input.connect(_on_details_dismiss)
	strength_upgrade.pressed.connect(_choose_upgrade.bind("strength"))
	hp_upgrade.pressed.connect(_choose_upgrade.bind("max_hp"))
	familiar_option.accessibility_name = "Фамильяр Харуто"
	familiar_option.item_selected.connect(_on_familiar_selected)
	familiar_button.pressed.connect(_upgrade_familiar)
	session.profile_changed.connect(_on_profile_changed)
	_refresh_background()
	if _open_hero_on_ready:
		_open_character(HERO_ID)
		if upgrade_row.visible:
			strength_upgrade.grab_focus()
	else:
		_show_catalog()

func handle_back() -> bool:
	if details_layer.visible:
		_close_details()
	elif profile.visible and not _open_hero_on_ready:
		_show_catalog(selected_character_id)
	else:
		navigate_requested.emit("world")
	return true

func _show_catalog(focus_id: String = HERO_ID) -> void:
	selected_character_id = ""
	profile.hide()
	catalog.show()
	%CatalogArt.show()
	%Heading.text = "Персонажи"
	_set_back_label("К пути")
	_refresh_catalog()
	var tile: Button = catalog_buttons.get(focus_id, catalog_buttons[HERO_ID])
	tile.grab_focus()

func _refresh_catalog() -> void:
	var roster: Array[String] = session.available_character_ids()
	for character_id: String in catalog_buttons.keys():
		if not roster.has(character_id):
			var tile: Button = catalog_buttons[character_id]
			%Roster.remove_child(tile)
			tile.queue_free()
			catalog_buttons.erase(character_id)
	var total: int = 0
	for character_id: String in roster:
		var state: CharacterState = session.character_state(character_id)
		if not catalog_buttons.has(character_id):
			catalog_buttons[character_id] = _create_catalog_tile(character_id)
		var tile: Button = catalog_buttons[character_id]
		var power: int = state.power_rating()
		var upgrade_choices: int = state.pending_upgrade_choices
		tile.get_node("Inset/Contents/Name").text = state.definition.display_name
		tile.get_node("Inset/Contents/Level").text = "Ур. %d" % state.level
		tile.get_node("Inset/Contents/Power").text = "Мощность %d" % power
		var badge: Label = tile.get_node("Inset/Contents/Upgrades")
		badge.text = "Улучшения: %d" % upgrade_choices
		badge.visible = upgrade_choices > 0
		tile.accessibility_name = "%s · Ур. %d · Мощность %d" % [state.definition.display_name, state.level, power]
		if badge.visible:
			tile.accessibility_name += " · " + badge.text
		total += power
	%RosterCount.text = "В отряде: %d" % roster.size()
	%TotalPower.text = "Общая мощность %d" % total

func _create_catalog_tile(character_id: String) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size.y = 116
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.pressed.connect(_open_character.bind(character_id))
	%Roster.add_child(tile)
	var inset := MarginContainer.new()
	inset.name = "Inset"
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 5)
	tile.add_child(inset)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var contents := VBoxContainer.new()
	contents.name = "Contents"
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_theme_constant_override("separation", 1)
	inset.add_child(contents)
	_tile_label(contents, "Name", 10, AppTheme.COLOR_TEXT)
	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.custom_minimum_size.y = 50
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_set_character_art(art, character_id)
	contents.add_child(art)
	_tile_label(contents, "Level", 8, AppTheme.COLOR_TEXT_DIM)
	_tile_label(contents, "Power", 9, AppTheme.COLOR_ACCENT)
	_tile_label(contents, "Upgrades", 8, AppTheme.COLOR_MAGIC)
	return tile

func _tile_label(parent: Container, label_name: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _open_character(character_id: String) -> void:
	selected_character_id = character_id
	catalog.hide()
	profile.show()
	%CatalogArt.hide()
	profile.scroll_vertical = 0
	%SlotHint.hide()
	_set_back_label("К списку персонажей" if not _open_hero_on_ready else "К пути")
	_set_character_art(equipment_strip.portrait, character_id)
	_refresh()
	back_button.grab_focus()

func _set_back_label(label: String) -> void:
	back_button.tooltip_text = label
	back_button.accessibility_name = label

func _set_character_art(art: TextureRect, character_id: String) -> void:
	var is_hero: bool = character_id == HERO_ID
	art.texture = _hero_art if is_hero else ArtMap.texture(ArtMap.UI["characters"])
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if is_hero else TextureRect.STRETCH_KEEP_CENTERED

func _on_profile_changed() -> void:
	_refresh_background()
	if catalog.visible:
		_refresh_catalog()
	elif session.available_character_ids().has(selected_character_id):
		_refresh()
	else:
		if details_layer.visible:
			_close_details()
		_show_catalog()

func _refresh_background() -> void:
	var key: String = "world_lioren" if session.location_id == "lioren" else "world_forest_edge"
	var texture: Texture2D = ArtMap.texture(ArtMap.BACKGROUNDS[key])
	%CatalogArt.texture = texture
	%StageArt.texture = texture

func _refresh() -> void:
	var state: CharacterState = session.character_state(selected_character_id)
	if state == null:
		return
	%Heading.text = state.definition.display_name
	%Level.text = "Уровень %d" % state.level
	%Power.text = "Мощность %d" % state.power_rating()
	stats_label.text = "HP %d/%d · Сила %d\nЗащита %d · Мана %d" % [state.current_hp, state.max_hp, state.strength, state.defense, state.mana]
	equipment_strip.set_character(selected_character_id)
	details_view.character_id = selected_character_id
	_refresh_progression(state)
	_refresh_familiar()

func _refresh_progression(state: CharacterState) -> void:
	var required_xp: int = state.xp_to_next_level()
	var has_next: bool = required_xp > 0
	var gains: Dictionary[String, int] = state.upgrade_gains()
	%NextLevel.text = "Следующий уровень · %d" % (state.level + 1) if has_next else "Максимальный уровень"
	%Experience.text = "%d / %d XP" % [state.experience, required_xp]
	%Experience.visible = has_next
	%ExperienceBar.visible = has_next
	if has_next:
		%ExperienceBar.max_value = required_xp
		%ExperienceBar.value = state.experience
	%NextGain.visible = has_next
	%NextGain.text = "На выбор: Сила %+d или макс. HP %+d" % [gains["strength"], gains["max_hp"]]
	var ability_lines: Array[String] = []
	for ability: AbilityDefinition in state.definition.abilities:
		if has_next and ability.unlock_level == state.level + 1:
			%NextGain.text += "\nОткроется «%s»" % ability.display_name
		elif state.level >= ability.unlock_level:
			if state == session.hero and session.quest_flags.get(GameSession.GROVE_REPORTED, false):
				ability_lines.append("Точный выпад I · бонус в окно уязвимости")
			else:
				ability_lines.append("%s · готова в бою" % ability.display_name)
		else:
			ability_lines.append("%s · ур. %d" % [ability.display_name, ability.unlock_level])
	if state == session.hero and session.quest_flags.get(GameSession.HOLLOW_TEMPO, false):
		ability_lines.append("Смена темпа I · быстрый замах после уклонения")
	%Abilities.visible = not ability_lines.is_empty()
	%Abilities.text = "\n".join(ability_lines)
	var has_choices: bool = state.pending_upgrade_choices > 0
	%UpgradeCount.visible = has_choices
	%UpgradeCount.text = "Улучшения на выбор: %d" % state.pending_upgrade_choices
	upgrade_row.visible = has_choices
	strength_upgrade.text = "Сила %d → %d" % [state.strength, state.strength + gains["strength"]]
	hp_upgrade.text = "HP %d → %d" % [state.max_hp, state.max_hp + gains["max_hp"]]

func _refresh_familiar() -> void:
	familiar_option.clear()
	var assigned: FamiliarDefinition = session.assigned_familiar(selected_character_id)
	var is_hero: bool = selected_character_id == HERO_ID
	if is_hero:
		familiar_option.add_item("Без фамильяра")
		familiar_option.set_item_metadata(0, "")
		for familiar_id: String in session.familiars.get("owned", {}):
			var definition: FamiliarDefinition = session.familiar_definition(familiar_id)
			if definition != null and definition.bound_character_id.is_empty():
				familiar_option.add_item("%s · Ур. %d" % [definition.display_name, session.familiar_level(familiar_id)])
				var slot: int = familiar_option.item_count - 1
				familiar_option.set_item_metadata(slot, familiar_id)
				if assigned != null and assigned.id == familiar_id:
					familiar_option.select(slot)
	var can_select: bool = is_hero and familiar_option.item_count > 1
	familiar_option.visible = can_select
	var assigned_level: int = session.familiar_level(assigned.id) if assigned != null else 0
	%FamiliarStatus.visible = not can_select
	%FamiliarStatus.text = "Фамильяр: %s · Ур. %d" % [assigned.display_name, assigned_level] if assigned != null else "Фамильяр не назначен"
	familiar_button.visible = not is_hero and assigned != null and assigned_level < assigned.max_level
	familiar_button.text = "Развить фамильяра"
	if not is_hero and assigned != null and assigned_level >= assigned.max_level:
		%FamiliarStatus.text += " · Максимум"

func _on_familiar_selected(index: int) -> void:
	var familiar_id: String = String(familiar_option.get_item_metadata(index))
	var changed: bool = session.clear_familiar(HERO_ID) if familiar_id.is_empty() else session.assign_familiar(HERO_ID, familiar_id)
	if not changed:
		_refresh_familiar()

func _show_familiar(_character_id: String) -> void:
	profile.ensure_control_visible(%FamiliarPanel)
	if familiar_option.visible:
		familiar_option.grab_focus()
	elif familiar_button.visible:
		familiar_button.grab_focus()

func _upgrade_familiar() -> void:
	if session.upgrade_familiar(selected_character_id) and not familiar_button.visible:
		equipment_strip.slot_buttons["familiar"].grab_focus()

func _choose_upgrade(upgrade_id: String) -> void:
	if session.choose_upgrade(upgrade_id, selected_character_id) and not upgrade_row.visible:
		back_button.grab_focus()

func _open_details(instance_id: String) -> void:
	if not details_view.present_instance(instance_id):
		return
	%SlotHint.hide()
	details_layer.show()
	_focus_guard.capture(details_layer)
	details_view.close_button.grab_focus()

func _on_empty_slot(slot_id: String) -> void:
	%SlotHint.text = "Слот «%s» пуст. Вещи можно надеть в рюкзаке." % UiText.slot(slot_id)
	%SlotHint.show()

func _on_item_action(instance_id: String, slot_id: String, equipped: bool) -> void:
	var changed: bool = session.unequip_item(slot_id, selected_character_id) if equipped else session.equip_item(instance_id, selected_character_id)
	if changed:
		%SlotHint.hide()
		details_view.present_instance(instance_id)

func _close_details() -> void:
	details_layer.hide()
	_focus_guard.restore()

func _on_details_dismiss(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		_close_details()
