class_name CheckpointService
extends RefCounted

signal changed
## Канал завершён: снимок вычислен доменом и staged в pending_completion.
## В список точек он попадает только после подтверждённой записи SaveService
## (граница commit живёт в GameRoot, по образцу claim боевой добычи).
signal completion_ready

const CHANNEL_TICKS: int = 300
const MANUAL_LIMIT: int = 3

var manual_snapshots: Array[Dictionary] = []
var first_trace_snapshot: Dictionary = {}
var first_trace_available: bool = true
var channel_active: bool = false
var channel_ticks: int = 0
## Завершённый, но ещё не закоммиченный снимок фиксации. Домен не применяет
## его к manual_snapshots сам: при ошибке записи живое состояние совпадает
## с последним подтверждённым, а повтор commit идемпотентен.
var pending_completion: Dictionary = {}

var _session_ref: WeakRef
var _sequence: int = 0
var session: GameSession:
	get:
		return _session_ref.get_ref() as GameSession

func _init(game_session: GameSession) -> void:
	_session_ref = weakref(game_session)

func initialize() -> void:
	manual_snapshots.clear()
	_sequence = 0
	channel_active = false
	channel_ticks = 0
	pending_completion = {}
	first_trace_available = true
	first_trace_snapshot = _make_snapshot("first_trace", 0)
	changed.emit()

## Снимок «Первый след» изначально делается при reset_session (до пролога).
## Семантически точка — «Старт пути»: обновляем на границе входа в мир, чтобы
## возврат не откатывал story-флаги пролога. Потраченную точку не возрождаем.
func refresh_first_trace() -> void:
	if not first_trace_available:
		return
	first_trace_snapshot = _make_snapshot("first_trace", 0)
	changed.emit()

func can_begin() -> bool:
	return (
		not channel_active
		and pending_completion.is_empty()
		and manual_snapshots.size() < MANUAL_LIMIT
		and session.traces < 3
		and (session.location_id != GameSession.LOCATION_GROVE or session.grove_stage() == "clearing")
		and not session.in_combat
		and session.pending_battle_result.is_empty()
		and session.pending_story_reward.is_empty()
		and not session.awaiting_return
		and not session.is_transaction_active()
		and not session.is_pursued
		and not session.is_moving
	)

func begin() -> bool:
	if not can_begin():
		return false
	channel_active = true
	channel_ticks = 0
	changed.emit()
	return true

func cancel() -> void:
	channel_active = false
	channel_ticks = 0
	changed.emit()

func notify_movement() -> void:
	if channel_active:
		cancel()

func advance_ticks(count: int) -> void:
	for _tick: int in range(maxi(0, count)):
		if not channel_active:
			return
		if session.in_combat or session.is_pursued or session.is_moving:
			cancel()
			return
		channel_ticks += 1
		if channel_ticks == CHANNEL_TICKS:
			channel_active = false
			_sequence += 1
			pending_completion = _make_snapshot("checkpoint_%06d" % _sequence, _sequence)
			completion_ready.emit()

func has_pending_completion() -> bool:
	return not pending_completion.is_empty()

## Переносит staged-снимок в список точек. Вызывается на кандидате внутри
## границы commit; живое состояние получает итог целиком через apply_dto.
func apply_completion() -> bool:
	if pending_completion.is_empty():
		return false
	if session.location_id == GameSession.LOCATION_GROVE:
		session.world_flags[GameSession.GROVE_SEALED] = true
		pending_completion["profile"]["world_flags"][GameSession.GROVE_SEALED] = true
	manual_snapshots.append(pending_completion.duplicate(true))
	pending_completion = {}
	changed.emit()
	return true

## Чистый план удаления: не мутирует сервис. Применение — apply_delete_plan.
func delete_plan(checkpoint_id: String) -> Dictionary:
	for index: int in range(manual_snapshots.size()):
		if manual_snapshots[index]["checkpoint_id"] == checkpoint_id:
			return {
				"kind": "delete",
				"checkpoint_id": checkpoint_id,
				"manual_snapshots": manual_snapshots.slice(0, index) + manual_snapshots.slice(index + 1),
			}
	return {}

