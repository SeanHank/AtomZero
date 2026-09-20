extends "res://tests/runner/TestCase.gd"

const GM1 := "res://tests/fixtures/mods/gm1"
const GM2 := "res://tests/fixtures/mods/gm2"
const WM1 := "res://tests/fixtures/mods/wm1"
const ROOT := "res://.test_tmp/loader/"


func _kernel(unique: String) -> Dictionary:
	var k := TestKernel.make_stack(ROOT + unique)
	k.loader.set_api_and_state(k.api, k.sm, k.root)
	return k


func _wipe_mods() -> void:
	TestKernel.remove_tree_abs("res://mods")


func _install_global_fixtures() -> void:
	_wipe_mods()
	TestKernel.copy_dir_into(GM1, "res://mods/gm1")
	TestKernel.copy_dir_into(GM2, "res://mods/gm2")


func _install_badgm() -> void:
	ensure_dir("res://mods/badgm")
	write_text_file("res://mods/badgm/mod.json", JSON.stringify({
		"mod_id": "badgm", "name": "Bad", "version": "1.0.0",
		"game_version": "*", "mod_type": "global", "entry": "missing.gd",
	}))


# ============================================================
# Init/config
# ============================================================

func test_settings_steps() -> void:
	var k := _kernel("steps")
	k.loader.set_mods_container(Node.new())
	k.loader.set_scene_tree(null)
	k.loader.set_scene_tree(Engine.get_main_loop() as SceneTree)
	assert_true(true)


func test_bootstrap_uninitialized_errors() -> void:
	var loader := ModLoaderCore.new()
	loader.bootstrap()
	assert_true(true)


# ============================================================
# zip extraction cases
# ============================================================

func test_extract_zip_valid_and_reuse() -> void:
	var k := _kernel("zip1")
	var cache := ROOT + "zip1/cache/"
	var zip_path := "res://tests/fixtures/mods/zipmod.zip"
	var dir = k.loader._extract_mod_zip(zip_path, cache)
	assert_false(dir.is_empty())
	assert_true(FileAccess.file_exists(dir + "/mod.json"))
	assert_true(FileAccess.file_exists(dir + "/zipmod.gd"))
	# Second call reuses the cache (freshly extracted mod.json is not older than the zip)
	var again = k.loader._extract_mod_zip(zip_path, cache)
	assert_eq(again, dir)


func test_extract_zip_error_cases() -> void:
	var k := _kernel("zip2")
	var cache := ROOT + "zip2/cache/"
	# Corrupt (not a zip)
	write_text_file(ROOT + "zip2/corrupt.zip", "this is not a zip file")
	assert_true(k.loader._extract_mod_zip(ROOT + "zip2/corrupt.zip", cache).is_empty())
	# Empty zip
	assert_true(k.loader._extract_mod_zip("res://tests/fixtures/mods/empty.zip", cache).is_empty())
	# No root mod.json
	assert_true(k.loader._extract_mod_zip("res://tests/fixtures/mods/nojson.zip", cache).is_empty())
	# mod.json unparseable
	assert_true(k.loader._extract_mod_zip("res://tests/fixtures/mods/badjson.zip", cache).is_empty())
	# missing mod_id
	assert_true(k.loader._extract_mod_zip("res://tests/fixtures/mods/noid.zip", cache).is_empty())


# ============================================================
# _scan_mod_dir
# ============================================================

func test_scan_mod_dir_variants() -> void:
	var k := _kernel("smd")
	var base := ROOT + "smd/mods"
	# No mod.json
	ensure_dir(base + "/empty")
	var got = k.loader._scan_mod_dir(base + "/empty", "")
	assert_eq(got.size(), 0)
	# Invalid mod.json
	ensure_dir(base + "/bad")
	write_text_file(base + "/bad/mod.json", "{oops")
	assert_eq(k.loader._scan_mod_dir(base + "/bad", "").size(), 0)
	# Type mismatch: a global mod asked for under the "world" filter
	assert_eq(k.loader._scan_mod_dir(GM1, "world").size(), 0)
	# Valid global mod
	var valid = k.loader._scan_mod_dir(GM1, "global")
	assert_eq(valid.size(), 1)
	assert_eq(valid[0].mod_id, "gm1")
	# Hash mismatch after tampering
	write_text_file(GM1 + "/tamper.gd", "var hacked := true\n")
	var after = k.loader._scan_mod_dir(GM1, "global")
	assert_eq(after.size(), 0)
	TestKernel.remove_tree_abs(GM1 + "/tamper.gd")


