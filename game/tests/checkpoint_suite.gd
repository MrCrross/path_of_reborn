extends RefCounted

const DomainSuite = preload("res://tests/domain_suite.gd")
const TestContext = DomainSuite.TestContext

func run() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	results.append(_run_case("checkpoint_creation_requires_300_ticks_once", _test_channel_completion))
	results.append(_run_case("movement_combat_and_pursuit_cancel_channel", _test_channel_cancel))
	results.append(_run_case("manual_limit_three_and_explicit_delete", _test_limit))
	results.append(_run_case("snapshots_are_deep_and_default_is_latest", _test_snapshot_and_default))
	results.append(_run_case("restore_removes_selected_and_later_points", _test_restore_selection))
	results.append(_run_case("profile_rolls_back_while_meta_survives", _test_rollback_and_meta))
	results.append(_run_case("post_rollback_victory_grants_ordinary_reward_and_meta_stays_once", _test_repeat_victory))
	results.append(_run_case("first_death_costs_one_then_fallback_costs_two", _test_trace_costs))
	results.append(_run_case("fallback_removes_only_unsecured_echo_crystals", _test_fallback_crystals))
	results.append(_run_case("third_trace_forces_lioren_and_rest_preserves_world", _test_rest))
	results.append(_run_case("completion_is_staged_until_applied_once", _test_completion_staging))
	results.append(_run_case("restore_plan_is_pure_and_matches_apply", _test_restore_plan))
	results.append(_run_case("delete_plan_is_pure_and_matches_apply", _test_delete_plan))
	return results

func _run_case(case_name: String, test: Callable) -> Dictionary:
	var context := TestContext.new()
	test.call(context)
	return {"name": case_name, "checks": context.checks}

func _create_point(session: GameSession) -> void:
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	# Доменный аналог подтверждённой записи: staged-снимок переходит в список.
	# В runtime этот шаг выполняет граница commit в GameRoot через кандидата.
	session.checkpoints.apply_completion()

func _win(session: GameSession, enemy_id: String = "moss_slime") -> void:
	var combat := session.start_combat(enemy_id)
	combat.enemy.current_hp = 1
	combat.advance_ticks(combat.hero.definition.attack_startup_ticks + 1)

func _claim(session: GameSession) -> void:
	DomainSuite.claim_pending(session)

func _test_channel_completion(context: TestContext) -> void:
	var session := GameSession.new()
	context.check(session.checkpoints.begin(), "First channel can begin outside combat")
	context.check(not session.checkpoints.begin(), "Repeated begin cannot restart an active channel")
	session.checkpoints.advance_ticks(299)
	context.check(session.checkpoints.channel_active and session.checkpoints.manual_snapshots.is_empty(), "299 ticks do not create a point")
	session.checkpoints.advance_ticks(1)
	context.check(not session.checkpoints.channel_active and session.checkpoints.manual_snapshots.is_empty(), "300 ticks stage the point without publishing it")
	context.check(session.checkpoints.has_pending_completion(), "Completion is staged for the application commit")
	context.check(not session.checkpoints.begin(), "A new channel cannot start while a completion is staged")
	context.check(session.checkpoints.apply_completion() and session.checkpoints.manual_snapshots.size() == 1, "Applying the staged completion creates one point")
	context.check(not session.checkpoints.apply_completion(), "Applying the staged completion is a single-shot no-op")
	session.checkpoints.advance_ticks(30)
	context.check(session.checkpoints.manual_snapshots.size() == 1, "Ticks after completion cannot create another point")

func _test_channel_cancel(context: TestContext) -> void:
	var session := GameSession.new()
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(20)
	session.is_moving = true
	session.checkpoints.advance_ticks(1)
	context.check(not session.checkpoints.channel_active and session.checkpoints.channel_ticks == 0, "Movement cancels and clears channel progress")
	session.is_moving = false
	session.checkpoints.begin()
	session.in_combat = true
	session.checkpoints.advance_ticks(1)
	context.check(not session.checkpoints.channel_active and session.checkpoints.manual_snapshots.is_empty(), "Combat cancels without creating a point")
	session.in_combat = false
	session.checkpoints.begin()
	session.is_pursued = true
	context.check(not session.checkpoints.begin(), "Pursuit blocks a new channel")
	session.checkpoints.advance_ticks(1)
	context.check(not session.checkpoints.channel_active, "Pursuit cancels an active channel")

