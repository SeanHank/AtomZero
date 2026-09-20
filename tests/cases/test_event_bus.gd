extends "res://tests/runner/TestCase.gd"

var _emitted: Array = []
var _tick_seen: Array = []
var _physics_seen: Array = []


func _on_ev(payload: Dictionary) -> void:
	_emitted.append(payload.get("n", 0))


func _on_ev_plus(payload: Dictionary) -> void:
	_emitted.append(payload.get("n", 0) + 100)


func _on_tick(payload: Dictionary) -> void:
	_tick_seen.append(payload.get("tick", -1))


func _on_physics(payload: Dictionary) -> void:
	_physics_seen.append(payload.get("tick", -1))


func _make_bus() -> EventBus:
	var bus := EventBus.new()
	bus.init(null)
	return bus


func test_init_subscribe_emit() -> void:
	var bus := _make_bus()
	_emitted.clear()
	var sub := bus.subscribe("ev", Callable(self, "_on_ev"))
	assert_eq(bus.get_subscriber_count("ev"), 1)
	assert_eq(bus.get_all_event_names(), ["ev"])
	bus.emit("ev", {"n": 7})
	assert_eq(_emitted, [7])
	bus.unsubscribe(sub)
	assert_eq(bus.get_subscriber_count("ev"), 0)


func test_emit_priority_order() -> void:
	var bus := _make_bus()
	_emitted.clear()
	bus.subscribe("ev", Callable(self, "_on_ev_plus"), 10)
	bus.subscribe("ev", Callable(self, "_on_ev"), 5)
	bus.emit("ev", {"n": 1})
	assert_eq(_emitted, [1, 101])


func test_stop_propagation() -> void:
	var bus := _make_bus()
	_emitted.clear()
	bus.subscribe("ev", func(payload):
		bus.stop_propagation()
		_emitted.append("first"), -10)
	bus.subscribe("ev", func(payload):
		_emitted.append("second"), 10)
	bus.emit("ev", {})
	assert_eq(_emitted, ["first"])


func test_emit_deferred() -> void:
	var bus := _make_bus()
	_emitted.clear()
	bus.subscribe("ev", Callable(self, "_on_ev"))
	bus.emit_deferred("ev", {"n": 99})
	assert_eq(_emitted.size(), 0)
	await await_frame()
	assert_eq(_emitted, [99])


func test_world_context_binding() -> void:
	var bus := _make_bus()
	_emitted.clear()
	bus.on_world_load("w1")
	var sub := bus.subscribe("ev", Callable(self, "_on_ev"), 0, "mod1")
	assert_eq(sub.world_id, "w1")
	bus.emit("ev", {"n": 3})
	assert_eq(_emitted, [3])
	bus.on_world_unload("w1")
	assert_eq(bus.get_subscriber_count("ev"), 0)
	var sub2 := bus.subscribe("ev", Callable(self, "_on_ev"), 0, "mod2")
	assert_eq(sub2.world_id, "")
	bus.remove_mod_subscriptions("mod2", "")
	assert_eq(bus.get_subscriber_count("ev"), 0)


func test_remove_mod_subscriptions_global() -> void:
	var bus := _make_bus()
	bus.subscribe("ev", Callable(self, "_on_ev"), 0, "modx")
	bus.remove_mod_subscriptions("modx", "")
	assert_eq(bus.get_subscriber_count("ev"), 0)


func test_tick_channel() -> void:
	var bus := _make_bus()
	_tick_seen.clear()
	var c := Callable(self, "_on_tick")
	bus.subscribe_tick(c)
	bus.dispatch_tick(0.5, 11)
	assert_eq(_tick_seen, [11])
	bus.unsubscribe_tick(c)
	bus.dispatch_tick(0.5, 12)
	assert_eq(_tick_seen.size(), 1)


func test_tick_pending_adds_during_dispatch() -> void:
	var bus := _make_bus()
	var handled: Array = []
	var extra := func(payload):
		handled.append(payload.get("tick", -1))
	var adder := func(payload):
		bus.subscribe_tick(extra)
	bus.subscribe_tick(adder)
	bus.dispatch_tick(0.1, 1)
	assert_eq(handled.size(), 0)
	bus.dispatch_tick(0.1, 2)
	assert_eq(handled, [2])


func test_tick_pending_rems_during_dispatch() -> void:
	var bus := _make_bus()
	_tick_seen.clear()
	var victim := Callable(self, "_on_tick")
	var remover := func(payload):
		bus.unsubscribe_tick(victim)
	bus.subscribe_tick(victim)
	bus.subscribe_tick(remover)
	bus.dispatch_tick(0.1, 1)
	assert_eq(_tick_seen.size(), 1)
	bus.dispatch_tick(0.1, 2)
	assert_eq(_tick_seen.size(), 1)


func test_physics_tick_channel() -> void:
	var bus := _make_bus()
	_physics_seen.clear()
	var c := Callable(self, "_on_physics")
	bus.subscribe_physics_tick(c)
	bus.dispatch_physics_tick(0.2, 5)
	assert_eq(_physics_seen, [5])
	bus.unsubscribe_physics_tick(c)
	bus.dispatch_physics_tick(0.2, 6)
	assert_eq(_physics_seen.size(), 1)


func test_physics_tick_pending_adds() -> void:
	var bus := _make_bus()
	var handled: Array = []
	var extra := func(payload):
		handled.append(payload.get("tick", -1))
	var adder := func(payload):
		bus.subscribe_physics_tick(extra)
	bus.subscribe_physics_tick(adder)
	bus.dispatch_physics_tick(0.1, 7)
	assert_eq(handled.size(), 0)
	bus.dispatch_physics_tick(0.1, 8)
	assert_eq(handled, [8])


func test_physics_tick_pending_rems() -> void:
	var bus := _make_bus()
	_physics_seen.clear()
	var victim := Callable(self, "_on_physics")
	var remover := func(payload):
		bus.unsubscribe_physics_tick(victim)
	bus.subscribe_physics_tick(victim)
	bus.subscribe_physics_tick(remover)
	bus.dispatch_physics_tick(0.1, 1)
	assert_eq(_physics_seen.size(), 1)
	bus.dispatch_physics_tick(0.1, 2)
	assert_eq(_physics_seen.size(), 1)


func test_subscriber_threshold_warns() -> void:
	var bus := _make_bus()
	for i in range(EventBus.MAX_SUBSCRIBERS_PER_EVENT + 2):
		bus.subscribe("hot", Callable(self, "_on_ev"))
	assert_eq(bus.get_subscriber_count("hot"), EventBus.MAX_SUBSCRIBERS_PER_EVENT + 2)


func test_get_all_event_names_merges_world() -> void:
	var bus := _make_bus()
	bus.subscribe("g", Callable(self, "_on_ev"))
	bus.on_world_load("w")
	bus.subscribe("w-only", Callable(self, "_on_ev"), 0, "modw")
	var names := bus.get_all_event_names()
	assert_true(names.has("g"))
	assert_true(names.has("w-only"))


func test_emit_world_merge() -> void:
	var bus := _make_bus()
	_emitted.clear()
	bus.subscribe("ev", Callable(self, "_on_ev"), 1)
	bus.on_world_load("w")
	bus.subscribe("ev", Callable(self, "_on_ev_plus"), 2)
	bus.emit("ev", {"n": 5})
	assert_eq(_emitted, [5, 105])


func test_deferred_emit_impl() -> void:
	var bus := _make_bus()
	_emitted.clear()
	bus.subscribe("dv", Callable(self, "_on_ev"))
	bus._deferred_emit_impl("dv", {"n": 1})
	assert_eq(_emitted, [1])