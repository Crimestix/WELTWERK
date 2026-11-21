extends SceneTree
## Führt alle Tests aus. Aufruf:
##   godot --headless --path D:\WELTWERK --script res://tests/run_tests.gd
## Endet mit Code 1, wenn ein Test fehlschlägt.

const SUITES := [
	"res://tests/test_fixed_random.gd",
	"res://tests/test_heightfield.gd",
	"res://tests/test_style_landscape.gd",
	"res://tests/test_world.gd",
	"res://tests/test_target_landscape.gd",
	"res://tests/test_continents.gd",
	"res://tests/test_shape_edit.gd",
	"res://tests/test_terrain_forms.gd",
	"res://tests/test_landmarks.gd",
]


func _initialize() -> void:
	var passed := 0
	var failed := 0
	for path in SUITES:
		var suite: TestSuite = load(path).new()
		for method in suite.get_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			suite.failures.clear()
			suite.call(name)
			if suite.failures.is_empty():
				passed += 1
			else:
				failed += 1
				printerr("FEHLER %s › %s" % [path.get_file(), name])
				for message in suite.failures:
					printerr("    ", message)
	print("Tests: %d bestanden, %d fehlgeschlagen" % [passed, failed])
	quit(1 if failed > 0 else 0)
