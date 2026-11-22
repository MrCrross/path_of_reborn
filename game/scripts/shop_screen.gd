extends Control

signal navigate_requested(destination: String)
signal shop_deal_requested(deal: Dictionary)
signal open_bag_requested(instance_id: String)

const TAB_BUY: String = "buy"
const TAB_SELL: String = "sell"
const TAB_EXCHANGE: String = "exchange"
const COUNTER_EDGE: float = 463.0 / 960.0

var session: GameSession
var _tab: String = TAB_BUY
var _deal: Dictionary = {}
var _committing: bool = false
var _appraisal_id: String = ""
var _dialogue_kind: String = ""
var _pending_focus_key: String = ""
var _focus_guard := ModalFocus.new()

var back_button: Button
var title_label: Label
var wallet_labels: Dictionary[String, Label] = {}
var buy_tab: Button
var sell_tab: Button
var exchange_tab: Button
var _catalog_ui: SafeArea
var _background: TextureRect
var _catalog_scroll: ScrollContainer
var rows_box: VBoxContainer
var status_label: Label
var talk_button: Button
var bag_button: Button
var merchant_still: TextureRect
var dialogue: DialogueOverlay
var deal_layer: Control
var _item_details: ItemDetailsView
var _exchange_header: HBoxContainer
var _exchange_close: Button
var deal_qty_row: HBoxContainer
var deal_qty_label: Label
var deal_summary: Label
var deal_reason: Label
var deal_confirm: Button

func configure(game_session: GameSession) -> void:
	session = game_session

func handle_back() -> bool:
	if deal_layer != null and deal_layer.visible:
		_close_deal()
		return true
	if dialogue != null and dialogue.is_active():
		if _dialogue_kind == "talk":
			dialogue.stop()
			_on_dialogue_finished("shop")
		return true
	navigate_requested.emit("world")
	return true

func _ready() -> void:
	if session == null:
		session = GameSession.new()
	_build_scene()
	_start_entry_scene()

func _start_entry_scene() -> void:
	if not session.world_flags.get(GameSession.WORLD_FLAG_SHOP_INTRO_DONE, false):
		_tab = TAB_SELL
		var crystal := _first_sellable_crystal()
		var assessment := "Кристаллы Эха можно продать здесь. Принеси добычу с Тропы, и я назову цену."
		if crystal != null:
			_appraisal_id = crystal.instance_id
			assessment = "За этот Кристалл Эха дам %s за штуку. Остальное решай сам." % UiText.astra(crystal.sale_price_copper)
		var jacket_price := UiText.astra(int(_find_offer("wanderer_jacket").get("price_copper", 0)))
		var substitutions := {"{assessment}": assessment, "{jacket_price}": jacket_price}
		if _play_dialogue("intro", "Оценить кристалл" if crystal != null else "", substitutions):
			return
	if session.world_flags.get(GameSession.WORLD_FLAG_SHOP_FIRST_PURCHASE_DONE, false) and not session.world_flags.get(GameSession.WORLD_FLAG_SHOP_PURCHASE_BRIEFING_DONE, false):
		if _play_dialogue("purchase", "К сделкам"):
			return
	status_label.text = "Дайдзиро: Снова ты. Смотри, что нужно."
	if not session.seen_cue_ids.has("tutorial_shop_sale") and not session.world_flags.get(GameSession.WORLD_FLAG_SHOP_FIRST_SALE_DONE, false):
		var crystal := _first_sellable_crystal()
		if crystal != null:
			_appraisal_id = crystal.instance_id
			_tab = TAB_SELL
	_refresh_all()
	_restore_row_focus()
	_show_trade_tutorial()

func _play_dialogue(kind: String, last_caption: String, substitutions: Dictionary = {}) -> bool:
	if not dialogue.play("res://data/narrative/shop_%s.json" % kind, last_caption, kind != "talk", substitutions):
		return false
	_dialogue_kind = kind
	_catalog_ui.hide()
	_show_shop_art(kind == "intro" and not _appraisal_id.is_empty())
	return true

func _first_sellable_crystal() -> ItemInstance:
	for item: ItemInstance in session.inventory.items:
		if item.definition_id == "echo_crystal" and _can_sell(item):
			return item
	return null

