# Headless test batch runner. Attached to TestRunner.tscn (the temporary
# project's main scene). Discovers tests/cases/*.gd, selects the worker's
# batch via CLI args, runs each test_*() method (awaits coroutines), then
# writes a JSON result + coverage snapshot and sets the process exit code.
#
# CLI (arguments passed after `--` to the Godot binary):
#   --batch-idx <int>     which worker batch this process runs (default 0)
#   --batch-count <int>   total number of batches (default 1)
#   --only <substr>       run only case paths containing substr
#   --output <abs path>   where to write the merged worker JSON (required)
extends Node

const CASES_DIR := "res://tests/cases"
const CASE_BASE := "res://tests/runner/TestCase.gd"

var _batch_idx: int = 0
var _batch_count: int = 1
var _only: String = ""
var _output_path: String = ""
var _verbose: bool = false

var _results: Array = []
var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _started_at: int = 0


func _ready() -> void:
	if not _parse_args():
		return
	_started_at = Time.get_ticks_msec()
	if _verbose:
		print("[atomzero-test] batch %d/%d output=%s" % [_batch_idx + 1, _batch_count, _output_path])
	var paths := _discover_cases()
	_apply_batch(paths)
	await _run_batch(paths)
	_finish()


func _parse_args() -> bool:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--batch-idx":
				_batch_idx = int(args[i + 1])
				i += 1
			"--batch-count":
				_batch_count = maxi(int(args[i + 1]), 1)
				i += 1
			"--only":
				_only = args[i + 1]
				i += 1
			"--output":
				_output_path = args[i + 1]
				i += 1
			"--verbose":
				_verbose = true
		i += 1
	if _output_path.is_empty():
		push_error("[atomzero-test] missing --output path")
		return false
	return true


func _discover_cases() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(CASES_DIR)
	if dir == null:
		if _verbose:
			print("[atomzero-test] no cases dir at %s" % CASES_DIR)
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".gd"):
			out.append(CASES_DIR + "/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _apply_batch(paths: Array[String]) -> void:
	if not _only.is_empty():
		var filtered := paths.filter(func(p: String) -> bool: return p.contains(_only))
		paths.clear()
		paths.append_array(filtered)
	if _batch_count <= 1 or paths.is_empty():
		return
	var per := int(ceil(float(paths.size()) / float(_batch_count)))
	var start := _batch_idx * per
	var end := mini(start + per, paths.size())
	for i in range(paths.size() - 1, -1, -1):
		if i < start or i >= end:
			paths.remove_at(i)


func _is_subclass_of(script: Script, base: Script) -> bool:
	if script == null or script == base:
		return false
	var cur: Script = script
	while cur != null:
		if cur == base:
			return true
		cur = cur.get_base_script() as Script
	return false


func _run_batch(paths: Array[String]) -> void:
	var base := load(CASE_BASE)
	for path in paths:
		var script: Script = load(path)
		if script == null:
			_record(path, "", "error", 0, "failed to load script %s" % path)
			continue
		if not _is_subclass_of(script, base):
			_skipped += 1
			if _verbose:
				print("[atomzero-test] skip (not a test case): %s" % path)
			continue
		var tc: Object = script.new(self)
		if tc == null:
			_record(path, "", "error", 0, "failed to instantiate %s" % path)
			continue
		if _verbose:
			print("[atomzero-test] case: %s" % path)
		await _run_case(path, tc)


func _test_methods(script: Script) -> Array[String]:
	var out: Array[String] = []
	for m in script.get_script_method_list():
		var name: String = m.get("name", "")
		if name.begins_with("test_"):
			out.append(name)
	out.sort()
	return out


func _run_case(path: String, tc: Object) -> void:
	var methods := _test_methods(tc.get_script())
	if methods.is_empty():
		_skipped += 1
		return
	if tc.has_method("before_all"):
		tc.call("before_all")
	for m in methods:
		_skip_after_each_failure(tc)
		tc.call("_reset_test_state")
		tc.call("before_each")
		var t0 := Time.get_ticks_msec()
		await tc.call(m)
		var dur := Time.get_ticks_msec() - t0
		var status := "passed"
		var msg := ""
		match bool(tc.call("_has_failed")):
			true:
				status = "failed"
				_failed += 1
			_:
				_passed += 1
		var msgs: Array[String] = tc.call("_collect_failures")
		if not msgs.is_empty():
			msg = " | ".join(msgs)
		tc.call("after_each")
		_record(path, m, status, dur, msg)
	if tc.has_method("after_all"):
		tc.call("after_all")


func _skip_after_each_failure(tc: Object) -> void:
	# Hook point for future xfail/skip logic. Currently a no-op.
	pass


func _record(case_path: String, test: String, status: String, duration_ms: int, message: String) -> void:
	_results.append({
		"case": case_path.get_file(),
		"test": test,
		"status": status,
		"duration_ms": duration_ms,
		"message": message,
	})


func notify_failure(_tc: Object, _msg: String) -> void:
	pass


func _finish() -> void:
	var hub := get_node_or_null("/root/CoverageHub")
	var doc := {
		"batch_idx": _batch_idx,
		"summary": {
			"passed": _passed,
			"failed": _failed,
			"skipped": _skipped,
			"total": _passed + _failed + _skipped,
			"duration_ms": Time.get_ticks_msec() - _started_at,
		},
		"results": _results,
		"coverage": hub.snapshot() if hub != null else {},
		"engine": str(Engine.get_version_info().get("string", "")),
	}
	var f := FileAccess.open(_output_path, FileAccess.WRITE)
	if f == null:
		push_error("[atomzero-test] cannot write %s" % _output_path)
		get_tree().quit(2)
		return
	f.store_string(JSON.stringify(doc, "\t", false))
	f.close()
	print("[atomzero-test] batch %d: passed=%d failed=%d skipped=%d" % [_batch_idx, _passed, _failed, _skipped])
	get_tree().quit(1 if _failed > 0 else 0)