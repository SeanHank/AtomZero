# AtomZero logging system
# Design doc §8 Debug and logging system
#
# Log levels (smaller value = more verbose):
#   TRACE = 0  Extremely fine-grained per-frame, per-chunk tracing
#   DEBUG = 1  Debug info (state changes, loading steps)
#   INFO  = 2  Normal info (Mod load complete, world switch)
#   WARN  = 3  Warnings (missing dependency but degradable, subscriber over threshold)
#   ERROR = 4  Errors (Mod load failed, hash mismatch)
#   FATAL = 5  Fatal errors (core crash, cannot continue running)
#
# Output targets:
#   - Editor Output panel (only when OS.is_debug_build())
#   - Console stdout (always)
#   - Log file <writable_root>/logs/atomzero.log (always, 10MB rolling archive, keep 5)
#
# Crash handling (§8.3.3):
#   - Auto flush to disk on process exit
#   - Auto open the log file when a crash is detected
#   - Generate a crash report crash_<timestamp>.txt
class_name AtomLogger
extends RefCounted

# ===== Log level constants =====
const LEVEL_TRACE: int = 0
const LEVEL_DEBUG: int = 1
const LEVEL_INFO: int = 2
const LEVEL_WARN: int = 3
const LEVEL_ERROR: int = 4
const LEVEL_FATAL: int = 5

const LEVEL_NAMES: Array[String] = ["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"]

# ===== Config constants =====
const MAX_LOG_FILE_SIZE: int = 10 * 1024 * 1024  # 10MB triggers rolling archive
const MAX_ARCHIVES: int = 5                          # Keep 5 archives
const RECENT_WARN_ERROR_BUFFER: int = 10             # Debug overlay shows the last N WARN/ERROR entries
const RECENT_LOG_BUFFER_FOR_CRASH: int = 100         # Crash report keeps the last N log entries

# ===== Runtime state =====
var _level: int = LEVEL_INFO
var _log_file_path: String = ""
var _logs_dir: String = ""
var _recent_lines: Array[String] = []        # All recent logs (for crash report)
var _recent_warn_error: Array[String] = []   # Recent WARN/ERROR (for debug overlay)
var _crash_detected: bool = false
var _tree: SceneTree = null
var _initialized: bool = false


# Initialize the logging system
# logs_dir: absolute path to the logs directory (provided by Bootstrap.get_logs_dir())
# tree: SceneTree reference (kept for future extension; exit cleanup is called by Bootstrap._exit_tree)
func init(logs_dir: String = "", tree: SceneTree = null) -> void:
	_logs_dir = logs_dir
	_tree = tree
	if _logs_dir.is_empty():
		_logs_dir = "res://logs/"
	_ensure_dir(_logs_dir)
	_log_file_path = _logs_dir + "atomzero.log"
	# Exit cleanup is called directly by Bootstrap._exit_tree() via logger._on_tree_exiting()
	# SceneTree has no tree_exiting signal (that signal is on Node)
	_initialized = true
	# Initial banner
	var banner := "================ AtomZero Startup ================"
	_write_raw(LEVEL_INFO, "AtomLogger", banner)


# Set the global log level (numeric value or level name string)
func set_level(level: Variant) -> void:
	if level is int:
		_level = clampi(level, LEVEL_TRACE, LEVEL_FATAL)
	elif level is String:
		_level = _level_name_to_int(level)
	else:
		push_warning("AtomLogger.set_level: invalid level type %s" % typeof(level))


func get_level() -> int:
	return _level


func is_debug_enabled() -> bool:
	return _level <= LEVEL_DEBUG


func is_trace_enabled() -> bool:
	return _level <= LEVEL_TRACE


# ===== Per-level log API =====
func trace(tag: String, msg: String) -> void:
	if _level <= LEVEL_TRACE:
		_write_raw(LEVEL_TRACE, tag, msg)


func debug(tag: String, msg: String) -> void:
	if _level <= LEVEL_DEBUG:
		_write_raw(LEVEL_DEBUG, tag, msg)


func info(tag: String, msg: String) -> void:
	if _level <= LEVEL_INFO:
		_write_raw(LEVEL_INFO, tag, msg)


func warn(tag: String, msg: String) -> void:
	if _level <= LEVEL_WARN:
		_write_raw(LEVEL_WARN, tag, msg)


func error(tag: String, msg: String) -> void:
	if _level <= LEVEL_ERROR:
		_write_raw(LEVEL_ERROR, tag, msg)


func fatal(tag: String, msg: String) -> void:
	if _level <= LEVEL_FATAL:
		_write_raw(LEVEL_FATAL, tag, msg)


# Mark the crash status (used to open the log file on tree_exiting)
func mark_crash() -> void:
	_crash_detected = true


# Get the last N WARN/ERROR log entries (for the debug overlay)
func get_recent_warn_error() -> Array[String]:
	return _recent_warn_error.duplicate()


