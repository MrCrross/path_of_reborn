class_name LootGenerator
extends RefCounted

func generate(table: LootTableDefinition, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var rewards: Array[Dictionary] = []
	for _roll: int in range(maxi(0, table.rolls)):
		var total_weight: float = 0.0
		for entry: LootEntryDefinition in table.entries:
			total_weight += maxf(0.0, entry.weight)
		if total_weight <= 0.0:
			continue
		var roll_value: float = rng.randf() * total_weight
		var cursor: float = 0.0
		for entry: LootEntryDefinition in table.entries:
			cursor += maxf(0.0, entry.weight)
			if roll_value <= cursor and entry.weight > 0.0:
				rewards.append({
					"item_id": entry.item_id,
					"quantity": rng.randi_range(entry.min_quantity, entry.max_quantity),
					"aspect_id": entry.aspect_id,
				})
				break
	return rewards
