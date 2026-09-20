extends "res://tests/runner/TestCase.gd"


func test_constructor_fields() -> void:
	var sub := EventSubscription.new("my:event", Callable(self, "noop"), 5, "mod_a", "world_1")
	assert_eq(sub.event_name, "my:event")
	assert_eq(sub.priority, 5)
	assert_eq(sub.mod_id, "mod_a")
	assert_eq(sub.world_id, "world_1")
	assert_true(sub.callable.is_valid())


func test_constructor_defaults() -> void:
	var sub := EventSubscription.new()
	assert_eq(sub.event_name, "")
	assert_eq(sub.priority, 0)
	assert_eq(sub.mod_id, "")
	assert_eq(sub.world_id, "")


func noop() -> void:
	pass