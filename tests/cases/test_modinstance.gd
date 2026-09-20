extends "res://tests/runner/TestCase.gd"


func _make_desc() -> ModDescriptor:
	return ModDescriptor.from_dict({
		"mod_id": "m", "name": "n", "version": "1.0.0", "game_version": "*", "entry": "m.gd",
	})


func test_init_with_desc() -> void:
	var desc := _make_desc()
	var inst := ModInstance.new(desc)
	assert_eq(inst.descriptor, desc)
	assert_false(inst.loaded)


func test_init_without_desc() -> void:
	var inst := ModInstance.new()
	assert_null(inst.descriptor)


func test_set_instance() -> void:
	var desc := _make_desc()
	var node := Node.new()
	var inst := ModInstance.new(desc)
	inst.set_instance(node, null)
	assert_eq(inst.script_instance, node)
	assert_eq(inst.node, node)


func test_getters() -> void:
	var desc := ModDescriptor.from_dict({
		"mod_id": "m", "name": "n", "version": "3.2.1", "game_version": "*", "entry": "m.gd",
	})
	var inst := ModInstance.new(desc)
	assert_eq(inst.get_mod_id(), "m")
	assert_eq(inst.get_mod_type(), "global")
	assert_eq(inst.get_version(), "3.2.1")
	var empty := ModInstance.new()
	assert_eq(empty.get_mod_id(), "")
	assert_eq(empty.get_mod_type(), "")
	assert_eq(empty.get_version(), "")


func test_call_if_exists_null_instance() -> void:
	var inst := ModInstance.new()
	inst.call_if_exists("_on_bootstrap")
	assert_true(true)


func test_call_if_exists_with_fixture_instance() -> void:
	var script := load("res://tests/fixtures/mods/gm1/gm1.gd")
	var node: Node = script.new()
	var inst := ModInstance.new(_make_desc())
	inst.set_instance(node, null)
	inst.call_if_exists("_on_bootstrap")
	assert_true(true)


func test_call_if_exists_absent_method() -> void:
	var script := load("res://tests/fixtures/mods/gm1/gm1.gd")
	var node: Node = script.new()
	var inst := ModInstance.new(_make_desc())
	inst.set_instance(node, null)
	inst.call_if_exists("_never_defined_method__")
	assert_true(true)