# Force flush buffers to disk
func flush() -> void:
	# The current implementation writes to disk directly per log line; no extra flush needed.
	# This method is kept for future extension (buffered write mode).
	pass


# ===== Internal implementation =====

func _level_name_to_int(name: String) -> int:
	var upper := name.to_upper()
	var idx := LEVEL_NAMES.find(upper)
	if idx < 0:
		push_warning("AtomLogger: unknown log level '%s', using INFO" % name)
		return LEVEL_INFO
	return idx


func _format_line(level: int, tag: String, msg: String) -> String:
	# Format: [timestamp] [level] [source tag] message
	var ts := Time.get_datetime_string_from_system(false, true)
	var ms := Time.get_ticks_msec() % 1000
	var level_name := LEVEL_NAMES[level] if level >= 0 and level < LEVEL_NAMES.size() else "????"
	# Pad the level name to 5 characters wide
	while level_name.length() < 5:
		level_name += " "
	return "[%s.%03d] [%s] [%s] %s" % [ts, ms, level_name, tag, msg]


func _write_raw(level: int, tag: String, msg: String) -> void:
	var line := _format_line(level, tag, msg)
	# 1. Always output to stdout
	print(line)
	# 2. Editor Output (debug build only)
	if OS.is_debug_build():
		# print also goes to the editor output, no extra handling here
		pass
	# 3. Write to the log file
	_write_to_file(line)
	# 4. Maintain the recent log buffer
	_recent_lines.append(line)
	while _recent_lines.size() > RECENT_LOG_BUFFER_FOR_CRASH:
		_recent_lines.pop_front()
	# 5. Maintain the WARN/ERROR buffer
	if level >= LEVEL_WARN:
		_recent_warn_error.append(line)
		while _recent_warn_error.size() > RECENT_WARN_ERROR_BUFFER:
			_recent_warn_error.pop_front()


func _write_to_file(line: String) -> void:
	if _log_file_path.is_empty():
		return
	# Check file size, rolling archive if needed
	_rollover_if_needed()
	var f: FileAccess = null
	if FileAccess.file_exists(_log_file_path):
		# File exists: open in READ_WRITE mode (no truncation), seek to end to append
		f = FileAccess.open(_log_file_path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		# File does not exist: create in WRITE mode
		f = FileAccess.open(_log_file_path, FileAccess.WRITE)
	if f == null:
		# File cannot be opened, fall back to push_warning (to avoid infinite recursion)
		push_warning("AtomLogger: unable to open log file %s" % _log_file_path)
		return
	f.store_line(line)
	f.close()


func _rollover_if_needed() -> void:
	if not FileAccess.file_exists(_log_file_path):
		return
	# Get size by opening the file, to avoid reading the whole file into memory
	var f := FileAccess.open(_log_file_path, FileAccess.READ)
	if f == null:
		return
	var size := f.get_length()
	f.close()
	if size < MAX_LOG_FILE_SIZE:
		return
	# Rolling: delete the oldest, rename .4 -> .5 (deleted), .3 -> .4 ... .log -> .1
	var oldest := _log_file_path + ".%d" % MAX_ARCHIVES
	if FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(oldest)
	for i in range(MAX_ARCHIVES - 1, 0, -1):
		var src := _log_file_path + ".%d" % i
		var dst := _log_file_path + ".%d" % (i + 1)
		if FileAccess.file_exists(src):
			DirAccess.rename_absolute(src, dst)
	# Current log -> .1
	DirAccess.rename_absolute(_log_file_path, _log_file_path + ".1")


func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)


# tree_exiting signal callback: ensure logs are flushed to disk, open log on crash
func _on_tree_exiting() -> void:
	# Generate a crash report (if a crash is detected)
	if _crash_detected:
		_generate_crash_report()
		# Auto open the log file (§8.3.3)
		if not _log_file_path.is_empty():
			var uri := "file://" + _log_file_path
			OS.shell_open(uri)


# Generate a crash report <writable_root>/logs/crash_<timestamp>.txt (§8.3.4)
func _generate_crash_report() -> void:
	if _logs_dir.is_empty():
		return
	var ts := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_")
	var path := _logs_dir + "crash_%s.txt" % ts
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("========== AtomZero Crash Report ==========")
	f.store_line("Time: %s" % Time.get_datetime_string_from_system(false, true))
	f.store_line("Game version: 2026.6.30")
	f.store_line("Engine version: %s" % Engine.get_version_info().get("string", "unknown"))
	f.store_line("Platform: %s" % OS.get_name())
	f.store_line("")
	f.store_line("===== System Information =====")
	f.store_line("CPU: %s" % OS.get_processor_name())
	f.store_line("CPU cores: %d" % OS.get_processor_count())
	f.store_line("Memory (static): %d MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1024 / 1024))
	f.store_line("")
	f.store_line("===== Last %d log entries =====" % _recent_lines.size())
	for line in _recent_lines:
		f.store_line(line)
	f.close()
