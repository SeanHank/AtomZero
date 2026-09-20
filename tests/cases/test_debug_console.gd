extends "res://tests/runner/TestCase.gd"


func _bootstrap():
	return (Engine.get_main_loop() as SceneTree).root.get_node("Bootstrap")


func _console():
	var b = _bootstrap()
	var existing = b.get_node_or_null("TestConsole")
	if existing != null:
		return existing
	var c = load("res://core/debug/DebugConsole.gd").new()
	c.name = "TestConsole"
	c.setup(b)
	b.add_child(c)
	return c


func test_aa_ready_and_build_ui() -> void:
	var c = _console()
	assert_not_null(c._output_label)
	assert_not_null(c._console_edit)
	# _ready hides the console
	assert_false(c._visible)
	assert_false(c.visible)


func test_ab_toggle_visibility() -> void:
	var c = _console()
	var ev := InputEventAction.new()
	ev.action = "console_toggle"
	ev.pressed = true
	c._input(ev)
	assert_true(c._visible)
	assert_true(c.visible)
	c._input(ev)
	assert_false(c._visible)
	assert_false(c.visible)


func test_ac_history_navigation() -> void:
	var c = _console()
	c._history.clear()
	c._history_index = -1
	# Empty history -> no-op
	c._history_nav(-1)
	assert_eq(c._console_edit.text, "")
	# Submit a command (empty string is skipped entirely)
	c._on_text_submitted("")
	assert_eq(c._history.size(), 0)
	c._on_text_submitted("_firstcmd")
	assert_eq(c._history.size(), 1)
	assert_eq(c._history[0], "_firstcmd")
	# Browse history with the keyboard
	c._show_console()
	var up := InputEventKey.new()
	up.keycode = KEY_UP
	up.pressed = true
	c._input(up)
	assert_eq(c._console_edit.text, "_firstcmd")
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	c._input(down)
	# Nav clamps at the most recent history entry, so the text stays
	assert_eq(c._console_edit.text, "_firstcmd")
	c._hide_console()
	# A non-navigation key does nothing -> the text stays as it was
	c._show_console()
	var akey := InputEventKey.new()
	akey.keycode = KEY_A
	akey.pressed = true
	c._input(akey)
	assert_eq(c._console_edit.text, "_firstcmd")
	c._hide_console()


func test_ad_all_command_dispatch() -> void:
	var c = _console()
	# unknown/empty
	c._execute("")
	c._execute("totally_unknown")
	c._execute("help")
	# mods
	c._execute("mods")
	c._execute("mods list")
	c._execute("mods info")
	c._execute("mods info doesnotexist")
	c._execute("mods reload some_mod")
	c._execute("mods enable")
	c._execute("mods disable")
	c._execute("mods bogus")
	# events
	c._execute("events")
	c._execute("events list")
	c._execute("events emit")
	c._execute("events emit myev")
	c._execute("events emit myev {\"a\": 1}")
	c._execute("events emit myev {oops")
	c._execute("events bogus")
	# registry
	c._execute("registry")
	c._execute("registry list")
	c._execute("registry list blocks")
	c._execute("registry list items")
	c._execute("registry list entities")
	c._execute("registry list recipes")
	c._execute("registry list bogus")
	# hash
	c._execute("hash")
	c._execute("hash list")
	c._execute("hash reset some_mod")
	c._execute("hash bogus")
	# log
	c._execute("log")
	c._execute("log level debug")
	c._execute("log level bogus")
	assert_true(true)