func _can_sell(item: ItemInstance) -> bool:
	return item.sellable and item.sale_price_copper > 0 and not session.inventory.is_equipped(item.instance_id)

func _find_offer(offer_id: String) -> Dictionary:
	for offer: Dictionary in session.shop_offers():
		if offer.get("offer_id") == offer_id:
			return offer
	return {}

func _build_scene() -> void:
	_build_art()
	_catalog_ui = SafeArea.new()
	_catalog_ui.padding = 6
	add_child(_catalog_ui)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_catalog_ui.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 3)
	column.add_child(header)
	back_button = Button.new()
	# По плану размещения — стрелка; подпись держит accessibility-текст, чтобы
	# шапка не выходила за 180 px при широкой метрике шрифта названия лавки.
	UiIcons.apply(back_button, "back", "Назад в город")
	back_button.pressed.connect(func() -> void: navigate_requested.emit("world"))
	header.add_child(back_button)
	var title_slot := Control.new()
	title_slot.custom_minimum_size = Vector2(0, 24)
	title_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_slot)
	title_label = Label.new()
	title_label.text = "Сверчок и Сумрак"
	title_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.clip_text = true
	title_label.add_theme_font_size_override("font_size", 9)
	title_label.add_theme_color_override("font_color", AppTheme.COLOR_TEXT)
	title_label.add_theme_color_override("font_shadow_color", AppTheme.COLOR_PANEL)
	title_label.add_theme_constant_override("shadow_offset_x", 1)
	title_label.add_theme_constant_override("shadow_offset_y", 1)
	title_slot.add_child(title_label)
	var header_spacer := Control.new()
	header_spacer.custom_minimum_size.x = UiIcons.TOUCH_SIZE
	header.add_child(header_spacer)
	var wallet_panel := PanelContainer.new()
	wallet_panel.add_theme_stylebox_override("panel", AppTheme.flat(AppTheme.COLOR_PANEL, AppTheme.COLOR_PANEL_BORDER, 1, 2))
	column.add_child(wallet_panel)
	var wallet_row := HBoxContainer.new()
	wallet_row.add_theme_constant_override("separation", 0)
	wallet_panel.add_child(wallet_row)
	for coin: String in GameSession.COIN_TYPES:
		var balance := HBoxContainer.new()
		balance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		balance.alignment = BoxContainer.ALIGNMENT_CENTER
		balance.add_theme_constant_override("separation", 2)
		wallet_row.add_child(balance)
		var icon := TextureRect.new()
		icon.texture = UiIcons.astra(coin)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size.x = 16
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		balance.add_child(icon)
		var amount := Label.new()
		amount.custom_minimum_size.y = 24
		amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		amount.add_theme_font_size_override("font_size", 8)
		balance.add_child(amount)
		wallet_labels[coin] = amount
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	column.add_child(tabs)
	buy_tab = _tab_button("Купить", TAB_BUY)
	tabs.add_child(buy_tab)
	sell_tab = _tab_button("Продать", TAB_SELL)
	tabs.add_child(sell_tab)
	exchange_tab = _tab_button("Обмен", TAB_EXCHANGE)
	tabs.add_child(exchange_tab)
	_catalog_scroll = ScrollContainer.new()
	_catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_catalog_scroll)
	rows_box = VBoxContainer.new()
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override("separation", 3)
	_catalog_scroll.add_child(rows_box)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 8)
	status_label.add_theme_color_override("font_color", AppTheme.COLOR_TEXT_DIM)
	column.add_child(status_label)
	talk_button = Button.new()
	talk_button.text = "Поговорить с Дайдзиро"
	talk_button.custom_minimum_size = Vector2(0, 24)
	talk_button.add_theme_font_size_override("font_size", 8)
	talk_button.pressed.connect(_on_talk_pressed)
	column.add_child(talk_button)
	bag_button = Button.new()
	bag_button.text = "Сумка"
	bag_button.custom_minimum_size = Vector2(0, 24)
	bag_button.add_theme_font_size_override("font_size", 8)
	bag_button.pressed.connect(_on_bag_pressed)
	column.add_child(bag_button)
	dialogue = DialogueOverlay.new()
	dialogue.name = "Dialogue"
	dialogue.configure(session)
	dialogue.command_requested.connect(_on_dialogue_command)
	dialogue.finished.connect(_on_dialogue_finished)
	add_child(dialogue)
	_build_deal_card()

