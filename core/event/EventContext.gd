# World event context
# Maintains an independent subscription context for each world, cleared on world unload (design doc §2.4 item 2).
# World Mod subscriptions are automatically bound to the current world context; on world unload,
# all subscriptions in that context are removed.
class_name EventContext
extends RefCounted

# The world ID this context belongs to
var world_id: String = ""

# mod_id -> Array[EventSubscription]
# Grouped by source Mod, convenient for unsubscribing by Mod or by whole world
var _by_mod: Dictionary = {}

# event_name -> Array[EventSubscription]
# Grouped by event name, convenient for querying subscriber count
var _by_event: Dictionary = {}


func _init(p_world_id: String = "") -> void:
	world_id = p_world_id


# Register a subscription into this context
func add(sub: EventSubscription) -> void:
	sub.world_id = world_id
	# Group by Mod
	var mod_subs: Array = _by_mod.get(sub.mod_id, [])
	mod_subs.append(sub)
	_by_mod[sub.mod_id] = mod_subs
	# Group by event
	var evt_subs: Array = _by_event.get(sub.event_name, [])
	evt_subs.append(sub)
	_by_event[sub.event_name] = evt_subs


# Remove a specified subscription
func remove(sub: EventSubscription) -> void:
	var mod_subs: Array = _by_mod.get(sub.mod_id, [])
	mod_subs.erase(sub)
	if mod_subs.is_empty():
		_by_mod.erase(sub.mod_id)
	else:
		_by_mod[sub.mod_id] = mod_subs
	var evt_subs: Array = _by_event.get(sub.event_name, [])
	evt_subs.erase(sub)
	if evt_subs.is_empty():
		_by_event.erase(sub.event_name)
	else:
		_by_event[sub.event_name] = evt_subs


# Remove all subscriptions of a specified Mod (for Mod unload)
func remove_mod(mod_id: String) -> Array[EventSubscription]:
	var removed: Array[EventSubscription] = []
	var mod_subs: Array = _by_mod.get(mod_id, [])
	for sub in mod_subs:
		removed.append(sub)
		var evt_subs: Array = _by_event.get(sub.event_name, [])
		evt_subs.erase(sub)
		if evt_subs.is_empty():
			_by_event.erase(sub.event_name)
		else:
			_by_event[sub.event_name] = evt_subs
	_by_mod.erase(mod_id)
	return removed


# Clear all subscriptions (called on world unload)
func clear() -> Array[EventSubscription]:
	var all: Array[EventSubscription] = []
	for mod_id in _by_mod.keys():
		for sub in _by_mod[mod_id]:
			all.append(sub)
	_by_mod.clear()
	_by_event.clear()
	return all


# Get the subscriber count for a specified event
func count_subscribers(event_name: String) -> int:
	var arr: Array = _by_event.get(event_name, [])
	return arr.size()


# Get all event names
func get_event_names() -> Array[String]:
	var names: Array[String] = []
	for k in _by_event.keys():
		names.append(k)
	return names


# Get subscriptions for a specified event (already sorted by priority)
func get_subscribers(event_name: String) -> Array[EventSubscription]:
	var arr: Array = _by_event.get(event_name, [])
	# Sort by priority ascending (smaller value = executed first)
	arr.sort_custom(func(a, b): return a.priority < b.priority)
	# Copy to a typed array to satisfy the return type requirement
	var result: Array[EventSubscription] = []
	result.assign(arr)
	return result
