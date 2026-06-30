# AtomZero Hash Whitelist Verifier (TOFU model)
# Design doc §9.2 Hash whitelist verification
#
# Trust On First Use model:
#   1. First load: compute SHA256 of all Mod metadata files + verify binary file size (manifest.json),
#      store into the whitelist hash_whitelist.json
#   2. Subsequent loads: recompute hash and compare against whitelist; mismatch rejects loading (HASH_MISMATCH)
#
# Hash strategy (§9.2.3):
#   - Metadata files (.gd/.json/.tres/.tscn): streaming 64KB chunk read, constant memory
#   - Binary resources (.png/.wav/.ogg/.ttf etc.): O(1) stat verification via manifest.json size declaration
#   - manifest.json itself participates in hashing as a metadata file
#   - Development Mode has no manifest, only metadata files are verified
class_name HashVerifier
extends RefCounted

const CHUNK_SIZE: int = 65536  # 64KB streaming read chunk size (constant memory usage)
const METADATA_EXTS: Array[String] = [".gd", ".json", ".tres", ".tscn"]
const WHITELIST_FILENAME: String = "hash_whitelist.json"

var _logger: AtomLogger = null
var _writable_root: String = ""
var _whitelist_path: String = ""
var _whitelist: Dictionary = {}      # mod_id -> { version, files_hash, trusted_at, file_count }
var _initialized: bool = false


# Initialize
# writable_root: writable root path (Bootstrap.get_writable_root())
func init(logger: AtomLogger, writable_root: String) -> void:
	_logger = logger
	_writable_root = writable_root
	_whitelist_path = writable_root + WHITELIST_FILENAME
	_load_whitelist()
	_initialized = true


# Verify a Mod
# mod_id: Mod unique identifier
# mod_dir: Mod physical directory absolute path
# mod_version: Mod version (for whitelist records)
# Returns true on pass (first use trusts directly or hash matches), false on rejection
func verify(mod_id: String, mod_dir: String, mod_version: String = "") -> bool:
	if not _initialized:
		push_error("HashVerifier not initialized")
		return false
	var current_hash := compute_mod_hash(mod_dir)
	var stored: Dictionary = _whitelist.get(mod_id, {})
	var stored_hash: String = stored.get("files_hash", "")
	if stored_hash.is_empty():
		# First use: trust directly and store into whitelist (TOFU model, no confirmation dialog)
		# Design doc §9.2.1: first load auto-trusts, simplifying the flow to avoid blocking Bootstrap
		_store_trust(mod_id, current_hash, mod_version, _count_metadata_files(mod_dir))
		if _logger:
			_logger.info("HashVerifier", "Mod %s first load, hash recorded to whitelist" % mod_id)
		return true
	if current_hash != stored_hash:
		if _logger:
			_logger.error("HashVerifier", "Mod %s hash mismatch, refusing to load" % mod_id)
		return false
	return true


# Reset the trust of a specified Mod (for the console `hash reset` command)
func reset_trust(mod_id: String) -> void:
	if _whitelist.has(mod_id):
		_whitelist.erase(mod_id)
		_save_whitelist()
		if _logger:
			_logger.info("HashVerifier", "Reset trust for Mod %s" % mod_id)


# Get all Mod info in the whitelist (for the console `hash list` command)
func list_trusted() -> Dictionary:
	return _whitelist.duplicate(true)


# ============================================================
# Hash computation
# ============================================================

