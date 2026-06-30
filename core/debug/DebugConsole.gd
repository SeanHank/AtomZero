# AtomZero built-in debug console
# Design doc §8.2.1
#
# In the development environment, press `/` to open the built-in console, supporting the following commands:
#   mods list / info / reload / enable / disable
#   events list / emit
#   registry list blocks / items / entities / recipes
#   hash list / reset
#   log level <level>
extends Control

var _bootstrap: Node = null
var _console_edit: LineEdit = null
var _output_label: RichTextLabel = null
var _visible: bool = false
var _history: Array[String] = []
var _history_index: int = -1


func _ready() -> void:
	# The console occupies about 45% of the bottom of the screen, full width
	# Does not cover the top, preserving display space for the DebugOverlay HUD (top-left corner)
	anchor_left = 0.0
	anchor_top = 0.55
	anchor_right = 1.0
	anchor_bottom = 1.0
	# Use _input instead of _unhandled_input: when the console is open the LineEdit grabs focus,
	# _unhandled_input would be consumed by the GUI and not receive the toggle event
	set_process_input(true)
	_build_ui()
	_hide_console()


func setup(bootstrap: Node) -> void:
	_bootstrap = bootstrap


func _build_ui() -> void:
	# Semi-transparent background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Container
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_top = 16
	vbox.offset_right = -16
	vbox.offset_bottom = -16
	add_child(vbox)
	# Output area
	_output_label = RichTextLabel.new()
	_output_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output_label.bbcode_enabled = true
	_output_label.scroll_following = true
	_output_label.add_theme_font_override("normal_font", get_theme_default_font())
	vbox.add_child(_output_label)
	# Input box
	_console_edit = LineEdit.new()
	_console_edit.placeholder_text = "Enter command (/ to toggle, up/down to browse history)"
	vbox.add_child(_console_edit)
	_console_edit.text_submitted.connect(_on_text_submitted)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("console_toggle"):
		if _visible:
			_hide_console()
		else:
			_show_console()
		get_viewport().set_input_as_handled()
		return
	if not _visible:
		return
	# History browsing (intercept up/down when the console is visible, to avoid LineEdit moving the caret)
	if event is InputEventKey and event.pressed:
		var ek: InputEventKey = event
		if ek.keycode == KEY_UP:
			_history_nav(-1)
			get_viewport().set_input_as_handled()
		elif ek.keycode == KEY_DOWN:
			_history_nav(1)
			get_viewport().set_input_as_handled()


func _show_console() -> void:
	_visible = true
	visible = true
	_console_edit.grab_focus()


func _hide_console() -> void:
	_visible = false
	visible = false


func _history_nav(dir: int) -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index + dir, -1, _history.size() - 1)
	if _history_index < 0:
		_console_edit.text = ""
	else:
		_console_edit.text = _history[_history_index]
	_console_edit.caret_column = _console_edit.text.length()


func _on_text_submitted(text: String) -> void:
	var cmd := text.strip_edges()
	_console_edit.text = ""
	if cmd.is_empty():
		return
	_history.append(cmd)
	_history_index = _history.size()
	_print("[color=gray]$ %s[/color]" % cmd)
	_execute(cmd)


func _print(msg: String) -> void:
	if _output_label != null:
		_output_label.append_text(msg + "\n")


# ============================================================
# Command dispatch
# ============================================================

func _execute(cmd: String) -> void:
	var parts := cmd.split(" ", false)
	if parts.is_empty():
		return
	var main: String = parts[0]
	var args: Array = parts.slice(1)
	match main:
		"mods":
			_cmd_mods(args)
		"events":
			_cmd_events(args)
		"registry":
			_cmd_registry(args)
		"hash":
			_cmd_hash(args)
		"log":
			_cmd_log(args)
		"help":
			_cmd_help()
		_:
			_print("[color=red]Unknown command: %s[/color]" % main)


func _cmd_help() -> void:
	_print("Available commands:")
	_print("  mods list                       List all loaded Mods")
	_print("  mods info <mod_id>              Show Mod details")
	_print("  mods reload <mod_id>            Hot reload Global Mod data")
	_print("  events list                     List event subscribers")
	_print("  events emit <name> [json]       Emit an event")
	_print("  registry list blocks|items|...  List registry")
	_print("  hash list                       List hash whitelist")
	_print("  hash reset <mod_id>             Reset Mod trust")
	_print("  log level <level>               Set log level")


