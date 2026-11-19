extends RefCounted

const DomainSuite = preload("res://tests/domain_suite.gd")
const TestContext = DomainSuite.TestContext
const EXPECTED_IDS: Array[String] = [
	"DIA_INTRO_001", "DIA_INTRO_002", "TUT_STORY_002", "DIA_INTRO_003", "DIA_INTRO_004", "DIA_INTRO_005", "DIA_INTRO_006", "TUT_STORY_003", "DIA_INTRO_007", "DIA_INTRO_008", "DIA_INTRO_009",
	"DIA_GODDESS_001", "DIA_GODDESS_002", "DIA_GODDESS_003", "DIA_GODDESS_004", "DIA_GODDESS_005", "DIA_GODDESS_006", "DIA_GODDESS_007", "DIA_GODDESS_008", "DIA_GODDESS_009", "DIA_GODDESS_010", "DIA_GODDESS_011", "DIA_GODDESS_012", "DIA_GODDESS_013", "DIA_GODDESS_014", "DIA_GODDESS_015", "DIA_GODDESS_016", "DIA_GODDESS_017", "DIA_GODDESS_018", "DIA_GODDESS_019", "DIA_GODDESS_020", "DIA_GODDESS_021", "DIA_GODDESS_022", "DIA_GODDESS_023", "DIA_GODDESS_024", "DIA_GODDESS_025", "DIA_GODDESS_026", "DIA_GODDESS_027", "DIA_GODDESS_028", "DIA_GODDESS_029", "DIA_GODDESS_030", "DIA_GODDESS_031", "DIA_GODDESS_032", "TITLE",
]

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_run_case("prologue_data_ids_order_parts_and_references", _test_data))
	results.append(_run_case("dialogue_validation_rejects_invalid_graph_and_commands", _test_validation))
	results.append(_run_case("pagination_preserves_every_line_and_part", _test_pagination))
	results.append(_run_case("transition_blocks_repeated_tap", _test_transition))
	results.append(_run_case("look_requires_marked_interaction", _test_look))
	results.append(_run_case("hold_release_cancels_and_completion_fires_once", _test_hold))
	results.append(_run_case("once_seen_survives_save_and_checkpoint_restores_npc", _test_once_and_npc))
	results.append(_run_case("full_prologue_reaches_world_with_bounded_input", _test_full_prologue))
	return results

func _run_case(case_name: String, test: Callable) -> Dictionary:
	var context := TestContext.new()
	test.call(context)
	return {"name": case_name, "checks": context.checks}

func _runner(cues: Array[Dictionary], session: GameSession = null) -> DialogueRunner:
	var runner := DialogueRunner.new()
	runner.configure(session if session != null else GameSession.new())
	runner.entries = cues
	return runner

func _test_data(context: TestContext) -> void:
	var runner := DialogueRunner.new()
	context.check(runner.load_file("res://data/narrative/prologue.json"), "Production JSON parses and validates")
	var ids: Array[String] = []
	for cue: Dictionary in runner.entries:
		ids.append(cue["id"])
	context.check(ids == EXPECTED_IDS, "All 44 stable cue IDs match canonical order")
	context.check(runner.entries[29]["parts"].size() == 4, "DIA_GODDESS_019 has four visual parts")
	context.check(runner.entries.back()["destination"] == "world", "Title card exits to gameplay, never to montage")

func _test_validation(context: TestContext) -> void:
	var valid: Array[Dictionary] = [{"id": "DIA_TEST", "text": "ok", "destination": "world"}]
	context.check(DialogueRunner.validate_entries(valid), "Minimal linear data is valid")
	var duplicate: Array[Dictionary] = [{"id": "DIA_TEST", "text": "a"}, {"id": "DIA_TEST", "text": "b", "destination": "world"}]
	context.check(not DialogueRunner.validate_entries(duplicate), "Duplicate IDs are refused")
	var broken: Array[Dictionary] = [{"id": "DIA_TEST", "text": "a", "next": "DIA_MISSING"}]
	context.check(not DialogueRunner.validate_entries(broken), "Missing next reference is refused")
	var unknown_command: Array[Dictionary] = [{"id": "DIA_TEST", "text": "a", "destination": "world", "commands": [{"type": "quit_game", "key": "x", "value": true}]}]
	context.check(not DialogueRunner.validate_entries(unknown_command), "Command whitelist is enforced")
	var unknown_destination: Array[Dictionary] = [{"id": "DIA_TEST", "text": "a", "destination": "montage"}]
	context.check(not DialogueRunner.validate_entries(unknown_destination), "Destination whitelist excludes the preview montage loop")
	var unreachable: Array[Dictionary] = [{"id": "DIA_TEST", "text": "a", "destination": "world"}, {"id": "DIA_ORPHAN", "text": "b", "destination": "world"}]
	context.check(not DialogueRunner.validate_entries(unreachable), "Unreachable required cues are refused")

