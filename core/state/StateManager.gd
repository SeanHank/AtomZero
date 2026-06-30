# AtomZero State Manager
# Design doc §1.2 and §5.3.1
#
# Tracks the current state (bootstrapping / main menu / world loading / world running), driving World Mods switching.
# State machine definition (§5.3.1):
#   [*] --> BOOTSTRAP
#   BOOTSTRAP --> MAIN_MENU              (GlobalModsReady)
#   MAIN_MENU --> WORLD_LOADING          (select world)
#   WORLD_LOADING --> WORLD_RUNNING      (WorldLoadComplete)
#   WORLD_RUNNING --> WORLD_UNLOADING    (exit world)
#   WORLD_UNLOADING --> MAIN_MENU        (WorldUnloadComplete)
#   WORLD_LOADING/WORLD_RUNNING --> CRASH (load failed / runtime error)
#   CRASH --> [*]
class_name StateManager
extends RefCounted

var _logger: AtomLogger = null
var _event_bus: EventBus = null
var _state: int = GameState.State.BOOTSTRAP
var _current_world_id: String = ""
var _current_world_seed: int = 0
var _initialized: bool = false


func init(logger: AtomLogger, event_bus: EventBus) -> void:
	_logger = logger
	_event_bus = event_bus
	_state = GameState.State.BOOTSTRAP
	_initialized = true


# ===== State queries =====

func get_state() -> int:
	return _state


func get_state_name() -> String:
	return GameState.state_name(_state)


func get_current_world_id() -> String:
	return _current_world_id


func get_current_world_seed() -> int:
	return _current_world_seed


func is_world_loaded() -> bool:
	return _state == GameState.State.WORLD_RUNNING or _state == GameState.State.WORLD_LOADING


func is_world_running() -> bool:
	return _state == GameState.State.WORLD_RUNNING


# ===== State transitions (called by ModLoaderCore) =====

# Global Mods load complete -> MAIN_MENU
func transition_to_main_menu() -> void:
	_state = GameState.State.MAIN_MENU
	if _logger:
		_logger.debug("StateManager", "State -> MAIN_MENU")


# Start loading world -> WORLD_LOADING
func transition_to_world_loading(world_id: String, world_seed: int) -> void:
	_state = GameState.State.WORLD_LOADING
	_current_world_id = world_id
	_current_world_seed = world_seed
	if _logger:
		_logger.debug("StateManager", "State -> WORLD_LOADING (world=%s)" % world_id)


# World load complete -> WORLD_RUNNING
func transition_to_world_running() -> void:
	_state = GameState.State.WORLD_RUNNING
	if _logger:
		_logger.debug("StateManager", "State -> WORLD_RUNNING")


# Start unloading world -> WORLD_UNLOADING
func transition_to_world_unloading() -> void:
	_state = GameState.State.WORLD_UNLOADING
	if _logger:
		_logger.debug("StateManager", "State -> WORLD_UNLOADING")


# World unload complete -> MAIN_MENU
func transition_to_main_menu_after_unload() -> void:
	_state = GameState.State.MAIN_MENU
	_current_world_id = ""
	_current_world_seed = 0
	if _logger:
		_logger.debug("StateManager", "State -> MAIN_MENU (world unloaded)")


# Crash -> CRASH
func transition_to_crash() -> void:
	_state = GameState.State.CRASH
	if _logger:
		_logger.fatal("StateManager", "State -> CRASH")
