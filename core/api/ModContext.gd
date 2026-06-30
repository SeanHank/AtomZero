# Mod context
# Maintains context info (mod_id, mod_type, world_id, etc.) for each Mod instance
# ModAPI's sub APIs use this context to auto-inject mod_id and world_id
class_name ModContext
extends RefCounted

var mod_id: String = ""
var mod_type: String = "global"  # "global" or "world"
var world_id: String = ""        # For World Mods, the current world ID
var world_seed: int = 0
var mod_version: String = ""


func _init(p_mod_id: String = "", p_mod_type: String = "global") -> void:
	mod_id = p_mod_id
	mod_type = p_mod_type


func is_world_mod() -> bool:
	return mod_type == "world"


func is_global_mod() -> bool:
	return mod_type == "global"
