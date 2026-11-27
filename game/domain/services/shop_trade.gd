extends RefCounted
## Validates each quote against the current inventory, wallet and stock.
## An empty receipt means that the transaction made no changes.

const CATALOG_PATH := "res://data/shop/cricket_twilight.json"
const MAX_ASTRAS := 9223372036854775807
const COPPER := "copper"
const SILVER := "silver"
const GOLD := "gold"
const COIN_TYPES: Array[String] = [COPPER, SILVER, GOLD]
const EXCHANGE_RATE := 100

static var _catalog: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		if file == null:
			return {"shop_id": "cricket_twilight", "offers": []}
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) == OK and parser.data is Dictionary and parser.data.get("offers") is Array:
			_catalog = parser.data
		else:
			_catalog = {"shop_id": "cricket_twilight", "offers": []}
	return _catalog

static func offers(inventory: InventoryService, world_flags: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Variant in catalog().get("offers", []):
		if entry is not Dictionary:
			continue
		var offer_id := String(entry.get("offer_id", ""))
		var definition := inventory.get_definition(String(entry.get("item_id", "")))
		if offer_id.is_empty() or definition == null:
			continue
		var once_flag := String(entry.get("once_flag", ""))
		var limit := maxi(0, int(entry.get("purchase_limit", 0)))
		var remaining := -1
		if limit > 0:
			remaining = limit - int(not once_flag.is_empty() and bool(world_flags.get(once_flag, false)))
		result.append({
			"offer_id": offer_id,
			"item_id": definition.id,
			"display_name": definition.display_name,
			"price_copper": maxi(0, int(entry.get("price_copper", definition.sale_price_copper))),
			"purchase_limit": limit,
			"remaining": remaining,
			"sold_out": remaining == 0,
			"once_flag": once_flag,
		})
	return result

static func trade_total(unit_price: int, quantity: int) -> int:
	@warning_ignore("integer_division")
	if unit_price <= 0 or quantity <= 0 or unit_price > MAX_ASTRAS / quantity:
		return 0
	return unit_price * quantity

static func buy(
	inventory: InventoryService, wallet: Dictionary[String, int], world_flags: Dictionary,
	offer_id: String, quantity: int, expected_price: int
) -> Dictionary:
	for offer: Dictionary in offers(inventory, world_flags):
		if offer["offer_id"] != offer_id:
			continue
		var remaining: int = offer["remaining"]
		if remaining >= 0 and quantity > remaining:
			return {}
		var price: int = offer["price_copper"]
		var total := trade_total(price, quantity)
		if total <= 0 or wallet[COPPER] < total or (expected_price >= 0 and price != expected_price):
			return {}
		var definition := inventory.get_definition(offer["item_id"])
		if definition == null or definition.id.is_empty() or definition.stack_limit <= 0:
			return {}
		wallet[COPPER] -= total
		var instance_ids: Array[String] = []
		for item: ItemInstance in inventory.add(definition, quantity):
			instance_ids.append(item.instance_id)
		var once_flag: String = offer["once_flag"]
		if not once_flag.is_empty():
			world_flags[once_flag] = true
		return {
			"kind": "buy",
			"offer_id": offer_id,
			"item_id": definition.id,
			"display_name": definition.display_name,
			"quantity": quantity,
			"unit_price_copper": price,
			"total_copper": total,
			"instance_ids": instance_ids,
			"balance_after": wallet[COPPER],
		}
	return {}

static func sell(
	inventory: InventoryService, wallet: Dictionary[String, int], instance_id: String,
	quantity: int, expected_price: int, expected_stock: int
) -> Dictionary:
	var item := inventory.get_item(instance_id)
	if item == null or not item.sellable or item.quantity < quantity or inventory.is_equipped(instance_id):
		return {}
	if (expected_price >= 0 and item.sale_price_copper != expected_price) or (expected_stock >= 0 and item.quantity != expected_stock):
		return {}
	var total := trade_total(item.sale_price_copper, quantity)
	if total <= 0 or wallet[COPPER] > MAX_ASTRAS - total:
		return {}
	if not inventory.remove(instance_id, quantity):
		return {}
	wallet[COPPER] += total
	var definition := inventory.get_definition(item.definition_id)
	return {
		"kind": "sell",
		"instance_id": instance_id,
		"item_id": item.definition_id,
		"display_name": definition.display_name if definition != null else item.definition_id,
		"quantity": quantity,
		"unit_price_copper": item.sale_price_copper,
		"total_copper": total,
		"balance_after": wallet[COPPER],
	}

static func exchange_quote(wallet: Dictionary[String, int], from_coin: String, to_coin: String) -> Dictionary:
	var from_index := COIN_TYPES.find(from_coin)
	var to_index := COIN_TYPES.find(to_coin)
	if from_index < 0 or to_index < 0 or absi(from_index - to_index) != 1:
		return {}
	var spend := EXCHANGE_RATE if from_index < to_index else 1
	var receive := 1 if from_index < to_index else EXCHANGE_RATE
	var from_balance: int = wallet[from_coin]
	var to_balance: int = wallet[to_coin]
	@warning_ignore("integer_division")
	var max_quantity := mini(from_balance / spend, (MAX_ASTRAS - to_balance) / receive)
	return {
		"spend": spend,
		"receive": receive,
		"from_balance": from_balance,
		"to_balance": to_balance,
		"max_quantity": max_quantity,
	}

static func exchange(
	wallet: Dictionary[String, int], from_coin: String, to_coin: String,
	quantity: int, expected_quote: Dictionary
) -> Dictionary:
	var quote := exchange_quote(wallet, from_coin, to_coin)
	if quantity < 1 or quote.is_empty() or quote != expected_quote or quantity > int(quote["max_quantity"]):
		return {}
	var spent := int(quote["spend"]) * quantity
	var received := int(quote["receive"]) * quantity
	wallet[from_coin] -= spent
	wallet[to_coin] += received
	return {"kind": "exchange", "from_coin": from_coin, "to_coin": to_coin, "spent": spent, "received": received}
