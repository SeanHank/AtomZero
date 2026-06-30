# Mod metadata descriptor
# Design doc §4.1 Mod metadata format definition
#
# Parsed from mod.json, contains all the metadata of the Mod.
# The valid field indicates whether it passed basic validation.
class_name ModDescriptor
extends RefCounted

var mod_id: String = ""
var name: String = ""
var version: String = ""
var game_version: String = ""
var author: String = ""
var description: String = ""
var url: String = ""
var license: String = ""

var mod_type: String = "global"  # "global" or "world"
var entry: String = ""

var dependencies: Array = []          # [{id, version}]
var soft_dependencies: Array = []     # [{id, version}]

var load_priority: int = 1000        # default 1000
var load_before: Array[String] = []
var load_after: Array[String] = []

var resource_overrides: Array = []   # [{target_mod, target_path, source_path}]

# Metadata
var mod_dir: String = ""             # Mod physical directory absolute path
var meta_path: String = ""           # mod.json path
var valid: bool = false
var error_msg: String = ""

# Runtime status (set by the loading flow)
var status: String = GameState.OK


# Load from a mod.json file
static func from_file(meta_path: String) -> ModDescriptor:
	var desc := ModDescriptor.new()
	desc.meta_path = meta_path
	if not FileAccess.file_exists(meta_path):
		desc.error_msg = "mod.json does not exist: %s" % meta_path
		return desc
	var text := FileAccess.get_file_as_string(meta_path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		desc.error_msg = "mod.json parse failed: %s" % meta_path
		return desc
	desc._from_dict(parsed)
	# mod_dir is the directory containing meta_path
	desc.mod_dir = meta_path.get_base_dir()
	return desc


# Construct from a dictionary (for testing)
static func from_dict(data: Dictionary, mod_dir: String = "") -> ModDescriptor:
	var desc := ModDescriptor.new()
	desc.mod_dir = mod_dir
	desc._from_dict(data)
	return desc


func _from_dict(data: Dictionary) -> void:
	mod_id = data.get("mod_id", "")
	name = data.get("name", "")
	version = data.get("version", "")
	game_version = data.get("game_version", "")
	author = data.get("author", "")
	description = data.get("description", "")
	url = data.get("url", "")
	license = data.get("license", "")
	mod_type = data.get("mod_type", "global")
	entry = data.get("entry", "")
	dependencies = data.get("dependencies", [])
	soft_dependencies = data.get("soft_dependencies", [])
	resource_overrides = data.get("resource_overrides", [])
	var load_order: Dictionary = data.get("load_order", {})
	load_priority = int(load_order.get("priority", 1000))
	var lb: Array = load_order.get("load_before", [])
	for s in lb:
		load_before.append(s)
	var la: Array = load_order.get("load_after", [])
	for s in la:
		load_after.append(s)
	_validate()


# Basic validation
func _validate() -> void:
	valid = true
	error_msg = ""
	# mod_id must satisfy ^[a-z][a-z0-9_]*$
	if mod_id.is_empty():
		valid = false
		error_msg = "mod_id is empty"
		return
	if not _is_valid_mod_id(mod_id):
		valid = false
		error_msg = "mod_id format invalid (must be ^[a-z][a-z0-9_]*$): %s" % mod_id
		return
	# Required fields
	if name.is_empty():
		valid = false
		error_msg = "name is empty"
		return
	if version.is_empty():
		valid = false
		error_msg = "version is empty"
		return
	if game_version.is_empty():
		valid = false
		error_msg = "game_version is empty"
		return
	if mod_type != "global" and mod_type != "world":
		valid = false
		error_msg = "mod_type must be 'global' or 'world'"
		return
	if entry.is_empty():
		valid = false
		error_msg = "entry is empty"
		return


func _is_valid_mod_id(id: String) -> bool:
	if id.is_empty():
		return false
	# First character must be a-z
	var first := id[0]
	if not (first >= 'a' and first <= 'z'):
		return false
	# Remaining characters must be a-z0-9_
	for i in range(1, id.length()):
		var ch := id[i]
		if not ((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_'):
			return false
	return true


# Get the list of hard dependency IDs
func get_dependency_ids() -> Array[String]:
	var ids: Array[String] = []
	for dep in dependencies:
		ids.append(dep.get("id", ""))
	return ids


# Get the list of soft dependency IDs
func get_soft_dependency_ids() -> Array[String]:
	var ids: Array[String] = []
	for dep in soft_dependencies:
		ids.append(dep.get("id", ""))
	return ids


# To string (for debugging)
func to_string_repr() -> String:
	return "%s v%s (%s) [valid=%s, status=%s]" % [mod_id, version, mod_type, valid, status]
