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
	results.append(_run_case("first_pass_preserves_canonical_ids_and_continue", _test_first_pass))
	results.append(_run_case("skip_sequence_finishes_with_postconditions_once", _test_skip))
	results.append(_run_case("lioren_gates_and_shop_files_validate_with_postconditions", _test_lioren_and_shop_data))
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
	session.checkpoints.apply_completion()
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

func _test_first_pass(context: TestContext) -> void:
	var session := GameSession.new()
	var runner := DialogueRunner.new()
	runner.configure(session)
	runner.first_pass_only = true
	runner.command_requested.connect(func(command: Dictionary) -> void: session.world_flags[command["key"]] = command["value"])
	context.check(runner.load_file("res://data/narrative/prologue.json") and runner.entries.size() == EXPECTED_IDS.size(), "First pass retains the canonical 44-cue source")
	context.check(runner.start() and runner.current_cue().get("id") == "DIA_INTRO_001", "First pass starts at the shortened opening")
	var visited: Array[String] = []
	var guard: int = 0
	while not runner.is_finished and guard < 300:
		runner.advance_ticks(DialogueRunner.TRANSITION_TICKS)
		var cue_id: String = String(runner.current_cue().get("id", ""))
		match runner.current_kind():
			"look": runner.look()
			"hold":
				runner.begin_hold()
				runner.advance_ticks(DialogueRunner.HOLD_TICKS)
			_:
				_tap_through(runner)
		if not cue_id.is_empty() and not visited.has(cue_id):
			visited.append(cue_id)
		guard += 1
	context.check(runner.is_finished and visited.size() == 15, "First pass reaches World through 15 selected cues")
	context.check(visited.has("DIA_INTRO_007") and visited.has("DIA_GODDESS_006") and visited.has("TITLE"), "First pass keeps the rescue, Yui outcome and exit")
	context.check(not visited.has("DIA_GODDESS_019") and not session.seen_cue_ids.has("DIA_GODDESS_019"), "Deferred system explanations are not marked as read")
	context.check(session.world_flags.get("prologue_completed") == true, "First pass executes the Title postcondition")
	var mid_session := GameSession.new()
	var mid := DialogueRunner.new()
	mid.configure(mid_session)
	mid.first_pass_only = true
	mid.load_file("res://data/narrative/prologue.json")
	mid.start()
	mid.tap()
	var continued_session := GameSession.new()
	continued_session.apply_state_dto(SaveService.new().capture(mid_session))
	var continued := DialogueRunner.new()
	continued.configure(continued_session)
	continued.first_pass_only = true
	continued.load_file("res://data/narrative/prologue.json")
	continued.start()
	context.check(mid.current_cue().get("id") == "TUT_STORY_002" and continued.current_cue().get("id") == "TUT_STORY_002", "Continue resumes after the last completed first-pass cue")
	var completed_session := GameSession.new()
	completed_session.apply_state_dto(SaveService.new().capture(session))
	context.check(completed_session.world_flags.get("prologue_completed") == true, "Completed first pass continues through the existing save DTO")

func _test_skip(context: TestContext) -> void:
	var session := GameSession.new()
	var command_counts: Dictionary = {}
	var runner := DialogueRunner.new()
	runner.configure(session)
	runner.command_requested.connect(func(command: Dictionary) -> void:
		session.world_flags[command["key"]] = command["value"]
		command_counts[command["key"]] = int(command_counts.get(command["key"], 0)) + 1
	)
	context.check(runner.load_file("res://data/narrative/prologue.json") and runner.start(), "Prologue ready for skip from the first cue")
	runner.skip_sequence()
	context.check(runner.is_finished, "Skip reaches the same terminal state as normal completion")
	context.check(runner.destination == "world", "Skip exits to gameplay, never to a montage")
	context.check(session.world_flags.get("prologue_completed") == true, "Skip applies the required story postconditions")
	context.check(int(command_counts.get("prologue_completed", 0)) == 1, "Whitelisted commands run exactly once")
	context.check(session.seen_cue_ids.is_empty(), "Skipped cues are not recorded as read")
	runner.skip_sequence()
	context.check(int(command_counts.get("prologue_completed", 0)) == 1 and runner.is_finished, "Second skip is a no-op")
	# Граница экрана пролога (mark_path_started): снимок «Первый след» переснимается
	# со story-флагами, иначе возврат откатывает prologue_completed и Continue
	# снова отправляет в катсцену.
	session.mark_path_started()
	var refreshed: Dictionary = session.checkpoints.first_trace_snapshot
	context.check(refreshed.get("profile", {}).get("world_flags", {}).get("prologue_completed") == true, "Path start refreshes the First Trace snapshot with story flags")
	# Пропуск из середины hold: тот же единственный переход и постусловия.
	var mid_session := GameSession.new()
	var mid := DialogueRunner.new()
	mid.configure(mid_session)
	mid.command_requested.connect(func(command: Dictionary) -> void: mid_session.world_flags[command["key"]] = command["value"])
	context.check(mid.load_file("res://data/narrative/prologue.json") and mid.start(), "Second runner starts for mid-hold skip")
	# Доходим до TUT_STORY_003 (hold): 0–1 line, 2 look, 3–6 line, 7 hold.
	for cue_number: int in range(7):
		mid.advance_ticks(DialogueRunner.TRANSITION_TICKS)
		if mid.current_kind() == "look":
			mid.look()
		else:
			_tap_through(mid)
	mid.advance_ticks(DialogueRunner.TRANSITION_TICKS)
	context.check(mid.current_kind() == "hold", "Fixture reaches the hold cue")
	mid.begin_hold()
	mid.advance_ticks(3)
	context.check(mid.holding, "Hold is in progress before skip")
	mid.skip_sequence()
	context.check(mid.is_finished and not mid.holding and mid.hold_ticks == 0, "Skip stops hold state and finishes")
	context.check(mid_session.world_flags.get("prologue_completed") == true, "Mid-hold skip keeps postconditions")
	context.check(not mid_session.seen_cue_ids.has("TUT_STORY_003") and not mid_session.seen_cue_ids.has("DIA_GODDESS_001") and not mid_session.seen_cue_ids.has("TITLE"), "Skipped cues are not recorded as read")
	context.check(mid_session.seen_cue_ids.size() == 7, "Only the seven actually played cues keep their seen flags")

