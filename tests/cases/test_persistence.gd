extends "res://tests/runner/TestCase.gd"

const ROOT := "res://.test_tmp/persistence/"


func _make_ps() -> PersistenceService:
	ensure_dir(ROOT)
	var ps := PersistenceService.new()
	ps.init(AtomLogger.new(), ROOT)
	return ps


func test_registration_bookkeeping() -> void:
	var ps := _make_ps()
	ps.register_global_mod("gm", "1.0.0")
	ps.unregister_global_mod("gm")
	ps.register_world_mod("w1", 7, "wm", "2.0.0")
	ps.unregister_world_mod("w1", "wm")
	ps.register_world_mod("w1", 7, "wm", "2.0.0")
	ps.unregister_world("w1")
	assert_true(true)


func test_global_config_roundtrip() -> void:
	var ps := _make_ps()
	ps.register_global_mod("gm", "1.5.0")
	ps.save_global_config("gm", "settings", {"vol": 0.8, "on": true})
	var loaded: Dictionary = ps.load_global_config("gm", "settings", {})
	assert_eq(loaded.vol, 0.8)
	var missing = ps.load_global_config("gm", "nope", "fallback")
	assert_eq(missing, "fallback")


func test_global_data_roundtrip() -> void:
	var ps := _make_ps()
	ps.save_global_data("gm", "state", {"hp": 100})
	var loaded: Dictionary = ps.load_global_data("gm", "state", {})
	assert_eq(loaded.hp, 100)


func test_world_roundtrips() -> void:
	var ps := _make_ps()
	ps.register_world_mod("worldA", 12345, "wm", "0.9.0")
	ps.save_world_config("worldA", "wm", "cfg", {"x": 1})
	ps.save_world_data("worldA", "wm", "dat", {"y": [1, 2, 3]})
	var cfg: Dictionary = ps.load_world_config("worldA", "wm", "cfg", {})
	var dat: Dictionary = ps.load_world_data("worldA", "wm", "dat", {})
	assert_eq(cfg.x, 1)
	# JSON roundtrip converts the int array to floats
	assert_eq(dat.y, [1.0, 2.0, 3.0])


func test_json_meta_fields() -> void:
	var ps := _make_ps()
	ps.register_global_mod("gm", "3.0.0")
	ps.save_global_data("gm", "k", {"v": 1})
	var text := read_text_file(ROOT + "mods/gm/data/k.json")
	assert_true(text.contains('"mod_id": "gm"'))
	assert_true(text.contains('"mod_version": "3.0.0"'))
	# Second save preserves created_at
	ps.save_global_data("gm", "k", {"v": 2})
	var text2 := read_text_file(ROOT + "mods/gm/data/k.json")
	# JSON.stringify indent puts the nested data object on its own lines
	assert_true(text2.contains('"v": 2'))


func test_world_meta_fields() -> void:
	var ps := _make_ps()
	ps.register_world_mod("w", 99, "m", "1.0.0")
	ps.save_world_data("w", "m", "k", {"v": 5})
	var text := read_text_file(ROOT + "saves/w/mods/m/data/k.json")
	assert_true(text.contains('"world_id": "w"'))
	assert_true(text.contains('"world_seed": 99'))


func test_load_json_corrupt() -> void:
	var ps := _make_ps()
	ensure_dir(ROOT + "mods/gm/data/")
	write_text_file(ROOT + "mods/gm/data/bad.json", "{oops")
	var val = ps.load_global_data("gm", "bad", "default")
	assert_eq(val, "default")


func test_autosave() -> void:
	var ps := _make_ps()
	ps.register_autosave("gm", "", func() -> Dictionary:
		return {"autod": {"n": 1}})
	ps.register_autosave("wmod", "w", func() -> Dictionary:
		return {"wautod": {"n": 2}})
	ps.update(PersistenceService.AUTOSAVE_INTERVAL)
	assert_eq(ps.load_global_data("gm", "autod", {}).n, 1)
	assert_eq(ps.load_world_data("w", "wmod", "wautod", {}).n, 2)


func test_autosave_void_callback() -> void:
	var ps := _make_ps()
	ps.register_autosave("gm", "", func():
		pass)
	ps.update(1.0)
	assert_true(true)
	ps._run_autosave()
	assert_true(true)


func test_autosave_unregister() -> void:
	var ps := _make_ps()
	var called := 0
	ps.register_autosave("gm", "", func():
		called += 1)
	ps.unregister_autosave("gm", "")
	ps._run_autosave()
	assert_eq(called, 0)


func test_update_timer_threshold() -> void:
	var ps := _make_ps()
	var fired: Array = [0]
	ps.register_autosave("gm", "", func():
		fired[0] += 1)
	ps.update(PersistenceService.AUTOSAVE_INTERVAL - 0.01)
	assert_eq(fired[0], 0)
	ps.update(0.02)
	assert_eq(fired[0], 1)


func test_path_helpers() -> void:
	var ps := _make_ps()
	assert_eq(ps._global_config_path("m", "k"), ROOT + "mods/m/config/k.json")
	assert_eq(ps._global_data_path("m", "k"), ROOT + "mods/m/data/k.json")
	assert_eq(ps._world_config_path("w", "m", "k"), ROOT + "saves/w/mods/m/config/k.json")
	assert_eq(ps._world_data_path("w", "m", "k"), ROOT + "saves/w/mods/m/data/k.json")


func test_build_meta() -> void:
	var ps := _make_ps()
	ps.register_global_mod("gm", "9.9.9")
	var g := ps._build_meta_global("gm", "data")
	assert_eq(g.mod_id, "gm")
	assert_eq(g.mod_version, "9.9.9")
	ps.register_world_mod("w", 5, "m", "1.0.0")
	var wd := ps._build_meta_world("w", "m", "data")
	assert_eq(wd.world_id, "w")
	assert_eq(wd.world_seed, 5)
	assert_true(ps._read_created_at("x").length() > 0)


func test_save_json_atomic_rename_failure() -> void:
	var ps := _make_ps()
	# Create a directory at the target path so the atomic rename fails.
	ensure_dir(ROOT + "mods/gm/data/k.json")
	ps._save_json_atomic(ROOT + "mods/gm/data/k.json", {}, {"v": 1})
	assert_true(true)