func _build_art() -> void:
	var cover := AspectRatioContainer.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.ratio = 540.0 / 960.0
	cover.stretch_mode = AspectRatioContainer.STRETCH_COVER
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	var artboard := Control.new()
	artboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(artboard)
	_background = TextureRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artboard.add_child(_background)
	# Hide the lower body at the back edge of the painted counter. Both layers
	# use the same artboard so this edge stays fixed on taller viewports.
	var behind_counter := Control.new()
	behind_counter.anchor_right = 1.0
	behind_counter.anchor_bottom = COUNTER_EDGE
	behind_counter.clip_contents = true
	behind_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artboard.add_child(behind_counter)
	merchant_still = TextureRect.new()
	merchant_still.texture = ArtMap.texture(ArtMap.DAIJIRO_MERCHANT_STILL)
	merchant_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	merchant_still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	merchant_still.anchor_left = 0.28
	merchant_still.anchor_right = 0.78
	merchant_still.anchor_top = 0.55
	merchant_still.anchor_bottom = 1.33
	merchant_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	behind_counter.add_child(merchant_still)
	_show_shop_art(false)

func _show_shop_art(appraisal: bool) -> void:
	_background.texture = ArtMap.texture(ArtMap.BACKGROUNDS["shop_appraisal" if appraisal else "shop_cricket_twilight"])
	merchant_still.visible = not appraisal

func _tab_button(caption: String, tab: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, 24)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 9)
	button.pressed.connect(_on_tab_pressed.bind(tab))
	return button

func _build_deal_card() -> void:
	deal_layer = Control.new()
	deal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.8)
	dim.gui_input.connect(_on_deal_dim_input)
	deal_layer.add_child(dim)
	var safe := SafeArea.new()
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deal_layer.add_child(safe)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 156
	panel.add_theme_stylebox_override("panel", AppTheme.flat(AppTheme.COLOR_PANEL, AppTheme.COLOR_PANEL_BORDER, 1, 2))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	_item_details = ItemDetailsView.new()
	_item_details.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_item_details.configure(session)
	_item_details.close_requested.connect(_close_deal)
	column.add_child(_item_details)
	_exchange_header = HBoxContainer.new()
	column.add_child(_exchange_header)
	var exchange_title := Label.new()
	exchange_title.text = "Обмен астр"
	exchange_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exchange_title.add_theme_font_size_override("font_size", 10)
	_exchange_header.add_child(exchange_title)
	_exchange_close = Button.new()
	UiIcons.apply(_exchange_close, "close", "Закрыть обмен")
	_exchange_close.pressed.connect(_close_deal)
	_exchange_header.add_child(_exchange_close)
	deal_qty_row = HBoxContainer.new()
	deal_qty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	deal_qty_row.add_theme_constant_override("separation", 6)
	column.add_child(deal_qty_row)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(24, 24)
	minus.add_theme_font_size_override("font_size", 11)
	minus.accessibility_name = "Уменьшить количество"
	minus.pressed.connect(_on_deal_qty_delta.bind(-1))
	deal_qty_row.add_child(minus)
	deal_qty_label = Label.new()
	deal_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	deal_qty_label.custom_minimum_size = Vector2(28, 0)
	deal_qty_label.add_theme_font_size_override("font_size", 10)
	deal_qty_row.add_child(deal_qty_label)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(24, 24)
	plus.add_theme_font_size_override("font_size", 11)
	plus.accessibility_name = "Увеличить количество"
	plus.pressed.connect(_on_deal_qty_delta.bind(1))
	deal_qty_row.add_child(plus)
	deal_summary = Label.new()
	deal_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deal_summary.add_theme_font_size_override("font_size", 8)
	column.add_child(deal_summary)
	deal_reason = Label.new()
	deal_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deal_reason.add_theme_font_size_override("font_size", 8)
	deal_reason.add_theme_color_override("font_color", AppTheme.COLOR_DANGER)
	column.add_child(deal_reason)
	deal_confirm = Button.new()
	deal_confirm.custom_minimum_size = Vector2(0, 28)
	deal_confirm.theme_type_variation = &"PrimaryButton"
	deal_confirm.add_theme_font_size_override("font_size", 9)
	deal_confirm.pressed.connect(_on_deal_confirm)
	column.add_child(deal_confirm)
	deal_layer.hide()
	add_child(deal_layer)

