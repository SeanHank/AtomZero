extends "res://tests/runner/TestCase.gd"


func test_defaults() -> void:
	var ctx := ModContext.new()
	assert_eq(ctx.mod_id, "")
	assert_eq(ctx.mod_type, "global")
	assert_eq(ctx.world_id, "")
	assert_eq(ctx.world_seed, 0)
	assert_eq(ctx.mod_version, "")
	assert_true(ctx.is_global_mod())
	assert_false(ctx.is_world_mod())


func test_full_construction() -> void:
	var ctx := ModContext.new("mid", "world")
	ctx.world_id = "w5"
	ctx.world_seed = 99
	ctx.mod_version = "2.0.0"
	assert_eq(ctx.mod_id, "mid")
	assert_eq(ctx.world_id, "w5")
	assert_eq(ctx.world_seed, 99)
	assert_eq(ctx.mod_version, "2.0.0")
	assert_true(ctx.is_world_mod())
	assert_false(ctx.is_global_mod())