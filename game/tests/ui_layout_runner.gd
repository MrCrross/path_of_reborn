extends SceneTree

## GUI contracts in a real scene tree, with no SaveService or user-profile writes.
var _failed: int = 0
var _checks: int = 0
var _host: Control

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL ", message)

func _settle() -> void:
	for frame: int in range(4):
		await process_frame

func _screen(id: String, session: GameSession) -> Control:
	var screen: Control = load(SceneRouter.SCENES[id]).instantiate()
	if screen.has_method("configure"):
		screen.configure(session)
	_host.add_child(screen)
	await _settle()
	return screen

func _in_scroll(control: Control) -> bool:
	var parent: Node = control.get_parent()
	while parent != null and parent != _host:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false

func _bounds(screen: Control) -> void:
	var bounds := Rect2(Vector2.ZERO, _host.size)
	for node: Node in screen.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree() or _in_scroll(control):
			continue
		if control is Button or control is Label or control is ScrollContainer:
			_check(bounds.grow(0.5).encloses(control.get_global_rect()), "%s %s outside %s: %s" % [screen.name, screen.get_path_to(control), bounds, control.get_global_rect()])

func _run() -> void:
	_host = Control.new()
	_host.theme = AppTheme.build()
	root.add_child(_host)
	current_scene = _host
	for viewport_size: Vector2i in [Vector2i(180, 320), Vector2i(180, 400), Vector2i(195, 422), Vector2i(206, 458)]:
		root.size = viewport_size
		_host.size = Vector2(viewport_size)
		for id: String in SceneRouter.SCENES:
			var session := GameSession.new()
			if id == "combat":
				session.select_encounter("moss_slime")
			if id == "inventory":
				for item: ItemDefinition in session.item_definitions.values():
					session.inventory.add(item, 2)
			var screen: Control = await _screen(id, session)
			_bounds(screen)
			if id == "prologue":
				screen.runner.advance_ticks(60)
				var panel_box: StyleBox = screen.dialogue_panel.get_theme_stylebox("panel")
				_check(panel_box is StyleBoxFlat and panel_box.get_border_width_min() == 1, "Dialogue panel in Tokyo uses one thin shared outline")
				_check(screen.story_text.is_visible_in_tree() and screen.story_text.get_parent() == screen.dialogue_panel.get_node("Margin/Column"), "Dialogue text uses one shared panel without a nested underlay")
				_check(screen.page_cue.get_parent() == screen.dialogue_panel.get_node("Margin/Column/BottomRow"), "Dialogue continuation sits beside the reply inside the same panel")
				var skip: Button = screen.skip_button
				var skip_frame: StyleBoxFlat = skip.get_theme_stylebox("normal")
				_check(
					skip.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER
					and skip.size == Vector2(24, 24)
					and skip_frame.expand_margin_left == -3.0
					and skip_frame.expand_margin_right == -3.0,
					"Skip centers its icon and draws a smaller frame inside the touch target"
				)
				var previous_page: int = screen.runner.page_index
				var previous_cue: int = screen.runner.index
				var touch := InputEventScreenTouch.new()
				touch.position = screen.dialogue_panel.get_global_rect().get_center()
				touch.pressed = true
				root.push_input(touch, true)
				touch = touch.duplicate()
				touch.pressed = false
				root.push_input(touch, true)
				_check(
					(screen.runner.index == previous_cue and screen.runner.page_index == previous_page + 1) or (screen.runner.index > previous_cue and screen.runner.page_index == 0),
					"Touch inside dialogue panel advances one page or completes a one-page cue"
				)
				var skip_navigations: Dictionary = {"count": 0}
				screen.navigate_requested.connect(
					func(_destination: String) -> void: skip_navigations["count"] = int(skip_navigations["count"]) + 1
				)
				var seen_before_skip: Array = session.seen_cue_ids.keys()
				screen._on_skip_pressed()
				screen._on_skip_pressed()
				_check(int(skip_navigations["count"]) == 1, "Skip navigates exactly once on double tap")
				_check(
					session.world_flags.get("prologue_completed") == true and session.world_flags.get("prologue_skipped") == true,
					"Skip records completion and skipped outcome"
				)
				_check(session.seen_cue_ids.keys() == seen_before_skip, "GUI skip adds no seen flags for unplayed cues")
			if id != "prologue" and id != "combat":
				_check(root.gui_get_focus_owner() != null, "%s has initial keyboard focus" % id)
			if id == "characters":
				await _test_character_catalog(screen, session)
			if id == "inventory":
				var item_id: String = session.inventory.filter("weapon")[0].instance_id
				screen._on_item_pressed(item_id)
				await _settle()
				_bounds(screen)
				_check(root.gui_get_focus_owner() == screen.detail_close, "Item sheet owns focus")
				screen._on_equip_action_pressed()
				await _settle()
				_check(screen.items_list.get_child(0).focus_mode == Control.FOCUS_NONE, "Rebuilt grid stays outside modal keyboard focus")
				var comparison: String = screen.detail_compare.text
				_check("Параметры предмета" in comparison and not session.inventory.is_equipped(item_id), "Unequipped item preview uses real totals without double modifiers")
				_check(screen.details._comparison_box.get_child_count() > 1, "Item details show actual bonuses as separate rows")
				screen.handle_back()
				_check(not screen.details_layer.visible, "Back closes item sheet before navigation")
				var modal: ConfirmDialog = ConfirmDialog.open(screen, "Удалить?", "Проверка", "Удалить", "Отмена", true)
				await _settle()
				_check(screen.back_button.focus_mode == Control.FOCUS_NONE, "Modal excludes underlying controls from focus")
				modal._on_cancel_pressed()
				await _settle()
				_check(screen.back_button.focus_mode == Control.FOCUS_ALL, "Cancelling restores underlying focus modes")
			if id == "world":
				_check(screen.find_child("EncounterCard", true, false) == null, "World has no encounter card")
				_check(screen.settings_button.text.is_empty() and screen.settings_button.icon.resource_path.ends_with("settings_gear_steel_icon.png"), "World settings uses the illustrated gear")
				_check(screen.settings_button.get_theme_stylebox("normal") is StyleBoxEmpty and screen.balance_button.get_theme_stylebox("normal") is StyleBoxEmpty, "World HUD buttons have no background")
				_check(
					screen.characters_button.icon.resource_path == "res://art/ui/icons/characters_icon.png",
					"World character tab uses the section icon"
				)
				_check("Следующая встреча" in screen.main_action_button.text, "World CTA names the free-area tap action")
				_check(screen.main_action_button.pressed.get_connections().size() > 0, "World CTA is wired to its handler")
				_check(
					screen.hero_sprite.texture != null and screen.hero_sprite.texture.get_width() == 974,
					"World hero uses the source-resolution still"
				)
				var hero_solid: float = screen.hero_sprite.size.y * ArtMap.SOURCE_STILLS["haruto_exiled"]["solid_height_px"] / 1360.0
				_check(absf(hero_solid - SceneStaging.HERO_SOLID_HEIGHT) < 0.5, "World hero solid height matches the combat contract")
				_check(not screen.hero_health.is_visible_in_tree(), "Hero HP hidden at full health on path")
				var feet_y: float = SceneStaging.floor_y(screen.size.y)
				_check(
					screen.equipment_strip.get_global_rect().position.y >= feet_y - 1.0,
					"World rail stays below the feet line: rail=%s feet=%s" % [screen.equipment_strip.get_global_rect(), feet_y]
				)
				_check(not screen._inventory_badge.visible, "Inventory badge hidden without upgrades or new loot")
				session.hero.gain_xp(200)
				screen._refresh()
				_check(screen._inventory_badge.visible, "Inventory badge marks an available upgrade")
				_check(screen.upgrade_button.visible and "Выбрать улучшение" in screen.upgrade_button.text, "World offers an explicit path to the first upgrade")
				session.currency = 9223372036854775807
				session.hero.take_damage(2)
				screen._refresh()
				await _settle()
				_check(is_equal_approx(screen.location_label.get_global_rect().get_center().x, screen.size.x * 0.5), "World location stays centered with maximum balance")
				_check(not screen.location_label.get_global_rect().intersects(screen.balance_button.get_global_rect()), "World balance fits beside the location")
				_check(screen.equipment_strip.get_global_rect().position.y > feet_y, "World equipment stays below the actor with upgrade and heal hint visible")
				session.hero.pending_upgrade_choices = 0
				session.currency = 0
				screen._layout_scene()
				_check(screen.hero_health.is_visible_in_tree(), "Hero HP returns after damage")
				_check(screen.locked_label.visible and "восстановится" in screen.locked_label.text, "Damaged World state explains full healing before the next encounter")
				_check(screen.hero_health.find_child("Fill", true, false).size.x > 0, "Damaged HP bar keeps a visible remainder")
				session.hero.take_damage(999)
				screen._refresh()
				_check(screen.hero_health.find_child("Fill", true, false).size.x == 0, "Zero HP renders an empty bar, not a 1px ghost")
				_bounds(screen)
				session.hero.current_hp = session.hero.max_hp
				session.route_state["next_index"] = 1
				screen._refresh()
				await _settle()
				_check(screen.repeats_button.visible, "Repeat encounters stay available via the sheet entry")
				var nav_rail: Rect2 = screen.inventory_button.get_parent().get_global_rect()
				_check(
					nav_rail.encloses(screen.repeats_button.get_global_rect()) and not screen.repeats_button.get_global_rect().intersects(screen.equipment_strip.get_global_rect()),
					"Repeat entry stays inside the ordered rail without covering equipment"
				)
				var navigations: Dictionary = {"count": 0}
				screen.navigate_requested.connect(
					func(_destination: String) -> void: navigations["count"] = int(navigations["count"]) + 1
				)
				session.route_state["next_index"] = 0
				screen._refresh()
				screen._on_main_action_pressed()
				screen._on_main_action_pressed()
				_check(int(navigations["count"]) == 1, "Double tap starts exactly one encounter")
				_check(screen.main_action_button.disabled, "Main action locks after starting the encounter")
				# После разведчика основной CTA ведёт прямо на испытание; повторы вторичны.
				var done_session := GameSession.new()
				var done_screen: Control = await _screen("world", done_session)
				done_session.route_state["next_index"] = done_session.route_nodes().size()
				done_session.route_state["completed"] = true
				done_screen._refresh()
				_check("К испытанию" in done_screen.main_action_button.text, "Completed route promotes the next trial challenge")
				_check(done_screen.repeats_button.visible and done_screen.repeats_button.icon != null and "Повторы" in done_screen.repeats_button.tooltip_text, "Completed route keeps repeats as secondary access")
				var sheet_navigations: Dictionary = {"count": 0}
				done_screen.navigate_requested.connect(
					func(_destination: String) -> void: sheet_navigations["count"] = int(sheet_navigations["count"]) + 1
				)
				done_screen._on_main_action_pressed()
				_check(done_session.current_enemy_id == GameSession.TRIAL_ENEMY_ID and int(sheet_navigations["count"]) == 1, "Main action directly starts the trial")
				done_screen._navigating = false
				done_session.trial_echo_claimed = true
				done_screen._refresh()
				_check("Выбор встречи" in done_screen.main_action_button.text, "Claimed trial restores the general encounter choice")
				done_screen._on_main_action_pressed()
				_check(done_screen._sheet_open, "General choice opens the encounter sheet")
				var sheet_buttons: Array = done_screen.sheet_rows.get_children()
				_check(sheet_buttons.size() >= 2, "Sheet offers repeats plus the voluntary trial")
				_check(
					sheet_buttons[done_screen.sheet_rows.get_child_count() - 1] is Button and "Испытание" in (sheet_buttons[sheet_buttons.size() - 1] as Button).text,
					"Trial row is labeled as a voluntary challenge"
				)
				(sheet_buttons[0] as Button).pressed.emit()
				_check(int(sheet_navigations["count"]) == 2, "Sheet selection starts exactly one additional encounter")
				_check(not done_screen._sheet_open, "Sheet closes after selection")
				_host.remove_child(done_screen)
				done_screen.free()
			if id == "combat":
				screen.claim_requested.connect(func(result_id: String) -> void:
					if session.claim_battle_result(result_id):
						screen.navigate_requested.emit("world"))
				_check(screen.find_child("EnemyBar", true, false) == null, "Corner enemy HUD removed")
				_check(screen.find_child("HeroBar", true, false) == null, "Corner hero HP card removed")
				_check(screen.resolver.tick_count == 0, "Resolver does not tick during intro")
				_check(session.combat_format == GameSession.COMBAT_FORMAT_AUTO, "Full-auto is the default combat format")
				_check(screen.claim_button.pressed.get_connections().size() > 0, "The explicit claim button is wired")
				_check(not screen.dodge_button.is_visible_in_tree(), "Full-auto format hides the manual dodge button")
				_check(screen.format_label.is_visible_in_tree(), "Combat names the active combat format")
				screen._on_press_began()
				screen._on_press_ended()
				_check(
					screen.resolver.tick_count == 0 and screen.resolver.dodge_cooldown == 0,
					"Combat input ignored during intro"
				)
				screen._finish_intro()
				await _settle()
				_check(
					root.gui_get_focus_owner() != null and root.gui_get_focus_owner() != screen.dodge_button,
					"No hidden dodge focus in the full-auto format"
				)
				_check(screen.hero_health.is_visible_in_tree() and screen.enemy_health.is_visible_in_tree(), "HP displays shown over actors")
				var hero_head: Vector2 = ArtMap.HERO_EXILED["idle"]["head"]
				var enemy_head: Vector2 = ArtMap.ENEMY_SHEETS["moss_slime"]["idle"]["head"]
				_check(
					screen.hero_health.get_global_rect().end.y <= screen.hero_sprite.global_position.y + hero_head.y + 1.0,
					"Hero HP sits above hero head"
				)
				_check(
					screen.enemy_health.get_global_rect().end.y <= screen.enemy_sprite.global_position.y + enemy_head.y + 1.0,
					"Enemy HP sits above enemy head"
				)
				var pulse: Tween = screen.arena_presenter._telegraph_pulse
				for repeat: int in range(20):
					screen._refresh()
				_check(screen.arena_presenter._telegraph_pulse == pulse, "Repeated refresh keeps one telegraph tween")
				_check(screen.dodge_button.text.is_empty() and screen.dodge_button.icon != null, "Dodge uses a real, locally loaded icon")
				screen._spawn_damage_number("moss_slime", 3)
				await _settle()
				var damage: Label = screen.arena.get_child(screen.arena.get_child_count() - 1)
				_check(damage.position.x > screen.size.x * 0.5, "Damage stays over enemy instead of being repositioned by a Container")
				# Пауза: resolver и клипы стоят, возврат не догоняет упущенное.
				var ticks_at_pause: int = screen.resolver.tick_count
				screen._set_pause(true)
				for pause_frame: int in range(8):
					await process_frame
				_bounds(screen)
				_check(not screen.equipment_strip.is_visible_in_tree(), "Pause hides the combat equipment rail")
				_check(root.gui_get_focus_owner() == screen.resume_button, "Pause focuses Resume")
				for button: Button in [screen.resume_button, screen.format_switch, screen.speed_switch, screen.forfeit_button]:
					_check(button.size.y == 24.0, "Pause action %s keeps its compact touch height" % button.name)
				_check(screen.resolver.tick_count == ticks_at_pause, "Pause freezes the resolver")
				_check(not screen.hero_sprite.is_playing(), "Pause freezes the hero clip")
				screen._set_pause(false)
				_check(screen.equipment_strip.is_visible_in_tree() and root.gui_get_focus_owner() == screen.pause_button, "Resume restores the auto HUD and Pause focus")
				_check(screen.hero_sprite.is_playing(), "Resume continues the hero clip from the same frame")
				# Терминальная последовательность: домен один раз создаёт pending,
				# ничего не выдаёт и не уводит со сцены — чтение без таймера.
				var items_before: int = session.inventory.items.size()
				var combat_navigations: Dictionary = {"count": 0}
				screen.navigate_requested.connect(
					func(_destination: String) -> void: combat_navigations["count"] = int(combat_navigations["count"]) + 1
				)
				screen._on_press_began()
				while not screen.resolver.is_finished and screen.resolver.tick_count < 3000:
					screen.resolver.advance_ticks(30)
				_check(screen.resolver.is_finished and screen.resolver.won, "Auto-attack reaches victory in the layout runner")
				_check(screen.victory_label.is_visible_in_tree(), "Victory label shows after the terminal event")
				_check(not screen.result_panel.is_visible_in_tree(), "Victory reaction reads before the reward panel")
				await create_timer(screen.VICTORY_REACTION_SECONDS + 0.1).timeout
				_check(not screen._pointer_down and screen._pointer_candidate.is_empty(), "The pre-victory press is invalidated when the result appears")
				screen._on_press_ended()
				_check(screen.result_panel.is_visible_in_tree(), "Result panel shows the pending reward after the reaction")
				_check(screen.result_panel.get_global_rect().position.y >= 80.0 and is_equal_approx(screen.result_panel.get_global_rect().end.y, screen.size.y - 2.0), "Reward cards stay bottom-anchored at the lower edge")
				_check(screen.result_panel.size.x >= 120.0, "Result panel spans the reward width")
				_check(not session.pending_battle_result.is_empty(), "Terminal win creates exactly one pending result")
				_check(session.last_settlement.is_empty(), "Settlement stays unapplied until the claim")
				_check(session.inventory.items.size() == items_before, "Inventory is untouched before the claim")
				_check(int(combat_navigations["count"]) == 0, "Releasing the old finger does not claim or navigate")
				for wait_frame: int in range(30):
					await process_frame
				_check(int(combat_navigations["count"]) == 0, "Waiting on the result screen collects nothing")
				_check(not session.pending_battle_result.is_empty(), "Pending reward survives reading time")
				# Предмет: tap открывает детали, press/release и закрытие не собирают добычу.
				var pending_items: Array = session.pending_battle_result.get("items", [])
				if not pending_items.is_empty():
					var first_item: Dictionary = pending_items[0]
					screen._open_details(String(first_item.get("item_id", "")), String(first_item.get("aspect_id", "")))
					_check(screen.details_layer.is_visible_in_tree(), "Item tap opens the details sheet")
					screen._on_press_began()
					screen._on_press_ended()
					_check(int(combat_navigations["count"]) == 0 and not session.pending_battle_result.is_empty(), "Input inside details does not claim")
					screen._close_details()
					_check(int(combat_navigations["count"]) == 0 and not session.pending_battle_result.is_empty(), "Closing details does not claim")
				# Явное действие текущей карточки сохраняет выбор и проводит один claim.
				screen.result_panel.store_button.pressed.emit()
				_check(int(combat_navigations["count"]) == 1, "One card action claims and navigates exactly once")
				_check(session.pending_battle_result.is_empty(), "Claim closes the pending result")
				_check(session.inventory.items.size() > items_before, "Claim adds the loot to the inventory")
				_check(not session.last_settlement.is_empty(), "Claim records the settlement on the session")
			if id == "checkpoint":
				var checkpoint_back: Rect2 = screen.back_button.get_global_rect()
				var checkpoint_help: Rect2 = screen.get_node("%HelpButton").get_global_rect()
				var checkpoint_heading: Label = screen.contract_text
				_check(
					checkpoint_back.position.y == checkpoint_help.position.y
					and checkpoint_back.end.x <= checkpoint_heading.get_global_rect().position.x,
					"Checkpoint puts Back at the left end of the header"
				)
				_check(
					checkpoint_heading.get_theme_font_size("font_size") == 10
					and checkpoint_heading.get_global_rect().end.x <= checkpoint_help.position.x,
					"Checkpoint heading uses compact text and leaves room for both controls"
				)
				session.awaiting_return = true
				session.traces = 2
				screen._refresh_all()
				screen._on_option_pressed({"kind": "fallback", "id": "", "label": "Исходный след"})
				await _settle()
				_bounds(screen)
				_check(not screen.back_button.visible, "Checkpoint hides Back when return is mandatory")
				_check(screen.preview_text.text.contains("Лиорен"), "Third trace destination is shown before confirmation")
			_host.remove_child(screen)
			screen.free()
	_test_pagination()
	_test_safe_area()
	_test_scene_roots()
	await _test_claim_commit_failure()
	await _test_checkpoint_commit_failure()
	await _test_checkpoint_presentation()
	await _test_result_gestures()
	await _test_combat_mode_is_fixed_at_start()
	await _test_equipment_surfaces()
	print("UI_RESULT: checks=%d failed=%d" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)

