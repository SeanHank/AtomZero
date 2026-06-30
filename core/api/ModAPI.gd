# AtomZero ModAPI facade
# Design doc §6 API design
#
# Unified facade for Mods, aggregating all core services.
# A Mod receives a ModAPI instance in _init_mod(api), and should save it as a member variable for later use.
#
# Sub APIs (design doc §6.1.1):
#   logger:      LoggerAPI      Log
#   events:      EventAPI       Event
#   resources:   ResourceAPI    Resource loading
#   registry:    RegistryAPI    Registry
#   persistence:  PersistenceAPI Persistence
#   vfs:         VFSAPI         Virtual File System
#   world:       WorldAPI       World info
#   dev:         DevAPI         Development tools (debug build only)
class_name ModAPI
extends RefCounted

var logger: LoggerAPI
var events: EventAPI
var resources: ResourceAPI
var registry: RegistryAPI
var persistence: PersistenceAPI
var vfs: VFSAPI
var world: WorldAPI
var dev: DevAPI

var _context: ModContext = null
var _initialized: bool = false

# Original references to core services (used to build new sub APIs on create_for_mod)
var _logger_service: AtomLogger = null
var _event_bus_service: EventBus = null
var _vfs_service: ModVFS = null
var _persistence_service: PersistenceService = null
var _registry_service: RegistrySystem = null
var _state_manager_service: StateManager = null
var _mod_loader_service: Variant = null


# Initialize (called by Bootstrap._init_services, injecting all dependencies)
# Creates a base instance without a Mod context (ModLoaderCore calls create_for_mod to create a new instance when loading a Mod)
func init(logger_service: AtomLogger, event_bus: EventBus, vfs: ModVFS, persistence: PersistenceService, registry: RegistrySystem, state_manager: StateManager, mod_loader: Variant) -> void:
	_logger_service = logger_service
	_event_bus_service = event_bus
	_vfs_service = vfs
	_persistence_service = persistence
	_registry_service = registry
	_state_manager_service = state_manager
	_mod_loader_service = mod_loader
	_context = ModContext.new()
	_build_sub_apis()
	_initialized = true


# Create an independent ModAPI instance for the specified Mod (each Mod holds its own context)
# Design doc §6: a Mod receives an independent ModAPI instance in _init_mod(api)
func create_for_mod(mod_id: String, mod_type: String, world_id: String = "", world_seed: int = 0, mod_version: String = "") -> ModAPI:
	var new_api := ModAPI.new()
	# Share the underlying core service references
	new_api._logger_service = _logger_service
	new_api._event_bus_service = _event_bus_service
	new_api._vfs_service = _vfs_service
	new_api._persistence_service = _persistence_service
	new_api._registry_service = _registry_service
	new_api._state_manager_service = _state_manager_service
	new_api._mod_loader_service = _mod_loader_service
	# Independent Mod context
	new_api._context = ModContext.new(mod_id, mod_type)
	new_api._context.world_id = world_id
	new_api._context.world_seed = world_seed
	new_api._context.mod_version = mod_version
	# Build sub APIs that hold an independent mod_id/world_id context
	new_api._build_sub_apis()
	new_api._initialized = true
	return new_api


# Internal: build sub APIs (using mod_id / world_id from _context)
func _build_sub_apis() -> void:
	logger = LoggerAPI.new(_logger_service, _context.mod_id)
	events = EventAPI.new(_event_bus_service, _context.mod_id, _context.world_id)
	resources = ResourceAPI.new(_vfs_service, _context.mod_id, _context.world_id)
	registry = RegistryAPI.new(_registry_service, _context.mod_id, _context.world_id)
	persistence = PersistenceAPI.new(_persistence_service, _context.mod_id, _context.world_id)
	vfs = VFSAPI.new(_vfs_service, _context.mod_id, _context.world_id)
	world = WorldAPI.new(_state_manager_service)
	dev = DevAPI.new(_mod_loader_service, _logger_service)


# Get the Mod context
func get_context() -> ModContext:
	return _context
