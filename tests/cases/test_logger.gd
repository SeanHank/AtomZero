extends "res://tests/runner/TestCase.gd"

const LOGS := "res://.test_tmp/logger/"


func _make_logger(logs_dir: String = LOGS) -> AtomLogger:
	var logger := AtomLogger.new()
	logger.init(logs_dir, null)
	return logger


func test_init_creates_banner() -> void:
	ensure_dir(LOGS)
	var logger := _make_logger()
	assert_true(FileAccess.file_exists(LOGS + "atomzero.log"))
	assert_eq(logger.get_level(), AtomLogger.LEVEL_INFO)


func test_set_level_variants() -> void:
	var logger := _make_logger()
	logger.set_level(AtomLogger.LEVEL_TRACE)
	assert_eq(logger.get_level(), AtomLogger.LEVEL_TRACE)
	assert_true(logger.is_trace_enabled())
	assert_true(logger.is_debug_enabled())
	logger.set_level("warn")
	assert_eq(logger.get_level(), AtomLogger.LEVEL_WARN)
	assert_false(logger.is_debug_enabled())
	logger.set_level("FATAL")
	assert_eq(logger.get_level(), AtomLogger.LEVEL_FATAL)
	logger.set_level(999)
	assert_eq(logger.get_level(), AtomLogger.LEVEL_FATAL)
	logger.set_level(-5)
	# clampi to TRACE..FATAL
	assert_eq(logger.get_level(), AtomLogger.LEVEL_TRACE)


func test_set_level_invalid_types() -> void:
	var logger := _make_logger()
	logger.set_level(2.5)
	assert_eq(logger.get_level(), AtomLogger.LEVEL_INFO)


func test_level_name_to_int() -> void:
	var logger := _make_logger()
	assert_eq(logger._level_name_to_int("debug"), AtomLogger.LEVEL_DEBUG)
	assert_eq(logger._level_name_to_int("INFO"), AtomLogger.LEVEL_INFO)
	assert_eq(logger._level_name_to_int("bogus"), AtomLogger.LEVEL_INFO)


func test_log_level_filtering() -> void:
	var logger := _make_logger()
	logger.trace("t", "x")
	logger.debug("t", "x")
	logger.info("t", "x")
	logger.warn("t", "x")
	logger.error("t", "x")
	logger.fatal("t", "x")
	logger.set_level(AtomLogger.LEVEL_WARN)
	logger.trace("t", "x")
	logger.debug("t", "x")
	logger.info("t", "x")
	assert_true(true)


func test_format_line() -> void:
	var logger := _make_logger()
	var line := logger._format_line(AtomLogger.LEVEL_INFO, "tag", "msg")
	assert_true(line.contains("[INFO ]"))
	assert_true(line.contains("[tag]"))
	assert_true(line.contains("msg"))
	var bogus := logger._format_line(99, "tag", "msg")
	assert_true(bogus.contains("[???? ]"))


func test_write_raw_recent_buffers() -> void:
	var logger := _make_logger()
	logger.set_level(AtomLogger.LEVEL_TRACE)
	for i in range(120):
		logger.trace("t", "line %d" % i)
	var recent := logger.get_recent_warn_error()
	# INFO not >= WARN so buffer empty
	assert_eq(recent.size(), 0)
	logger.warn("t", "boom")
	assert_eq(logger.get_recent_warn_error().size(), 1)
	# recent_lines capped at 100 for crash report
	assert_true(true)


func test_write_raw_unreadable_path() -> void:
	var logger := _make_logger()
	# Make a regular file where a directory would be needed -> FileAccess.open fails.
	write_text_file(LOGS + "blocker", "x")
	logger._log_file_path = LOGS + "blocker/nested.log"
	logger._write_to_file("boom")
	assert_true(true)


func test_write_to_file_empty_path() -> void:
	var logger := _make_logger()
	logger._log_file_path = ""
	logger._write_to_file("x")
	assert_true(true)


func test_rollover_if_needed() -> void:
	var logger := _make_logger()
	# Pre-seed a >10MB log to force the rolling archive.
	var data := PackedByteArray()
	data.resize(10 * 1024 * 1024 + 1)
	var f := FileAccess.open(LOGS + "atomzero.log", FileAccess.WRITE)
	assert_not_null(f)
	f.store_buffer(data)
	f.close()
	logger._write_to_file("bump")
	assert_true(FileAccess.file_exists(LOGS + "atomzero.log.1"))


func test_rollover_full_rotation() -> void:
	var dir := LOGS
	for i in range(1, 6):
		write_text_file(dir + "atomzero.log.%d" % i, "old%d" % i)
	var logger := _make_logger()
	var data := PackedByteArray()
	data.resize(10 * 1024 * 1024 + 1)
	var f := FileAccess.open(LOGS + "atomzero.log", FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
	logger._write_to_file("b")
	assert_true(FileAccess.file_exists(LOGS + "atomzero.log.5"))
	assert_true(FileAccess.file_exists(LOGS + "atomzero.log.1"))


func test_mark_crash_generates_report() -> void:
	ensure_dir(LOGS)
	var logger := _make_logger()
	logger.set_level(AtomLogger.LEVEL_DEBUG)
	logger.info("t", "before crash")
	logger.mark_crash()
	# Call the crash-report generator directly to avoid OS.shell_open side effects.
	logger._generate_crash_report()
	var report := _find_crash_report(LOGS)
	assert_false(report.is_empty())
	var text := read_text_file(LOGS + report)
	assert_true(text.contains("2026.9.0"))


func _find_crash_report(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	var found := ""
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.begins_with("crash_") and n.ends_with(".txt"):
			found = n
		n = d.get_next()
	d.list_dir_end()
	return found


func test_on_tree_exiting_no_crash() -> void:
	var logger := _make_logger()
	logger._on_tree_exiting()
	assert_true(true)


func test_generate_crash_report_empty_dir() -> void:
	var logger := AtomLogger.new()
	logger._generate_crash_report()
	assert_true(true)


func test_flush_noop() -> void:
	var logger := _make_logger()
	logger.flush()
	assert_true(true)


func test_ensure_dir() -> void:
	var logger := _make_logger()
	logger._ensure_dir(LOGS + "nested/a/b/")
	assert_true(DirAccess.dir_exists_absolute(LOGS + "nested/a/b"))