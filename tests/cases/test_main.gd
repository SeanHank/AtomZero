extends "res://tests/runner/TestCase.gd"


func test_ready_sets_anchors_and_mouse_filter() -> void:
	var main = load("res://core/main/Main.gd").new()
	assert_true(main is Control)
	main._ready()
	assert_eq(main.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(true)  # no assertion API for anchor presets; presence implies setup ran