func _test_limit(context: TestContext) -> void:
	var session := GameSession.new()
	for _index: int in range(3):
		_create_point(session)
	context.check(session.checkpoints.manual_snapshots.size() == 3, "Three manual points are allowed")
	context.check(not session.checkpoints.begin(), "Fourth point cannot silently overwrite an older one")
	var second_id: String = session.checkpoints.manual_snapshots[1]["checkpoint_id"]
	context.check(session.checkpoints.delete_checkpoint(second_id), "Explicit delete frees a slot")
	_create_point(session)
	context.check(session.checkpoints.manual_snapshots.size() == 3, "A new point is allowed after deletion")
	context.check(session.checkpoints.manual_snapshots.back()["sequence"] == 4, "Sequence remains monotonous after deletion")

func _test_snapshot_and_default(context: TestContext) -> void:
	var session := GameSession.new()
	session.currency = 10
	session.hero.take_damage(3)
	_create_point(session)
	session.currency = 20
	session.hero.restore_full_health()
	_create_point(session)
	session.currency = 999
	session.hero.take_damage(5)
	session.world_flags["tree"] = "changed"
	session.awaiting_return = true
	context.check(session.checkpoints.restore(), "Default restore uses the latest point")
	context.check(session.currency == 20 and session.hero.current_hp == 10, "Latest snapshot restores HP, then one trace clamps it")
	context.check(not session.world_flags.has("tree"), "Later world mutation does not leak into the snapshot")
	context.check(session.checkpoints.manual_snapshots.size() == 1, "Latest point is consumed while the earlier point remains")

func _test_restore_selection(context: TestContext) -> void:
	var session := GameSession.new()
	for amount: int in [10, 20, 30]:
		session.currency = amount
		_create_point(session)
	var first_id: String = session.checkpoints.manual_snapshots[0]["checkpoint_id"]
	var second_id: String = session.checkpoints.manual_snapshots[1]["checkpoint_id"]
	session.awaiting_return = true
	context.check(session.checkpoints.restore(second_id), "An explicit earlier point can be selected")
	context.check(session.currency == 20, "Selected snapshot controls restored state")
	context.check(session.checkpoints.manual_snapshots.size() == 1 and session.checkpoints.manual_snapshots[0]["checkpoint_id"] == first_id, "Earlier point remains; selected and later points disappear")
	context.check(session.traces == 1, "Ordinary manual return adds exactly one trace")

func _test_rollback_and_meta(context: TestContext) -> void:
	var session := GameSession.new()
	var swords: Array[ItemInstance] = session.inventory.add(session.get_item_definition("training_sword"), 1)
	session.inventory.equip(swords[0].instance_id)
	session.currency = 25
	session.quest_flags["quest"] = "started"
	session.npc_flags["npc"] = "present"
	_create_point(session)
	session.inventory.remove(swords[0].instance_id)
	session.currency = 125
	session.quest_flags["quest"] = "complete"
	session.npc_flags.erase("npc")
	session.seen_cue_ids["DIA_TEST"] = true
	session.memory_flags["memory"] = true
	session.echoes = 4
	session.claimed_echo_enemy_ids["moss_slime"] = true
	session.adaptation_nodes["node"] = true
	session.techniques["technique"] = true
	session.enemy_journal["moss_slime"] = true
	session.awaiting_return = true
	session.checkpoints.restore()
	context.check(session.inventory.items.size() == 2 and session.currency == 25, "Sale rollback restores the item and removes sale money")
	context.check(session.inventory.is_equipped(swords[0].instance_id) and session.hero.strength == 5, "Equipment and derived stats are restored together")
	context.check(session.quest_flags["quest"] == "started" and session.npc_flags["npc"] == "present", "Quest and NPC state roll back consistently")
	context.check(session.seen_cue_ids.has("DIA_TEST") and session.memory_flags.has("memory"), "Seen and memory survive the return")
	context.check(session.echoes == 4 and session.claimed_echo_enemy_ids.has("moss_slime"), "Echoes and claimed IDs survive")
	context.check(session.adaptation_nodes.has("node") and session.techniques.has("technique") and session.enemy_journal.has("moss_slime"), "Adaptation, techniques and journal survive")