# Compute the comprehensive hash of a Mod (streaming 64KB chunks, constant memory)
# Design doc §9.2.3
func compute_mod_hash(mod_dir: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	# 1. Streaming hash of metadata files
	_hash_metadata_files(ctx, mod_dir)
	# 2. Binary files: verify manifest + size (without reading file contents)
	_verify_binary_files(ctx, mod_dir)
	return ctx.finish().hex_encode()


# Recursively traverse the directory, streaming hash of metadata files
func _hash_metadata_files(ctx: HashingContext, dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		# Skip the .godot import cache directory (should not participate in hashing)
		if dir.current_is_dir():
			if name != ".godot" and name != ".cache" and name != "config" and name != "data":
				_hash_metadata_files(ctx, dir_path + "/" + name)
		else:
			if _is_metadata_file(name):
				_hash_file_streaming(ctx, dir_path + "/" + name)
		name = dir.get_next()
	dir.list_dir_end()


# Streaming chunked file read, memory usage is constant at 64KB
func _hash_file_streaming(ctx: HashingContext, file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		# File unreadable: feed a marker into the hash to ensure the hash value changes
		ctx.update(("UNREADABLE:" + file_path).to_utf8_buffer())
		return
	# Also feed the file path into the hash, to avoid hash collisions when different files have the same content
	ctx.update(file_path.to_utf8_buffer())
	while file.get_position() < file.get_length():
		var remaining := file.get_length() - file.get_position()
		var chunk_size := mini(CHUNK_SIZE, remaining)
		ctx.update(file.get_buffer(chunk_size))
	file.close()


# Verify binary files: stat check via the manifest.json size declaration
func _verify_binary_files(ctx: HashingContext, mod_dir: String) -> void:
	var manifest_path := mod_dir + "/manifest.json"
	if not FileAccess.file_exists(manifest_path):
		# No manifest in Development Mode, skip
		return
	# manifest itself has already been hashed as a metadata file by _hash_metadata_files
	# Here we additionally verify the size of binary files
	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	var parsed: Variant = JSON.parse_string(manifest_text)
	if parsed == null or not (parsed is Dictionary):
		ctx.update("MANIFEST_INVALID".to_utf8_buffer())
		return
	var binary_files: Dictionary = parsed.get("binary_files", {})
	# Sort keys to ensure stable order
	var keys := binary_files.keys()
	keys.sort()
	for key in keys:
		var rel_path: String = key
		var entry: Dictionary = binary_files[key]
		var expected_size: int = int(entry.get("size", -1))
		var abs_path := mod_dir + "/" + rel_path
		if not FileAccess.file_exists(abs_path):
			ctx.update(("MISSING:" + rel_path).to_utf8_buffer())
			continue
		var f := FileAccess.open(abs_path, FileAccess.READ)
		if f == null:
			ctx.update(("UNREADABLE:" + rel_path).to_utf8_buffer())
			continue
		var actual_size := f.get_length()
		f.close()
		if actual_size != expected_size:
			ctx.update(("SIZE_MISMATCH:" + rel_path + ":" + str(actual_size) + ":" + str(expected_size)).to_utf8_buffer())
		else:
			ctx.update(("OK:" + rel_path + ":" + str(expected_size)).to_utf8_buffer())


func _is_metadata_file(name: String) -> bool:
	for ext in METADATA_EXTS:
		if name.ends_with(ext):
			return true
	return false


func _count_metadata_files(mod_dir: String) -> int:
	return _count_metadata_files_recursive(mod_dir)


func _count_metadata_files_recursive(dir_path: String) -> int:
	var count := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		if dir.current_is_dir():
			if name != ".godot" and name != ".cache" and name != "config" and name != "data":
				count += _count_metadata_files_recursive(dir_path + "/" + name)
		else:
			if _is_metadata_file(name):
				count += 1
		name = dir.get_next()
	dir.list_dir_end()
	return count


# ============================================================
# Whitelist persistence
# ============================================================

func _store_trust(mod_id: String, files_hash: String, mod_version: String, file_count: int) -> void:
	_whitelist[mod_id] = {
		"version": mod_version,
		"files_hash": files_hash,
		"trusted_at": Time.get_datetime_string_from_system(false, true),
		"file_count": file_count
	}
	_save_whitelist()


func _load_whitelist() -> void:
	if not FileAccess.file_exists(_whitelist_path):
		_whitelist = {}
		return
	var text := FileAccess.get_file_as_string(_whitelist_path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		_whitelist = {}
		return
	# Whitelist format: {"mods": {mod_id -> entry}}
	# _whitelist internally stores mod_id -> entry (without the "mods" wrapper layer)
	var mods: Dictionary = parsed.get("mods", {})
	if mods.is_empty():
		# Compatible with direct format mod_id -> entry
		_whitelist = parsed
	else:
		_whitelist = mods


func _save_whitelist() -> void:
	# Atomic write
	var tmp_path := _whitelist_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		if _logger:
			_logger.error("HashVerifier", "Unable to write whitelist: %s" % tmp_path)
		return
	var data := {"mods": _whitelist}
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp_path, _whitelist_path)
