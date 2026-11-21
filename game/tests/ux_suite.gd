extends RefCounted

## UX/UI регрессии: пагинация, однократные side effects, маршрут Continue,
## идемпотентный claim, локализованные подписи. Без GUI: проверяем реальные
## риски контрактов, а не декоративные координаты.

const DomainSuite = preload("res://tests/domain_suite.gd")
const TestContext = DomainSuite.TestContext

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_run_case("layout_aware_pagination_preserves_full_text", _test_pagination_policy))
	results.append(_run_case("cue_completed_fires_exactly_once_per_cue", _test_cue_completed_once))
	results.append(_run_case("continue_route_respects_prologue_completion", _test_continue_route))
	results.append(_run_case("claim_reward_is_idempotent", _test_claim_idempotent))
	results.append(_run_case("ui_text_covers_data_ids", _test_ui_text_coverage))
	results.append(_run_case("currency_boundaries_compact_suffixes_and_exact_int64", _test_currency_format))
	return results

func _run_case(case_name: String, test: Callable) -> Dictionary:
	var context := TestContext.new()
	test.call(context)
	return {"name": case_name, "checks": context.checks}

func _full_prologue_runner() -> DialogueRunner:
	var runner := DialogueRunner.new()
	runner.load_file("res://data/narrative/prologue.json")
	return runner

func _texts_of(cue: Dictionary) -> Array[String]:
	var texts: Array[String] = [String(cue.get("text", ""))]
	for part: Dictionary in cue.get("parts", []):
		texts.append(String(part.get("text", "")))
	return texts

func _normalized(text: String) -> String:
	var compact: PackedStringArray = text.split(" ", false)
	return " ".join(compact)

func _test_pagination_policy(context: TestContext) -> void:
	for limit: int in [32, 64, 88, 240]:
		var runner := _full_prologue_runner()
		runner.page_character_limit = limit
		var preserved := true
		for cue: Dictionary in runner.entries:
			# Все варианты текста cue (основной + parts) режутся по той же политике.
			for text: String in _texts_of(cue):
				var pages: Array[String] = DialogueRunner.paginate(text, limit)
				if _normalized(" ".join(pages)) != _normalized(text):
					preserved = false
		context.check(preserved, "Limit %d keeps every word without loss or duplication" % limit)
	var runner := _full_prologue_runner()
	runner.page_character_limit = 40
	var joined: String = ""
	for cue: Dictionary in runner.entries:
		for text: String in _texts_of(cue):
			joined += _normalized(" ".join(DialogueRunner.paginate(text, 40)))
	context.check(joined.length() > 0, "Paginated corpus is non-empty")

func _test_cue_completed_once(context: TestContext) -> void:
	var runner := DialogueRunner.new()
	runner.configure(GameSession.new())
	runner.entries = [
		{"id": "DIA_A", "text": "one"},
		{"id": "DIA_B", "text": "two", "enter": "flash"},
		{"id": "DIA_C", "text": "three", "destination": "world"},
	]
	var counts: Dictionary = {}
	runner.cue_completed.connect(func(cue_id: String) -> void: counts[cue_id] = int(counts.get(cue_id, 0)) + 1)
	runner.start()
	var guard: int = 0
	while not runner.is_finished and guard < 40:
		runner.tap()
		runner.advance_ticks(DialogueRunner.TRANSITION_TICKS)
		guard += 1
	context.check(runner.is_finished, "Runner finishes with bounded input")
	context.check(int(counts.get("DIA_A", 0)) == 1, "DIA_A completed exactly once")
	context.check(int(counts.get("DIA_B", 0)) == 1, "DIA_B completed exactly once")
	context.check(int(counts.get("DIA_C", 0)) == 1, "DIA_C completed exactly once")

func _test_continue_route(context: TestContext) -> void:
	var session := GameSession.new()
	context.check(GameRoot.route_for_continue(session) == "prologue", "Fresh profile continues into prologue")
	session.world_flags["prologue_completed"] = true
	context.check(GameRoot.route_for_continue(session) == "world", "Finished prologue continues into world")
	var combat := session.start_combat("moss_slime")
	combat.enemy.current_hp = 1
	combat.advance_ticks(combat.hero.definition.attack_startup_ticks + 1)
	context.check(GameRoot.route_for_continue(session) == "combat", "An unclaimed pending result routes to the combat screen before the world")
	DomainSuite.claim_pending(session)
	context.check(GameRoot.route_for_continue(session) == "world", "After the claim continue leads to the world again")
	session.awaiting_return = true
	context.check(GameRoot.route_for_continue(session) == "checkpoint", "Awaiting return routes to checkpoint first")

func _test_claim_idempotent(context: TestContext) -> void:
	var session := GameSession.new()
	var combat := session.start_combat("moss_slime")
	combat.enemy.current_hp = 1
	combat.advance_ticks(combat.hero.definition.attack_startup_ticks + 1)
	var items: int = session.inventory.items.size()
	var level: int = session.hero.level
	var echoes: int = session.echoes
	# Ошибочный повторный terminal event не должен дублировать выдачу.
	combat.finished.emit(true)
	context.check(session.inventory.items.size() == items, "Duplicate finished signal does not duplicate loot")
	context.check(session.hero.level == level, "Duplicate finished signal does not duplicate XP")
	context.check(session.echoes == echoes, "Duplicate finished signal does not duplicate the echo")

func _test_ui_text_coverage(context: TestContext) -> void:
	var session := GameSession.new()
	for item_id: String in session.item_definitions:
		var definition: ItemDefinition = session.item_definitions[item_id]
		context.check(UiText.RARITY_LABELS.has(definition.rarity_id), "%s rarity localized" % item_id)
		context.check(UiText.TYPE_LABELS.has(definition.type_id), "%s type localized" % item_id)
		if not definition.slot_id.is_empty():
			context.check(UiText.SLOT_LABELS.has(definition.slot_id), "%s slot localized" % item_id)
	# Аспекты из генератора добычи.
	for aspect_id: String in ["moss", "goblin"]:
		context.check(UiText.ASPECT_LABELS.has(aspect_id), "aspect %s localized" % aspect_id)


func _test_currency_format(context: TestContext) -> void:
	var compact_cases: Dictionary = {
		0: "0",
		999: "999",
		1000: "1K",
		999999: "999.9K",
		1000000: "1M",
		1000000000: "1B",
		1000000000000: "1T",
		9223372036854775807: "9223.3Q",
	}
	for value: int in compact_cases:
		context.check(UiText.currency_compact(value) == compact_cases[value], "Compact currency boundary %d: expected %s, got %s" % [value, compact_cases[value], UiText.currency_compact(value)])
	context.check(UiText.currency_exact(0) == "0 мед. астры", "Zero exact balance is explicit")
	context.check(UiText.currency_exact(999999) == "999 999 мед. астры", "Exact balance keeps all digits below one million")
	context.check(UiText.currency_exact(1000000) == "1 000 000 мед. астры", "Exact balance keeps all digits at one million")
	context.check(UiText.currency_exact(9223372036854775807) == "9 223 372 036 854 775 807 мед. астры", "The maximum supported int64 balance remains exactly readable")
	context.check(UiText.astra(2000) == "20 сер." and UiText.astra(2001) == "2 001 мед.", "The canonical 20-silver crystal uses one integer copper unit without ambiguous pricing")
