class_name TestSuite
extends RefCounted
## Grundlage für Tests: Methoden, die mit „test_“ beginnen, werden von run_tests.gd aufgerufen.

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_equal(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%s – erwartet %s, erhalten %s" % [message, str(expected), str(actual)])


func check_near(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s – erwartet %f ± %f, erhalten %f" % [message, expected, tolerance, actual])
