# Development tools API (design doc §6.1.1 and §5.4 §8.2)
# Enabled only when OS.is_debug_build() returns true
class_name DevAPI
extends RefCounted

var _mod_loader: Variant = null  # ModLoaderCore reference (Variant to avoid circular dependency)
var _logger: AtomLogger = null
var _debug_panels: Array = []
var _enabled: bool = false


func _init(mod_loader: Variant, logger: AtomLogger) -> void:
	_mod_loader = mod_loader
	_logger = logger
	_enabled = OS.is_debug_build()


# Hot-reload mod data (Global Mods only, §5.4)
func reload_mod_data(mod_id: String) -> void:
	if not _enabled:
		_logger.warn("DevAPI", "Data hot reload is disabled in release environment")
		return
	if _mod_loader != null and _mod_loader.has_method("reload_mod_data"):
		_mod_loader.reload_mod_data(mod_id)


# Register a custom debug panel (§8.2.3)
func register_debug_panel(panel: Node) -> void:
	if not _enabled:
		return
	_debug_panels.append(panel)
	if _mod_loader != null and _mod_loader.has_method("register_debug_panel"):
		_mod_loader.register_debug_panel(panel)


func get_debug_panels() -> Array:
	return _debug_panels


func is_enabled() -> bool:
	return _enabled
