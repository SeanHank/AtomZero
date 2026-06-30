# AtomZero Persistence Service
# Design doc §7 Persistence scheme
#
# Data categories (§7.1):
#   - Global Mod config: mods/<mod_id>/config/<key>.json
#   - Global Mod runtime data: mods/<mod_id>/data/<key>.json
#   - World Mod config: saves/<WorldName>/mods/<mod_id>/config/<key>.json
#   - World Mod runtime data: saves/<WorldName>/mods/<mod_id>/data/<key>.json
#
# Atomic write (§7.2.3): write .tmp first, then rename to the target file
#
# Meta fields auto-filled: mod_id, mod_version, world_id, world_seed, created_at, updated_at
# Mods only need to care about the data part
class_name PersistenceService
extends RefCounted

const AUTOSAVE_INTERVAL: float = 300.0  # Autosave interval: 5 minutes (§7.2.4)

var _logger: AtomLogger = null
var _writable_root: String = ""
var _initialized: bool = false

# Global Mod meta info cache: mod_id -> {version}
var _global_mod_info: Dictionary = {}
# World Mod meta info cache: world_id -> {mod_id -> {version, world_seed}}
var _world_mod_info: Dictionary = {}

# Autosave timer (accumulated time)
var _autosave_timer: float = 0.0
# Registered autosave callbacks: [{mod_id, world_id (can be empty), callable}]
var _autosave_callbacks: Array = []


func init(logger: AtomLogger, writable_root: String) -> void:
	_logger = logger
	_writable_root = writable_root
	_ensure_dir(_writable_root)
	_initialized = true


# ============================================================
# Mod meta info registration (called by ModLoaderCore on load)
# ============================================================

# Register Global Mod info (used to auto-fill mod_id, mod_version)
func register_global_mod(mod_id: String, mod_version: String) -> void:
	_global_mod_info[mod_id] = {"version": mod_version}


# Unregister a Global Mod
func unregister_global_mod(mod_id: String) -> void:
	_global_mod_info.erase(mod_id)


# Register World Mod info (used to auto-fill world_id, world_seed)
func register_world_mod(world_id: String, world_seed: int, mod_id: String, mod_version: String) -> void:
	if not _world_mod_info.has(world_id):
		_world_mod_info[world_id] = {"seed": world_seed, "mods": {}}
	_world_mod_info[world_id]["mods"][mod_id] = {"version": mod_version}


# Unregister a World Mod
func unregister_world_mod(world_id: String, mod_id: String) -> void:
	if _world_mod_info.has(world_id):
		_world_mod_info[world_id]["mods"].erase(mod_id)


# Unregister all Mod info for an entire world
func unregister_world(world_id: String) -> void:
	_world_mod_info.erase(world_id)


# ============================================================
# Global Mod config
# ============================================================

func save_global_config(mod_id: String, key: String, data: Variant) -> void:
	var path := _global_config_path(mod_id, key)
	var meta := _build_meta_global(mod_id, "config")
	_save_json_atomic(path, meta, data)


func load_global_config(mod_id: String, key: String, default: Variant = null) -> Variant:
	var path := _global_config_path(mod_id, key)
	return _load_json_data(path, default)


# ============================================================
# Global Mod runtime data
# ============================================================

func save_global_data(mod_id: String, key: String, data: Variant) -> void:
	var path := _global_data_path(mod_id, key)
	var meta := _build_meta_global(mod_id, "data")
	_save_json_atomic(path, meta, data)


func load_global_data(mod_id: String, key: String, default: Variant = null) -> Variant:
	var path := _global_data_path(mod_id, key)
	return _load_json_data(path, default)


# ============================================================
# World Mod config
# ============================================================

func save_world_config(world_id: String, mod_id: String, key: String, data: Variant) -> void:
	var path := _world_config_path(world_id, mod_id, key)
	var meta := _build_meta_world(world_id, mod_id, "config")
	_save_json_atomic(path, meta, data)


func load_world_config(world_id: String, mod_id: String, key: String, default: Variant = null) -> Variant:
	var path := _world_config_path(world_id, mod_id, key)
	return _load_json_data(path, default)


# ============================================================
# World Mod runtime data
# ============================================================

func save_world_data(world_id: String, mod_id: String, key: String, data: Variant) -> void:
	var path := _world_data_path(world_id, mod_id, key)
	var meta := _build_meta_world(world_id, mod_id, "data")
	_save_json_atomic(path, meta, data)


func load_world_data(world_id: String, mod_id: String, key: String, default: Variant = null) -> Variant:
	var path := _world_data_path(world_id, mod_id, key)
	return _load_json_data(path, default)


# ============================================================
# Autosave (§7.2.4)
# ============================================================

