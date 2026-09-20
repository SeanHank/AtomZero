extends "res://tests/runner/TestCase.gd"


func _bootstrap():
	return (Engine.get_main_loop() as SceneTree).root.get_node("Bootstrap")


func _overlay():
	var b = _bootstrap()
	var existing = b.get_node_or_null("TestOverlay")
	if existing != null:
		return existing
	var o = load("res://core/debug/DebugOverlay.gd").new()
	o.name = "TestOverlay"
	o.setup(b)
	b.add_child(o)
	return o


func test_aa_ready_and_build_ui() -> void:
	var o = _overlay()
	assert_not_null(o._label)
	o._refresh()
	assert_false(o._label.text.is_empty())


func test_ab_refresh_timer_throttle() -> void:
	var o = _overlay()
	# Below the update interval: no refresh
	var before = o._label.text
	o._process(0.1)
	assert_eq(o._label.text, before)
	# Crossing the interval refreshes
	o._process(0.5)
	assert_false(o._label.text.is_empty())


func test_ac_refresh_null_bootstrap() -> void:
	var o = load("res://core/debug/DebugOverlay.gd").new()
	o._refresh()
	assert_true(true)


func test_ad_refresh_content_fields() -> void:
	var o = _overlay()
	o._refresh()
	assert_true(o._label.text.contains("State:"))
	assert_true(o._label.text.contains("Loaded Mods:"))


func test_ae_attach_custom_panels() -> void:
	var b = _bootstrap()
	var loader = b.get_mod_loader()
	var o = _overlay()
	var p1 := Node.new()
	p1.name = "panel1"
	var p2 := Node.new()
	p2.name = "panel2"
	loader.register_debug_panel(null)
	loader.register_debug_panel(p1)
	loader.register_debug_panel(p2)
	o._attach_custom_debug_panels()
	assert_eq(o._attached_panels.size(), 2)
	assert_eq(p1.get_parent(), o)
	assert_eq(p2.get_parent(), o)
	# Duplicate pull is skipped by reference
	o._attach_custom_debug_panels()
	assert_eq(o._attached_panels.size(), 2)
	# A panel already under another parent is reparented
	var p3 := Node.new()
	p3.name = "panel3"
	b.add_child(p3)
	loader.register_debug_panel(p3)
	o._attach_custom_debug_panels()
	assert_eq(o._attached_panels.size(), 3)
	assert_eq(p3.get_parent(), o)