func _test_repeat_victory(context: TestContext) -> void:
	var session := GameSession.new()
	_create_point(session)
	_win(session)
	context.check(session.hero.level == 1 and session.echoes == 0 and session.inventory.items.size() == 1, "Win alone only creates a pending result: no XP, echo or items yet")
	_claim(session)
	context.check(session.hero.level == 2 and session.echoes == 1, "Claim grants XP and a primary echo exactly once")
	session.awaiting_return = true
	session.checkpoints.restore()
	context.check(session.hero.level == 1 and session.echoes == 1, "Return rolls back claimed XP but preserves claimed echo meta")
	context.check(session.pending_battle_result.is_empty(), "Rollback also clears any unclaimed pending of later runs")
	_win(session)
	context.check(session.start_combat("moss_slime") == null, "Pending result blocks a new encounter until it is claimed")
	_claim(session)
	context.check(session.hero.level == 2 and session.hero.experience == 0, "A new run after rollback grants the ordinary XP package again on claim")
	context.check(session.echoes == 1, "Meta echo still cannot be duplicated")

func _test_trace_costs(context: TestContext) -> void:
	var session := GameSession.new()
	session.awaiting_return = true
	context.check(session.checkpoints.restore("first_trace"), "Available First Trace uses the ordinary return rule")
	context.check(session.traces == 1 and session.hero.max_hp == 10 and session.hero.current_hp == 10, "First death costs one trace and clamps HP to rounded max")
	session.awaiting_return = true
	context.check(session.checkpoints.restore(), "With no available points the original First Trace is the fallback")
	context.check(session.traces == 3 and session.hero.max_hp == 8 and session.hero.current_hp == 8, "Fallback adds two traces in total for this death")
	context.check(session.location_id == "lioren" and not session.checkpoints.begin(), "Third trace forces Lioren and blocks new points")

func _test_fallback_crystals(context: TestContext) -> void:
	var session := GameSession.new()
	var echo: ItemDefinition = session.get_item_definition("echo_crystal")
	var unsecured: Array[ItemInstance] = session.inventory.add(echo, 2, "moss")
	var secured: Array[ItemInstance] = session.inventory.add(echo, 1, "goblin")
	secured[0].secured = true
	session.checkpoints.initialize()
	session.checkpoints.first_trace_available = false
	session.awaiting_return = true
	session.checkpoints.restore()
	context.check(session.traces == 2 and session.hero.max_hp == 9, "Fallback alone costs two traces")
	context.check(session.inventory.get_item(unsecured[0].instance_id) == null, "Unsecured crystals are removed")
	context.check(session.inventory.get_item(secured[0].instance_id) != null, "Secured crystals survive fallback")

func _test_rest(context: TestContext) -> void:
	var session := GameSession.new()
	context.check(not session.checkpoints.rest(), "Rest is refused outside Lioren")
	session.checkpoints.first_trace_available = false
	session.awaiting_return = true
	session.checkpoints.restore()
	session.awaiting_return = true
	session.checkpoints.restore()
	context.check(session.traces == 3 and session.location_id == "lioren", "Two fallback deaths reach the third trace")
	session.currency = 77
	session.world_flags["spent"] = true
	var hp_before: int = session.hero.current_hp
	context.check(session.checkpoints.rest() and session.traces == 0 and session.hero.max_hp == 12, "Lioren rest clears traces and HP penalty")
	context.check(session.currency == 77 and session.world_flags.has("spent") and session.hero.current_hp == hp_before, "Rest does not resurrect resources, world state or free HP")
	context.check(session.checkpoints.begin(), "Creation is available again after rest")