func _tap_through(runner: DialogueRunner) -> void:
	# Реплика завершается проходом по страницам, а не одним tap.
	var index: int = runner.index
	for step: int in range(24):
		if runner.index != index or runner.is_finished:
			return
		runner.tap()

func _normalized(text: String) -> String:
	return " ".join(text.split(" ", false))

func _test_lioren_and_shop_data(context: TestContext) -> void:
	var files: Dictionary = {
		"res://data/narrative/lioren_gates.json": {"last_destination": "lioren_map", "flag": "lioren_shop_unlocked"},
		"res://data/narrative/shop_intro.json": {"last_destination": "shop", "flag": "shop_intro_done"},
		"res://data/narrative/shop_talk.json": {"last_destination": "shop", "flag": ""},
		"res://data/narrative/shop_purchase.json": {"last_destination": "shop", "flag": "shop_purchase_briefing_done"},
	}
	for path: String in files:
		var runner := DialogueRunner.new()
		context.check(runner.load_file(path), "Production JSON parses and validates: %s" % path)
		context.check(runner.entries.size() >= 3, "%s keeps a real scene, not a stub" % path)
		context.check(runner.entries.back().get("destination", "") == files[path]["last_destination"], "%s exits to its expected route" % path)
		var flag: String = files[path]["flag"]
		if not flag.is_empty():
			var commands: Array = runner.entries.back().get("commands", [])
			var has_flag_command: bool = commands.any(func(command: Variant) -> bool:
				return typeof(command) == TYPE_DICTIONARY and command.get("type", "") == "set_world_flag" and command.get("key", "") == flag and command.get("value") == true)
			context.check(has_flag_command, "%s records its story-line flag %s on the last cue" % [path, flag])
	var intro := DialogueRunner.new()
	intro.load_file("res://data/narrative/shop_intro.json")
	var appraisal_hidden: bool = true
	for cue: Dictionary in intro.entries:
		if String(cue.get("text", "")).to_lower().contains("сумрачн"):
			appraisal_hidden = false
	context.check(appraisal_hidden, "Pure twilight crystal appraisal stays hidden until the story item exists")
	# Полный проход ворот с постусловием, как у пролога.
	var session := GameSession.new()
	var gates := DialogueRunner.new()
	gates.configure(session)
	gates.command_requested.connect(func(command: Dictionary) -> void: session.world_flags[command["key"]] = command.get("value"))
	context.check(gates.load_file("res://data/narrative/lioren_gates.json") and gates.start(), "Gates scene starts from production data")
	var guard: int = 0
	while not gates.is_finished and guard < 100:
		gates.tap()
		guard += 1
	context.check(gates.is_finished and gates.destination == "lioren_map", "Gates reach the Lioren map within the bounded loop")
	context.check(session.world_flags.get(GameSession.WORLD_FLAG_LIOREN_SHOP_UNLOCKED) == true, "Gates open the shop access flag")
	session.world_flags.erase(GameSession.WORLD_FLAG_LIOREN_SHOP_UNLOCKED)
	gates.replay_seen_commands = true
	gates.start()
	context.check(gates.current_cue().get("id") == "DIA_CITY_006", "Reopening after a rollback restores the missing completion cue without replaying read lines")
	while not gates.is_finished:
		gates.tap()
	context.check(session.shop_access_unlocked(), "The restored cue can open the shop again after a rollback")
