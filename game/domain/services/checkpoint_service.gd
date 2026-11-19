class_name CheckpointService
extends RefCounted

signal changed

const CHANNEL_TICKS: int = 300
const MANUAL_LIMIT: int = 3

var manual_snapshots: Array[Dictionary] = []
var first_trace_snapshot: Dictionary = {}
var first_trace_available: bool = true
var channel_active: bool = false
var channel_ticks: int = 0

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
	first_trace_available = true
	first_trace_snapshot = _make_snapshot("first_trace", 0)
	changed.emit()

func can_begin() -> bool:
	return (
		not channel_active
		and manual_snapshots.size() < MANUAL_LIMIT
		and session.traces < 3
		and not session.in_combat
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
			manual_snapshots.append(_make_snapshot("checkpoint_%06d" % _sequence, _sequence))
			changed.emit()

func delete_checkpoint(checkpoint_id: String) -> bool:
	for index: int in range(manual_snapshots.size()):
		if manual_snapshots[index]["checkpoint_id"] == checkpoint_id:
			manual_snapshots.remove_at(index)
			changed.emit()
			return true
	return false

func restore(checkpoint_id: String = "") -> bool:
	if not session.awaiting_return:
		return false
	var selected_id: String = checkpoint_id
	if selected_id.is_empty():
		if not manual_snapshots.is_empty():
			selected_id = manual_snapshots.back()["checkpoint_id"]
		elif first_trace_available:
			selected_id = "first_trace"
		else:
			return _restore_fallback()
	if selected_id == "first_trace" and first_trace_available:
		var snapshot: Dictionary = first_trace_snapshot.duplicate(true)
		manual_snapshots.clear()
		first_trace_available = false
		_restore_profile(snapshot, 1)
		return true
	for index: int in range(manual_snapshots.size()):
		if manual_snapshots[index]["checkpoint_id"] == selected_id:
			var snapshot: Dictionary = manual_snapshots[index].duplicate(true)
			manual_snapshots = manual_snapshots.slice(0, index)
			_restore_profile(snapshot, 1)
			return true
	return false

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
	}

func apply_dto(dto: Dictionary) -> void:
	manual_snapshots.assign(dto.get("manual_snapshots", []).duplicate(true))
	first_trace_snapshot = dto.get("first_trace_snapshot", {}).duplicate(true)
	first_trace_available = bool(dto.get("first_trace_available", true))
	_sequence = maxi(0, int(dto.get("sequence", 0)))
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

func _restore_fallback() -> bool:
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
	return true
