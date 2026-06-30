# Logger API (design doc §6.1.1)
# Mods call via _api.logger.*
class_name LoggerAPI
extends RefCounted

var _logger: AtomLogger = null
var _mod_id: String = ""


func _init(logger: AtomLogger, mod_id: String) -> void:
	_logger = logger
	_mod_id = mod_id


func trace(msg: String) -> void:
	_logger.trace(_mod_id, msg)


func debug(msg: String) -> void:
	_logger.debug(_mod_id, msg)


func info(msg: String) -> void:
	_logger.info(_mod_id, msg)


func warn(msg: String) -> void:
	_logger.warn(_mod_id, msg)


func error(msg: String) -> void:
	_logger.error(_mod_id, msg)


func fatal(msg: String) -> void:
	_logger.fatal(_mod_id, msg)


func is_debug_enabled() -> bool:
	return _logger.is_debug_enabled()


func is_trace_enabled() -> bool:
	return _logger.is_trace_enabled()
