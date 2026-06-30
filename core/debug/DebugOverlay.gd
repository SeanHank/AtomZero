# AtomZero debug overlay
# Design doc §8.2.2
#
# In the development environment, displays a HUD overlay showing in real time:
#   - Number of loaded Mods and number of failures
#   - Current FPS, memory usage
#   - Current world ID and state machine state
#   - Subscriber count per event (red prompt when over the threshold)
#   - Last 10 WARN/ERROR log entries
extends Control

var _bootstrap: Node = null
var _label: RichTextLabel = null
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.5  # refresh once every 0.5 seconds

# References to custom panels already attached to DebugOverlay (to avoid duplicate attachment)
var _attached_panels: Array = []


func _ready() -> void:
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bootstrap is a Node (not a Control), DebugOverlay's default size is 0x0,
	# the child Label's anchors are invalid. Set to full-screen anchors so that
	# Label's anchor_bottom=0.55 can be correctly anchored above the console
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func setup(bootstrap: Node) -> void:
	_bootstrap = bootstrap


func _build_ui() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Semi-transparent background
	_label.add_theme_stylebox_override("normal", _make_bg())
	# Top-left, bottom anchored above the console (the console starts at 55%, leave a 4px gap)
	_label.anchor_left = 0.0
	_label.anchor_top = 0.0
	_label.anchor_right = 0.0
	_label.anchor_bottom = 0.55
	_label.offset_left = 8
	_label.offset_top = 8
	_label.offset_right = 488
	_label.offset_bottom = -4
	_label.custom_minimum_size = Vector2(480, 200)
	add_child(_label)


func _make_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0
	_refresh()


func _refresh() -> void:
	if _bootstrap == null:
		return
	var text := ""
	# State
	var sm: StateManager = _bootstrap.get_state_manager()
	text += "[b]State:[/b] %s\n" % sm.get_state_name()
	text += "[b]World:[/b] %s\n" % (sm.get_current_world_id() if not sm.get_current_world_id().is_empty() else "(none)")
	# Performance
	text += "[b]FPS:[/b] %.1f\n" % Engine.get_frames_per_second()
	text += "[b]Memory (static):[/b] %.2f MB\n" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0 / 1024.0)
	# Mod count
	var mods: Array = _bootstrap.get_mod_loader().list_all_mods()
	text += "[b]Loaded Mods:[/b] %d\n" % mods.size()
	# Event subscribers (red when over the threshold)
	var bus: EventBus = _bootstrap.get_event_bus()
	var names := bus.get_all_event_names()
	if not names.is_empty():
		text += "[b]Event subscriptions:[/b]\n"
		for n in names:
			var count := bus.get_subscriber_count(n)
			if count > EventBus.MAX_SUBSCRIBERS_PER_EVENT:
				text += "  [color=red]%s: %d (over threshold!)[/color]\n" % [n, count]
			else:
				text += "  %s: %d\n" % [n, count]
	# Pull and attach custom debug panels registered by Mods (design doc §8.2.3)
	_attach_custom_debug_panels()
	text += "[b]Debug panels:[/b] %d\n" % _attached_panels.size()
	# Recent WARN/ERROR
	var logger: AtomLogger = _bootstrap.get_logger()
	var recent := logger.get_recent_warn_error()
	if not recent.is_empty():
		text += "[b]Recent logs:[/b]\n"
		for line in recent:
			text += "  %s\n" % line
	_label.text = text


# Pull custom debug panels registered by Mods from ModLoaderCore, attach to DebugOverlay
# Already attached panels are skipped (compared by reference)
func _attach_custom_debug_panels() -> void:
	var mod_loader = _bootstrap.get_mod_loader()
	if mod_loader == null or not mod_loader.has_method("get_custom_debug_panels"):
		return
	var panels: Array = mod_loader.get_custom_debug_panels()
	for panel in panels:
		if panel == null:
			continue
		if _attached_panels.has(panel):
			continue
		# If the panel is already under another parent, remove it first then attach to DebugOverlay
		if panel.get_parent() != null:
			panel.get_parent().remove_child(panel)
		add_child(panel)
		_attached_panels.append(panel)
