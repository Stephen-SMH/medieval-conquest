extends SceneTree
## Runs every test suite headless and exits with 1 if any check fails.
##   godot --headless -s tests/run_tests.gd

const SUITES := [
	preload("res://tests/test_map.gd"),
	preload("res://tests/test_units.gd"),
	preload("res://tests/test_battle.gd"),
	preload("res://tests/test_economy.gd"),
	preload("res://tests/test_v2.gd"),
]

var failures := 0
var checks := 0


func _init() -> void:
	for suite_script in SUITES:
		var suite = suite_script.new()
		print("\n== %s" % suite_script.resource_path.get_file())
		suite.run(self)
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(passed: bool, description: String) -> void:
	checks += 1
	if passed:
		print("  PASS  " + description)
	else:
		failures += 1
		print("  FAIL  " + description)
