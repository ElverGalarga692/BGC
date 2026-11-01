extends SceneTree
## Ejecuta todos los tests de res://tests/test_*.gd.
## Uso: godot --headless --path . -s res://tests/run_tests.gd

const TEST_DIR := "res://tests"


func _init() -> void:
	var total := 0
	var failed := 0
	for file in _test_files():
		var script: Script = load("%s/%s" % [TEST_DIR, file])
		if script == null or not script.can_instantiate():
			print("ERROR  no se pudo cargar %s" % file)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.call(name)
			total += 1
			if test.failures.is_empty():
				print("  ok   %s::%s" % [file, name])
			else:
				failed += 1
				print("  FAIL %s::%s" % [file, name])
				for f in test.failures:
					print("         %s" % f)
	print("\n%d tests, %d fallos" % [total, failed])
	quit(1 if failed > 0 else 0)


func _test_files() -> Array[String]:
	var files: Array[String] = []
	for file in DirAccess.get_files_at(TEST_DIR):
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			files.append(file)
	files.sort()
	return files
