# AtomZero custom ResourceFormatLoader
# Design doc §4.3.1 mod:// protocol based custom ResourceFormatLoader
#
# By registering a custom ResourceFormatLoader, uniformly handles mod:// protocol paths,
# deeply integrated with the Godot resource system.
#
# Cache key strategy (§4.3.1):
#   - Uniformly use CACHE_MODE_REUSE, with real_path as the cache key
#   - Multiple mod:// virtual paths resolving to the same real_path share the same resource instance
#   - Avoids duplicate loading and memory doubling
class_name ModResourceFormatLoader
extends ResourceFormatLoader

var _vfs: ModVFS = null


func _init(vfs: ModVFS = null) -> void:
	_vfs = vfs


# Register with ResourceLoader (at_front=true to take priority over native loaders)
func register() -> void:
	if _vfs == null:
		return
	ResourceLoader.add_resource_format_loader(self, true)


# Unregister
func unregister() -> void:
	if _vfs == null:
		return
	ResourceLoader.remove_resource_format_loader(self)


# Return all Godot native extensions (empty array, only handles mod:// paths)
# Note: returning empty avoids conflicts with native loaders; distinguished via _exists path detection
func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray()


# Handle all resource types
func _handles_type(type: StringName) -> bool:
	return true


# Load a resource
# Only handles mod:// protocol paths; other paths return null and are handled by the native loader
func _load(path: String, original_path: String, use_sub_threads: bool, cache_mode: int) -> Variant:
	if not path.begins_with("mod://"):
		return null
	if _vfs == null:
		return null
	var real_path := _vfs.resolve_virtual_path(path)
	if real_path.is_empty():
		return null
	# Record the mapping from virtual path to real path (used to clear cache references by prefix on world unload)
	_vfs.record_path_mapping(path, real_path)
	# Uniformly use CACHE_MODE_REUSE, with real_path as the cache key
	# Multiple mod:// virtual paths resolving to the same real_path share the same resource instance
	return ResourceLoader.load(real_path, "", ResourceLoader.CACHE_MODE_REUSE)


# Check whether a path exists
func _exists(path: String) -> bool:
	if not path.begins_with("mod://"):
		return false
	if _vfs == null:
		return false
	return not _vfs.resolve_virtual_path(path).is_empty()
