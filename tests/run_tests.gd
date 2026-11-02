extends SceneTree
## Runs every test suite headless and exits with 1 if any check fails.
##   godot --headless -s tests/run_tests.gd

const SUITES := [
	preload("res://tests/test_map.gd"),
	preload("res://tests/test_real_maps.gd"),
	preload("res://tests/test_units.gd"),
	preload("res://tests/test_battle.gd"),
	preload("res://tests/test_economy.gd"),
	preload("res://tests/test_v2.gd"),
	preload("res://tests/test_v3.gd"),
	preload("res://tests/test_v4.gd"),
	preload("res://tests/test_v5.gd"),
	preload("res://tests/test_visuals.gd"),
	preload("res://tests/test_polish.gd"),
	preload("res://tests/test_split.gd"),
]

var failures := 0
var checks := 0


func _init() -> void:
	var only := Array(OS.get_cmdline_user_args())
	for suite_script in SUITES:
		if not only.is_empty() and not only.any(func(name): return suite_script.resource_path.contains(name)):
			continue
		if not suite_script.can_instantiate():
			check(false, "%s compiles" % suite_script.resource_path.get_file())
			continue
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
