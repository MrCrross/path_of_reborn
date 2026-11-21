class_name ItemInstance
extends RefCounted

var instance_id: String = ""
var definition_id: String = ""
var quantity: int = 1
var aspect_id: String = ""
var secured: bool = false
var level: int = 1
var sale_price_copper: int = 0
var sellable: bool = false

func capture_dto() -> Dictionary:
	return {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"quantity": quantity,
		"aspect_id": aspect_id,
		"secured": secured,
		"level": level,
		"sale_price_copper": sale_price_copper,
		"sellable": sellable,
	}
