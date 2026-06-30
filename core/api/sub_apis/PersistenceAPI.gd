# Persistence API (design doc §6.1.1 and §7)
# Mods call via _api.persistence.*
# Automatically injects mod_id and world_id context
class_name PersistenceAPI
extends RefCounted

var _persistence: PersistenceService = null
var _mod_id: String = ""
var _world_id: String = ""  # Current world ID (set by ModContext for World Mods)


func _init(persistence: PersistenceService, mod_id: String, world_id: String = "") -> void:
	_persistence = persistence
	_mod_id = mod_id
	_world_id = world_id


# Config (typically user-adjustable settings)
func save_config(key: String, data: Variant) -> void:
	if not _world_id.is_empty():
		_persistence.save_world_config(_world_id, _mod_id, key, data)
	else:
		_persistence.save_global_config(_mod_id, key, data)


func load_config(key: String, default: Variant = null) -> Variant:
	if not _world_id.is_empty():
		return _persistence.load_world_config(_world_id, _mod_id, key, default)
	return _persistence.load_global_config(_mod_id, key, default)


# Runtime data (typically game progress, state)
func save_data(key: String, data: Variant) -> void:
	if not _world_id.is_empty():
		_persistence.save_world_data(_world_id, _mod_id, key, data)
	else:
		_persistence.save_global_data(_mod_id, key, data)


func load_data(key: String, default: Variant = null) -> Variant:
	if not _world_id.is_empty():
		return _persistence.load_world_data(_world_id, _mod_id, key, default)
	return _persistence.load_global_data(_mod_id, key, default)


# Register an autosave callback (triggered every 5 minutes)
# callable signature: func() -> Dictionary (returns the {key: data} to save)
func register_autosave(callable: Callable) -> void:
	_persistence.register_autosave(_mod_id, _world_id, callable)


func unregister_autosave() -> void:
	_persistence.unregister_autosave(_mod_id, _world_id)