func _test_claim_commit_failure() -> void:
	var game: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	game.save_path = "user://path_of_reborn_tests/ui_claim_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	await _settle()
	game.session.world_flags["prologue_completed"] = true
	game.save_service.save(game.session, game.save_path)
	game.session.select_encounter("moss_slime")
	game.router.go_to("combat")
	await _settle()
	var screen: Control = game.router.current_screen
	screen._set_pause(true)
	screen._on_format_switch_pressed()
	var preference_snapshot := PreferencesService.new()
	_check(preference_snapshot.load_preferences(game.preferences_path) and preference_snapshot.combat_format == GameSession.COMBAT_FORMAT_ACTIVE, "A05 pause preference is durable immediately, before the next battle")
	screen._on_format_switch_pressed()
	screen._set_pause(false)
	var blocker: String = ProjectSettings.globalize_path(game.save_path + ".tmp")
	DirAccess.make_dir_recursive_absolute(blocker)
	screen.resolver.advance_ticks(600)
	await create_timer(screen.VICTORY_REACTION_SECONDS + 0.1).timeout
	var result_id: String = String(game.session.pending_battle_result.get("result_id", ""))
	var pending_before: String = JSON.stringify(game.session.pending_battle_result)
	var inventory_count_before: int = game.session.inventory.items.size()
	_check(not result_id.is_empty() and game.session.inventory.items.size() == inventory_count_before, "A01 prepare creates pending without granting items")
	_check(screen.result_panel.is_visible_in_tree() and game.notice_bar.is_visible_in_tree(), "A01 failed prepare keeps a visible retryable result")
	var restored_prepare := GameSession.new()
	_check(SaveService.new().load_into(restored_prepare, game.save_path) and not restored_prepare.has_pending_battle_result() and restored_prepare.inventory.items.size() == inventory_count_before, "A01 failed prepare leaves the previous durable state without partial loot")
	DirAccess.remove_absolute(blocker)
	_check(game._autosave(), "A01 prepare retry saves the same result without rolling loot again")
	var restored_prepare_retry := GameSession.new()
	_check(SaveService.new().load_into(restored_prepare_retry, game.save_path) and JSON.stringify(restored_prepare_retry.pending_battle_result) == pending_before, "A01 prepare retry persists the identical pending")
	DirAccess.make_dir_recursive_absolute(blocker)
	screen.result_panel.store_button.pressed.emit()
	await _settle()
	pending_before = JSON.stringify(game.session.pending_battle_result)
	_check(game.router.current_screen == screen and screen.is_inside_tree(), "A01 failed claim commit keeps the result screen")
	_check(game.session.has_pending_battle_result() and JSON.stringify(game.session.pending_battle_result) == pending_before, "A01 failed claim rolls back to the identical rolled result")
	_check(game.session.inventory.items.size() == inventory_count_before and game.session.last_settlement.is_empty(), "A01 failed claim publishes no items or settlement")
	_check(game.notice_bar.is_visible_in_tree() and not game.notice_text.text.is_empty(), "A01 failure explains the retry in the visible UI")
	var restored_failed_claim := GameSession.new()
	_check(SaveService.new().load_into(restored_failed_claim, game.save_path) and restored_failed_claim.pending_battle_result.get("result_id", "") == result_id and restored_failed_claim.pending_battle_result.get("items", []) == game.session.pending_battle_result.get("items", []), "A01 restart after failed claim restores the same durable cards; an unconfirmed choice may be repeated")
	DirAccess.remove_absolute(blocker)
	if is_instance_valid(screen) and screen.is_inside_tree():
		screen._on_claim_pressed()
		await _settle()
		_check(game.router.current_screen.name == "World" and not game.session.has_pending_battle_result(), "A01 retry commits once and only then enters World")
		var restored := GameSession.new()
		_check(SaveService.new().load_into(restored, game.save_path) and restored.inventory.items.size() == game.session.inventory.items.size(), "A01 committed disk and memory agree")
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = ProjectSettings.globalize_path(game.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	game.queue_free()
	await _settle()

func _test_checkpoint_commit_failure() -> void:
	var game: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	game.save_path = "user://path_of_reborn_tests/ui_checkpoint_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	await _settle()
	game.session.world_flags["prologue_completed"] = true
	game.session.mark_path_started()
	game.save_service.save(game.session, game.save_path)
	game.router.go_to("checkpoint")
	await _settle()
	var screen: Control = game.router.current_screen
	var blocker: String = ProjectSettings.globalize_path(game.save_path + ".tmp")
	var disk := func() -> GameSession:
		var restored := GameSession.new()
		SaveService.new().load_into(restored, game.save_path)
		return restored

	# --- Фиксация при заблокированном .tmp: состояние остаётся подтверждённым.
	DirAccess.make_dir_recursive_absolute(blocker)
	screen._on_start_pressed()
	game.session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	for frame: int in range(4):
		await process_frame
		await physics_frame
	_check(game.session.checkpoints.manual_snapshots.is_empty(), "Checkpoint failed fixation does not publish the point in memory")
	_check(disk.call().checkpoints.manual_snapshots.is_empty(), "Checkpoint failed fixation does not reach the disk")
	_check(not screen.set_fx.is_visible_in_tree(), "Checkpoint failed fixation plays no success FX")
	_check(not game.notice_bar.is_visible_in_tree(), "Checkpoint failure is not a covering notice bar")
	_check(screen.error_box.is_visible_in_tree() and not screen.error_label.text.is_empty(), "Checkpoint failure shows an inline error near the action")
	_check(screen.error_label.text.contains("Повторите"), "Checkpoint error explains the retry")
	_check(root.gui_get_focus_owner() == screen.error_retry, "Checkpoint failure focuses the retry button")
	# --- Выход и повторный вход продолжают тот же pending после подключения сигналов.
	screen._on_back_pressed()
	await _settle()
	_check(game.router.current_screen.name == "World", "Checkpoint failure can return to World")
	DirAccess.remove_absolute(blocker)
	game.router.go_to("checkpoint")
	await _settle()
	screen = game.router.current_screen
	_check(game.session.checkpoints.manual_snapshots.size() == 1, "Checkpoint reopen commits exactly one pending point")
	_check(disk.call().checkpoints.manual_snapshots.size() == 1, "Checkpoint reopen reaches the disk")
	_check(not screen._commit_in_flight and screen._pending_commit.is_empty(), "Checkpoint reopen clears the completed commit state")
	_check(not screen.error_box.is_visible_in_tree(), "Checkpoint success clears the inline error")
	_check(screen.set_fx.is_visible_in_tree(), "Checkpoint success plays the set FX after the commit")
	_check(root.gui_get_focus_owner() == screen.start_button, "Checkpoint completion focuses the primary action")
	var committed_id: String = game.session.checkpoints.manual_snapshots[0]["checkpoint_id"]
	screen._on_error_retry_pressed()
	await _settle()
	_check(game.session.checkpoints.manual_snapshots.size() == 1, "A stray retry press cannot duplicate the committed point")

	# --- Удаление через настоящий ConfirmDialog при заблокированном .tmp.
	DirAccess.make_dir_recursive_absolute(blocker)
	screen._on_delete_pressed(committed_id, "Точка №1")
	await _settle()
	var dialog: ConfirmDialog
	for child: Node in screen.get_children():
		if child is ConfirmDialog:
			dialog = child
	_check(dialog != null, "Checkpoint delete opens the shared confirmation dialog")
	dialog._on_confirm_pressed()
	await _settle()
	_check(game.session.checkpoints.manual_snapshots.size() == 1, "Checkpoint failed delete keeps the point in memory")
	_check(disk.call().checkpoints.manual_snapshots.size() == 1, "Checkpoint failed delete keeps the point on disk")
	_check(screen.error_box.is_visible_in_tree(), "Checkpoint failed delete shows the inline error")
	_check(root.gui_get_focus_owner() == screen.error_retry, "Checkpoint failed delete focuses retry after restoring modal focus")
	DirAccess.remove_absolute(blocker)
	screen._on_error_retry_pressed()
	await _settle()
	_check(game.session.checkpoints.manual_snapshots.is_empty() and disk.call().checkpoints.manual_snapshots.is_empty(), "Checkpoint delete retry commits once in memory and on disk")

	# --- Возврат «Первый след» при заблокированном .tmp: ничего не расходуется.
	game.session.select_encounter("moss_slime")
	game.session.start_combat("moss_slime")
	game.session.abandon_combat()
	await _settle()
	game.save_service.save(game.session, game.save_path)
	_check(disk.call().awaiting_return, "Defeat state is durable before the return")
	DirAccess.make_dir_recursive_absolute(blocker)
	game.router.go_to("checkpoint")
	await _settle()
	screen = game.router.current_screen
	screen._on_option_pressed({"kind": "first_trace", "id": "first_trace", "label": "Первый след"})
	screen._on_confirm_return_pressed()
	await _settle()
	_check(game.router.current_screen == screen and screen.is_inside_tree(), "Checkpoint failed return keeps the player on the screen")
	_check(game.session.awaiting_return and game.session.checkpoints.first_trace_available, "Checkpoint failed return keeps the return right in memory")
	_check(game.session.traces == 0, "Checkpoint failed return spends no traces in memory")
	var disk_failed: GameSession = disk.call()
	_check(disk_failed.awaiting_return and disk_failed.checkpoints.first_trace_available and disk_failed.traces == 0, "Checkpoint failed return leaves the last confirmed disk state")
	_check(screen.error_box.is_visible_in_tree(), "Checkpoint failed return shows the inline error")
	_check(root.gui_get_focus_owner() == screen.error_retry, "Checkpoint failed return focuses the retry button")
	# --- Повтор возврата: расход, локация и следующий экран совпадают везде.
	DirAccess.remove_absolute(blocker)
	screen._on_error_retry_pressed()
	await _settle()
	_check(game.router.current_screen.name == "World", "Checkpoint return retry enters World only after the commit")
	_check(not game.session.awaiting_return and not game.session.checkpoints.first_trace_available, "Checkpoint return retry consumes the point exactly once")
	_check(game.session.traces == 1 and game.session.location_id == "forest_edge", "Checkpoint return retry adds the trace and keeps the location")
	var disk_restored: GameSession = disk.call()
	_check(not disk_restored.awaiting_return and disk_restored.traces == 1, "Checkpoint return retry persists traces and return state")
	var backup := GameSession.new()
	_check(SaveService.new().load_into(backup, game.save_path + ".bak") and backup.awaiting_return and backup.traces == 0, "Checkpoint commit keeps the backup as the previous confirmed state")
	for suffix: String in ["", ".tmp", ".bak"]:
		var path: String = ProjectSettings.globalize_path(game.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	game.queue_free()
	await _settle()

func _test_checkpoint_presentation() -> void:
	var game: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	game.save_path = "user://path_of_reborn_tests/ui_checkpoint_pres_%d.json" % Time.get_ticks_usec()
	root.add_child(game)
	await _settle()
	game.session.world_flags["prologue_completed"] = true
	game.session.mark_path_started()
	var screen: Control = await _screen_under(game, "checkpoint")
	# Фон совпадает с локацией сессии (маппинг как у World).
	_check(
		screen.background_art.texture == ArtMap.texture(ArtMap.BACKGROUNDS["world_forest_edge"]),
		"Checkpoint background shows the trail location behind the panel"
	)
	_check(screen.contract_text.text.contains("Следы 0/3"), "Checkpoint header names traces with a denominator")
	_check(not screen.points_count.is_visible_in_tree(), "Checkpoint hides the points counter in the empty state")
	game.session.location_id = "lioren"
	game.router.go_to("checkpoint")
	await _settle()
	screen = game.router.current_screen
	_check(
		screen.background_art.texture == ArtMap.texture(ArtMap.BACKGROUNDS["world_lioren"]),
		"Checkpoint background follows the Lioren location"
	)
	# Снимок в Лиорене: превью возврата показывает локацию выбранной точки.
	game.session.checkpoints.begin()
	game.session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	game.session.checkpoints.apply_completion()
	_check(game.session.checkpoints.manual_snapshots.size() == 1, "Checkpoint presentation fixture fixes one point")
	game.session.select_encounter("moss_slime")
	game.session.start_combat("moss_slime")
	game.session.abandon_combat()
	await _settle()
	game.router.go_to("checkpoint")
	await _settle()
	screen = game.router.current_screen
	_check(screen.points_count.is_visible_in_tree() and screen.points_count.text.contains("1/3"), "Checkpoint names the point count next to the list")
	var snapshot: Dictionary = game.session.checkpoints.manual_snapshots[0]
	_check(screen._snapshot_label(snapshot).contains("ур.\u00A0"), "Checkpoint keeps the level number on one line")
	screen._on_option_pressed({"kind": "manual", "id": snapshot["checkpoint_id"], "label": screen._snapshot_label(snapshot)})
	_check(
		screen.preview_art.is_visible_in_tree()
			and screen.preview_art.texture == ArtMap.texture(ArtMap.BACKGROUNDS["world_lioren"]),
		"Checkpoint return preview shows the snapshot location"
	)
	game.queue_free()
	await _settle()

func _screen_under(game: GameRoot, id: String) -> Control:
	game.router.go_to(id)
	await _settle()
	return game.router.current_screen

func _test_result_gestures() -> void:
	var session := GameSession.new()
	session.select_encounter("moss_slime")
	var screen: Control = await _screen("combat", session)
	screen._finish_intro()
	screen.resolver.advance_ticks(600)
	await create_timer(screen.VICTORY_REACTION_SECONDS + 0.1).timeout
	var navigations := {"count": 0}
	screen.navigate_requested.connect(func(_destination: String) -> void: navigations["count"] = int(navigations["count"]) + 1)
	screen.claim_requested.connect(func(result_id: String) -> void:
		if session.claim_battle_result(result_id):
			screen.navigate_requested.emit("world"))
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = Vector2(70, 180)
	press.pressed = true
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = Vector2(40, 180)
	release.pressed = false
	screen.result_panel._on_card_input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = release.position
	drag.relative = Vector2(-30, 0)
	screen.result_panel._on_card_input(drag)
	screen.result_panel._on_card_input(release)
	_check(int(navigations["count"]) == 1 and not session.has_pending_battle_result(), "A04 a completed left swipe stores a crystal and claims once")
	_host.remove_child(screen)
	screen.free()

	var canceled_session := GameSession.new()
	canceled_session.select_encounter("moss_slime")
	var canceled_screen: Control = await _screen("combat", canceled_session)
	canceled_screen._finish_intro()
	canceled_screen.resolver.advance_ticks(600)
	await create_timer(canceled_screen.VICTORY_REACTION_SECONDS + 0.1).timeout
	var result: CombatResultView = canceled_screen.result_panel
	var canceled_navigations := {"count": 0}
	canceled_screen.navigate_requested.connect(func(_destination: String) -> void: canceled_navigations["count"] = int(canceled_navigations["count"]) + 1)
	result._on_card_input(press)
	var canceled := release.duplicate() as InputEventScreenTouch
	canceled.canceled = true
	result._on_card_input(canceled)
	_check(int(canceled_navigations["count"]) == 0 and canceled_session.has_pending_battle_result(), "A04 canceled touch restores the card without a choice")
	result._on_card_input(press)
	var other_press := press.duplicate() as InputEventScreenTouch
	other_press.index = 1
	result._on_card_input(other_press)
	var other_release := release.duplicate() as InputEventScreenTouch
	other_release.index = 1
	result._on_card_input(other_release)
	result._on_card_input(release)
	_check(int(canceled_navigations["count"]) == 0 and canceled_session.has_pending_battle_result(), "A04 a second finger and foreign release cannot confirm a card")
	result._on_card_input(press)
	var diagonal := drag.duplicate() as InputEventScreenDrag
	diagonal.position = Vector2(100, 210)
	diagonal.relative = Vector2(30, 30)
	result._on_card_input(diagonal)
	var diagonal_release := release.duplicate() as InputEventScreenTouch
	diagonal_release.position = diagonal.position
	result._on_card_input(diagonal_release)
	_check(int(canceled_navigations["count"]) == 0 and result.card.position.x == 0, "A04 diagonal movement is not a horizontal swipe")
	result._on_card_input(press)
	var right := drag.duplicate() as InputEventScreenDrag
	right.position = Vector2(100, 180)
	right.relative = Vector2(30, 0)
	result._on_card_input(right)
	var right_release := release.duplicate() as InputEventScreenTouch
	right_release.position = right.position
	result._on_card_input(right_release)
	_check(int(canceled_navigations["count"]) == 0 and canceled_session.pending_battle_result.get("choices", {}).is_empty(), "A04 equip swipe is unavailable for a crystal")
	result._on_card_input(press)
	result._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	result._on_card_input(release)
	_check(int(canceled_navigations["count"]) == 0 and canceled_session.has_pending_battle_result(), "A04 focus loss cancels the candidate")
	_host.remove_child(canceled_screen)
	canceled_screen.free()

func _test_combat_mode_is_fixed_at_start() -> void:
	for initial: String in [GameSession.COMBAT_FORMAT_AUTO, GameSession.COMBAT_FORMAT_ACTIVE]:
		var session := GameSession.new()
		session.set_combat_format(initial)
		session.select_encounter("moss_slime")
		var screen: Control = await _screen("combat", session)
		screen._finish_intro()
		screen._set_pause(true)
		screen._on_format_switch_pressed()
		var current_active: bool = initial == GameSession.COMBAT_FORMAT_ACTIVE
		_check(screen.dodge_button.visible == current_active, "A05 pause preference does not replace current dodge controls: %s" % initial)
		_check(screen.resolver.auto_dodge_enabled != current_active, "A05 current resolver defense policy stays fixed: %s" % initial)
		var expected_mode: String = "ручной" if current_active else "авто"
		_check(expected_mode in screen.format_label.text.to_lower(), "A05 HUD names the current run, not next preference: %s" % initial)
		_check(screen.format_switch.text.begins_with("Включить ") and "со следующего боя" in screen.format_switch.text.to_lower(), "A05 pause names the action and scopes it to the next battle")
		_check(not screen.format_label.get_global_rect().intersects(screen.pause_button.get_global_rect()), "Compact mode indicator does not overlap Pause")
		screen._set_pause(false)
		if current_active:
			_check(screen.attack_button.size == Vector2(24, 24), "Manual attack keeps its compact touch area")
			_check(not screen.equipment_strip.get_global_rect().intersects(screen.actions.get_global_rect()), "Manual actions stay separate from equipment")
		while not screen.resolver.is_finished and screen.resolver.tick_count < 3000:
			if current_active:
				screen.resolver.request_attack()
			screen.resolver.advance_ticks(15)
		await create_timer(screen.VICTORY_REACTION_SECONDS + 0.1).timeout
		_check(screen.resolver.won and not screen.format_label.is_visible_in_tree(), "A07 result hides the combat mode label")
		_host.remove_child(screen)
		screen.free()

func _test_equipment_surfaces() -> void:
	var session := GameSession.new()
	var inventory: Control = await _screen("inventory", session)
	_check(inventory.equipment_strip.is_visible_in_tree() and not _in_scroll(inventory.equipment_strip), "A12 equipped block is pinned above the scrollable backpack")
	_check("Надето" in inventory.equipment_strip.slot_buttons["weapon"].accessibility_name and "Пусто" in inventory.equipment_strip.slot_buttons["helmet"].tooltip_text and "Пусто" in inventory.equipment_strip.slot_buttons["charm"].tooltip_text, "A12 equipped and empty slots are explicit")
	for slot_id: String in ArtMap.EMPTY_SLOT_ICONS:
		var slot_button: Button = inventory.equipment_strip.slot_buttons[slot_id]
		_check(slot_button.text.is_empty() and slot_button.icon.resource_path.ends_with(ArtMap.EMPTY_SLOT_ICONS[slot_id]), "Empty %s slot uses its own raster icon" % slot_id)
	session.unequip_item("weapon")
	await _settle()
	inventory.equipment_strip.slot_buttons["weapon"].pressed.emit()
	_check(inventory.filter_id == "weapon", "A12 empty weapon slot filters the existing backpack")
	inventory._on_filter_selected(0)
	var swords: Array[ItemInstance] = session.inventory.add(session.get_item_definition("training_sword"), 2)
	var charms: Array[ItemInstance] = session.inventory.add(session.get_item_definition("moss_charm"), 1)
	session.equip_item(swords[0].instance_id)
	session.equip_item(charms[0].instance_id)
	await _settle()
	_check(inventory.equipment_strip.slot_buttons["weapon"].icon != null and inventory.equipment_strip.slot_buttons["charm"].icon != null, "A12 occupied slots show real item icons")
	_check("Надето" in inventory.equipment_strip.slot_buttons["weapon"].accessibility_name, "A12 slot accessibility names the equipped state")
	inventory.equipment_strip.slot_buttons["weapon"].pressed.emit()
	await _settle()
	_check(inventory.details_layer.visible and inventory.details.action_button.text == "Снять", "A12 occupied slot opens common details with an available unequip action")
	_check(inventory.details.model["instance_id"] == swords[0].instance_id, "A12 slot details use the exact instance ID")
	inventory.handle_back()
	inventory._on_item_pressed(swords[1].instance_id)
	_check(inventory.details.model["current_instance_id"] == swords[0].instance_id and not inventory.details.model["equipped"], "A12 identical second instance is not confused with equipped selection")
	inventory.handle_back()
	_host.remove_child(inventory)
	inventory.free()

	var world: Control = await _screen("world", session)
	_check(world.equipment_strip.is_visible_in_tree(), "A12 World shows occupied equipment thumbnails")
	_check(world.weapon_icon.visible and world.weapon_icon.texture == ArtMap.item_icon("training_sword"), "A12 World uses the consistent weapon-icon fallback at the hero")
	_check(world.equipment_strip.get_global_rect().end.y <= world.inventory_button.get_global_rect().position.y, "A12 World equipment stays above the navigation rail")
	_check(not world.equipment_strip.get_global_rect().intersects(world.checkpoint_button.get_global_rect()), "A12 World equipment does not overlap the Checkpoint control")
	world.equipment_strip.slot_buttons["charm"].pressed.emit()
	await _settle()
	_check(world.details_layer.visible and world.details_view.model["instance_id"] == charms[0].instance_id and not world.details_view.action_button.visible, "A12 World thumbnail opens read-only details for its own slot")
	_check(world.handle_back() and not world.details_layer.visible, "A12 Back closes World item details")
	_bounds(world)
	_host.remove_child(world)
	world.free()

	session.select_encounter("moss_slime")
	var combat: Control = await _screen("combat", session)
	combat._finish_intro()
	_check(combat.equipment_strip.is_visible_in_tree(), "A12 combat shows occupied equipment thumbnails")
	_check(combat.weapon_sprite.visible and combat.weapon_sprite.texture == ArtMap.item_icon("training_sword"), "A12 combat uses the same weapon-icon fallback at the hero")
	_check(not combat.actions.is_visible_in_tree(), "A12 auto combat leaves the manual action row hidden")
	_check(combat.equipment_strip.get_global_rect().position.y > SceneStaging.floor_y(combat.size.y), "A12 combat equipment stays below the actors")
	combat.resolver.advance_ticks(600)
	await create_timer(combat.VICTORY_REACTION_SECONDS + 0.1).timeout
	_check(combat.resolver.is_finished and combat.resolver.won, "A12 equipped fixture reaches victory")
	_check(not combat.equipment_strip.is_visible_in_tree(), "A12 combat equipment strip is hidden on victory")
	var equipped_before: Dictionary = session.inventory.equipment.duplicate()
	combat._open_details("training_sword", "", 1)
	_check(combat.details_view.model["current_instance_id"] == swords[0].instance_id and not combat.details_view.action_button.visible, "A12 loot comparison names the current item and stays read-only")
	combat._close_details()
	_check(session.inventory.equipment == equipped_before and session.has_pending_battle_result(), "A12 preview neither equips nor collects loot")
	var long_result: Dictionary = session.pending_battle_result.duplicate(true)
	long_result["items"] = []
	long_result["choices"] = {}
	for index: int in range(12):
		long_result["items"].append({"entry_id": "long_%02d" % index, "item_id": "training_sword", "quantity": 1, "aspect_id": "", "level": 1, "sale_price_copper": 0, "sellable": false})
	combat._show_result_panel(long_result)
	await _settle()
	_check(combat.result_panel._entry.get("entry_id", "") == "long_00" and "осталось 12" in combat.result_panel.find_child("SwipeHints", true, false).text, "A12 multiple rewards are sequential cards with stable entry IDs")
	_check(combat.result_panel.card.focus_mode == Control.FOCUS_ALL and combat.result_panel.detail_button.focus_mode == Control.FOCUS_ALL, "A12 the compact reward card and details action have keyboard and controller focus")
	_bounds(combat)
	_host.remove_child(combat)
	combat.free()

	var upgrade_session := GameSession.new()
	upgrade_session.hero.gain_xp(4)
	var router := SceneRouter.new()
	router.configure(_host, upgrade_session)
	router.go_to("world")
	await _settle()
	var world_with_upgrade: Control = router.current_screen
	world_with_upgrade.upgrade_button.pressed.emit()
	await _settle()
	var upgrades: Control = router.current_screen
	_check(root.gui_get_focus_owner() == upgrades.strength_upgrade and upgrades.upgrade_row.visible, "Pending upgrade owns the opening focus")
	_check("Сила 3 → 4" in upgrades.strength_upgrade.text and "HP 12 → 16" in upgrades.hp_upgrade.text, "Upgrade actions show actual current and resulting stats")
	upgrades._choose_upgrade("strength")
	_check(upgrade_session.hero.strength == 4 and "Сила 4" in upgrades.stats_label.text, "Chosen strength updates the visible stats immediately")
	_check(not upgrades.upgrade_row.visible and upgrade_session.hero.pending_upgrade_choices == 0, "Spent upgrade leaves no stale action")
	upgrades.back_button.pressed.emit()
	_check(router.current_screen.name == "World", "Back from the World shortcut returns directly to World")
	_host.remove_child(router.current_screen)
	router.current_screen.free()

func _test_character_catalog(screen: Control, session: GameSession) -> void:
	_check(screen.catalog.visible and screen.catalog_buttons.size() == 1, "The initial catalog shows only the playable hero")
	_check(screen.get_node("%TotalPower").text == "Общая мощность 34", "Catalog displays the sum of playable character power")
	var hero_tile: Button = screen.catalog_buttons["haruto"]
	hero_tile.pressed.emit()
	await _settle()
	_bounds(screen)
	_check(screen.profile.visible and screen.get_node("%Heading").text == "Харуто", "Catalog tile opens Haruto's profile")
	_check(screen.get_node("%Experience").text == "0 / 4 XP" and "Точный удар" in screen.get_node("%NextGain").text, "Profile previews the real XP threshold and next ability")
	var strip: EquipmentStrip = screen.equipment_strip
	var weapon: Button = strip.slot_buttons["weapon"]
	var portrait: Rect2 = strip.portrait.get_global_rect()
	_check(portrait.size.y >= 108.0 and portrait.get_center().x == strip.get_global_rect().get_center().x, "Full-body art has room at the center of the equipment layout")
	for slot: String in EquipmentStrip.LEFT_SLOTS:
		var button: Button = strip.slot_buttons[slot]
		_check(button.get_global_rect().end.x <= portrait.position.x, "Left equipment slot stays outside the portrait: " + slot)
	for slot: String in EquipmentStrip.RIGHT_SLOTS:
		var button: Button = strip.slot_buttons[slot]
		_check(button.get_global_rect().position.x >= portrait.end.x, "Right equipment slot stays outside the portrait: " + slot)
	weapon.grab_focus()
	weapon.pressed.emit()
	await _settle()
	_bounds(screen)
	_check(screen.details_layer.visible and screen.details_view.model.get("equipped") == true, "Equipped item opens the shared item card")
	var bonus: Label = screen.details_view.compare_label.get_parent().get_child(1)
	_check(screen.details_view.scroll.get_global_rect().encloses(bonus.get_global_rect()), "Starting weapon bonus is visible without scrolling")
	_check(root.gui_get_focus_owner() == screen.details_view.close_button and screen.back_button.focus_mode == Control.FOCUS_NONE, "Item modal owns focus")
	var sword: ItemInstance = session.inventory.filter("weapon")[0]
	var before: int = session.hero.power_rating()
	screen.details_view.action_button.pressed.emit()
	_check(not session.inventory.is_equipped(sword.instance_id) and screen.details_layer.visible, "Unequip updates the open item card")
	_check(screen.get_node("%Power").text == "Мощность %d" % session.hero.power_rating(), "Profile power follows equipped stats")
	screen.details_view.action_button.pressed.emit()
	_check(session.hero.power_rating() == before, "Re-equipping restores the initial power")
	screen.handle_back()
	_check(screen.profile.visible and not screen.details_layer.visible and root.gui_get_focus_owner() == weapon, "Back closes the item modal and restores slot focus")
	screen.back_button.pressed.emit()
	_check(screen.catalog.visible and root.gui_get_focus_owner() == hero_tile, "Profile Back returns to the previously opened catalog tile")
	session.world_flags["road_companion_joined"] = true
	session.profile_changed.emit()
	await _settle()
	_check(screen.catalog_buttons.size() == 2, "A joined companion is added to the catalog")
	var companion: CharacterState = session.character_state("road_companion")
	_check(screen.get_node("%TotalPower").text == "Общая мощность %d" % (before + companion.power_rating()), "Catalog total includes the joined companion")
	screen.catalog_buttons["road_companion"].pressed.emit()
	await _settle()
	_check("макс. HP +3" in screen.get_node("%NextGain").text, "Companion profile previews its own upgrade values")
	_check(weapon.tooltip_text == "Оружие: Пусто" and screen.familiar_button.visible, "Companion sees its own equipment and familiar controls")
	companion.gain_xp(42)
	session.profile_changed.emit()
	_check(not screen.get_node("%ExperienceBar").visible and screen.upgrade_row.visible, "Maximum level hides XP but keeps unspent choices")

func _test_pagination() -> void:
	var runner := DialogueRunner.new()
	runner.load_file("res://data/narrative/prologue.json")
	var font: Font = ThemeDB.fallback_font
	for width: float in [140.0, 156.0, 180.0]:
		for cue: Dictionary in runner.entries:
			var texts: Array[String] = [String(cue.get("text", ""))]
			for part: Dictionary in cue.get("parts", []):
				texts.append(String(part.get("text", "")))
			for text: String in texts:
				var pages: Array[String] = DialoguePaginator.paginate(text, font, 10, width, 3)
				_check(" ".join(" ".join(pages).split(" ", false)) == " ".join(text.split(" ", false)), "Every word survives shaped pagination")
				for page: String in pages:
					var measured: Vector2 = font.get_multiline_string_size(page, HORIZONTAL_ALIGNMENT_LEFT, width, 10, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
					_check(measured.y <= font.get_height(10) * 3 + 0.1, "Every page fits three real shaped lines")

func _test_scene_roots() -> void:
	# Полноэкранные Control-корни со STOP-фильтром молча съедают tap по свободной
	# области (claim/добровольный ввод), не доходя до _unhandled_input.
	var game_root: Control = load("res://scenes/game_root.tscn").instantiate()
	_check(game_root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "GameRoot passes free-area taps to _unhandled_input")
	game_root.free()
	var combat: Control = load("res://scenes/combat.tscn").instantiate()
	_check(combat.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Combat root passes free-area taps to _unhandled_input")
	combat.free()

func _test_safe_area() -> void:
	var viewport := Rect2(0, 0, 180, 320)
	var transform := Transform2D(Vector2(2, 0), Vector2(0, 2), Vector2(15, 102))
	_check(SafeArea.margins_for(viewport, transform, Rect2(0, 40, 390, 760)) == Vector4.ZERO, "Cutout inside letterbox creates no extra UI margin")
	_check(SafeArea.margins_for(viewport, transform, Rect2(0, 122, 390, 600)) == Vector4(0, 10, 0, 10), "Safe area accounts for actual integer scale and offset")
