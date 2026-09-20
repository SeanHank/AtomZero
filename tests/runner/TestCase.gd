# pytest-style assertion/hook base class for AtomZero functional tests.
# A test case file must extend this script and define test_*() methods.
extends RefCounted

var runner: Object = null
var _failed: bool = false
var _fail_messages: Array[String] = []


func _init(p_runner: Object = null) -> void:
	runner = p_runner


# ===== pytest-like hooks (overridable) =====
func before_all() -> void:
	pass


func after_all() -> void:
	pass


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func _reset_test_state() -> void:
	_failed = false
	_fail_messages.clear()


func _has_failed() -> bool:
	return _failed


func _collect_failures() -> Array[String]:
	return _fail_messages


# ===== failure recording =====
func fail(msg: String) -> void:
	_failed = true
	_fail_messages.append(msg)
	if runner != null:
		runner.notify_failure(self, msg)


# ===== file helpers for fixture setup (writable res:// inside the test copy) =====
func ensure_dir(path: String) -> void:
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK and not DirAccess.dir_exists_absolute(path):
		fail("ensure_dir failed for %s (err=%s)" % [path, err])


func write_text_file(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		fail("cannot write %s" % path)
		return
	f.store_string(content)
	f.close()


func read_text_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		fail("cannot read %s" % path)
		return ""
	var content := f.get_as_text()
	f.close()
	return content


func wipe_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		DirAccess.remove_absolute(path)


func await_frame() -> void:
	var st := Engine.get_main_loop() as SceneTree
	if st != null:
		await st.process_frame


# ===== assertions =====
func assert_true(value: bool, msg: String = "expected value to be true") -> void:
	if not value:
		fail(msg)


func assert_false(value: bool, msg: String = "expected value to be false") -> void:
	if value:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		var m := "assert_eq failed: expected=%s actual=%s" % [str(expected), str(actual)]
		if not msg.is_empty():
			m += " | " + msg
		fail(m)


func assert_ne(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual == expected:
		var m := "assert_ne failed: expected=%s actual=%s" % [str(expected), str(actual)]
		if not msg.is_empty():
			m += " | " + msg
		fail(m)


func assert_null(value: Variant, msg: String = "expected null") -> void:
	if value != null:
		fail(msg + " (got %s)" % str(value))


func assert_not_null(value: Variant, msg: String = "expected non-null") -> void:
	if value == null:
		fail(msg)


func assert_almost_eq(actual: float, expected: float, epsilon: float = 0.0001) -> void:
	if absf(actual - expected) > epsilon:
		fail("assert_almost_eq failed: expected=%f actual=%f (eps=%f)" % [expected, actual, epsilon])


func assert_contains(container: Array, value: Variant) -> void:
	if not container.has(value):
		fail("assert_contains failed: array does not contain %s" % str(value))


func assert_not_contains(container: Array, value: Variant) -> void:
	if container.has(value):
		fail("assert_not_contains failed: array contains %s" % str(value))


func assert_has_key(d: Dictionary, key: Variant) -> void:
	if not d.has(key):
		fail("assert_has_key failed: dict has no key %s (keys=%s)" % [str(key), str(d.keys())])


func assert_empty(container) -> void:
	if container.size() != 0:
		fail("assert_empty failed: size=%d" % container.size())