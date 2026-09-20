extends "res://tests/runner/TestCase.gd"


func _stack() -> Dictionary:
	return TestKernel.make_stack("res://.test_tmp/api/mod_api/")


func test_init_builds_sub_apis() -> void:
	var s := _stack()
	var api: ModAPI = s.api
	assert_not_null(api.logger)
	assert_not_null(api.events)
	assert_not_null(api.resources)
	assert_not_null(api.registry)
	assert_not_null(api.persistence)
	assert_not_null(api.vfs)
	assert_not_null(api.world)
	assert_not_null(api.dev)
	var ctx: ModContext = api.get_context()
	assert_eq(ctx.mod_id, "")
	assert_false(api._initialized == false)


func test_create_for_mod_independent_context() -> void:
	var s := _stack()
	var base: ModAPI = s.api
	var api: ModAPI = base.create_for_mod("m1", "world", "w9", 7, "1.2.3")
	var ctx: ModContext = api.get_context()
	assert_eq(ctx.mod_id, "m1")
	assert_eq(ctx.mod_type, "world")
	assert_eq(ctx.world_id, "w9")
	assert_eq(ctx.world_seed, 7)
	assert_eq(ctx.mod_version, "1.2.3")
	assert_true(ctx.is_world_mod())
	assert_false(ctx.is_global_mod())
	assert_eq(api._logger_service, base._logger_service)
	assert_eq(api.events._mod_id, "m1")
	assert_eq(api.events._world_id, "w9")
	assert_eq(api.resources._world_id, "w9")
	assert_eq(api.persistence._world_id, "w9")
	assert_eq(api.vfs._world_id, "w9")
	assert_eq(api.registry._world_id, "w9")


func test_global_api_context() -> void:
	var s := _stack()
	var api: ModAPI = s.api.create_for_mod("gm", "global")
	var ctx: ModContext = api.get_context()
	assert_eq(ctx.mod_id, "gm")
	assert_true(ctx.is_global_mod())
	assert_false(ctx.is_world_mod())
	assert_eq(api.events._world_id, "")
	assert_eq(api.resources._world_id, "")