func _cmd_mods(args: Array) -> void:
	if args.is_empty():
		_print("[color=red]Usage: mods list|info|reload|enable|disable[/color]")
		return
	match args[0]:
		"list":
			var mods: Array = _bootstrap.get_mod_loader().list_all_mods()
			if mods.is_empty():
				_print("No loaded Mods")
				return
			for m in mods:
				var mod: Dictionary = m
				var line := "[LOADED] %s v%s (%s)" % [mod.mod_id, mod.version, mod.mod_type]
				if mod.has("world_id"):
					line += " (world=%s)" % mod.world_id
				_print(line)
		"info":
			if args.size() < 2:
				_print("[color=red]Usage: mods info <mod_id>[/color]")
				return
			var info: Dictionary = _bootstrap.get_mod_loader().get_mod_info(args[1])
			if info.is_empty():
				_print("[color=red]Mod not found: %s[/color]" % args[1])
				return
			_print("mod_id: %s" % info.mod_id)
			_print("name: %s" % info.name)
			_print("version: %s" % info.version)
			_print("mod_type: %s" % info.mod_type)
			_print("author: %s" % info.author)
			_print("description: %s" % info.description)
			_print("mod_dir: %s" % info.mod_dir)
		"reload":
			if args.size() < 2:
				_print("[color=red]Usage: mods reload <mod_id>[/color]")
				return
			_bootstrap.get_mod_loader().reload_mod_data(args[1])
			_print("Triggered data hot reload: %s" % args[1])
		"enable", "disable":
			_print("[color=yellow]Note: the current implementation does not support runtime enable/disable of Mods, restart the game[/color]")
		_:
			_print("[color=red]Unknown subcommand: mods %s[/color]" % args[0])


func _cmd_events(args: Array) -> void:
	if args.is_empty():
		_print("[color=red]Usage: events list|emit[/color]")
		return
	match args[0]:
		"list":
			var bus: EventBus = _bootstrap.get_event_bus()
			var names: Array[String] = bus.get_all_event_names()
			if names.is_empty():
				_print("No event subscriptions")
				return
			for n in names:
				var count: int = bus.get_subscriber_count(n)
				_print("  %s (subscribers: %d)" % [n, count])
		"emit":
			if args.size() < 2:
				_print("[color=red]Usage: events emit <event_name> [json][/color]")
				return
			var event_name: String = args[1]
			var payload: Dictionary = {}
			if args.size() >= 3:
				var json_str := " ".join(args.slice(2))
				var parsed: Variant = JSON.parse_string(json_str)
				if parsed != null and parsed is Dictionary:
					payload = parsed
				else:
					_print("[color=red]JSON parse failed: %s[/color]" % json_str)
					return
			_bootstrap.get_event_bus().emit(event_name, payload)
			_print("Emitted event: %s" % event_name)
		_:
			_print("[color=red]Unknown subcommand: events %s[/color]" % args[0])


func _cmd_registry(args: Array) -> void:
	if args.size() < 2 or args[0] != "list":
		_print("[color=red]Usage: registry list blocks|items|entities|recipes[/color]")
		return
	var reg: RegistrySystem = _bootstrap.get_registry()
	var ids: Array[String] = []
	match args[1]:
		"blocks": ids = reg.list_blocks()
		"items": ids = reg.list_items()
		"entities": ids = reg.list_entities()
		"recipes": ids = reg.list_recipes()
		_:
			_print("[color=red]Unknown category: %s[/color]" % args[1])
			return
	if ids.is_empty():
		_print("No registry entries")
		return
	for id in ids:
		_print("  %s" % id)


func _cmd_hash(args: Array) -> void:
	if args.is_empty():
		_print("[color=red]Usage: hash list|reset[/color]")
		return
	var hv: HashVerifier = _bootstrap.get_hash_verifier()
	match args[0]:
		"list":
			var trusted: Dictionary = hv.list_trusted()
			if trusted.is_empty():
				_print("Whitelist is empty")
				return
			for mod_id in trusted.keys():
				var entry: Dictionary = trusted[mod_id]
				_print("  %s v%s (trusted_at=%s)" % [mod_id, entry.version, entry.trusted_at])
		"reset":
			if args.size() < 2:
				_print("[color=red]Usage: hash reset <mod_id>[/color]")
				return
			hv.reset_trust(args[1])
			_print("Trust reset: %s" % args[1])
		_:
			_print("[color=red]Unknown subcommand: hash %s[/color]" % args[0])


func _cmd_log(args: Array) -> void:
	if args.size() < 2 or args[0] != "level":
		_print("[color=red]Usage: log level <TRACE|DEBUG|INFO|WARN|ERROR|FATAL>[/color]")
		return
	_bootstrap.get_logger().set_level(args[1])
	_print("Log level set to: %s" % args[1].to_upper())
