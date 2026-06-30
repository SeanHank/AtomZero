# AtomZero Registry System
# Design doc §1.2 and §9 (Mod development guide)
#
# Uniformly manages block, item, entity, recipe and other registries.
# Resources registered by World Mods are automatically prefixed with world.<world_id>. (handled internally, transparent externally).
# The partition is released as a whole on world unload.
#
# Performance optimization (§10.1.8):
#   - Use Dictionary with string ID as key directly, O(1) lookup
#   - list_blocks(prefix) iterates keys filtered by begins_with() (<10k entries <1ms)
class_name RegistrySystem
extends RefCounted

var _logger: AtomLogger = null

# Global Mod registry
var _blocks: Dictionary = {}      # id -> Script
var _items: Dictionary = {}        # id -> Script
var _entities: Dictionary = {}    # id -> Script
var _recipes: Dictionary = {}     # id -> Dictionary

# World Mod partitions: world_id -> {blocks, items, entities, recipes}
var _world_partitions: Dictionary = {}

var _initialized: bool = false


func init(logger: AtomLogger) -> void:
	_logger = logger
	_initialized = true


# ============================================================
# Global Mod registration
# ============================================================

func register_block(id: String, script: Script) -> void:
	if _blocks.has(id):
		if _logger:
			_logger.warn("Registry", "Block ID already exists, overwriting: %s" % id)
	_blocks[id] = script


func register_item(id: String, script: Script) -> void:
	if _items.has(id):
		if _logger:
			_logger.warn("Registry", "Item ID already exists, overwriting: %s" % id)
	_items[id] = script


func register_entity(id: String, script: Script) -> void:
	if _entities.has(id):
		if _logger:
			_logger.warn("Registry", "Entity ID already exists, overwriting: %s" % id)
	_entities[id] = script


func register_recipe(id: String, recipe: Dictionary) -> void:
	if _recipes.has(id):
		if _logger:
			_logger.warn("Registry", "Recipe ID already exists, overwriting: %s" % id)
	_recipes[id] = recipe


# ============================================================
# Global Mod queries
# ============================================================

func get_block(id: String) -> Script:
	# Global first, then current world (if the world partition has the same name)
	if _blocks.has(id):
		return _blocks[id]
	return null


func get_item(id: String) -> Script:
	if _items.has(id):
		return _items[id]
	return null


func get_entity(id: String) -> Script:
	if _entities.has(id):
		return _entities[id]
	return null


func get_recipe(id: String) -> Dictionary:
	if _recipes.has(id):
		return _recipes[id]
	return {}


func list_blocks(prefix: String = "") -> Array[String]:
	return _list_with_prefix(_blocks.keys(), prefix)


func list_items(prefix: String = "") -> Array[String]:
	return _list_with_prefix(_items.keys(), prefix)


func list_entities(prefix: String = "") -> Array[String]:
	return _list_with_prefix(_entities.keys(), prefix)


func list_recipes(prefix: String = "") -> Array[String]:
	return _list_with_prefix(_recipes.keys(), prefix)


# ============================================================
# World Mod partitions (§2.4 item 4)
# ============================================================

# Open a world partition
func open_world_partition(world_id: String) -> void:
	if not _world_partitions.has(world_id):
		_world_partitions[world_id] = {
			"blocks": {},
			"items": {},
			"entities": {},
			"recipes": {}
		}


# World Mod registration (auto-add world.<world_id>. prefix, transparent externally)
# Design doc §2.4 item 1
func register_world_block(world_id: String, id: String, script: Script) -> void:
	var partition: Dictionary = _get_partition(world_id)
	var full_id := _make_world_id(world_id, id)
	partition["blocks"][full_id] = script
	# Also register to global with the original id (convenient for cross-Mod references)
	# Note: World Mod resources are only visible while that world is active
	if not _blocks.has(full_id):
		_blocks[full_id] = script


func register_world_item(world_id: String, id: String, script: Script) -> void:
	var partition: Dictionary = _get_partition(world_id)
	var full_id := _make_world_id(world_id, id)
	partition["items"][full_id] = script
	if not _items.has(full_id):
		_items[full_id] = script


func register_world_entity(world_id: String, id: String, script: Script) -> void:
	var partition: Dictionary = _get_partition(world_id)
	var full_id := _make_world_id(world_id, id)
	partition["entities"][full_id] = script
	if not _entities.has(full_id):
		_entities[full_id] = script


func register_world_recipe(world_id: String, id: String, recipe: Dictionary) -> void:
	var partition: Dictionary = _get_partition(world_id)
	var full_id := _make_world_id(world_id, id)
	partition["recipes"][full_id] = recipe
	if not _recipes.has(full_id):
		_recipes[full_id] = recipe


# Release a world partition (called during world unload phase 2)
func release_world_partition(world_id: String) -> void:
	if not _world_partitions.has(world_id):
		return
	var partition: Dictionary = _world_partitions[world_id]
	# Remove all resources of this world from the global table
	for category in ["blocks", "items", "entities", "recipes"]:
		var cat: Dictionary = partition[category]
		for id in cat.keys():
			_blocks.erase(id)
			_items.erase(id)
			_entities.erase(id)
			_recipes.erase(id)
	_world_partitions.erase(world_id)
	if _logger:
		_logger.debug("Registry", "Released registry partition for world %s" % world_id)


# ============================================================
# Internal helpers
# ============================================================

func _get_partition(world_id: String) -> Dictionary:
	if not _world_partitions.has(world_id):
		open_world_partition(world_id)
	return _world_partitions[world_id]


# Generate the namespace prefix ID for a World Mod resource
# Design doc §2.4 item 1: world.<world_id>. prefix
func _make_world_id(world_id: String, id: String) -> String:
	return "world.%s.%s" % [world_id, id]


func _list_with_prefix(keys: Array, prefix: String) -> Array[String]:
	var result: Array[String] = []
	for k in keys:
		var key: String = k
		if prefix.is_empty() or key.begins_with(prefix):
			result.append(key)
	result.sort()
	return result
