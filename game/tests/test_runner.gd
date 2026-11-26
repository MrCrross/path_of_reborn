extends SceneTree

const DomainSuite = preload("res://tests/domain_suite.gd")
const CombatSuite = preload("res://tests/combat_suite.gd")
const InventorySuite = preload("res://tests/inventory_suite.gd")
const CheckpointSuite = preload("res://tests/checkpoint_suite.gd")
const SaveSuite = preload("res://tests/save_suite.gd")
const DialogueSuite = preload("res://tests/dialogue_suite.gd")
const UxSuite = preload("res://tests/ux_suite.gd")
const GroveSuite = preload("res://tests/grove_suite.gd")
const HollowSuite = preload("res://tests/hollow_suite.gd")
const EXPECTED_TEST_CASES: int = 106

var _passed: int = 0
var _failed: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var results: Array[Dictionary] = []
	results.append_array(DomainSuite.new().run())
	results.append_array(CombatSuite.new().run())
	results.append_array(InventorySuite.new().run())
	results.append_array(CheckpointSuite.new().run())
	results.append_array(SaveSuite.new().run())
	results.append_array(DialogueSuite.new().run())
	results.append_array(UxSuite.new().run())
	results.append_array(GroveSuite.new().run())
	results.append_array(HollowSuite.new().run())
	for result: Dictionary in results:
		_report_case(result)
	var unfinished: int = maxi(0, EXPECTED_TEST_CASES - results.size())
	for index: int in range(results.size(), EXPECTED_TEST_CASES):
		print("FAIL unfinished_test_case_%d: no result returned" % (index + 1))
	print("RESULT: passed=%d failed=%d unfinished=%d" % [_passed, _failed, unfinished])
	quit(1 if _failed > 0 or unfinished > 0 else 0)

func _report_case(result: Dictionary) -> void:
	var checks: Array = result["checks"]
	var failed_messages: Array[String] = []
	for check: Dictionary in checks:
		if not check["passed"]:
			failed_messages.append(check["message"])
	if checks.is_empty():
		failed_messages.append("No checks completed")
	if failed_messages.is_empty():
		_passed += 1
		print("PASS %s (%d checks)" % [result["name"], checks.size()])
		return
	_failed += 1
	for message: String in failed_messages:
		print("FAIL %s: %s" % [result["name"], message])
