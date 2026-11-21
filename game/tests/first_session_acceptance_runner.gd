extends SceneTree

const OUT := "res://../docs/reviews/first_session_iteration_2026_11_21"
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(360, 640), Vector2i(360, 800), Vector2i(390, 844), Vector2i(412, 915)]

var _checks: int = 0
var _failed: int = 0
var _actions: int = 0
var _save_path: String = ""
var _mode: String = "flow"
var _game: GameRoot
var _report: Dictionary = {"windows": [], "captures": [], "checks": []}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-path="):
			_save_path = argument.trim_prefix("--save-path=")
		elif argument.begins_with("--acceptance-mode="):
			_mode = argument.trim_prefix("--acceptance-mode=")
	if _save_path.is_empty():
		_save_path = "user://path_of_reborn_tests/first_session_%d.json" % Time.get_ticks_usec()
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(360, 640))
	await _frames(5)
	await _new_game_root()
	match _mode:
		"flow":
			await _flow()
		"continue":
			await _continue_flow()
		"checkpoint":
			await _checkpoint_flow()
		"movie":
			await _movie_flow()
		"active":
			await _active_flow()
		_:
			_check(false, "Unknown acceptance mode")
	_report["failed"] = _failed
	_report["checks_count"] = _checks
	var file := FileAccess.open(OUT + "/verification/" + _mode + "_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	print("FIRST_SESSION_ACCEPTANCE mode=%s checks=%d failed=%d" % [_mode, _checks, _failed])
	quit(1 if _failed > 0 else 0)

func _new_game_root() -> void:
	if is_instance_valid(_game):
		root.remove_child(_game)
		_game.free()
		await _frames(3)
	_game = load("res://scenes/game_root.tscn").instantiate()
	_game.save_path = _save_path
	root.add_child(_game)
	current_scene = _game
	await _frames(5)

func _flow() -> void:
	await _capture("01_title")
	var started_tick: int = _game.session.play_tick
	await _click(_game.router.current_screen.begin_button)
	_check(_game.router.current_screen.name == "Prologue", "Begin starts the prologue")
	await _capture("02_tokyo")
	var visited: Dictionary = {}
	var threshold_captured: bool = false
	var hold_captured: bool = false
	for step: int in range(300):
		var screen: Control = _game.router.current_screen
		if screen.name != "Prologue":
			break
		var runner: DialogueRunner = screen.runner
		visited[runner.current_cue().get("id", "")] = true
		if runner.current_shot() == "threshold" and not threshold_captured:
			threshold_captured = true
			await _capture("04_threshold")
		if runner.transition_ticks > 0:
			await _frames(1)
			continue
		match runner.current_kind():
			"look":
				await _drag(Vector2(90, 100), Vector2(30, 0))
			"hold":
				if not hold_captured:
					hold_captured = true
					await _capture("03_crosswalk_hold")
				await _hold(screen.hold_area, runner)
			_:
				await _click(screen.dialogue_panel)
	_check(_game.router.current_screen.name == "World", "First-pass prologue reaches World")
	_check(visited.size() == 15, "First pass visits the authored 15 cues")
	_report["prologue"] = {"actions": _actions - 1, "cues": visited.size(), "seconds_to_world": snappedf((_game.session.play_tick - started_tick) / 60.0, 0.01)}
	await _capture("05_first_trail")
	await _measure_windows("world")
	await _click(_game.router.current_screen.checkpoint_button)
	await _frames(16)
	await _capture("13_checkpoint")
	await _measure_windows("checkpoint")
	await _click(_game.router.current_screen.back_button)
	await _tap_world_progress()
	_check(_game.router.current_screen.name == "Combat", "A free-area tap starts the first encounter")
	var combat: Control = _game.router.current_screen
	_check(combat.resolver.auto_dodge_enabled and not combat.dodge_button.visible, "Clean profile keeps full auto as the default")
	await _wait_intro(combat)
	await _capture("06_slime")
	_check(not combat.format_label.get_global_rect().intersects(combat.pause_button.get_global_rect()), "Mode HUD and Pause do not intersect at 360x640")
	await _wait_result(combat)
	await _capture("07_first_loot")
	_check(_game.session.inventory.items.size() == 1 and not _has_item("echo_crystal") and _game.session.has_pending_battle_result(), "Victory waits for claim without granting the crystal")
	var result_id: String = String(_game.session.pending_battle_result.get("result_id", ""))
	await _frames(240)
	_check(combat.result_panel.visible and _game.session.has_pending_battle_result(), "Result remains open after four seconds")
	await _claim_result(combat)
	_check(_game.router.current_screen.name == "World" and not _game.session.has_pending_battle_result(), "One atomic claim returns to World")
	var claimed: Dictionary = _game.session.last_settlement.duplicate(true)
	_check(String(claimed.get("result_id", "")) == result_id, "Claim settles the displayed result")
	_check(not _has_item("training_sword"), "First route clear grants crystals, not the story sword")
	await _capture("08_trail_after_loot")
	_check(_game.router.current_screen.upgrade_button.visible, "World exposes the pending upgrade")
	await _click(_game.router.current_screen.upgrade_button)
	await _capture("09_bag")
	var inventory: Control = _game.router.current_screen
	_check(root.gui_get_focus_owner() == inventory.strength_upgrade, "First upgrade receives focus")
	_report["first_upgrade"] = {"actions": _actions, "seconds_from_new_game": snappedf((_game.session.play_tick - started_tick) / 60.0, 0.01), "strength_before": _game.session.hero.strength, "hp_before": _game.session.hero.max_hp}
	await _click(inventory.strength_upgrade)
	_check(_game.session.hero.strength == 4 and _game.session.hero.pending_upgrade_choices == 0, "Strength choice applies once and updates immediately")
	_report["first_upgrade"]["strength_after"] = _game.session.hero.strength
	await _measure_windows("inventory")
	await _click(inventory.back_button)
	await _tap_world_progress()
	await _advance_merchant_to_combat()
	combat = _game.router.current_screen
	_check(combat.name == "Combat" and not _has_item("training_sword"), "Daijiro's introduction starts the story fight without an early sword")
	await _wait_result(combat)
	await _capture("10_goblin_loot")
	await _claim_result(combat)
	_check(_game.router.current_screen.name == "Merchant" and not _has_item("training_sword"), "The story win returns to Daijiro before granting the sword")
	await _advance_merchant_to_gift()
	var merchant: Control = _game.router.current_screen
	_check(merchant.gift_layer.visible and not _has_item("training_sword"), "Gratitude opens the separate gift card before its claim")
	await _click(merchant.equip_button)
	_check(_game.router.current_screen.name == "World" and _has_item("training_sword"), "Daijiro grants exactly one sword after the completed introduction")
	await _capture("11_end_of_trail")
	_check("К испытанию" in _game.router.current_screen.main_action_button.text, "Scout completion promotes the trial")
	await _click(_game.router.current_screen.repeats_button)
	await _capture("12_encounter_sheet")
	_check(_game.router.current_screen.sheet_rows.get_child_count() >= 3, "Repeats remain available as secondary access")
	await _click(_game.router.current_screen.sheet_close)
	await _tap_world_progress()
	_check(_game.session.current_enemy_id == GameSession.TRIAL_ENEMY_ID and _game.router.current_screen.name == "Combat", "A free-area tap directly starts the trial")
	_report["final_actions"] = _actions

func _continue_flow() -> void:
	await _click(_game.router.current_screen.begin_button)
	for step: int in range(40):
		var screen: Control = _game.router.current_screen
		if screen.runner.index > 0:
			break
		await _click(screen.dialogue_panel)
		await _frames(12)
	var seen: Array = _game.session.seen_cue_ids.keys()
	_check(not seen.is_empty(), "Continue fixture completes at least one cue")
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	var restored: Control = _game.router.current_screen
	_check(restored.name == "Prologue", "Continue returns to unfinished prologue")
	_check(not seen.has(restored.runner.current_cue().get("id", "")), "Continue starts at the first unseen cue")
	await _click(restored.skip_button)
	_check(_game.router.current_screen.name == "World" and _game.session.world_flags.get("prologue_skipped", false), "Skip still reaches World and records its outcome")
	await _new_game_root()
	await _click(_game.router.current_screen.continue_button)
	_check(_game.router.current_screen.name == "World", "Continue after completion returns to World")

func _checkpoint_flow() -> void:
	await _click(_game.router.current_screen.begin_button)
	await _click(_game.router.current_screen.skip_button)
	await _click(_game.router.current_screen.checkpoint_button)
	var blocker: String = ProjectSettings.globalize_path(_save_path + ".tmp")
	_check(DirAccess.make_dir_recursive_absolute(blocker) == OK, "Creation failure blocker is ready")
	await _click(_game.router.current_screen.start_button)
	for step: int in range(420):
		if _game.router.current_screen.error_box.visible:
			break
		await _frames(1)
	var screen: Control = _game.router.current_screen
	_check(screen.error_box.visible and screen._commit_in_flight == false, "Creation failure exposes retry")
	await _capture("14_checkpoint_failed")
	await _click(screen.back_button)
	DirAccess.remove_absolute(blocker)
	await _click(_game.router.current_screen.checkpoint_button)
	for step: int in range(30):
		if _game.session.checkpoints.manual_snapshots.size() == 1:
			break
		await _frames(1)
	screen = _game.router.current_screen
	_check(_game.session.checkpoints.manual_snapshots.size() == 1 and not screen._commit_in_flight, "Reopening commits exactly one pending point")
	_check(_disk_points() == 1, "Reopened creation reaches the disk once")
	await _capture("15_checkpoint_reopened")
	_check(DirAccess.make_dir_recursive_absolute(blocker) == OK, "Deletion failure blocker is ready")
	var row: HBoxContainer = screen.points_list.get_child(0)
	await _click(row.get_child(row.get_child_count() - 1))
	var dialog: ConfirmDialog = null
	for child: Node in screen.get_children():
		if child is ConfirmDialog:
			dialog = child
	_check(dialog != null, "Delete opens the real confirmation dialog")
	if dialog != null:
		await _click(dialog._confirm)
	_check(screen.error_box.visible and _game.session.checkpoints.manual_snapshots.size() == 1, "Failed deletion preserves the point")
	_check(root.gui_get_focus_owner() == screen.error_retry, "Delete failure focuses Retry after modal closes")
	_check(_disk_points() == 1, "Failed deletion preserves the disk point")
	DirAccess.remove_absolute(blocker)
	await _click(screen.error_retry)
	_check(_game.session.checkpoints.manual_snapshots.is_empty() and _disk_points() == 0, "Delete retry removes the point once")
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	_check(int(disk.get("schema_version", 0)) == SaveService.CURRENT_VERSION, "Checkpoint flow preserves the current save schema")

func _active_flow() -> void:
	await _click(_game.router.current_screen.begin_button)
	await _click(_game.router.current_screen.skip_button)
	await _frames(30)
	await _tap_world_progress()
	var combat: Control = _game.router.current_screen
	_check(combat.name == "Combat", "Active fixture enters its first combat")
	if combat.name != "Combat":
		return
	await _wait_intro(combat)
	await _click(combat.pause_button)
	_check(combat.format_switch.text.begins_with("Включить ручной бой"), "Pause names the next-click action")
	await _click(combat.format_switch)
	_check(combat.resolver.combat_format == GameSession.COMBAT_FORMAT_AUTO and _game.session.combat_format == GameSession.COMBAT_FORMAT_ACTIVE, "Pause changes only the next-battle preference")
	await _click(combat.resume_button)
	await _wait_result(combat)
	await _claim_result(combat)
	await _tap_world_progress()
	await _advance_merchant_to_combat()
	combat = _game.router.current_screen
	await _wait_intro(combat)
	_check(combat.attack_button.visible and combat.dodge_button.visible and combat.format_label.text == "Ручной", "Next encounter enables intentional manual attack and dodge")
	await _click(combat.attack_button)
	_check(combat.resolver.hero_attack_cooldown > 0, "The touch attack button drives the real resolver")
	_check(not combat.format_label.get_global_rect().intersects(combat.pause_button.get_global_rect()), "Active mode HUD does not overlap Pause")
	await _capture("17_active_next")

func _movie_flow() -> void:
	await _click(_game.router.current_screen.begin_button)
	await _click(_game.router.current_screen.skip_button)
	await _frames(90)
	await _tap_world_progress()
	var combat: Control = _game.router.current_screen
	await _wait_result(combat, 1200)
	await _frames(90)
	await _claim_result(combat)
	await _frames(90)
	_check(_game.router.current_screen.name == "World", "Movie route completes a normal-speed encounter")

func _tap_world_progress() -> void:
	var screen: Control = _game.router.current_screen
	var point: Vector2 = Vector2(screen.size.x * 0.5, screen.size.y * 0.42)
	await _tap(point)


func _tap(point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	root.push_input(press, true)
	_actions += 1
	await _frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.pressed = false
	root.push_input(release, true)
	await _frames(5)


func _claim_result(screen: Control) -> void:
	for step: int in range(8):
		if not _game.session.has_pending_battle_result():
			break
		await _click(screen.result_panel.card)
	_check(not _game.session.has_pending_battle_result(), "Every visible reward card participates in one atomic claim")


func _advance_merchant_to_combat() -> void:
	for step: int in range(16):
		var screen: Control = _game.router.current_screen
		if screen.name != "Merchant":
			break
		await _click(screen.next_button)
	_check(_game.router.current_screen.name == "Combat", "Daijiro's intervention leads to the story scout encounter")


func _advance_merchant_to_gift() -> void:
	for step: int in range(16):
		var screen: Control = _game.router.current_screen
		if screen.name != "Merchant" or screen.gift_layer.visible:
			break
		await _click(screen.next_button)


func _wait_intro(screen: Control) -> void:
	for step: int in range(120):
		if not screen._intro_active:
			return
		await _frames(1)
	_check(false, "Combat intro finishes")

func _wait_result(screen: Control, limit: int = 900) -> void:
	for step: int in range(limit):
		if screen._result_visible:
			await _frames(3)
			return
		await _frames(1)
	_check(false, "Combat reaches its visible result")

func _measure_windows(label: String) -> void:
	for window_size: Vector2i in WINDOW_SIZES:
		DisplayServer.window_set_size(window_size)
		await _frames(8)
		var screen: Control = _game.router.current_screen
		var transform: Transform2D = root.get_screen_transform()
		var gameplay_rect := Rect2(transform * screen.global_position, screen.size * transform.get_scale())
		var measurement: Dictionary = {
			"screen_state": label,
			"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
			"image": [root.get_texture().get_width(), root.get_texture().get_height()],
			"logical_viewport": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
			"screen_host": [screen.size.x, screen.size.y],
			"scale": [transform.get_scale().x, transform.get_scale().y],
			"offset": [transform.origin.x, transform.origin.y],
			"gameplay_pixels": [gameplay_rect.size.x, gameplay_rect.size.y],
			"gameplay_area_ratio": snappedf(gameplay_rect.get_area() / float(window_size.x * window_size.y), 0.001),
			"safe_area": str(DisplayServer.get_display_safe_area()),
			"safe_margins": [_game.get_node("SafeArea").get_theme_constant("margin_left"), _game.get_node("SafeArea").get_theme_constant("margin_top"), _game.get_node("SafeArea").get_theme_constant("margin_right"), _game.get_node("SafeArea").get_theme_constant("margin_bottom")],
		}
		_report["windows"].append(measurement)
		_check(screen.size.y >= 320.0 and Rect2(Vector2.ZERO, Vector2(window_size)).encloses(gameplay_rect), "%s uses the real %s window within integer-scale bounds" % [label, window_size])
		_check(_visible_bounds_valid(screen), "%s has no visible out-of-window controls at %s" % [label, window_size])
		if label == "world" and window_size == Vector2i(390, 844):
			await _capture("16_tall_view")
	DisplayServer.window_set_size(Vector2i(360, 640))
	await _frames(8)

func _visible_bounds_valid(screen: Control) -> bool:
	for node: Node in screen.find_children("*", "Control", true, false):
		var control: Control = node
		if not control.is_visible_in_tree() or not (control is Button or control is Label):
			continue
		if not screen.get_global_rect().grow(0.5).encloses(control.get_global_rect()):
			return false
	return true

func _has_item(item_id: String) -> bool:
	for item: ItemInstance in _game.session.inventory.items:
		if item.definition_id == item_id:
			return true
	return false

func _disk_points() -> int:
	var restored := GameSession.new()
	if not SaveService.new().load_into(restored, _save_path):
		return -1
	return restored.checkpoints.manual_snapshots.size()

func _click(control: Control) -> void:
	await _frames(2)
	var point: Vector2 = control.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	root.push_input(press, true)
	_actions += 1
	await _frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.pressed = false
	root.push_input(release, true)
	await _frames(3)

func _drag(point: Vector2, relative: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	root.push_input(press, true)
	_actions += 1
	await _frames(2)
	var motion := InputEventMouseMotion.new()
	motion.position = point + relative
	motion.relative = relative
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await _frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point + relative
	release.pressed = false
	root.push_input(release, true)
	await _frames(3)

func _hold(control: Control, runner: DialogueRunner) -> void:
	var cue_index: int = runner.index
	var point: Vector2 = control.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	root.push_input(press, true)
	_actions += 1
	for step: int in range(70):
		if runner.index != cue_index or runner.is_finished:
			break
		await _frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.pressed = false
	root.push_input(release, true)
	await _frames(3)

func _capture(label: String) -> void:
	await _frames(4)
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUT + "/" + label + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = image.save_png(path)
	_report["captures"].append({"label": label, "size": [image.get_width(), image.get_height()], "error": error})
	_check(error == OK, "Capture %s" % label)

func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame

func _check(ok: bool, message: String) -> void:
	_checks += 1
	_report["checks"].append({"ok": ok, "message": message})
	if not ok:
		_failed += 1
		printerr("FAIL ", message)
