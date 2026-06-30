# Registry API (design doc §6.1.1 and §9)
# Mods call via _api.registry.*
class_name RegistryAPI
extends RefCounted

var _registry: RegistrySystem = null
var _mod_id: String = ""
var _world_id: String = ""  # Current world ID (set by ModContext for World Mods)


func _init(registry: RegistrySystem, mod_id: String, world_id: String = "") -> void:
	_registry = registry
	_mod_id = mod_id
	_world_id = world_id


# Register a block
func register_block(id: String, script: Script) -> void:
	# Automatically prefix with mod_id if id has no colon
	var full_id := _qualify_id(id)
	if not _world_id.is_empty():
		_registry.register_world_block(_world_id, full_id, script)
	else:
		_registry.register_block(full_id, script)


# Register an item
func register_item(id: String, script: Script) -> void:
	var full_id := _qualify_id(id)
	if not _world_id.is_empty():
		_registry.register_world_item(_world_id, full_id, script)
	else:
		_registry.register_item(full_id, script)


# Register an entity
func register_entity(id: String, script: Script) -> void:
	var full_id := _qualify_id(id)
	if not _world_id.is_empty():
		_registry.register_world_entity(_world_id, full_id, script)
	else:
		_registry.register_entity(full_id, script)


# Register a recipe
func register_recipe(id: String, recipe: Dictionary) -> void:
	var full_id := _qualify_id(id)
	if not _world_id.is_empty():
		_registry.register_world_recipe(_world_id, full_id, recipe)
	else:
		_registry.register_recipe(full_id, recipe)


# Query a block script
func get_block(id: String) -> Script:
	return _registry.get_block(id)


# Query an item script
func get_item(id: String) -> Script:
	return _registry.get_item(id)


# Query an entity script
func get_entity(id: String) -> Script:
	return _registry.get_entity(id)


# Query a recipe
func get_recipe(id: String) -> Dictionary:
	return _registry.get_recipe(id)


# List all block IDs (can be filtered by prefix)
func list_blocks(prefix: String = "") -> Array[String]:
	return _registry.list_blocks(prefix)


# List all item IDs
func list_items(prefix: String = "") -> Array[String]:
	return _registry.list_items(prefix)


# List all entity IDs
func list_entities(prefix: String = "") -> Array[String]:
	return _registry.list_entities(prefix)


# List all recipe IDs
func list_recipes(prefix: String = "") -> Array[String]:
	return _registry.list_recipes(prefix)


# Automatically prefix with mod_id (if id has no colon)
func _qualify_id(id: String) -> String:
	if id.find(":") >= 0:
		return id
	return "%s:%s" % [_mod_id, id]