func _on_tab_pressed(tab: String) -> void:
	if _tab == tab:
		return
	_tab = tab
	_pending_focus_key = ""
	status_label.text = ""
	_catalog_scroll.scroll_vertical = 0
	_refresh_all()
	_active_tab_button().grab_focus()

func _active_tab_button() -> Button:
	match _tab:
		TAB_SELL:
			return sell_tab
		TAB_EXCHANGE:
			return exchange_tab
	return buy_tab

func _on_talk_pressed() -> void:
	_play_dialogue("talk", "Вернуться")

func _on_bag_pressed() -> void:
	var jacket: ItemInstance = _jacket_instance()
	if jacket == null:
		return
	open_bag_requested.emit(jacket.instance_id)

func _jacket_instance() -> ItemInstance:
	for item: ItemInstance in session.inventory.items:
		if item.definition_id == "wanderer_jacket":
			return item
	return null

func _on_dialogue_command(command: Dictionary) -> void:
	var key: String = String(command.get("key", ""))
	if command.get("type", "") == "set_world_flag":
		session.world_flags[key] = command.get("value")
	elif command.get("type", "") == "set_npc_flag":
		session.npc_flags[key] = command.get("value")

func _on_dialogue_finished(_destination: String) -> void:
	var intro: bool = _dialogue_kind == "intro"
	var talk: bool = _dialogue_kind == "talk"
	_dialogue_kind = ""
	_show_shop_art(false)
	_catalog_ui.show()
	if intro:
		_pending_focus_key = "sell:" + _appraisal_id
	_refresh_all()
	if talk and talk_button.visible:
		talk_button.grab_focus()
	else:
		_restore_row_focus()
	if intro:
		_show_trade_tutorial()

func _show_trade_tutorial() -> void:
	if session.world_flags.get(GameSession.WORLD_FLAG_SHOP_FIRST_PURCHASE_DONE, false):
		return
	if session.world_flags.get(GameSession.WORLD_FLAG_SHOP_FIRST_SALE_DONE, false):
		ConfirmDialog.tutorial(self, session, "tutorial_shop_purchase", "Первая покупка",
			"Откройте «Купить» и выберите Куртку странника. В карточке видны прибавка к защите, цена и остаток астр.")
	elif not _appraisal_id.is_empty():
		ConfirmDialog.tutorial(self, session, "tutorial_shop_sale", "Первая продажа",
			"Откройте подсвеченный кристалл на вкладке «Продать». Проверьте количество и выручку, затем подтвердите продажу.")

## --- Список и вкладки ---

func _refresh_all() -> void:
	for coin: String in GameSession.COIN_TYPES:
		var amount: Label = wallet_labels[coin]
		amount.text = "%s\n%s" % [UiText.coin_count(session.wallet[coin]), UiText.COIN_SUFFIXES[coin]]
		amount.accessibility_name = UiText.astra(session.wallet[coin], coin)
		amount.get_parent_control().tooltip_text = amount.accessibility_name
	for tab: Button in [buy_tab, sell_tab, exchange_tab]:
		tab.theme_type_variation = &"PrimaryButton" if tab == _active_tab_button() else &""
	talk_button.visible = session.world_flags.get(GameSession.WORLD_FLAG_SHOP_INTRO_DONE, false) and not session.seen_cue_ids.has("DIA_SHOP_014")
	var jacket: ItemInstance = _jacket_instance()
	bag_button.visible = (
		jacket != null
		and not session.inventory.is_equipped(jacket.instance_id)
		and bool(session.world_flags.get(GameSession.WORLD_FLAG_SHOP_PURCHASE_BRIEFING_DONE, false))
	)
	_refresh_rows()
	status_label.visible = not status_label.text.is_empty()

