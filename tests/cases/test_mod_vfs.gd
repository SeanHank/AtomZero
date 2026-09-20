extends "res://tests/runner/TestCase.gd"

const GM1 := "res://tests/fixtures/mods/gm1"
const WM1 := "res://tests/fixtures/mods/wm1"


func _make_vfs() -> ModVFS:
	var vfs := ModVFS.new()
	vfs.init(AtomLogger.new())
	return vfs


func test_resolve_global() -> void:
	var vfs := _make_vfs()
	vfs.mount_global("gm1", GM1, [])
	var p := vfs.resolve_virtual_path("mod://global/gm1/gm1.gd")
	assert_false(p.is_empty())
	assert_true(vfs.resolve_virtual_path("mod://global/gm1/nope.gd").is_empty())
	assert_true(vfs.resolve_virtual_path("mod://world/ww/gm1/thing.tres").is_empty())


func test_resolve_malformed() -> void:
	var vfs := _make_vfs()
	assert_true(vfs.resolve_virtual_path("").is_empty())
	assert_true(vfs.resolve_virtual_path("file://x").is_empty())
	assert_true(vfs.resolve_virtual_path("mod://").is_empty())
	assert_true(vfs.resolve_virtual_path("mod://global").is_empty())
	assert_true(vfs.resolve_virtual_path("mod://bogus/x").is_empty())


func test_world_resolve_and_fallback() -> void:
	var vfs := _make_vfs()
	vfs.mount_world("w1", "wm", WM1, [])
	var p := vfs.resolve_virtual_path("mod://world/w1/wm/thing.tres")
	assert_false(p.is_empty())
	vfs.unmount_world("w1", "wm")
	assert_true(vfs.resolve_virtual_path("mod://world/w1/wm/thing.tres").is_empty())


func test_world_fallback_to_global() -> void:
	var vfs := _make_vfs()
	vfs.mount_global("wm", WM1, [])
	vfs.mount_world("w2", "wm", WM1, [])
	var p := vfs.resolve_virtual_path("mod://world/w2/wm/thing.tres")
	assert_false(p.is_empty())


func test_overrides() -> void:
	var vfs := _make_vfs()
	vfs.mount_global("wm", WM1, [{
		"target_mod": "consumer",
		"target_path": "icons/tool.tres",
		"source_path": "thing.tres",
	}])
	# Override maps consumer's icons/tool.tres to wm1's thing.tres
	var p := vfs.resolve_virtual_path("mod://global/consumer/icons/tool.tres")
	assert_false(p.is_empty())
	# A broken override (missing source) is registered but ignored at resolve time
	vfs.mount_global("other", GM1, [{
		"target_mod": "consumer",
		"target_path": "gone.tres",
		"source_path": "missing.tres",
	}])
	assert_true(vfs.resolve_virtual_path("mod://global/consumer/gone.tres").is_empty())
	# Invalid override entries are skipped
	vfs.mount_global("bad", GM1, [
		"not-a-dict",
		{"target_mod": "", "target_path": "a", "source_path": "b"},
		{"target_mod": "x", "target_path": "", "source_path": "b"},
	])
	assert_true(vfs.resolve_virtual_path("mod://global/x/a").is_empty())


func test_override_priority_later_wins() -> void:
	var vfs := _make_vfs()
	vfs.mount_global("wm", WM1, [{
		"target_mod": "t", "target_path": "r.tres", "source_path": "thing.tres",
	}])
	var first := vfs.resolve_virtual_path("mod://global/t/r.tres")
	vfs.mount_global("gm", GM1, [{
		"target_mod": "t", "target_path": "r.tres", "source_path": "gm1.gd",
	}])
	var second := vfs.resolve_virtual_path("mod://global/t/r.tres")
	assert_false(first.is_empty())
	assert_false(second.is_empty())
	assert_ne(first, second)


func test_path_mapping_and_lru() -> void:
	var vfs := _make_vfs()
	for i in range(ModVFS.MAX_LRU_CACHE_SIZE + 20):
		vfs.record_path_mapping("mod://global/m/x/%03d" % i, "/real/%03d" % i)
	assert_true(vfs._path_mappings.size() <= ModVFS.MAX_LRU_CACHE_SIZE)
	# The oldest entries were evicted
	assert_false(vfs._path_mappings.has("mod://global/m/x/000"))


func test_world_path_mappings_cleared() -> void:
	var vfs := _make_vfs()
	vfs.mount_world("w9", "m", WM1, [])
	vfs.record_path_mapping("mod://world/w9/m/a/thing.tres", WM1 + "/thing.tres")
	vfs.record_path_mapping("mod://world/w9/m/b/thing.tres", WM1 + "/thing.tres")
	vfs.record_path_mapping("mod://global/z/c.gd", GM1 + "/gm1.gd")
	vfs.unmount_world_all("w9")
	assert_true(vfs._world_mounts.is_empty())
	assert_eq(vfs._path_mappings.size(), 1)


func test_mount_info() -> void:
	var vfs := _make_vfs()
	vfs.mount_global("gm1", GM1, [])
	var info := vfs.get_mount_info()
	assert_true(info.global.has("gm1"))
	assert_eq(info.global["gm1"], GM1)
	assert_true(info.world.is_empty())


func test_unmount_global_removes_override_registration() -> void:
	var vfs := _make_vfs()
	vfs.mount_global("gm1", GM1, [])
	assert_eq(vfs.get_global_mod_dir("gm1"), GM1)
	vfs.unmount_global("gm1")
	assert_eq(vfs.get_global_mod_dir("gm1"), "")


func test_world_mod_dir_getters() -> void:
	var vfs := _make_vfs()
	vfs.mount_world("w", "m", WM1, [])
	assert_eq(vfs.get_world_mod_dir("w", "m"), WM1)
	assert_eq(vfs.get_world_mod_dir("w", "x"), "")
	# unmount_world on a nonexistent world is safe
	vfs.unmount_world("nope", "m")
	assert_true(true)


func test_static_path_builders() -> void:
	assert_eq(ModVFS.make_global_path("a", "b/c"), "mod://global/a/b/c")
	assert_eq(ModVFS.make_world_path("w", "m", "d.e"), "mod://world/w/m/d.e")


func test_join_parts() -> void:
	var vfs := _make_vfs()
	var parts := PackedStringArray(["mod", "global", "m", "a", "b"])
	assert_eq(vfs._join_parts(parts, 2), "m/a/b")
	assert_eq(vfs._join_parts(parts, 4), "b")