func apply_delete_plan(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	manual_snapshots.assign((plan["manual_snapshots"] as Array).duplicate(true))
	changed.emit()

## Чистый план возврата: повторяет логику выбора restore(), но ничего не меняет.
## GameRoot применяет его к кандидату и записывает; живое состояние меняется
## только после успешного save().
func restore_plan(checkpoint_id: String = "") -> Dictionary:
	if not session.awaiting_return:
		return {}
	var selected_id: String = checkpoint_id
	if selected_id.is_empty():
		if not manual_snapshots.is_empty():
			selected_id = manual_snapshots.back()["checkpoint_id"]
		elif first_trace_available:
			selected_id = "first_trace"
		else:
			return {
				"kind": "fallback",
				"fallback": true,
				"trace_cost": 2,
			}
	if selected_id == "first_trace" and first_trace_available:
		return {
			"kind": "first_trace",
			"checkpoint_id": "first_trace",
			"snapshot": first_trace_snapshot.duplicate(true),
			"manual_snapshots": [] as Array[Dictionary],
			"first_trace_available": false,
			"trace_cost": 1,
		}
	for index: int in range(manual_snapshots.size()):
		if manual_snapshots[index]["checkpoint_id"] == selected_id:
			return {
				"kind": "manual",
				"checkpoint_id": selected_id,
				"snapshot": manual_snapshots[index].duplicate(true),
				"manual_snapshots": manual_snapshots.slice(0, index),
				"first_trace_available": first_trace_available,
				"trace_cost": 1,
			}
	return {}

func apply_restore_plan(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	if bool(plan.get("fallback", false)):
		_apply_fallback()
		return
	manual_snapshots.assign((plan["manual_snapshots"] as Array).duplicate(true))
	first_trace_available = bool(plan["first_trace_available"])
	_restore_profile(plan["snapshot"], int(plan["trace_cost"]))

func delete_checkpoint(checkpoint_id: String) -> bool:
	var plan: Dictionary = delete_plan(checkpoint_id)
	if plan.is_empty():
		return false
	apply_delete_plan(plan)
	return true

func restore(checkpoint_id: String = "") -> bool:
	var plan: Dictionary = restore_plan(checkpoint_id)
	if plan.is_empty():
		return false
	apply_restore_plan(plan)
	return true

func rest() -> bool:
	if session.location_id != "lioren":
		return false
	session.traces = 0
	session.hero.set_void_traces(0)
	session.profile_changed.emit()
	changed.emit()
	return true

func capture_dto() -> Dictionary:
	return {
		"manual_snapshots": manual_snapshots.duplicate(true),
		"first_trace_snapshot": first_trace_snapshot.duplicate(true),
		"first_trace_available": first_trace_available,
		"sequence": _sequence,
		"pending_completion": pending_completion.duplicate(true),
	}

func apply_dto(dto: Dictionary) -> void:
	manual_snapshots.assign(dto.get("manual_snapshots", []).duplicate(true))
	first_trace_snapshot = dto.get("first_trace_snapshot", {}).duplicate(true)
	first_trace_available = bool(dto.get("first_trace_available", true))
	_sequence = maxi(0, int(dto.get("sequence", 0)))
	pending_completion = dto.get("pending_completion", {}).duplicate(true)
	channel_active = false
	channel_ticks = 0
	changed.emit()

func _make_snapshot(checkpoint_id: String, sequence: int) -> Dictionary:
	return {
		"checkpoint_id": checkpoint_id,
		"sequence": sequence,
		"location_id": session.location_id,
		"profile": session.capture_profile_dto(),
	}

func _restore_profile(snapshot: Dictionary, trace_cost: int) -> void:
	session.apply_profile_dto(snapshot["profile"].duplicate(true))
	session.location_id = snapshot["location_id"]
	session.traces = mini(3, session.traces + trace_cost)
	session.hero.set_void_traces(session.traces)
	session.awaiting_return = false
	session.in_combat = false
	if session.traces == 3:
		session.location_id = "lioren"
	session.profile_changed.emit()
	changed.emit()

func _apply_fallback() -> void:
	manual_snapshots.clear()
	first_trace_available = false
	session.apply_profile_dto(first_trace_snapshot["profile"].duplicate(true))
	for item: ItemInstance in session.inventory.items.duplicate():
		var definition: ItemDefinition = session.get_item_definition(item.definition_id)
		if definition.type_id == "echo" and not item.secured:
			session.inventory.remove(item.instance_id, item.quantity)
	session.location_id = first_trace_snapshot["location_id"]
	session.traces = mini(3, session.traces + 2)
	session.hero.set_void_traces(session.traces)
	session.awaiting_return = false
	session.in_combat = false
	if session.traces == 3:
		session.location_id = "lioren"
	session.profile_changed.emit()
	changed.emit()