func _refresh_rows() -> void:
	var previous_scroll: int = _catalog_scroll.scroll_vertical
	for child: Node in rows_box.get_children():
		rows_box.remove_child(child)
		child.queue_free()
	match _tab:
		TAB_BUY:
			_build_buy_rows()
		TAB_SELL:
			_build_sell_rows()
		TAB_EXCHANGE:
			for index: int in range(GameSession.COIN_TYPES.size() - 1):
				var lower: String = GameSession.COIN_TYPES[index]
				var higher: String = GameSession.COIN_TYPES[index + 1]
				_add_exchange_row(lower, higher)
				_add_exchange_row(higher, lower)
	if rows_box.get_child_count() == 0:
		var empty := Label.new()
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 8)
		empty.add_theme_color_override("font_color", AppTheme.COLOR_TEXT_DIM)
		empty.text = "Покупок пока нет." if _tab == TAB_BUY else "Кристаллов для продажи нет. Они выпадают из монстров на Тропе."
		rows_box.add_child(empty)
	_catalog_scroll.set_deferred("scroll_vertical", previous_scroll)

func _build_buy_rows() -> void:
	for offer: Dictionary in session.shop_offers():
		var price: int = int(offer.get("price_copper", 0))
		var sold_out: bool = bool(offer.get("sold_out", false))
		var button := Button.new()
		# Две строки: min-ширина кнопки считается по самой длинной строке, а не
		# по всей подписи — иначе длинное русское имя раздувает цепочку
		# контейнеров и выталкивает шапку за 180 px (метрика fallback-шрифта
		# плавает от запуска к запуску).
		button.text = "%s%s\n%s" % [
			String(offer.get("display_name", "")),
			" · Куплено" if sold_out else "",
			UiText.astra(price),
		]
		var offer_id: String = offer["offer_id"]
		var row_key: String = "buy:" + offer_id
		button.set_meta(&"trade_row", row_key)
		button.icon = ArtMap.item_icon(String(offer.get("item_id", "")))
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", UiIcons.ICON_SIZE)
		button.custom_minimum_size = Vector2(0, 30)
		button.add_theme_font_size_override("font_size", 8)
		button.accessibility_name = "Купить %s за %s" % [String(offer.get("display_name", "")), UiText.astra(price)]
		button.disabled = sold_out
		if not sold_out:
			button.pressed.connect(_open_deal.bind({"kind": "buy", "offer_id": offer_id, "row_key": row_key}))
		rows_box.add_child(button)

func _build_sell_rows() -> void:
	for item: ItemInstance in session.inventory.items:
		if not _can_sell(item):
			continue
		var definition: ItemDefinition = session.get_item_definition(item.definition_id)
		if definition == null:
			continue
		var name: String = definition.display_name
		var aspect: String = UiText.aspect(item.aspect_id)
		if not aspect.is_empty():
			name = "%s · %s" % [name, aspect]
		var button := Button.new()
		button.text = "%s ×%d\n%s/шт" % [name, item.quantity, UiText.astra(item.sale_price_copper)]
		var row_key: String = "sell:" + item.instance_id
		button.set_meta(&"trade_row", row_key)
		button.icon = ArtMap.item_icon(item.definition_id, item.aspect_id)
		UiIcons.tint(button, Color.WHITE)
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", UiIcons.ICON_SIZE)
		button.custom_minimum_size = Vector2(0, 30)
		button.add_theme_font_size_override("font_size", 8)
		button.accessibility_name = "Продать %s, %d штук по %s" % [name, item.quantity, UiText.astra(item.sale_price_copper)]
		if item.instance_id == _appraisal_id and not session.world_flags.get(GameSession.WORLD_FLAG_SHOP_FIRST_SALE_DONE, false):
			button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(_open_deal.bind({"kind": "sell", "instance_id": item.instance_id, "row_key": row_key}))
		rows_box.add_child(button)

func _offer_max_qty(offer: Dictionary) -> int:
	var remaining: int = int(offer.get("remaining", -1))
	return remaining if remaining > 0 else 99

func _add_exchange_row(from_coin: String, to_coin: String) -> void:
	var quote: Dictionary = session.coin_exchange_quote(from_coin, to_coin)
	var button := Button.new()
	button.text = _exchange_amounts(from_coin, to_coin, int(quote["spend"]), int(quote["receive"]))
	button.icon = UiIcons.astra(from_coin)
	UiIcons.tint(button, Color.WHITE)
	button.add_theme_constant_override("icon_max_width", UiIcons.ICON_SIZE)
	button.custom_minimum_size.y = 28
	button.add_theme_font_size_override("font_size", 9)
	button.accessibility_name = "Обменять " + button.text
	var row_key: String = "exchange:%s:%s" % [from_coin, to_coin]
	button.set_meta(&"trade_row", row_key)
	button.pressed.connect(_open_deal.bind({"kind": "exchange", "from_coin": from_coin, "to_coin": to_coin, "row_key": row_key}))
	rows_box.add_child(button)

