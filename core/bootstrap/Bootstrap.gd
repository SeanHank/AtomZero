# AtomZero Bootstrap (the only Autoload)
# Design doc §1.3 Single Bootstrap Autoload + explicit in-code initialization
#
# Only one Autoload is registered in project.godot to avoid multi-Autoload ordering
# dependencies and circular initialization issues.
# All core services are instantiated explicitly by Bootstrap in code, so dependency
# relationships are readable, testable, and assertable.
#
# Responsibilities:
#   1. Instantiate all core services in explicit order
#   2. Drive EventBus tick / physics_tick dispatch (every frame / every physics frame)
#   3. Cleanup on process exit (save data, release resources)
#   4. Automatically open the log file on crash (§8.3)
extends Node

# ===== Development/Release mode switch (§3.3) =====
# true  = Development Mode, writable root is res:// (read/write inside the editor)
# false = Release Mode, writable root is the game export root directory
#         (the directory containing the executable, §3.2)
const MOD_DEV_MODE: bool = false

# Current game version (design doc header: 2026.6.30)
const GAME_VERSION: String = "2026.6.30"

# ===== Core service references =====
var logger: AtomLogger
var hash_verifier: HashVerifier
var event_bus: EventBus
var mod_vfs: ModVFS
var persistence: PersistenceService
var registry: RegistrySystem
var mod_loader: ModLoaderCore
var state_manager: StateManager
var mod_api: ModAPI

# Parent node container for Mod instances
var _mods_container: Node = null

# Custom ResourceFormatLoader
var _resource_format_loader: ModResourceFormatLoader = null

# tick counters
var _tick_counter: int = 0
var _physics_tick_counter: int = 0

# Debug console and overlay
var _debug_console: Node = null
var _debug_overlay: Node = null


# ============================================================
# Path helper functions (§3.3)
# ============================================================

# Get the writable root path
# Design doc §3.2: In Release Mode, mods/, .cache/, saves/, logs/ are siblings of the executable
static func get_writable_root() -> String:
	if MOD_DEV_MODE:
		return "res://"
	# Release Mode: use the executable's directory as the game export root directory
	var game_root := OS.get_executable_path().get_base_dir()
	# macOS .app bundle structure: <game_root>/AtomZero.app/Contents/MacOS/AtomZero
	# Need to ascend 3 levels to the parent directory of .app (i.e. the game export root directory)
	if OS.get_name() == "macOS" and game_root.ends_with("/Contents/MacOS"):
		game_root = game_root.get_base_dir().get_base_dir().get_base_dir()
	return game_root + "/"

# Global Mods storage directory
static func get_global_mods_dir() -> String:
	return get_writable_root() + "mods/"

# World save root directory
static func get_saves_dir() -> String:
	return get_writable_root() + "saves/"

# Mods directory for a specific world
static func get_world_mods_dir(world_id: String) -> String:
	return get_saves_dir() + world_id + "/mods/"

# Logs directory
static func get_logs_dir() -> String:
	return get_writable_root() + "logs/"

# .cache directory (release .zip extraction cache)
static func get_cache_dir() -> String:
	return get_writable_root() + ".cache/"


# ============================================================
# Startup entry
# ============================================================

func _ready() -> void:
	# 1. Explicitly initialize all core services in code (dependency chain is linear and visible)
	_init_services()
	# 2. Create the Mod instance container
	_mods_container = Node.new()
	_mods_container.name = "ModsContainer"
	add_child(_mods_container)
	# 3. Register the custom ResourceFormatLoader (mod:// protocol)
	_resource_format_loader = ModResourceFormatLoader.new(mod_vfs)
	_resource_format_loader.register()
	# 4. Set ModLoaderCore's API and state references
	mod_loader.set_api_and_state(mod_api, state_manager, get_writable_root())
	mod_loader.set_mods_container(_mods_container)
	mod_loader.set_scene_tree(get_tree())
	# 5. Start the Mod loading flow (phased async loading, design doc §10.1.4)
	mod_loader.bootstrap()
	# 6. Initialize debug tools (debug build only)
	if OS.is_debug_build():
		_init_debug_tools()
	# 7. Exit cleanup is handled by _exit_tree() (SceneTree has no tree_exiting signal)


