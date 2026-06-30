# Mod runtime instance
# Design doc §1.2 and §5 loading flow design
#
# Wraps the runtime state of a loaded Mod: script instance, node, status, API reference.
class_name ModInstance
extends RefCounted

var descriptor: ModDescriptor = null    # Metadata
var api: ModAPI = null                   # Injected ModAPI instance
var script_instance: Node = null        # Mod main entry script instance (Node derived)
var node: Node = null                    # Same as script_instance (alias kept for convenience)
var loaded: bool = false                # Whether successfully loaded and initialized


func _init(desc: ModDescriptor = null) -> void:
	descriptor = desc


# Set the runtime instance
func set_instance(instance: Node, mod_api: ModAPI) -> void:
	script_instance = instance
	node = instance
	api = mod_api


func get_mod_id() -> String:
	return descriptor.mod_id if descriptor != null else ""


func get_mod_type() -> String:
	return descriptor.mod_type if descriptor != null else ""


func get_version() -> String:
	return descriptor.version if descriptor != null else ""


# Call a Mod callback method (if it exists)
func call_if_exists(method_name: String, args: Array = []) -> void:
	if script_instance == null:
		return
	if script_instance.has_method(method_name):
		script_instance.callv(method_name, args)
