extends "res://tests/runner/TestCase.gd"


func test_init_mod_noop() -> void:
	var imod := IMod.new()
	imod._init_mod(ModAPI.new())
	assert_true(true)


func test_is_ref_counted() -> void:
	var imod := IMod.new()
	assert_true(imod is RefCounted)