extends "res://tests/runner/TestCase.gd"


func _sub(event: String, mod_id: String = "", priority: int = 0) -> EventSubscription:
	return EventSubscription.new(event, Callable(self, "noop"), priority, mod_id, "")


func noop() -> void:
	pass


func test_init_world_id() -> void:
	var ctx := EventContext.new("w1")
	assert_eq(ctx.world_id, "w1")
	var global := EventContext.new()
	assert_eq(global.world_id, "")


func test_add_assigns_world_id_and_rows() -> void:
	var ctx := EventContext.new("w9")
	var s := _sub("ev", "m1")
	ctx.add(s)
	assert_eq(s.world_id, "w9")
	assert_eq(ctx.count_subscribers("ev"), 1)
	assert_eq(ctx.get_subscribers("ev").size(), 1)


func test_remove() -> void:
	var ctx := EventContext.new()
	var s := _sub("ev", "m1")
	ctx.add(s)
	ctx.remove(s)
	assert_eq(ctx.count_subscribers("ev"), 0)
	assert_eq(ctx.get_event_names().size(), 0)


func test_remove_mod() -> void:
	var ctx := EventContext.new()
	var a := _sub("e1", "m1")
	var b := _sub("e2", "m1")
	var c := _sub("e3", "m2")
	ctx.add(a)
	ctx.add(b)
	ctx.add(c)
	var removed := ctx.remove_mod("m1")
	assert_eq(removed.size(), 2)
	assert_eq(ctx.count_subscribers("e1"), 0)
	assert_eq(ctx.count_subscribers("e2"), 0)
	assert_eq(ctx.count_subscribers("e3"), 1)


func test_clear() -> void:
	var ctx := EventContext.new("w")
	var a := _sub("e1", "m1")
	var b := _sub("e2", "m2")
	ctx.add(a)
	ctx.add(b)
	var all := ctx.clear()
	assert_eq(all.size(), 2)
	assert_eq(ctx.get_event_names().size(), 0)
	assert_eq(ctx.count_subscribers("e1"), 0)


func test_get_subscribers_sorted_by_priority() -> void:
	var ctx := EventContext.new()
	var low := _sub("ev", "m1", 50)
	var high := _sub("ev", "m2", 10)
	var mid := _sub("ev", "m3", 30)
	ctx.add(low)
	ctx.add(high)
	ctx.add(mid)
	var subs := ctx.get_subscribers("ev")
	assert_eq(subs.size(), 3)
	assert_eq(subs[0].priority, 10)
	assert_eq(subs[1].priority, 30)
	assert_eq(subs[2].priority, 50)


func test_get_event_names_union() -> void:
	var ctx := EventContext.new()
	ctx.add(_sub("a"))
	ctx.add(_sub("b"))
	ctx.add(_sub("a"))
	assert_eq(ctx.get_event_names().size(), 2)
	assert_true(ctx.get_event_names().has("a"))
	assert_true(ctx.get_event_names().has("b"))