func _test_completion_staging(context: TestContext) -> void:
	var session := GameSession.new()
	_create_point(session)
	var dto: Dictionary = session.checkpoints.capture_dto()
	context.check((dto["pending_completion"] as Dictionary).is_empty() and dto["manual_snapshots"].size() == 1, "Sanity: fixture holds one applied point and no staging")
	session.checkpoints.begin()
	session.checkpoints.advance_ticks(CheckpointService.CHANNEL_TICKS)
	context.check(session.checkpoints.has_pending_completion(), "Second channel stages its completion")
	var staged_id: String = session.checkpoints.pending_completion["checkpoint_id"]
	context.check(staged_id != session.checkpoints.manual_snapshots[0]["checkpoint_id"], "Staged snapshot has its own id")
	var restored := GameSession.new()
	restored.apply_state_dto({
		"meta": {"traces": 0, "echoes": 0, "claimed_echo_enemy_ids": {}, "seen_cue_ids": {}, "memory_flags": {}, "adaptation_nodes": {}, "techniques": {}, "enemy_journal": {}, "trial_echo_claimed": false},
		"profile": session.capture_profile_dto(),
		"checkpoints": session.checkpoints.capture_dto(),
		"location_id": session.location_id,
		"current_enemy_id": "",
		"pending_reward": [],
		"pending_battle_result": {},
		"combat_format": GameSession.COMBAT_FORMAT_AUTO,
		"loot": {"seed": session.loot_seed, "state": str(session.loot_rng.state)},
		"awaiting_return": false,
	})
	context.check(restored.checkpoints.has_pending_completion(), "Staged completion survives a save/load round trip")
	context.check(restored.checkpoints.pending_completion["checkpoint_id"] == staged_id, "Staged id is stable across the round trip")

func _test_restore_plan(context: TestContext) -> void:
	var session := GameSession.new()
	session.currency = 10
	_create_point(session)
	session.currency = 20
	_create_point(session)
	session.currency = 999
	session.awaiting_return = true
	var service: CheckpointService = session.checkpoints
	var second_id: String = service.manual_snapshots[1]["checkpoint_id"]
	var before: String = JSON.stringify(service.capture_dto())
	var plan: Dictionary = service.restore_plan(second_id)
	context.check(not plan.is_empty(), "An explicit earlier point yields a plan")
	context.check(JSON.stringify(service.capture_dto()) == before, "Computing the plan does not mutate the service")
	context.check(plan["trace_cost"] == 1, "Ordinary plan costs one trace")
	service.apply_restore_plan(plan)
	context.check(session.currency == 20, "Applying the plan restores the selected snapshot")
	context.check(service.manual_snapshots.size() == 1, "Applying the plan consumes the selected and later points")
	context.check(session.traces == 1 and not session.awaiting_return, "Applying the plan spends the trace and closes the return")

func _test_delete_plan(context: TestContext) -> void:
	var session := GameSession.new()
	for amount: int in [10, 20, 30]:
		session.currency = amount
		_create_point(session)
	var service: CheckpointService = session.checkpoints
	var middle_id: String = service.manual_snapshots[1]["checkpoint_id"]
	var before: String = JSON.stringify(service.capture_dto())
	var plan: Dictionary = service.delete_plan(middle_id)
	context.check(not plan.is_empty(), "Existing point yields a delete plan")
	context.check(JSON.stringify(service.capture_dto()) == before, "Computing the delete plan does not mutate the service")
	context.check((plan["manual_snapshots"] as Array).size() == 2, "Delete plan keeps the other two points")
	service.apply_delete_plan(plan)
	context.check(service.manual_snapshots.size() == 2, "Applying the delete plan removes exactly one point")
	context.check(service.delete_plan(middle_id).is_empty(), "Deleted id no longer yields a plan")
	context.check(service.restore_plan(middle_id).is_empty(), "Restore plan for unknown id is empty outside mutation")
