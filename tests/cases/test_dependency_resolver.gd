extends "res://tests/runner/TestCase.gd"


func _desc(mod_id: String, game_version: String = "^2026.9.0", priority: int = 1000,
		deps: Array = [], before: Array = [], after: Array = []) -> ModDescriptor:
	return ModDescriptor.from_dict({
		"mod_id": mod_id,
		"name": mod_id,
		"version": "1.0.0",
		"game_version": game_version,
		"mod_type": "global",
		"entry": "m.gd",
		"dependencies": deps,
		"load_order": {"priority": priority, "load_before": before, "load_after": after},
	})


func test_init() -> void:
	var r := DependencyResolver.new()
	r.init(null)
	assert_not_null(r)


func test_check_game_version_alpha_beta_skips() -> void:
	var r := DependencyResolver.new()
	assert_false(r.check_game_version("^2026.9.0", "2026.6.30"))
	assert_true(r.check_game_version("^2026.9.0", "2026.9.0"))
	assert_true(r.check_game_version(">=9.0.0", "Alpha 0.1"))
	assert_true(r.check_game_version(">=9.0.0", "Beta 1.0"))


func test_resolve_simple_order_by_priority() -> void:
	var r := DependencyResolver.new()
	var a := _desc("a", "*", 100)
	var b := _desc("b", "*", 10)
	var c := _desc("c", "*", 50)
	var out := r.resolve([b, c, a])
	assert_eq(out.failed.size(), 0)
	var ids: Array[String] = []
	for d in out.resolved:
		ids.append(d.mod_id)
	assert_eq(ids, ["b", "c", "a"])


func test_resolve_dependency_edge() -> void:
	var r := DependencyResolver.new()
	var a := _desc("a", "*", 500, [{ "id": "top", "version": "*" }])
	var top := _desc("top", "*", 200)
	var out := r.resolve([top, a])
	var ids: Array[String] = []
	for d in out.resolved:
		ids.append(d.mod_id)
	assert_eq(ids, ["top", "a"])


func test_resolve_load_after_and_before() -> void:
	var r := DependencyResolver.new()
	var a := _desc("a", "*", 100, [], [], ["b"])
	var b := _desc("b", "*", 100, [], ["a"], [])
	var out := r.resolve([a, b])
	var ids: Array[String] = []
	for d in out.resolved:
		ids.append(d.mod_id)
	assert_eq(ids, ["b", "a"])


func test_resolve_invalid_meta() -> void:
	var r := DependencyResolver.new()
	var bad := _desc("bad", "*")
	bad.valid = false
	bad.error_msg = "broken"
	var out := r.resolve([bad])
	assert_eq(out.resolved.size(), 0)
	assert_eq(out.failed.size(), 1)
	assert_eq(bad.status, GameState.LOAD_FAILED)
	assert_true(String(out.failed[0].reason).contains("INVALID_META"))


func test_resolve_invalid_version() -> void:
	var r := DependencyResolver.new()
	var old := _desc("old", ">=2030.0.0")
	var out := r.resolve([old])
	assert_eq(out.failed.size(), 1)
	assert_eq(old.status, GameState.INVALID_VERSION)
	assert_true(String(out.failed[0].reason).contains("INVALID_VERSION"))


func test_resolve_missing_dependency() -> void:
	var r := DependencyResolver.new()
	var need := _desc("need", "*", 100, [{ "id": "ghost", "version": "1.0.0" }])
	var out := r.resolve([need])
	assert_eq(out.failed.size(), 1)
	assert_eq(need.status, GameState.MISSING_DEP)
	assert_true(String(out.failed[0].reason).contains("MISSING_DEP: ghost"))


func test_resolve_dep_version_not_satisfied() -> void:
	var r := DependencyResolver.new()
	var prov := _desc("prov", "*", 100, [])
	prov.version = "0.5.0"
	var want := _desc("want", "*", 100, [{ "id": "prov", "version": ">=2.0.0" }])
	var out := r.resolve([prov, want])
	assert_eq(out.failed.size(), 1)
	assert_eq(want.status, GameState.MISSING_DEP)


func test_resolve_cycle() -> void:
	var r := DependencyResolver.new()
	var x := _desc("x", "*", 100, [{ "id": "y", "version": "*" }])
	var y := _desc("y", "*", 100, [{ "id": "x", "version": "*" }])
	var out := r.resolve([x, y])
	assert_eq(out.resolved.size(), 0)
	assert_eq(out.failed.size(), 2)
	assert_eq(x.status, GameState.CIRCULAR_DEP)
	assert_eq(y.status, GameState.CIRCULAR_DEP)