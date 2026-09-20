extends "res://tests/runner/TestCase.gd"


func _make_sm() -> StateManager:
	var sm := StateManager.new()
	sm.init(null, EventBus.new())
	return sm


func test_initial_state() -> void:
	var sm := _make_sm()
	assert_eq(sm.get_state(), GameState.State.BOOTSTRAP)
	assert_eq(sm.get_state_name(), "BOOTSTRAP")
	assert_false(sm.is_world_loaded())
	assert_false(sm.is_world_running())


func test_get_world_info_defaults() -> void:
	var sm := _make_sm()
	assert_eq(sm.get_current_world_id(), "")
	assert_eq(sm.get_current_world_seed(), 0)


func test_transitions() -> void:
	var sm := _make_sm()
	sm.transition_to_main_menu()
	assert_eq(sm.get_state(), GameState.State.MAIN_MENU)

	sm.transition_to_world_loading("w1", 42)
	assert_eq(sm.get_state(), GameState.State.WORLD_LOADING)
	assert_eq(sm.get_current_world_id(), "w1")
	assert_eq(sm.get_current_world_seed(), 42)
	assert_true(sm.is_world_loaded())
	assert_false(sm.is_world_running())

	sm.transition_to_world_running()
	assert_eq(sm.get_state(), GameState.State.WORLD_RUNNING)
	assert_true(sm.is_world_loaded())
	assert_true(sm.is_world_running())

	sm.transition_to_world_unloading()
	assert_eq(sm.get_state(), GameState.State.WORLD_UNLOADING)
	assert_false(sm.is_world_loaded())
	assert_false(sm.is_world_running())

	sm.transition_to_main_menu_after_unload()
	assert_eq(sm.get_state(), GameState.State.MAIN_MENU)
	assert_eq(sm.get_current_world_id(), "")
	assert_eq(sm.get_current_world_seed(), 0)


func test_transition_to_crash() -> void:
	var sm := _make_sm()
	sm.transition_to_crash()
	assert_eq(sm.get_state(), GameState.State.CRASH)