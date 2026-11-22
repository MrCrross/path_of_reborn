extends SceneTree

const OUT := "res://../docs/reviews/first_session_iteration_2026_11_21/swipe_probe"

var _checks: int = 0
var _failed: int = 0
var _view: CombatResultView
var _session: GameSession
var _result: Dictionary
var _choices: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(360, 640))
	await _frames(5)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_session = GameSession.new()
	_session.select_encounter("moss_slime")
	var combat: CombatResolver = _session.start_combat(_session.current_enemy_id)
	combat.enemy.current_hp = 1
	combat.advance_ticks(combat.hero.definition.attack_startup_ticks + 1)
	_result = _session.pending_battle_result.duplicate(true)
	var sword_def: ItemDefinition = _session.get_item_definition("training_sword")
	_result["items"].insert(0, {"entry_id": "entry_000901", "item_id": "training_sword", "aspect_id": "", "quantity": 1, "level": 1, "sale_price_copper": sword_def.sale_price_copper, "sellable": true})

	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.theme = AppTheme.build()
	root.add_child(host)
	_view = CombatResultView.new()
	host.add_child(_view)
	_view.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_view.offset_left = 6
	_view.offset_right = -6
	_view.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_view.choice_requested.connect(func(entry_id: String, action: String) -> void: _choices.append({"entry_id": entry_id, "action": action}))
	_view.present(_session, _result)
	_view.present_next(_result)
	await _frames(4)

	_check(_view.card.is_visible_in_tree() and not _view.summary_button.is_visible_in_tree() and not _view.claim_button.is_visible_in_tree(), "Находка показана отдельной карточкой")
	_shot("01_card_equipment")

	await _gesture(Vector2(-26, 0), "")
	_check(_choices == [{"entry_id": "entry_000901", "action": "store"}], "Свайп влево по мечу отправляет «Взять»")

	_choices.clear()
	_view.present_next(_result)
	await _frames(3)
	await _gesture(Vector2(26, 0), "02_card_drag_right")
	_check(_choices == [{"entry_id": "entry_000901", "action": "equip"}], "Свайп вправо по мечу отправляет «Надеть»")

	_choices.clear()
	_view.present_next(_result)
	await _frames(3)
	await _gesture(Vector2(2, 1), "")
	_check(_choices == [{"entry_id": "entry_000901", "action": "store"}], "Короткое касание карточки берёт предмет")

	_choices.clear()
	_view.present_next(_result)
	await _frames(3)
	await _gesture(Vector2(8, 0), "")
	_check(_choices.is_empty() and _view.card.position.x == 0, "Жест короче порога не подтверждается, карточка возвращается")

	_choices.clear()
	_view.present_next(_result)
	await _frames(3)
	await _gesture(Vector2(2, 30), "")
	_check(_choices.is_empty() and _view.card.position.x == 0, "Вертикальный жест не считается свайпом, карточка возвращается")

	var crystal_result: Dictionary = _session.pending_battle_result.duplicate(true)
	_view.present_next(crystal_result)
	await _frames(3)
	_check(not _view._can_equip, "Карточка кристалла не предлагает «Надеть»")
	_shot("03_card_crystal")
	_choices.clear()
	await _gesture(Vector2(-26, 0), "")
	_check(_choices.size() == 1 and _choices[0]["action"] == "store", "Свайп влево по кристаллу отправляет «Взять»")

	print("SWIPE_PROBE checks=%d failed=%d" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)

func _gesture(delta: Vector2, shot_label: String) -> void:
	var center: Vector2 = _view.card.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = center
	press.pressed = true
	root.push_input(press, true)
	await _frames(2)
	var steps: int = maxi(1, int(absf(delta.x) + absf(delta.y)) / 4)
	for step: int in range(1, steps + 1):
		var motion := InputEventMouseMotion.new()
		motion.position = center + delta * (float(step) / steps)
		motion.relative = delta / steps
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await _frames(1)
	if not shot_label.is_empty():
		_shot(shot_label)
		await _frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = center + delta
	release.pressed = false
	root.push_input(release, true)
	await _frames(2)

func _shot(label: String) -> void:
	await _frames(2)
	var image: Image = root.get_texture().get_image()
	image.save_png(OUT + "/" + label + ".png")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("ok: " + label)
	else:
		_failed += 1
		print("FAIL: " + label)

func _frames(count: int) -> void:
	for i: int in count:
		await process_frame