func _exchange_amounts(from_coin: String, to_coin: String, spent: int, received: int) -> String:
	return "%s → %s" % [UiText.astra(spent, from_coin), UiText.astra(received, to_coin)]

## Фокус после перестроения списка: на сохранённую строку, иначе на первую
## доступную, иначе на текущую вкладку.
func _restore_row_focus() -> void:
	for child: Node in rows_box.get_children():
		if child is Button and not (child as Button).disabled and child.get_meta(&"trade_row", "") == _pending_focus_key:
			(child as Button).grab_focus()
			return
	for child: Node in rows_box.get_children():
		if child is Button and not (child as Button).disabled:
			(child as Button).grab_focus()
			return
	_active_tab_button().grab_focus()

## --- Карточка сделки ---

func _open_deal(payload: Dictionary) -> void:
	if _committing or dialogue.is_active():
		return
	_deal = payload.duplicate()
	_deal["quantity"] = 1
	var is_exchange: bool = _deal["kind"] == "exchange"
	_item_details.visible = not is_exchange
	_exchange_header.visible = is_exchange
	deal_layer.show()
	_focus_guard.capture(deal_layer)
	_refresh_deal()
	if deal_confirm.disabled:
		(_exchange_close if is_exchange else _item_details.close_button).grab_focus()
	else:
		deal_confirm.grab_focus()

func _close_deal() -> void:
	if _committing:
		return
	deal_layer.hide()
	_focus_guard.restore()
	_deal = {}

func _on_deal_dim_input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		_close_deal()

func _on_deal_qty_delta(delta: int) -> void:
	if _deal.is_empty():
		return
	var quantity: int = int(_deal["quantity"])
	if delta > 0 and quantity >= int(_deal["max_qty"]):
		return
	_deal["quantity"] = maxi(1, quantity + delta)
	_refresh_deal()

## Живые числа карточки: всё пересчитывается из текущей сессии, поэтому
## изменившиеся условия видны до подтверждения, а отказ записи оставляет
## те же значения для повтора.
func _refresh_deal() -> void:
	if _deal.is_empty():
		return
	if _deal["kind"] == "exchange":
		_refresh_exchange_deal()
		return
	var buying: bool = _deal.get("kind") == "buy"
	var quantity: int = int(_deal.get("quantity", 1))
	var unit_price: int
	var available_qty: int
	if buying:
		var offer := _find_offer(String(_deal["offer_id"]))
		if offer.is_empty():
			_close_deal()
			return
		unit_price = int(offer["price_copper"])
		available_qty = 0 if bool(offer["sold_out"]) else _offer_max_qty(offer)
		_item_details.present_reward(String(offer["item_id"]), "", quantity)
	else:
		var item: ItemInstance = session.inventory.get_item(String(_deal["instance_id"]))
		if item == null or not _can_sell(item):
			_close_deal()
			return
		unit_price = item.sale_price_copper
		available_qty = item.quantity
		_item_details.present_instance(item.instance_id)
	_item_details.meta_label.hide()
	_item_details.description_label.hide()
	_item_details.custom_minimum_size.y = 100 if buying else 86
	_item_details.compare_label.get_parent().visible = buying
	_item_details.compare_label.visible = buying and _item_details.model.get("current_item") != null
	_deal["unit_price_copper"] = unit_price
	_deal["stock"] = available_qty
	_deal["max_qty"] = maxi(1, available_qty)
	deal_qty_row.visible = available_qty > 1
	deal_qty_label.text = "×%d" % quantity
	var total: int = GameSession.trade_total(unit_price, quantity)
	deal_summary.text = UiText.astra(total)
	deal_confirm.text = "Купить" if buying else "Продать"
	var reason: String = ""
	if available_qty <= 0:
		reason = "Куплено"
	elif quantity > available_qty:
		_deal["quantity"] = available_qty
		_refresh_deal()
		return
	elif total == 0 or (not buying and session.wallet[GameSession.COPPER] > GameSession.MAX_ASTRAS - total):
		reason = "Сумма превышает доступный предел"
	elif buying and session.wallet[GameSession.COPPER] < total:
		reason = "Не хватает %s" % UiText.astra(total - session.wallet[GameSession.COPPER])
	else:
		var balance_after: int = session.wallet[GameSession.COPPER] - total if buying else session.wallet[GameSession.COPPER] + total
		deal_summary.text += "   ·   Баланс %s" % UiText.astra(balance_after)
	deal_reason.text = reason
	deal_reason.visible = not reason.is_empty()
	deal_confirm.disabled = not reason.is_empty() or _committing

