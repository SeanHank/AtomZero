extends "res://tests/runner/TestCase.gd"


func test_from_file_valid() -> void:
	var desc := ModDescriptor.from_file("res://tests/fixtures/mods/gm1/mod.json")
	assert_not_null(desc)
	assert_true(desc.valid)
	assert_eq(desc.mod_id, "gm1")
	assert_eq(desc.mod_type, "global")
	assert_eq(desc.entry, "gm1.gd")
	assert_eq(desc.version, "1.0.0")
	assert_true(desc.mod_dir.ends_with("tests/fixtures/mods/gm1"))


func test_from_file_missing() -> void:
	var desc := ModDescriptor.from_file("res://tests/fixtures/mods/does_not_exist/mod.json")
	assert_false(desc.valid)
	assert_true(desc.error_msg.contains("does not exist"))


func test_from_file_corrupt_json() -> void:
	ensure_dir("res://.test_tmp/desc/corrupt")
	write_text_file("res://.test_tmp/desc/corrupt/mod.json", "{not valid json")
	var desc := ModDescriptor.from_file("res://.test_tmp/desc/corrupt/mod.json")
	assert_false(desc.valid)
	assert_true(desc.error_msg.contains("parse failed"))


func test_from_dict_valid() -> void:
	var desc := ModDescriptor.from_dict({
		"mod_id": "testmod",
		"name": "T",
		"version": "1.0.0",
		"game_version": ">=2026.9.0",
		"mod_type": "global",
		"entry": "t.gd",
	}, "res://mods/testmod")
	assert_true(desc.valid)
	assert_eq(desc.mod_dir, "res://mods/testmod")
	assert_eq(desc.load_priority, 1000)
	assert_eq(desc.status, GameState.OK)


func test_from_dict_fields_mapped() -> void:
	var desc := ModDescriptor.from_dict({
		"mod_id": "testmod",
		"name": "T",
		"version": "1.5.0",
		"game_version": "*",
		"author": "a",
		"description": "d",
		"url": "u",
		"license": "MIT",
		"mod_type": "world",
		"entry": "t.gd",
		"dependencies": [{"id": "x", "version": "1.0.0"}],
		"soft_dependencies": [{"id": "y"}],
		"resource_overrides": [{"target_mod": "z", "target_path": "p", "source_path": "s"}],
		"load_order": {"priority": 42, "load_before": ["b"], "load_after": ["a"]},
	})
	assert_eq(desc.version, "1.5.0")
	assert_eq(desc.mod_type, "world")
	assert_eq(desc.load_priority, 42)
	assert_eq(desc.load_before, ["b"])
	assert_eq(desc.load_after, ["a"])
	assert_eq(desc.dependencies.size(), 1)


func test_validate_branches() -> void:
	var base := {
		"mod_id": "m",
		"name": "n",
		"version": "1.0.0",
		"game_version": "*",
		"mod_type": "global",
		"entry": "m.gd",
	}
	var d1 := ModDescriptor.from_dict(base.duplicate())
	assert_true(d1.valid)

	var empty_id := ModDescriptor.from_dict(base.duplicate())
	empty_id.mod_id = ""
	empty_id._validate()
	assert_false(empty_id.valid)
	assert_true(empty_id.error_msg.contains("mod_id is empty"))

	var bad_id := ModDescriptor.from_dict(base.duplicate())
	bad_id.mod_id = "9Bad-ID"
	bad_id._validate()
	assert_false(bad_id.valid)
	assert_true(bad_id.error_msg.contains("format invalid"))

	var empty_name := ModDescriptor.from_dict(base.duplicate())
	empty_name.name = ""
	empty_name._validate()
	assert_false(empty_name.valid)
	assert_true(empty_name.error_msg.contains("name is empty"))

	var empty_version := ModDescriptor.from_dict(base.duplicate())
	empty_version.version = ""
	empty_version._validate()
	assert_false(empty_version.valid)
	assert_true(empty_version.error_msg.contains("version is empty"))

	var empty_gv := ModDescriptor.from_dict(base.duplicate())
	empty_gv.game_version = ""
	empty_gv._validate()
	assert_false(empty_gv.valid)
	assert_true(empty_gv.error_msg.contains("game_version"))

	var bad_type := ModDescriptor.from_dict(base.duplicate())
	bad_type.mod_type = "silly"
	bad_type._validate()
	assert_false(bad_type.valid)
	assert_true(bad_type.error_msg.contains("mod_type"))

	var empty_entry := ModDescriptor.from_dict(base.duplicate())
	empty_entry.entry = ""
	empty_entry._validate()
	assert_false(empty_entry.valid)
	assert_true(empty_entry.error_msg.contains("entry is empty"))


func test_is_valid_mod_id() -> void:
	var d := ModDescriptor.new()
	assert_true(d._is_valid_mod_id("abc"))
	assert_true(d._is_valid_mod_id("a1_z"))
	assert_false(d._is_valid_mod_id(""))
	assert_false(d._is_valid_mod_id("9ab"))
	assert_false(d._is_valid_mod_id("A"))
	assert_false(d._is_valid_mod_id("a-b"))
	assert_false(d._is_valid_mod_id("a.b"))


func test_get_dependency_ids() -> void:
	var desc := ModDescriptor.from_dict({
		"mod_id": "m",
		"name": "n",
		"version": "1",
		"game_version": "*",
		"entry": "m.gd",
		"dependencies": [{"id": "b"}, {"id": "c", "version": "2.0.0"}],
	})
	assert_eq(desc.get_dependency_ids(), ["b", "c"])


func test_get_soft_dependency_ids() -> void:
	var desc := ModDescriptor.from_dict({
		"mod_id": "m",
		"name": "n",
		"version": "1",
		"game_version": "*",
		"entry": "m.gd",
		"soft_dependencies": [{"id": "s1"}, {"id": "s2"}],
	})
	assert_eq(desc.get_soft_dependency_ids(), ["s1", "s2"])


func test_to_string_repr() -> void:
	var desc := ModDescriptor.from_dict({
		"mod_id": "m",
		"name": "n",
		"version": "9.9.9",
		"game_version": "*",
		"entry": "m.gd",
	})
	assert_true(desc.to_string_repr().contains("m v9.9.9"))
	assert_true(desc.to_string_repr().contains("valid=true"))