# Explicitly initialize all core services in code
# Design doc §1.3
func _init_services() -> void:
	# AtomLogger is initialized first (other services depend on it)
	logger = AtomLogger.new()
	logger.init(get_logs_dir(), get_tree())

	# HashVerifier
	hash_verifier = HashVerifier.new()
	hash_verifier.init(logger, get_writable_root())

	# EventBus
	event_bus = EventBus.new()
	event_bus.init(logger)

	# ModVFS
	mod_vfs = ModVFS.new()
	mod_vfs.init(logger)

	# PersistenceService
	persistence = PersistenceService.new()
	persistence.init(logger, get_writable_root())

	# RegistrySystem
	registry = RegistrySystem.new()
	registry.init(logger)

	# ModLoaderCore
	mod_loader = ModLoaderCore.new()
	mod_loader.init(logger, hash_verifier, event_bus, mod_vfs, persistence, registry)

	# StateManager
	state_manager = StateManager.new()
	state_manager.init(logger, event_bus)

	# ModAPI (facade, aggregating the above capabilities)
	mod_api = ModAPI.new()
	mod_api.init(logger, event_bus, mod_vfs, persistence, registry, state_manager, mod_loader)


# ============================================================
# Frame loop: drive EventBus tick / physics_tick dispatch
# Design doc §6.2.2
# core:tick and core:physics_tick are only dispatched while the current world is running
# ============================================================

func _process(delta: float) -> void:
	# Persistence service autosave timer
	persistence.update(delta)
	# Only dispatch tick while the current world is running (design doc §7.5.2)
	if state_manager.is_world_running():
		_tick_counter += 1
		event_bus.dispatch_tick(delta, _tick_counter)


func _physics_process(delta: float) -> void:
	if state_manager.is_world_running():
		_physics_tick_counter += 1
		event_bus.dispatch_physics_tick(delta, _physics_tick_counter)


# ============================================================
# Debug tools initialization
# ============================================================

func _init_debug_tools() -> void:
	# Console
	var console_script := load("res://core/debug/DebugConsole.gd")
	if console_script != null:
		_debug_console = console_script.new()
		_debug_console.setup(self)
		add_child(_debug_console)
	# Debug overlay
	var overlay_script := load("res://core/debug/DebugOverlay.gd")
	if overlay_script != null:
		_debug_overlay = overlay_script.new()
		_debug_overlay.setup(self)
		add_child(_debug_overlay)


# ============================================================
# Process exit handling (Bootstrap is a Node, _exit_tree is called when the node leaves the scene tree)
# ============================================================

func _exit_tree() -> void:
	# Unload all Global Mods (save data, §7.2.4)
	if mod_loader != null:
		mod_loader.unload_all_global_mods()
	# Unregister the custom ResourceFormatLoader
	if _resource_format_loader != null:
		_resource_format_loader.unregister()
	# Flush logs to disk + crash handling
	if logger != null:
		logger._on_tree_exiting()
		logger.flush()


# ============================================================
# Public API (for debug tools and external callers)
# ============================================================

func get_mod_loader() -> ModLoaderCore:
	return mod_loader


func get_state_manager() -> StateManager:
	return state_manager


func get_event_bus() -> EventBus:
	return event_bus


func get_logger() -> AtomLogger:
	return logger


func get_hash_verifier() -> HashVerifier:
	return hash_verifier


func get_registry() -> RegistrySystem:
	return registry


func get_mod_vfs() -> ModVFS:
	return mod_vfs


func get_persistence() -> PersistenceService:
	return persistence


func get_mod_api() -> ModAPI:
	return mod_api


# ============================================================
# World load/unload entry (called by main menu UI)
# ============================================================

# Load the specified world (including World Mods)
# Coroutine: mod_loader.load_world_mods() internally awaits background resource preload (design doc §10.1.6)
# Caller must await (e.g. UI button callback)
func load_world(world_id: String, world_seed: int = 0) -> void:
	await mod_loader.load_world_mods(world_id, world_seed)


# Unload the current world
func unload_current_world() -> void:
	var world_id := state_manager.get_current_world_id()
	if not world_id.is_empty():
		mod_loader.unload_world_mods(world_id)
