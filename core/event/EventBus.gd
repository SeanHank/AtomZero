# AtomZero Event Bus
# Design doc §6.2 Event system design
#
# Features:
#   1. General event channel: subscribe / unsubscribe / emit / emit_deferred / stop_propagation
#      - Priority sort (smaller value = executed first)
#      - Cancel propagation
#      - Subscriber count monitoring (WARN log over the 256 threshold, does not block)
#   2. Dedicated fast channel for high-frequency events: core:tick / core:physics_tick
#      - Pre-allocated Dictionary payload, zero allocation
#      - Dedicated subscriber array, direct iteration
#      - Deferred modification queue (avoid crashes from modifying the array during iteration)
#   3. World event context: World Mod subscriptions bind to the current world, auto-cleared on world unload
class_name EventBus
extends RefCounted

const MAX_SUBSCRIBERS_PER_EVENT: int = 256  # Subscriber count alarm threshold

var _logger: AtomLogger = null
var _initialized: bool = false

# ===== General event channel =====
# event_name -> EventContext (global context + per-world context)
var _global_context: EventContext = null
var _world_contexts: Dictionary = {}  # world_id -> EventContext
var _current_world_id: String = ""     # currently active world (used to bind when World Mod subscribes)

# Cancel propagation flag (only valid within the emit call stack)
var _stop_propagation_flag: bool = false

# ===== Dedicated fast channel for high-frequency events (design doc §6.2.2) =====
var _tick_payload: Dictionary = {}
var _tick_subscribers: Array[Callable] = []
var _pending_tick_adds: Array[Callable] = []
var _pending_tick_rems: Array[Callable] = []
var _is_dispatching_tick: bool = false

var _physics_tick_payload: Dictionary = {}
var _physics_tick_subscribers: Array[Callable] = []
var _pending_physics_tick_adds: Array[Callable] = []
var _pending_physics_tick_rems: Array[Callable] = []
var _is_dispatching_physics_tick: bool = false


# Initialize
func init(logger: AtomLogger) -> void:
	_logger = logger
	_global_context = EventContext.new("")
	_initialized = true


# ============================================================
# General event API
# ============================================================

# Subscribe to an event
# event_name: event name (recommended to use GameEvents constants or <mod_id>:<event> namespace)
# callable: callback, signature is func(payload: Dictionary)
# priority: priority, smaller value = executed first, default 0
# mod_id: Mod the subscriber belongs to (used for auto-cleanup on World Mod unload; empty means core)
# Returns an EventSubscription handle
func subscribe(event_name: String, callable: Callable, priority: int = 0, mod_id: String = "") -> EventSubscription:
	var sub := EventSubscription.new(event_name, callable, priority, mod_id, "")
	# World Mod subscriptions bind to the current world context
	if not _current_world_id.is_empty() and not mod_id.is_empty():
		var ctx: EventContext = _world_contexts.get(_current_world_id, null)
		if ctx != null:
			sub.world_id = _current_world_id
			ctx.add(sub)
		else:
			_global_context.add(sub)
	else:
		_global_context.add(sub)
	# Subscriber count monitoring
	_check_subscriber_threshold(event_name)
	return sub


# Unsubscribe
func unsubscribe(sub: EventSubscription) -> void:
	if sub == null:
		return
	if not sub.world_id.is_empty():
		var ctx: EventContext = _world_contexts.get(sub.world_id, null)
		if ctx != null:
			ctx.remove(sub)
	else:
		_global_context.remove(sub)


# Synchronously emit an event
func emit(event_name: String, payload: Dictionary = {}) -> void:
	# Collect subscribers: global first, then current world (merged then sorted by priority)
	var subs: Array[EventSubscription] = []
	subs.append_array(_global_context.get_subscribers(event_name))
	if not _current_world_id.is_empty():
		var ctx: EventContext = _world_contexts.get(_current_world_id, null)
		if ctx != null:
			subs.append_array(ctx.get_subscribers(event_name))
	# Sort by priority ascending
	subs.sort_custom(func(a, b): return a.priority < b.priority)
	# Dispatch
	_stop_propagation_flag = false
	for sub in subs:
		if _stop_propagation_flag:
			break
		sub.callable.call(payload)
	_stop_propagation_flag = false


# Defer emitting an event (dispatched next frame)
func emit_deferred(event_name: String, payload: Dictionary = {}) -> void:
	# Copy payload, to avoid modification during the deferral
	var payload_copy := payload.duplicate(true)
	# Use Callable to bind the current instance and method name
	var cb := Callable(self, "_deferred_emit_impl")
	(cb.bind(event_name, payload_copy)).call_deferred()


# Cancel propagation of the current event (only valid when called inside a callback)
func stop_propagation() -> void:
	_stop_propagation_flag = true


# Get the subscriber count for the specified event (global + current world)
func get_subscriber_count(event_name: String) -> int:
	var count := _global_context.count_subscribers(event_name)
	if not _current_world_id.is_empty():
		var ctx: EventContext = _world_contexts.get(_current_world_id, null)
		if ctx != null:
			count += ctx.count_subscribers(event_name)
	return count


