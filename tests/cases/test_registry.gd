extends "res://tests/runner/TestCase.gd"


func _make_reg() -> RegistrySystem:
	var reg := RegistrySystem.new()
	reg.init(null)
	return reg


func _script() -> Script:
	return load("res://tests/fixtures/mods/gm1/gm1.gd")


func test_global_registration_and_query() -> void:
	var reg := _make_reg()
	var s := _script()
	reg.register_block("b1", s)
	reg.register_item("i1", s)
	reg.register_entity("e1", s)
	reg.register_recipe("r1", {"a": 1})
	assert_eq(reg.get_block("b1"), s)
	assert_eq(reg.get_item("i1"), s)
	assert_eq(reg.get_entity("e1"), s)
	assert_eq(reg.get_recipe("r1").a, 1)
	assert_null(reg.get_block("missing"))
	assert_eq(reg.get_recipe("missing"), {})
	# duplicate registration warns + overwrites (no throw)
	reg.register_block("b1", s)
	assert_true(true)


func test_list_with_prefix() -> void:
	var reg := _make_reg()
	var s := _script()
	for i in range(3):
		reg.register_block("stone_%d" % i, s)
		reg.register_block("wood_%d" % i, s)
	reg.register_entity("creep", s)
	assert_true(reg.list_blocks("stone_").size() == 3)
	assert_true(reg.list_blocks().size() == 6)
	assert_true(reg.list_items().size() == 0)
	# lists are sorted
	var ids := reg.list_blocks("wood_")
	assert_eq(ids[0], "wood_0")
	assert_eq(ids[2], "wood_2")


func test_world_partition() -> void:
	var reg := _make_reg()
	var s := _script()
	reg.open_world_partition("w1")
	reg.register_world_block("w1", "rock", s)
	reg.register_world_item("w1", "gem", s)
	reg.register_world_entity("w1", "goblin", s)
	reg.register_world_recipe("w1", "recipe", {"r": 1})
	# internally prefixed
	assert_not_null(reg.get_block("world.w1.rock"))
	assert_true(reg.list_blocks("world.w1.").has("world.w1.rock"))
	# global aliases are also recorded (same dict -> present)
	assert_true(reg.list_blocks().has("world.w1.rock"))
	reg.release_world_partition("w1")
	assert_null(reg.get_block("world.w1.rock"))
	assert_true(reg.list_blocks().is_empty())


func test_get_partition_auto_opens() -> void:
	var reg := _make_reg()
	assert_false(reg._world_partitions.has("x"))
	var p := reg._get_partition("x")
	assert_true(reg._world_partitions.has("x"))
	assert_has_key(p, "blocks")


func test_make_world_id() -> void:
	var reg := _make_reg()
	assert_eq(reg._make_world_id("w", "id"), "world.w.id")


func test_release_missing_partition_safe() -> void:
	var reg := _make_reg()
	reg.release_world_partition("nope")
	assert_true(true)