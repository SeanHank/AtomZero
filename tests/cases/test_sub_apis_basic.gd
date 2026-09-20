extends "res://tests/runner/TestCase.gd"

const GM1 := "res://tests/fixtures/mods/gm1"
const WM1 := "res://tests/fixtures/mods/wm1"


func _stack(root: String = "res://.test_tmp/api/basic/") -> Dictionary:
	return TestKernel.make_stack(root)


# ===== LoggerAPI =====

func test_logger_api_levels_and_flags() -> void:
	var s := _stack()
	var api := LoggerAPI.new(s.logger, "mymod")
	s.logger.set_level(AtomLogger.LEVEL_TRACE)
	assert_true(api.is_trace_enabled())
	assert_true(api.is_debug_enabled())
	api.trace("t")
	api.debug("d")
	api.info("i")
	api.warn("w")
	api.error("e")
	api.fatal("f")
	s.logger.set_level(AtomLogger.LEVEL_WARN)
	assert_false(api.is_debug_enabled())
	assert_false(api.is_trace_enabled())


# ===== VFSAPI =====

func test_vfs_api_global_paths_and_resolve() -> void:
	var s := _stack()
	s.vfs.mount_global("mid", GM1, [])
	var api := VFSAPI.new(s.vfs, "mid", "")
	assert_eq(api.get_mod_data_dir(), "res://mods/mid/data/")
	assert_eq(api.get_mod_config_dir(), "res://mods/mid/config/")
	assert_eq(api.get_mod_dir(), GM1)
	assert_false(api.resolve_virtual_path("mod://global/mid/gm1.gd").is_empty())
	assert_eq(api.make_global_path("x", "y"), "mod://global/x/y")
	assert_eq(api.make_world_path("w", "x", "y"), "mod://world/w/x/y")


func test_vfs_api_world_paths() -> void:
	var s := _stack()
	s.vfs.mount_world("wz", "mid", WM1, [])
	var api := VFSAPI.new(s.vfs, "mid", "wz")
	assert_eq(api.get_mod_data_dir(), "res://saves/wz/mods/mid/data/")
	assert_eq(api.get_mod_config_dir(), "res://saves/wz/mods/mid/config/")
	assert_eq(api.get_mod_dir(), WM1)


# ===== WorldAPI =====

func test_world_api_state_projection() -> void:
	var s := _stack()
	var api := WorldAPI.new(s.sm)
	assert_eq(api.get_current_world_id(), "")
	assert_false(api.is_world_loaded())
	assert_eq(api.get_world_seed(), 0)
	s.sm.transition_to_world_loading("w", 42)
	assert_true(api.is_world_loaded())
	assert_eq(api.get_current_world_id(), "w")
	assert_eq(api.get_world_seed(), 42)
	assert_eq(api.get_state_name(), "WORLD_LOADING")
	s.sm.transition_to_world_running()
	assert_eq(api.get_state_name(), "WORLD_RUNNING")


# ===== DevAPI =====

func test_dev_api_disabled_hash_branch() -> void:
	var s := _stack()
	var api := DevAPI.new(s.loader, s.logger)
	api._enabled = false
	assert_false(api.is_enabled())
	api.reload_mod_data("anything")
	var panel := ColorRect.new()
	api.register_debug_panel(panel)
	assert_true(api.get_debug_panels().is_empty())


func test_dev_api_enabled_with_loader() -> void:
	var s := _stack()
	var api := DevAPI.new(s.loader, s.logger)
	api._enabled = true
	assert_true(api.is_enabled())
	api.reload_mod_data("not_loaded")
	var panel := ColorRect.new()
	api.register_debug_panel(panel)
	assert_eq(api.get_debug_panels().size(), 1)
	assert_true(s.loader.get_custom_debug_panels().size() >= 1)


func test_dev_api_enabled_null_loader() -> void:
	var s := _stack()
	var api := DevAPI.new(null, s.logger)
	api._enabled = true
	api.reload_mod_data("x")
	api.register_debug_panel(ColorRect.new())
	assert_eq(api.get_debug_panels().size(), 1)