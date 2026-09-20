extends "res://tests/runner/TestCase.gd"

const GM1 := "res://tests/fixtures/mods/gm1"


func _make_loader() -> ModResourceFormatLoader:
	var vfs := ModVFS.new()
	vfs.init(AtomLogger.new())
	vfs.mount_global("gm1", GM1, [])
	return ModResourceFormatLoader.new(vfs)


func test_uninitialized_noop() -> void:
	var l := ModResourceFormatLoader.new()
	l.register()
	l.unregister()
	assert_eq(l._get_recognized_extensions(), PackedStringArray())
	assert_true(l._handles_type("Texture2D"))
	assert_null(l._load("mod://global/gm1/gm1.gd", "", false, 0))
	assert_false(l._exists("mod://global/gm1/gm1.gd"))
	assert_null(l._load("notmod://x", "", false, 0))


func test_extension_and_type_handlers() -> void:
	var l := _make_loader()
	assert_eq(l._get_recognized_extensions(), PackedStringArray())
	assert_true(l._handles_type("Texture2D"))
	assert_true(l._handles_type("PackedScene"))


func test_exists() -> void:
	var l := _make_loader()
	assert_true(l._exists("mod://global/gm1/gm1.gd"))
	assert_false(l._exists("mod://global/gm1/gone.gd"))
	assert_false(l._exists("res://core/Main.gd"))


func test_load_resolves_and_records_mapping() -> void:
	var l := _make_loader()
	var res: Variant = l._load("mod://global/gm1/gm1.gd", "mod://global/gm1/gm1.gd", false, ResourceLoader.CACHE_MODE_REUSE)
	assert_not_null(res)
	assert_true(res is Script)
	assert_true(l._vfs._path_mappings.has("mod://global/gm1/gm1.gd"))


func test_load_unresolvable_returns_null() -> void:
	var l := _make_loader()
	assert_null(l._load("mod://global/gm1/absent.gd", "", false, 0))


func test_register_and_unregister() -> void:
	var l := _make_loader()
	l.register()
	l.unregister()
	assert_true(true)