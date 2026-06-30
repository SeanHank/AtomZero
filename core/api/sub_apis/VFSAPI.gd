# Virtual File System API (design doc §6.1.1 and §4.3)
# Mods call via _api.vfs.*
class_name VFSAPI
extends RefCounted

var _vfs: ModVFS = null
var _mod_id: String = ""
var _world_id: String = ""


func _init(vfs: ModVFS, mod_id: String, world_id: String = "") -> void:
	_vfs = vfs
	_mod_id = mod_id
	_world_id = world_id


# Get absolute path of the Mod data directory
func get_mod_data_dir() -> String:
	if not _world_id.is_empty():
		var world_mods_dir := Bootstrap.get_world_mods_dir(_world_id)
		return world_mods_dir + _mod_id + "/data/"
	return Bootstrap.get_global_mods_dir() + _mod_id + "/data/"


# Get absolute path of the Mod config directory
func get_mod_config_dir() -> String:
	if not _world_id.is_empty():
		var world_mods_dir := Bootstrap.get_world_mods_dir(_world_id)
		return world_mods_dir + _mod_id + "/config/"
	return Bootstrap.get_global_mods_dir() + _mod_id + "/config/"


# Resolve a mod:// virtual path to a physical path
func resolve_virtual_path(virtual_path: String) -> String:
	return _vfs.resolve_virtual_path(virtual_path)


# Build a Global Mod virtual path
func make_global_path(mod_id: String, rel_path: String) -> String:
	return ModVFS.make_global_path(mod_id, rel_path)


# Build a World Mod virtual path
func make_world_path(world_id: String, mod_id: String, rel_path: String) -> String:
	return ModVFS.make_world_path(world_id, mod_id, rel_path)


# Get the Mod physical directory
func get_mod_dir() -> String:
	if not _world_id.is_empty():
		return _vfs.get_world_mod_dir(_world_id, _mod_id)
	return _vfs.get_global_mod_dir(_mod_id)
