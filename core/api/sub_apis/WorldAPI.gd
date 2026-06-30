# World API (design doc §6.1.1)
# Mods call via _api.world.*
class_name WorldAPI
extends RefCounted

var _state_manager: StateManager = null


func _init(state_manager: StateManager) -> void:
	_state_manager = state_manager


# Current world ID (returns an empty string when no world is loaded)
func get_current_world_id() -> String:
	return _state_manager.get_current_world_id()


# Whether a world is currently running
func is_world_loaded() -> bool:
	return _state_manager.is_world_loaded()


# Current world seed
func get_world_seed() -> int:
	return _state_manager.get_current_world_seed()


# Current state machine state name
func get_state_name() -> String:
	return _state_manager.get_state_name()