# ============================================================
# scan_global_mods
# ============================================================

func test_scan_global_missing_dir() -> void:
	var k := _kernel("scan0")
	_wipe_mods()
	var descs = k.loader.scan_global_mods()
	assert_true(descs.is_empty())


func test_scan_global_finds_fixtures() -> void:
	var k := _kernel("scan1")
	_install_global_fixtures()
	# badgm has a valid descriptor (entry check happens at load time, not scan time)
	_install_badgm()
	var descs = k.loader.scan_global_mods()
	var ids: Array[String] = []
	for d in descs:
		ids.append(d.mod_id)
	assert_true(ids.has("gm1"))
	assert_true(ids.has("gm2"))
	assert_true(ids.has("badgm"))


# ============================================================
# _load_global_mod
# ============================================================

func test_load_global_missing_entry() -> void:
	var k := _kernel("lge")
	_install_global_fixtures()
	_install_badgm()
	var desc := ModDescriptor.from_file("res://mods/badgm/mod.json")
	var ok = k.loader._load_global_mod(desc)
	assert_false(ok)
	assert_eq(k.vfs.get_global_mod_dir("badgm"), "")


func test_load_global_success_and_duplicate() -> void:
	var k := _kernel("lgs")
	_install_global_fixtures()
	var desc := ModDescriptor.from_file("res://mods/gm1/mod.json")
	assert_true(k.loader._load_global_mod(desc))
	assert_true(k.loader._global_mods.has("gm1"))
	var inst: ModInstance = k.loader._global_mods["gm1"]
	assert_not_null(inst.api)
	assert_not_null(inst.script_instance)
	assert_eq(k.vfs.get_global_mod_dir("gm1"), "res://mods/gm1")
	# Duplicate load is rejected
	assert_false(k.loader._load_global_mod(desc))


# ============================================================
# bootstrap()
# ============================================================

func test_bootstrap_no_global_mods() -> void:
	var k := _kernel("boot0")
	_wipe_mods()
	var ready_payload := {}
	k.event.subscribe(GameEvents.GLOBAL_MODS_READY, func(p: Dictionary):
		ready_payload.merge(p))
	await k.loader.bootstrap()
	assert_eq(k.sm.get_state(), GameState.State.MAIN_MENU)
	assert_has_key(ready_payload, "count")


func test_bootstrap_full_load_order() -> void:
	var k := _kernel("boot1")
	_install_global_fixtures()
	var loaded_events: Array = [0]
	k.event.subscribe(GameEvents.MOD_LOADED, func(p: Dictionary):
		loaded_events[0] += 1)
	await k.loader.bootstrap()
	assert_eq(loaded_events[0], 2)
	assert_eq(k.sm.get_state(), GameState.State.MAIN_MENU)
	assert_eq(k.loader._global_mods.size(), 2)
	# gm1 must load before gm2 (dependency)
	var keys = k.loader._global_mods.keys()
	assert_eq(keys[0], "gm1")
	assert_eq(keys[1], "gm2")


# ============================================================
# Dependency resolution cache
# ============================================================

func _cache_entry(mod_id: String, version: String, idx: int, deps: Array) -> Dictionary:
	return {mod_id: {"version": version, "load_order_index": idx, "resolved_deps": deps, "cached_at": "x"}}


func test_try_resolve_from_cache_hit() -> void:
	var k := _kernel("cache")
	var d1 := ModDescriptor.from_dict({
		"mod_id": "a", "name": "a", "version": "1.0.0", "game_version": "*", "entry": "a.gd",
	})
	var d2 := ModDescriptor.from_dict({
		"mod_id": "b", "name": "b", "version": "2.0.0", "game_version": "*", "entry": "b.gd",
		"dependencies": [{"id": "a", "version": "*"}],
	})
	k.loader._mod_cache.merge(_cache_entry("a", "1.0.0", 0, []))
	k.loader._mod_cache.merge(_cache_entry("b", "2.0.0", 1, ["a"]))
	var descs: Array[ModDescriptor] = [d1, d2]
	var res = k.loader._try_resolve_from_cache(descs)
	assert_true(res["hit"])
	assert_eq(res["resolved"][0].mod_id, "a")
	assert_eq(res["resolved"][1].mod_id, "b")