# Register an autosave callback
# callable signature: func() -> {key: data, ...} (returns the data dict to save)
# or func() -> void (Mod calls save_* itself)
func register_autosave(mod_id: String, world_id: String, callable: Callable) -> void:
	_autosave_callbacks.append({"mod_id": mod_id, "world_id": world_id, "callable": callable})


func unregister_autosave(mod_id: String, world_id: String) -> void:
	var i := 0
	while i < _autosave_callbacks.size():
		var entry: Dictionary = _autosave_callbacks[i]
		if entry.mod_id == mod_id and entry.world_id == world_id:
			_autosave_callbacks.remove_at(i)
		else:
			i += 1


# Called every frame, accumulates time to trigger autosave (called by Bootstrap._process)
func update(delta: float) -> void:
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		_run_autosave()


func _run_autosave() -> void:
	if _logger:
		_logger.info("Persistence", "Triggered autosave")
	for entry in _autosave_callbacks:
		var callable: Callable = entry.callable
		var result: Variant = callable.call()
		if result is Dictionary:
			var mod_id: String = entry.mod_id
			var world_id: String = entry.world_id
			for key in result.keys():
				if world_id.is_empty():
					save_global_data(mod_id, key, result[key])
				else:
					save_world_data(world_id, mod_id, key, result[key])


# ============================================================
# Path computation
# ============================================================

func _global_config_path(mod_id: String, key: String) -> String:
	return _writable_root + "mods/" + mod_id + "/config/" + key + ".json"


func _global_data_path(mod_id: String, key: String) -> String:
	return _writable_root + "mods/" + mod_id + "/data/" + key + ".json"


func _world_config_path(world_id: String, mod_id: String, key: String) -> String:
	return _writable_root + "saves/" + world_id + "/mods/" + mod_id + "/config/" + key + ".json"


func _world_data_path(world_id: String, mod_id: String, key: String) -> String:
	return _writable_root + "saves/" + world_id + "/mods/" + mod_id + "/data/" + key + ".json"


# ============================================================
# Meta info building and atomic write
# ============================================================

func _build_meta_global(mod_id: String, kind: String) -> Dictionary:
	var mod_info: Dictionary = _global_mod_info.get(mod_id, {})
	var now := Time.get_datetime_string_from_system(false, true)
	var path := _global_config_path(mod_id, "_meta")  # placeholder
	# Read created_at of the existing file (preserve it)
	var existing_created := now
	if kind == "config":
		existing_created = _read_created_at(_global_config_path(mod_id, "_meta"))
	else:
		existing_created = _read_created_at(_global_data_path(mod_id, "_meta"))
	return {
		"mod_id": mod_id,
		"mod_version": mod_info.get("version", ""),
		"created_at": existing_created,
		"updated_at": now
	}


func _build_meta_world(world_id: String, mod_id: String, kind: String) -> Dictionary:
	var world_info: Dictionary = _world_mod_info.get(world_id, {})
	var mod_info: Dictionary = world_info.get("mods", {}).get(mod_id, {})
	var now := Time.get_datetime_string_from_system(false, true)
	var existing_created := now
	if kind == "config":
		existing_created = _read_created_at(_world_config_path(world_id, mod_id, "_meta"))
	else:
		existing_created = _read_created_at(_world_data_path(world_id, mod_id, "_meta"))
	return {
		"mod_id": mod_id,
		"mod_version": mod_info.get("version", ""),
		"world_id": world_id,
		"world_seed": world_info.get("seed", 0),
		"created_at": existing_created,
		"updated_at": now
	}


func _read_created_at(path: String) -> String:
	# _meta is a placeholder; actually read from any existing file in the same directory
	# Simplified: directly return the current time (on first write)
	return Time.get_datetime_string_from_system(false, true)


# Atomic write JSON (§7.2.3)
func _save_json_atomic(path: String, meta: Dictionary, data: Variant) -> void:
	var dir_path := path.get_base_dir()
	_ensure_dir(dir_path)
	var obj := {
		"mod_id": meta.get("mod_id", ""),
		"mod_version": meta.get("mod_version", ""),
		"created_at": meta.get("created_at", ""),
		"updated_at": meta.get("updated_at", ""),
		"data": data
	}
	if meta.has("world_id"):
		obj["world_id"] = meta["world_id"]
	if meta.has("world_seed"):
		obj["world_seed"] = meta["world_seed"]
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		if _logger:
			_logger.error("Persistence", "Unable to write file: %s" % tmp_path)
		return
	f.store_string(JSON.stringify(obj, "\t"))
	f.close()
	# Atomic rename
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK and _logger:
		_logger.error("Persistence", "Rename failed: %s -> %s (err=%d)" % [tmp_path, path, err])


func _load_json_data(path: String, default: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return default
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		if _logger:
			_logger.warn("Persistence", "JSON parse failed: %s" % path)
		return default
	return parsed.get("data", default)


func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
