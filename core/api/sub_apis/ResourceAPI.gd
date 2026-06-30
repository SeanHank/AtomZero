# Resource API (design doc §6.1.1 and §4.3)
# Based on the mod:// protocol, deeply integrated with ResourceLoader
class_name ResourceAPI
extends RefCounted

var _vfs: ModVFS = null
var _mod_id: String = ""
var _world_id: String = ""


func _init(vfs: ModVFS, mod_id: String, world_id: String = "") -> void:
	_vfs = vfs
	_mod_id = mod_id
	_world_id = world_id


# Synchronously load a resource (blocking)
# mod_id: the Mod the resource belongs to (defaults to the current Mod)
# relative_path: path relative to the Mod root directory
func load(mod_id: String = "", relative_path: String = "") -> Resource:
	# Support two call styles: load("mod_id", "path") or load("path")
	var actual_mod := mod_id
	var actual_path := relative_path
	if relative_path.is_empty():
		# Single-argument call: load("path")
		actual_path = mod_id
		actual_mod = _mod_id
	if actual_mod.is_empty():
		actual_mod = _mod_id
	var virtual_path := _build_virtual_path(actual_mod, actual_path)
	return ResourceLoader.load(virtual_path, "", ResourceLoader.CACHE_MODE_REUSE)


# Asynchronously request a load (non-blocking)
func load_threaded(mod_id: String = "", relative_path: String = "") -> void:
	var actual_mod := mod_id
	var actual_path := relative_path
	if relative_path.is_empty():
		actual_path = mod_id
		actual_mod = _mod_id
	if actual_mod.is_empty():
		actual_mod = _mod_id
	var virtual_path := _build_virtual_path(actual_mod, actual_path)
	ResourceLoader.load_threaded_request(virtual_path)


# Get the threaded load status
# Returns ResourceLoader.THREAD_LOAD_*
func get_load_threaded_status(mod_id: String = "", relative_path: String = "") -> int:
	var actual_mod := mod_id
	var actual_path := relative_path
	if relative_path.is_empty():
		actual_path = mod_id
		actual_mod = _mod_id
	if actual_mod.is_empty():
		actual_mod = _mod_id
	var virtual_path := _build_virtual_path(actual_mod, actual_path)
	return ResourceLoader.load_threaded_get_status(virtual_path)


# Get the threaded load result
func get_load_threaded(mod_id: String = "", relative_path: String = "") -> Resource:
	var actual_mod := mod_id
	var actual_path := relative_path
	if relative_path.is_empty():
		actual_path = mod_id
		actual_mod = _mod_id
	if actual_mod.is_empty():
		actual_mod = _mod_id
	var virtual_path := _build_virtual_path(actual_mod, actual_path)
	return ResourceLoader.load_threaded_get(virtual_path)


# Check whether a resource exists
func exists(mod_id: String = "", relative_path: String = "") -> bool:
	var actual_mod := mod_id
	var actual_path := relative_path
	if relative_path.is_empty():
		actual_path = mod_id
		actual_mod = _mod_id
	if actual_mod.is_empty():
		actual_mod = _mod_id
	var virtual_path := _build_virtual_path(actual_mod, actual_path)
	# Resolve via VFS to check whether it exists at a physical path
	var real_path := _vfs.resolve_virtual_path(virtual_path)
	return not real_path.is_empty()


# Build a mod:// virtual path
func _build_virtual_path(mod_id: String, rel_path: String) -> String:
	if not _world_id.is_empty():
		return ModVFS.make_world_path(_world_id, mod_id, rel_path)
	return ModVFS.make_global_path(mod_id, rel_path)