func _test_pagination(context: TestContext) -> void:
	var runner := DialogueRunner.new()
	runner.load_file("res://data/narrative/prologue.json")
	var paginated_lines: int = 0
	var preserved: bool = true
	for cue: Dictionary in runner.entries:
		var texts: Array[String] = [String(cue.get("text", ""))]
		for part: Dictionary in cue.get("parts", []):
			texts.append(part["text"])
		for text: String in texts:
			var pages: Array[String] = DialogueRunner.paginate(text, 40)
			paginated_lines += int(pages.size() > 1)
			if _normalized(" ".join(pages)) != _normalized(text):
				preserved = false
	context.check(preserved, "Pagination retains all words without duplication or loss")
	context.check(paginated_lines > 5, "Long canonical lines really produce multiple pages")

func _test_transition(context: TestContext) -> void:
	var runner := _runner([
		{"id": "DIA_TEST", "text": "one", "enter": "approach"},
		{"id": "DIA_NEXT", "text": "two", "destination": "world"},
	])
	runner.start()
	context.check(not runner.tap() and runner.index == 0, "Tap during enter transition is ignored")
	context.check(not runner.tap() and runner.index == 0, "Repeated tap cannot skip the cue")
	runner.advance_ticks(DialogueRunner.TRANSITION_TICKS)
	context.check(runner.tap() and runner.index == 1, "Tap works after the transition ends")

func _test_look(context: TestContext) -> void:
	var runner := _runner([
		{"id": "TUT_STORY_002", "kind": "look", "text": "look"},
		{"id": "DIA_NEXT", "text": "two", "destination": "world"},
	])
	runner.start()
	context.check(not runner.tap() and runner.index == 0, "Generic tap does not complete look")
	context.check(runner.look() and runner.index == 1, "Marked look interaction advances exactly once")

func _test_hold(context: TestContext) -> void:
	var runner := _runner([
		{"id": "TUT_STORY_003", "kind": "hold", "text": "hold"},
		{"id": "DIA_NEXT", "text": "two", "destination": "world"},
	])
	runner.start()
	context.check(not runner.tap() and runner.index == 0, "Tap does not complete hold")
	runner.begin_hold()
	runner.advance_ticks(DialogueRunner.HOLD_TICKS - 1)
	runner.release_hold()
	context.check(runner.index == 0 and runner.hold_ticks == 0 and not runner.holding, "Early release resets hold progress")
	runner.begin_hold()
	runner.advance_ticks(DialogueRunner.HOLD_TICKS)
	context.check(runner.index == 1 and not runner.holding, "Completed hold advances once and stops consuming ticks")
	var index_after: int = runner.index
	runner.advance_ticks(30)
	context.check(runner.index == index_after, "Ticks after hold completion do not repeat the action")

func _test_once_and_npc(context: TestContext) -> void:
	var session := GameSession.new()
	session.npc_flags["npc"] = "present"
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	session.npc_flags.erase("npc")
	session.awaiting_return = true
	session.checkpoints.restore()
	context.check(session.npc_flags.get("npc") == "present", "Checkpoint restores NPC state")
	var runner := _runner([{"id": "DIA_ONCE", "text": "once", "once": true, "destination": "world"}], session)
	runner.start()
	runner.tap()
	context.check(session.seen_cue_ids.has("DIA_ONCE") and runner.is_finished, "Once cue records its stable ID")
	var save := SaveService.new()
	var restored := GameSession.new()
	restored.apply_state_dto(save.capture(session))
	var repeated := _runner(runner.entries, restored)
	repeated.start()
	context.check(repeated.is_finished and repeated.destination == "world", "Seen Once cue does not repeat after save/load DTO restore")

func _test_full_prologue(context: TestContext) -> void:
	var session := GameSession.new()
	var runner := DialogueRunner.new()
	runner.configure(session)
	runner.command_requested.connect(func(command: Dictionary) -> void: session.world_flags[command["key"]] = command["value"])
	context.check(runner.load_file("res://data/narrative/prologue.json") and runner.start(), "Full prologue starts from production data")
	var steps: int = 0
	while not runner.is_finished and steps < 1000:
		steps += 1
		if runner.transition_ticks > 0:
			runner.advance_ticks(1)
		else:
			match runner.current_kind():
				"look":
					runner.look()
				"hold":
					runner.begin_hold()
					runner.advance_ticks(DialogueRunner.HOLD_TICKS)
				_:
					runner.tap()
	context.check(runner.is_finished and runner.destination == "world" and steps < 1000, "Every required cue reaches gameplay within the bounded loop")
	context.check(session.seen_cue_ids.size() == EXPECTED_IDS.size(), "Every cue records its Once flag exactly once")
	context.check(session.world_flags.get("prologue_completed") == true, "Title command reaches the session owner")

func _normalized(text: String) -> String:
	return " ".join(text.split(" ", false))
