class_name ItemInstance
extends RefCounted

var instance_id: String = ""
var definition_id: String = ""
var quantity: int = 1
var aspect_id: String = ""
var secured: bool = false

func capture_dto() -> Dictionary:
	return {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"quantity": quantity,
		"aspect_id": aspect_id,
		"secured": secured,
	}
