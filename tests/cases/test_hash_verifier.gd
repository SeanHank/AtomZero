extends "res://tests/runner/TestCase.gd"

const ROOT := "res://.test_tmp/hash/"


func _make_hv(unique: String = "") -> Dictionary:
	var root := ROOT + unique
	if not root.ends_with("/"):
		root += "/"
	ensure_dir(root)
	var logger := AtomLogger.new()
	logger.init(root + "logs/", null)
	var hv := HashVerifier.new()
	hv.init(logger, root)
	return {"hv": hv, "root": root}


func _make_mod_dir_root(unique: String) -> String:
	var root := ROOT + unique + "/"
	ensure_dir(root)
	return root


func _write_mod(dir: String, content: String = "var x := 1\n") -> void:
	ensure_dir(dir)
	write_text_file(dir + "mod.json", '{"mod_id": "m", "version": "1.0.0"}')
	write_text_file(dir + "m.gd", content)


func test_first_use_trusts_and_persists() -> void:
	var ctx := _make_hv("t1")
	var hv: HashVerifier = ctx.hv
	var mod_dir := _make_mod_dir_root("t1_mod")
	_write_mod(mod_dir)
	var ok := hv.verify("m", mod_dir, "1.0.0")
	assert_true(ok)
	var trusted: Dictionary = hv.list_trusted()
	assert_true(trusted.has("m"))
	assert_eq(trusted["m"].version, "1.0.0")
	assert_true(FileAccess.file_exists(ctx.root + "hash_whitelist.json"))


func test_verify_repeat_and_mismatch() -> void:
	var ctx := _make_hv("t2")
	var hv: HashVerifier = ctx.hv
	var mod_dir := _make_mod_dir_root("t2_mod")
	_write_mod(mod_dir, "var a := 1\n")
	assert_true(hv.verify("m", mod_dir, "1.0.0"))
	assert_true(hv.verify("m", mod_dir, "1.0.0"))
	write_text_file(mod_dir + "m.gd", "var a := 2   # changed\n")
	assert_false(hv.verify("m", mod_dir, "1.0.0"))


func test_reset_trust() -> void:
	var ctx := _make_hv("t3")
	var hv: HashVerifier = ctx.hv
	var mod_dir := _make_mod_dir_root("t3_mod")
	_write_mod(mod_dir)
	assert_true(hv.verify("m", mod_dir, "1.0.0"))
	hv.reset_trust("m")
	assert_false(hv.list_trusted().has("m"))
	hv.reset_trust("never_existed")
	assert_true(true)


func test_verify_not_initialized() -> void:
	var hv := HashVerifier.new()
	var res := hv.verify("m", "res://", "1.0.0")
	assert_false(res)


func test_compute_mod_hash_shape() -> void:
	var ctx := _make_hv("t4")
	var hv: HashVerifier = ctx.hv
	var mod_dir := _make_mod_dir_root("t4_mod")
	_write_mod(mod_dir)
	var h := hv.compute_mod_hash(mod_dir)
	assert_eq(h.length(), 64)


func test_metadata_ext_detection() -> void:
	var ctx := _make_hv("t5")
	var hv: HashVerifier = ctx.hv
	assert_true(hv._is_metadata_file("a.gd"))
	assert_true(hv._is_metadata_file("a.json"))
	assert_true(hv._is_metadata_file("a.aaaa.tres"))
	assert_true(hv._is_metadata_file("scene.tscn"))
	assert_false(hv._is_metadata_file("a.png"))
	assert_false(hv._is_metadata_file("a.txt"))


func test_hash_file_streaming_unreadable() -> void:
	var ctx := _make_hv("t6")
	var hv: HashVerifier = ctx.hv
	var hctx := HashingContext.new()
	assert_eq(hctx.start(HashingContext.HASH_SHA256), OK)
	# Passing a directory path makes FileAccess.open fail -> UNREADABLE marker
	ensure_dir(ROOT + "t6_dir")
	hv._hash_file_streaming(hctx, ROOT + "t6_dir")
	var digest := hctx.finish().hex_encode()
	assert_false(digest.is_empty())


func test_verify_binary_manifest_covered() -> void:
	var ctx := _make_hv("t7")
	var hv: HashVerifier = ctx.hv
	var mod_dir := _make_mod_dir_root("t7_mod")
	ensure_dir(mod_dir)
	write_text_file(mod_dir + "manifest.json", JSON.stringify({
		"binary_files": {
			"ok.bin": {"size": 3},
			"missing.bin": {"size": 2},
			"wrong.bin": {"size": 100}
		}
	}))
	write_text_file(mod_dir + "ok.bin", "abc")
	write_text_file(mod_dir + "wrong.bin", "1")
	var h := hv.compute_mod_hash(mod_dir)
	assert_eq(h.length(), 64)


func test_verify_binary_manifest_invalid() -> void:
	var ctx := _make_hv("t8")
	var hv: HashVerifier = ctx.hv
	var mod_dir := _make_mod_dir_root("t8_mod")
	ensure_dir(mod_dir)
	write_text_file(mod_dir + "manifest.json", "{oops")
	var h := hv.compute_mod_hash(mod_dir)
	assert_eq(h.length(), 64)


func test_count_metadata_files_recursive() -> void:
	var ctx := _make_hv("t9")
	var hv: HashVerifier = ctx.hv
	var mod_dir := _make_mod_dir_root("t9_mod")
	ensure_dir(mod_dir + "sub/")
	write_text_file(mod_dir + "a.gd", "")
	write_text_file(mod_dir + "b.json", "")
	write_text_file(mod_dir + "c.png", "")
	write_text_file(mod_dir + "sub/d.tres", "")
	assert_eq(hv._count_metadata_files(mod_dir), 3)
	assert_eq(hv._count_metadata_files_recursive(mod_dir + "missing"), 0)


func test_load_whitelist_variants() -> void:
	var ctx := _make_hv("t10")
	var hv: HashVerifier = ctx.hv
	# Wrapper format with "mods" key
	write_text_file(ctx.root + "w.json", '{"mods": {"a": {"version": "1"}}}')
	hv._whitelist_path = ctx.root + "w.json"
	hv._load_whitelist()
	assert_true(hv.list_trusted().has("a"))
	# Direct format
	write_text_file(ctx.root + "d.json", '{"b": {"version": "2"}}')
	hv._whitelist_path = ctx.root + "d.json"
	hv._load_whitelist()
	assert_true(hv.list_trusted().has("b"))
	# Corrupt JSON
	write_text_file(ctx.root + "c.json", "{nope")
	hv._whitelist_path = ctx.root + "c.json"
	hv._load_whitelist()
	# Missing file
	hv._whitelist_path = ctx.root + "none.json"
	hv._load_whitelist()
	assert_true(hv.list_trusted().is_empty())


func test_save_whitelist_write_failure() -> void:
	var ctx := _make_hv("t11")
	var hv: HashVerifier = ctx.hv
	var mod_dir := _make_mod_dir_root("t11_mod")
	_write_mod(mod_dir)
	assert_true(hv.verify("m", mod_dir, "1.0.0"))
	# Block the .tmp path with a directory so any future save fails gracefully
	ensure_dir(ctx.root + "hash_whitelist.json.tmp")
	hv.reset_trust("m")
	assert_true(true)