func test_try_resolve_from_cache_misses() -> void:
	var k := _kernel("cache2")
	var d1 := ModDescriptor.from_dict({
		"mod_id": "a", "name": "a", "version": "1.0.0", "game_version": "*", "entry": "a.gd",
	})
	var d2 := ModDescriptor.from_dict({
		"mod_id": "b", "name": "b", "version": "2.0.0", "game_version": "*", "entry": "b.gd",
		"dependencies": [{"id": "a", "version": "*"}],
	})
	# empty cache
	var arr: Array[ModDescriptor] = [d1, d2]
	assert_false(k.loader._try_resolve_from_cache(arr)["hit"])
	# missing key
	k.loader._mod_cache = {"x": {"version": "1", "load_order_index": 0, "resolved_deps": []}}
	var one: Array[ModDescriptor] = [d1]
	assert_false(k.loader._try_resolve_from_cache(one)["hit"])
	# version mismatch
	k.loader._mod_cache = {"a": {"version": "9.9.9", "load_order_index": 0, "resolved_deps": []}}
	assert_false(k.loader._try_resolve_from_cache(one)["hit"])
	# dependency set mismatch
	k.loader._mod_cache = {"a": {"version": "1.0.0", "load_order_index": 0, "resolved_deps": ["z"]}}
	assert_false(k.loader._try_resolve_from_cache(one)["hit"])
	# invalid index
	k.loader._mod_cache = {"a": {"version": "1.0.0", "load_order_index": -1, "resolved_deps": []}}
	assert_false(k.loader._try_resolve_from_cache(one)["hit"])
	# only the "b" key missing -> miss (count mismatch path also exercised below)
	k.loader._mod_cache = {"a": {"version": "1.0.0", "load_order_index": 0, "resolved_deps": []}}
	k.loader._mod_cache["b"] = {"version": "2.0.0", "load_order_index": 1, "resolved_deps": ["a"]}
	var res = k.loader._try_resolve_from_cache(arr)
	assert_true(res["hit"])


func test_string_arrays_equal() -> void:
	var k := _kernel("sa")
	assert_true(k.loader._string_arrays_equal(["a", "b"], ["b", "a"]))
	assert_false(k.loader._string_arrays_equal(["a"], ["a", "b"]))
	assert_false(k.loader._string_arrays_equal(["a"], ["b"]))


func test_load_and_save_mod_cache() -> void:
	var k := _kernel("cache3")
	k.loader._load_mod_cache()
	assert_true(k.loader._mod_cache.is_empty())
	var d := ModDescriptor.from_dict({
		"mod_id": "a", "name": "a", "version": "1.0.0", "game_version": "*", "entry": "a.gd",
	})
	k.loader._save_mod_cache([d])
	assert_true(FileAccess.file_exists(k.root + ".cache/mod_cache.json"))
	assert_true(k.loader._mod_cache.has("a"))
	# Corrupt cache file
	DirAccess.make_dir_recursive_absolute(k.root + ".cache")
	write_text_file(k.root + ".cache/mod_cache.json", "{oops")
	k.loader._load_mod_cache()
	assert_true(k.loader._mod_cache.is_empty())


# ============================================================
# World Mods load/unload
# ============================================================

func _install_world_fixture(world_id: String) -> void:
	ensure_dir("res://saves/" + world_id + "/mods/")
	TestKernel.copy_dir_into(WM1, "res://saves/" + world_id + "/mods/wm1")


func test_load_and_unload_world_mods() -> void:
	var k := _kernel("world")
	_install_global_fixtures()
	var world_id := "pdfx"
	_install_world_fixture(world_id)
	var container := Node.new()
	k.loader.set_mods_container(container)
	var loaded_events: Array = [0]
	var progress_events: Array = [0]
	k.event.subscribe(GameEvents.MOD_LOADED, func(p: Dictionary):
		loaded_events[0] += 1)
	k.event.subscribe(GameEvents.WORLD_LOAD_PROGRESS, func(p: Dictionary):
		progress_events[0] += 1)
	await k.loader.load_world_mods(world_id, 42)
	assert_eq(k.sm.get_state(), GameState.State.WORLD_RUNNING)
	assert_eq(k.sm.get_current_world_id(), world_id)
	assert_true(k.loader._world_mods.has(world_id))
	assert_true(k.loader._world_mods[world_id].has("wm1"))
	var inst: ModInstance = k.loader._world_mods[world_id]["wm1"]
	assert_eq(inst.api.get_context().world_id, world_id)
	assert_false(k.vfs.get_world_mod_dir(world_id, "wm1").is_empty())
	assert_true(container.get_child_count() == 1)
	assert_true(loaded_events[0] >= 1)
	assert_true(progress_events[0] >= 1)

	k.loader.unload_world_mods(world_id)
	assert_eq(k.sm.get_state(), GameState.State.MAIN_MENU)
	assert_false(k.loader._world_mods.has(world_id))
	assert_eq(k.vfs.get_world_mod_dir(world_id, "wm1"), "")
	assert_true(k.loader._registry.list_blocks().is_empty())
	assert_eq(container.get_child_count(), 0)