# Get all event names (for debugging)
func get_all_event_names() -> Array[String]:
	var names: Array[String] = []
	names.append_array(_global_context.get_event_names())
	if not _current_world_id.is_empty():
		var ctx: EventContext = _world_contexts.get(_current_world_id, null)
		if ctx != null:
			var world_names := ctx.get_event_names()
			for n in world_names:
				if not names.has(n):
					names.append(n)
	return names


# ============================================================
# Dedicated fast channel for high-frequency events (design doc §6.2.2)
# ============================================================

# Subscribe to tick (every frame)
func subscribe_tick(callable: Callable) -> void:
	if _is_dispatching_tick:
		_pending_tick_adds.append(callable)
	else:
		_tick_subscribers.append(callable)


func unsubscribe_tick(callable: Callable) -> void:
	if _is_dispatching_tick:
		_pending_tick_rems.append(callable)
	else:
		_tick_subscribers.erase(callable)


# Subscribe to physics_tick (every physics frame)
func subscribe_physics_tick(callable: Callable) -> void:
	if _is_dispatching_physics_tick:
		_pending_physics_tick_adds.append(callable)
	else:
		_physics_tick_subscribers.append(callable)


func unsubscribe_physics_tick(callable: Callable) -> void:
	if _is_dispatching_physics_tick:
		_pending_physics_tick_rems.append(callable)
	else:
		_physics_tick_subscribers.erase(callable)


# Dispatch the tick event (called by Bootstrap._process)
func dispatch_tick(delta: float, tick: int) -> void:
	_tick_payload.clear()
	_tick_payload["delta"] = delta
	_tick_payload["tick"] = tick
	_is_dispatching_tick = true
	# Iterate over the snapshot; modifications to the original array do not affect iteration
	var snapshot := _tick_subscribers.duplicate()
	for cb in snapshot:
		# If the subscriber was removed during dispatch (in _pending_tick_rems), skip
		if _pending_tick_rems.has(cb):
			continue
		cb.call(_tick_payload)
	_is_dispatching_tick = false
	_flush_pending_tick_changes()


# Dispatch the physics_tick event (called by Bootstrap._physics_process)
func dispatch_physics_tick(delta: float, tick: int) -> void:
	_physics_tick_payload.clear()
	_physics_tick_payload["delta"] = delta
	_physics_tick_payload["tick"] = tick
	_is_dispatching_physics_tick = true
	var snapshot := _physics_tick_subscribers.duplicate()
	for cb in snapshot:
		if _pending_physics_tick_rems.has(cb):
			continue
		cb.call(_physics_tick_payload)
	_is_dispatching_physics_tick = false
	_flush_pending_physics_tick_changes()


func _flush_pending_tick_changes() -> void:
	for cb in _pending_tick_rems:
		_tick_subscribers.erase(cb)
	_pending_tick_rems.clear()
	for cb in _pending_tick_adds:
		_tick_subscribers.append(cb)
	_pending_tick_adds.clear()


func _flush_pending_physics_tick_changes() -> void:
	for cb in _pending_physics_tick_rems:
		_physics_tick_subscribers.erase(cb)
	_pending_physics_tick_rems.clear()
	for cb in _pending_physics_tick_adds:
		_physics_tick_subscribers.append(cb)
	_pending_physics_tick_adds.clear()


# ============================================================
# World context management (design doc §2.4)
# ============================================================

# Create an independent event context on world load
func on_world_load(world_id: String) -> void:
	if not _world_contexts.has(world_id):
		_world_contexts[world_id] = EventContext.new(world_id)
	_current_world_id = world_id


# World unload phase 2: clear all subscriptions for this world (design doc §2.5)
func on_world_unload(world_id: String) -> void:
	var ctx: EventContext = _world_contexts.get(world_id, null)
	if ctx != null:
		ctx.clear()
		_world_contexts.erase(world_id)
	if _current_world_id == world_id:
		_current_world_id = ""


# Remove all subscriptions of a specified Mod in a specified world (for Mod unload)
func remove_mod_subscriptions(mod_id: String, world_id: String = "") -> void:
	if world_id.is_empty():
		# Global removal
		_global_context.remove_mod(mod_id)
		for wid in _world_contexts.keys():
			_world_contexts[wid].remove_mod(mod_id)
	else:
		var ctx: EventContext = _world_contexts.get(world_id, null)
		if ctx != null:
			ctx.remove_mod(mod_id)


# ============================================================
# Internal helpers
# ============================================================

# Internal implementation of emit_deferred (called via Callable)
func _deferred_emit_impl(event_name: String, payload: Dictionary) -> void:
	emit(event_name, payload)


func _check_subscriber_threshold(event_name: String) -> void:
	var count := get_subscriber_count(event_name)
	if count > MAX_SUBSCRIBERS_PER_EVENT and _logger != null:
		_logger.warn("EventBus", "Event %s subscriber count exceeds threshold %d (current %d)" % [event_name, MAX_SUBSCRIBERS_PER_EVENT, count])
