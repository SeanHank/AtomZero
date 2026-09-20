extends "res://tests/runner/TestCase.gd"

const GM1 := "res://tests/fixtures/mods/gm1"
const ROOT := "res://.test_tmp/api/game/"

var _received: Array = []


func _on_ev(payload: Dictionary) -> void:
	_received.append(payload.get("n", 0))


func _stack() -> Dictionary:
	return TestKernel.make_stack(ROOT)


func _bootstrap():
	return (Engine.get_main_loop() as SceneTree).root.get_node("Bootstrap")


# `ResourceAPI` load/threaded APIs resolve mod:// virtual paths through the
# per-test stack VFS to the fixture's real path, then load from disk.
func _mount_gm1(s: Dictionary) -> void:
	s.vfs.mount_global("gm1", GM1, [])


# ===== EventAPI =====

func test_event_api_subscribe_emit() -> void:
	var s := _stack()
	_received.clear()
	var api := EventAPI.new(s.event, "modx", "")
	var sub := api.subscribe("ev", Callable(self, "_on_ev"))
	assert_eq(sub.mod_id, "modx")
	assert_eq(api.get_subscriber_count("ev"), 1)
	api.emit("ev", {"n": 5})
	assert_eq(_received, [5])
	api.unsubscribe(sub)
	assert_eq(api.get_subscriber_count("ev"), 0)


func test_event_api_emit_deferred() -> void:
	var s := _stack()
	_received.clear()
	var api := EventAPI.new(s.event, "modx", "")
	api.subscribe("ev", Callable(self, "_on_ev"))
	api.emit_deferred("ev", {"n": 9})
	assert_eq(_received.size(), 0)
	await await_frame()
	assert_eq(_received, [9])


func test_event_api_stop_propagation() -> void:
	var s := _stack()
	_received.clear()
	var api := EventAPI.new(s.event, "modx", "")
	api.subscribe("ev", func(payload):
		api.stop_propagation()
		_received.append("first"), -1)
	api.subscribe("ev", func(payload):
		_received.append("second"), 1)
	api.emit("ev", {})
	assert_eq(_received, ["first"])


func test_event_api_tick_channels() -> void:
	var s := _stack()
	var ticks: Array = []
	var api := EventAPI.new(s.event, "modx", "")
	var cb := func(payload):
		ticks.append(payload.get("tick", -1))
	api.subscribe_tick(cb)
	s.event.dispatch_tick(0.1, 1)
	assert_eq(ticks, [1])
	api.unsubscribe_tick(cb)
	s.event.dispatch_tick(0.1, 2)
	assert_eq(ticks.size(), 1)

	var pticks: Array = []
	var pcb := func(payload):
		pticks.append(payload.get("tick", -1))
	api.subscribe_physics_tick(pcb)
	s.event.dispatch_physics_tick(0.1, 3)
	assert_eq(pticks, [3])
	api.unsubscribe_physics_tick(pcb)


# ===== ResourceAPI =====

func test_resource_api_load_and_exists() -> void:
	var s := _stack()
	_mount_gm1(s)
	var api := ResourceAPI.new(s.vfs, "gm1", "")
	assert_true(api.exists("gm1.gd"))
	assert_false(api.exists("missing.gd"))
	var res := api.load("gm1", "gm1.gd")
	assert_not_null(res)
	assert_true(res is Script)
	# Single-argument style uses the current mod
	var res2 := api.load("gm1.gd")
	assert_not_null(res2)
	# Unknown mod resolves nothing
	assert_null(api.load("unknownmod", "x.gd"))


func test_resource_api_empty_mod_falls_back() -> void:
	var s := _stack()
	_mount_gm1(s)
	var api := ResourceAPI.new(s.vfs, "gm1", "")
	assert_not_null(api.load("", "gm1.gd"))
	api.load_threaded("absent.gd")


func test_resource_api_threaded() -> void:
	var s := _stack()
	_mount_gm1(s)
	var api := ResourceAPI.new(s.vfs, "gm1", "")
	api.load_threaded("gm1.gd")
	var tries := 0
	while api.get_load_threaded_status("gm1.gd") == ResourceLoader.THREAD_LOAD_IN_PROGRESS and tries < 200:
		tries += 1
		await await_frame()
	assert_true(api.get_load_threaded_status("gm1.gd") == ResourceLoader.THREAD_LOAD_LOADED)
	assert_not_null(api.get_load_threaded("gm1.gd"))


func test_resource_api_world_path() -> void:
	var s := _stack()
	_mount_gm1(s)
	var api := ResourceAPI.new(s.vfs, "gm1", "worldname")
	var path := api._build_virtual_path("gm1", "x.gd")
	assert_eq(path, "mod://world/worldname/gm1/x.gd")
	var global_api := ResourceAPI.new(s.vfs, "gm1", "")
	assert_eq(global_api._build_virtual_path("gm1", "y.gd"), "mod://global/gm1/y.gd")


# ===== RegistryAPI =====

func test_registry_api_global_qualify() -> void:
	var s := _stack()
	var api := RegistryAPI.new(s.registry, "modx", "")
	assert_eq(api._qualify_id("a"), "modx:a")
	assert_eq(api._qualify_id("a:b"), "a:b")
	var script := load(GM1 + "/gm1.gd")
	api.register_block("cobble", script)
	assert_not_null(api.get_block("modx:cobble"))
	assert_true(api.list_blocks().has("modx:cobble"))
	api.register_item("thing", script)
	api.register_entity("ent", script)
	api.register_recipe("rec", {"a": 1})
	assert_not_null(api.get_item("modx:thing"))
	assert_not_null(api.get_entity("modx:ent"))
	assert_eq(api.get_recipe("modx:rec").a, 1)
	assert_true(api.list_items().has("modx:thing"))
	assert_true(api.list_entities().has("modx:ent"))
	assert_true(api.list_recipes().has("modx:rec"))


func test_registry_api_world() -> void:
	var s := _stack()
	var api := RegistryAPI.new(s.registry, "modw", "w1")
	var script := load(GM1 + "/gm1.gd")
	api.register_block("stone", script)
	assert_not_null(s.registry.get_block("world.w1.modw:stone"))


# ===== PersistenceAPI =====

func test_persistence_api_global() -> void:
	var s := _stack()
	var api := PersistenceAPI.new(s.persistence, "pmod", "")
	api.save_config("k", {"vol": 3})
	assert_eq(api.load_config("k", {}).vol, 3)
	api.save_data("d", {"hp": 50})
	assert_eq(api.load_data("d", {}).hp, 50)
	assert_eq(api.load_data("missing", "def"), "def")


func test_persistence_api_world() -> void:
	var s := _stack()
	var api := PersistenceAPI.new(s.persistence, "pmod", "wz")
	api.save_config("c", {"a": 1})
	api.save_data("d", {"b": 2})
	assert_eq(api.load_config("c", {}).a, 1)
	assert_eq(api.load_data("d", {}).b, 2)
	assert_true(FileAccess.file_exists(ROOT + "saves/wz/mods/pmod/data/d.json"))


func test_persistence_api_autosave() -> void:
	var s := _stack()
	var api := PersistenceAPI.new(s.persistence, "pmod", "")
	var called: Array = [false]
	api.register_autosave(func() -> Dictionary:
		called[0] = true
		return {"auto": {"n": 1}})
	s.persistence.update(300.0)
	assert_true(called[0])
	assert_eq(api.load_data("auto", {}).n, 1)
	api.unregister_autosave()
	s.persistence.update(300.0)
	assert_true(called[0])