extends "res://tests/runner/TestCase.gd"

const WM1 := "res://tests/fixtures/mods/wm1"


func _bootstrap():
	return (Engine.get_main_loop() as SceneTree).root.get_node("Bootstrap")


# ============================================================
# Static path helpers
# ============================================================

func test_aa_static_paths() -> void:
	var B = load("res://core/bootstrap/Bootstrap.gd")
	assert_eq(B.get_writable_root(), "res://")
	assert_eq(B.get_global_mods_dir(), "res://mods/")
	assert_eq(B.get_saves_dir(), "res://saves/")
	assert_eq(B.get_world_mods_dir("w"), "res://saves/w/mods/")
	assert_eq(B.get_logs_dir(), "res://logs/")
	assert_eq(B.get_cache_dir(), "res://.cache/")
	assert_eq(B.GAME_VERSION, "2026.9.0")


# ============================================================
# Service getters
# ============================================================

func test_ab_service_getters() -> void:
	var b = _bootstrap()
	assert_not_null(b.get_mod_loader())
	assert_not_null(b.get_state_manager())
	assert_not_null(b.get_event_bus())
	assert_not_null(b.get_logger())
	assert_not_null(b.get_hash_verifier())
	assert_not_null(b.get_registry())
	assert_not_null(b.get_mod_vfs())
	assert_not_null(b.get_persistence())
	assert_not_null(b.get_mod_api())
	# _ready() and _init_services() ran via the autoload
	assert_not_null(b._mods_container)


# ============================================================
# Debug tool bootstrap
# ============================================================

func test_ac_init_debug_tools() -> void:
	var b = _bootstrap()
	if b._debug_console != null or b._debug_overlay != null:
		return
	b._init_debug_tools()
	assert_not_null(b._debug_console)
	assert_not_null(b._debug_overlay)


# ============================================================
# Frame loop tick dispatch
# ============================================================

func test_ad_tick_and_physics_dispatch() -> void:
	var b = _bootstrap()
	b.set_process(false)
	b.set_physics_process(false)
	var bus: EventBus = b.get_event_bus()
	var sm: StateManager = b.get_state_manager()
	var ticks: Array = []
	var pticks: Array = []
	var on_tick := func(p): ticks.append(p.get("tick", -1))
	var on_ptick := func(p): pticks.append(p.get("tick", -1))
	bus.subscribe_tick(on_tick)
	bus.subscribe_physics_tick(on_ptick)
	# No dispatch while in the main menu
	b._process(0.016)
	b._physics_process(0.016)
	assert_eq(ticks.size(), 0)
	assert_eq(pticks.size(), 0)
	# Enter a running world -> dispatch happens
	sm.transition_to_world_loading("tickw", 1)
	sm.transition_to_world_running()
	b._process(0.016)
	assert_eq(ticks.size(), 1)
	assert_eq(ticks[0], 1)
	b._physics_process(0.016)
	assert_eq(pticks.size(), 1)
	assert_eq(pticks[0], 1)
	bus.unsubscribe_tick(on_tick)
	bus.unsubscribe_physics_tick(on_ptick)
	sm.transition_to_world_unloading()
	sm.transition_to_main_menu_after_unload()


# ============================================================
# World load/unload through Bootstrap
# ============================================================

func test_ae_world_load_and_unload() -> void:
	var b = _bootstrap()
	var sm: StateManager = b.get_state_manager()
	if not sm.get_current_world_id().is_empty():
		b.unload_current_world()
	var world_id := "bootstrap.world"
	var world_mods_dir := "res://saves/%s/mods/wm1" % world_id
	ensure_dir("res://saves/" + world_id + "/mods/")
	TestKernel.copy_dir_into(WM1, world_mods_dir)
	await b.load_world(world_id, 7)
	assert_eq(sm.get_state(), GameState.State.WORLD_RUNNING)
	assert_eq(sm.get_current_world_id(), world_id)
	var info: Dictionary = b.get_mod_loader().get_mod_info("wm1")
	assert_eq(info.world_id, world_id)
	# Unload returns to the main menu
	b.unload_current_world()
	assert_eq(sm.get_state(), GameState.State.MAIN_MENU)
	assert_true(sm.get_current_world_id().is_empty())
	# Unloading with no world loaded is a no-op
	b.unload_current_world()
	assert_true(sm.get_current_world_id().is_empty())


# ============================================================
# Exit cleanup (runs last)
# ============================================================

func test_zzz_exit_tree() -> void:
	var b = _bootstrap()
	b._exit_tree()
	assert_true(true)