func _refresh_exchange_deal() -> void:
	var from_coin: String = _deal["from_coin"]
	var to_coin: String = _deal["to_coin"]
	var quote: Dictionary = session.coin_exchange_quote(from_coin, to_coin)
	var available: int = int(quote["max_quantity"])
	var quantity: int = clampi(int(_deal["quantity"]), 1, maxi(1, available))
	_deal["quote"] = quote
	_deal["max_qty"] = maxi(1, available)
	_deal["quantity"] = quantity
	deal_qty_row.visible = available > 1
	deal_qty_label.text = "×%d" % quantity
	var spent: int = int(quote["spend"]) * quantity
	var received: int = int(quote["receive"]) * quantity
	deal_summary.text = _exchange_amounts(from_coin, to_coin, spent, received)
	var reason: String = ""
	if int(quote["from_balance"]) < spent:
		reason = "Не хватает %s" % UiText.astra(spent - int(quote["from_balance"]), from_coin)
	elif available == 0:
		reason = "Достигнут предел монет в кошельке"
	else:
		deal_summary.text += "\nПосле обмена  %s · %s" % [
			UiText.astra(int(quote["from_balance"]) - spent, from_coin),
			UiText.astra(int(quote["to_balance"]) + received, to_coin),
		]
	deal_reason.text = reason
	deal_reason.visible = not reason.is_empty()
	deal_confirm.text = "Обменять"
	deal_confirm.disabled = available == 0 or _committing

func _on_deal_confirm() -> void:
	if _committing or _deal.is_empty() or deal_confirm.disabled:
		return
	_committing = true
	deal_confirm.disabled = true
	_pending_focus_key = String(_deal["row_key"])
	shop_deal_requested.emit(_deal.duplicate(true))

## Вызывается GameRoot после успешной записи сделки: карточка закрывается,
## кошелёк и список обновляются, вкладка и позиция сохраняются.
func deal_committed(deal: Dictionary) -> void:
	_committing = false
	_deal = {}
	deal_layer.hide()
	_focus_guard.restore()
	if deal.get("kind", "") == "exchange":
		status_label.text = "Обменено  " + _exchange_amounts(deal["from_coin"], deal["to_coin"], deal["spent"], deal["received"])
		_refresh_all()
		_restore_row_focus()
		return
	var is_buy: bool = String(deal.get("kind", "")) == "buy"
	status_label.text = "%s: %s ×%d · %s%s" % [
		"Куплено" if is_buy else "Продано",
		String(deal.get("display_name", "")),
		int(deal.get("quantity", 1)),
		"−" if is_buy else "+",
		UiText.astra(int(deal.get("total_copper", 0))),
	]
	_refresh_all()
	_restore_row_focus()
	if (
		is_buy
		and String(deal.get("item_id", "")) == "wanderer_jacket"
		and not bool(session.world_flags.get(GameSession.WORLD_FLAG_SHOP_PURCHASE_BRIEFING_DONE, false))
	):
		_play_dialogue("purchase", "К сделкам")
	elif not is_buy:
		_show_trade_tutorial()

## Ошибка записи: сессия не изменена — карточка остаётся с теми же числами.
func deal_rejected(message: String) -> void:
	_committing = false
	_pending_focus_key = ""
	_refresh_deal()
	if deal_layer.visible:
		if deal_reason.text.is_empty():
			deal_reason.text = message
		deal_reason.show()
	else:
		status_label.text = message
		_refresh_all()
		_restore_row_focus()
