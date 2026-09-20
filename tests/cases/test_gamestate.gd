extends "res://tests/runner/TestCase.gd"


func test_state_name_all() -> void:
	assert_eq(GameState.state_name(GameState.State.BOOTSTRAP), "BOOTSTRAP")
	assert_eq(GameState.state_name(GameState.State.MAIN_MENU), "MAIN_MENU")
	assert_eq(GameState.state_name(GameState.State.WORLD_LOADING), "WORLD_LOADING")
	assert_eq(GameState.state_name(GameState.State.WORLD_RUNNING), "WORLD_RUNNING")
	assert_eq(GameState.state_name(GameState.State.WORLD_UNLOADING), "WORLD_UNLOADING")
	assert_eq(GameState.state_name(GameState.State.CRASH), "CRASH")
	assert_eq(GameState.state_name(12345), "UNKNOWN")


func test_constants() -> void:
	assert_eq(GameState.OK, "OK")
	assert_eq(GameState.HASH_MISMATCH, "HASH_MISMATCH")
	assert_eq(GameState.CIRCULAR_DEP, "CIRCULAR_DEP")