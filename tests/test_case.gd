class_name TestCase
extends RefCounted
## Base de los tests. Cada método que empieza por "test_" es un test.

var failures: Array[String] = []


func assert_true(value: bool, message: String = "") -> void:
	if not value:
		_fail("se esperaba true. %s" % message)


func assert_false(value: bool, message: String = "") -> void:
	if value:
		_fail("se esperaba false. %s" % message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("se esperaba %s, se obtuvo %s. %s" % [var_to_str(expected), var_to_str(actual), message])


func assert_ne(actual: Variant, not_expected: Variant, message: String = "") -> void:
	if typeof(actual) == typeof(not_expected) and actual == not_expected:
		_fail("no se esperaba %s. %s" % [var_to_str(not_expected), message])


func _fail(message: String) -> void:
	failures.append(message)
