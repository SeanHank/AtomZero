# Autoload in the throwaway instrumented test copy. The instrumentation step
# inserts `CoverageHub.hit("res://core/<file>", "<func>")` probes after every
# function signature; each probe records one hit per function per call. The
# orchestrator merges the per-worker snapshots and compares them against the
# full function inventory to enforce the coverage threshold.
extends Node

var _data: Dictionary = {}


func hit(path: String, func_name: String) -> void:
	if not _data.has(path):
		_data[path] = {}
	var hits: Dictionary = _data[path]
	hits[func_name] = int(hits.get(func_name, 0)) + 1


func snapshot() -> Dictionary:
	return _data.duplicate(true)


func clear() -> void:
	_data.clear()


func count_paths() -> int:
	return _data.size()