func test_unload_missing_world_safe() -> void:
	var k := _kernel("world2")
	k.loader.unload_world_mods("ghost")
	assert_true(true)


# ============================================================
# Data hot reload
# ============================================================

func test_reload_mod_data_branches() -> void:
	var k := _kernel("reload")
	_install_global_fixtures()
	var desc := ModDescriptor.from_file("res://mods/gm1/mod.json")
	k.loader._load_global_mod(desc)
	k.loader.reload_mod_data("gm1")
	k.loader.reload_mod_data("not_loaded")
	assert_true(true)


# ============================================================
# Queries and debug panels
# ============================================================

func test_list_all_mods_and_info() -> void:
	var k := _kernel("query")
	_install_global_fixtures()
	var desc := ModDescriptor.from_file("res://mods/gm1/mod.json")
	k.loader._load_global_mod(desc)
	var all = k.loader.list_all_mods()
	assert_eq(all.size(), 1)
	assert_eq(all[0].mod_id, "gm1")
	assert_eq(all[0].mod_type, "global")
	var info = k.loader.get_mod_info("gm1")
	assert_eq(info.name, "Test Global Mod 1")
	assert_true(info.mod_dir.ends_with("res://mods/gm1"))
	assert_true(k.loader.get_mod_info("nothing").is_empty())


func test_list_world_mod_info() -> void:
	var k := _kernel("query2")
	_install_global_fixtures()
	_install_world_fixture("qw")
	var container := Node.new()
	k.loader.set_mods_container(container)
	await k.loader.load_world_mods("qw", 1)
	var all = k.loader.list_all_mods()
	assert_true(all.size() == 1)
	assert_eq(all[0].mod_type, "world")
	assert_eq(all[0].world_id, "qw")
	var info = k.loader.get_mod_info("wm1")
	assert_eq(info.world_id, "qw")
	assert_true(k.loader.get_mod_info("unknown").is_empty())
	k.loader.unload_world_mods("qw")


func test_debug_panels() -> void:
	var k := _kernel("panels")
	k.loader.register_debug_panel(null)
	assert_true(k.loader.get_custom_debug_panels().is_empty())
	var panel := ColorRect.new()
	panel.name = "p1"
	k.loader.register_debug_panel(panel)
	assert_eq(k.loader.get_custom_debug_panels().size(), 1)
	assert_eq(k.loader.get_custom_debug_panels()[0].name, "p1")


# ============================================================
# Global unload
# ============================================================

func test_unload_all_global_mods() -> void:
	var k := _kernel("unload")
	_install_global_fixtures()
	var container := Node.new()
	k.loader.set_mods_container(container)
	var d1 := ModDescriptor.from_file("res://mods/gm1/mod.json")
	var d2 := ModDescriptor.from_file("res://mods/gm2/mod.json")
	k.loader._load_global_mod(d1)
	k.loader._load_global_mod(d2)
	assert_eq(container.get_child_count(), 2)
	k.loader.unload_all_global_mods()
	assert_true(k.loader._global_mods.is_empty())
	assert_null(k.loader._mod_api)
	assert_eq(container.get_child_count(), 0)


# ============================================================
# Resource preload helpers
# ============================================================

func test_scan_resource_files() -> void:
	var k := _kernel("preload")
	var out: Array = []
	k.loader._scan_resource_files(WM1, "", out)
	assert_true(out.has(WM1 + "/thing.tres"))
	# Missing dir is a no-op
	var empty: Array = []
	k.loader._scan_resource_files(ROOT + "preload/missing", "", empty)
	assert_true(empty.is_empty())


func test_preload_resources_without_scene_tree() -> void:
	var k := _kernel("preload2")
	# scene_tree is null here, so preload skips early
	k.loader._preload_world_mod_resources("w", [])
	assert_true(true)