# Event API (design doc §6.1.1 and §6.2)
# Mods call via _api.events.*
class_name EventAPI
extends RefCounted

var _event_bus: EventBus = null
var _mod_id: String = ""
var _world_id: String = ""  # Current world ID (set by ModContext for World Mods)


func _init(event_bus: EventBus, mod_id: String, world_id: String = "") -> void:
	_event_bus = event_bus
	_mod_id = mod_id
	_world_id = world_id


# General events (low frequency)
func subscribe(event_name: String, callable: Callable, priority: int = 0) -> EventSubscription:
	return _event_bus.subscribe(event_name, callable, priority, _mod_id)


func unsubscribe(subscription: EventSubscription) -> void:
	_event_bus.unsubscribe(subscription)


func emit(event_name: String, payload: Dictionary = {}) -> void:
	_event_bus.emit(event_name, payload)


func emit_deferred(event_name: String, payload: Dictionary = {}) -> void:
	_event_bus.emit_deferred(event_name, payload)


func stop_propagation() -> void:
	_event_bus.stop_propagation()


# Fast channel dedicated to high-frequency events (tick / physics_tick)
func subscribe_tick(callable: Callable) -> void:
	_event_bus.subscribe_tick(callable)


func unsubscribe_tick(callable: Callable) -> void:
	_event_bus.unsubscribe_tick(callable)


func subscribe_physics_tick(callable: Callable) -> void:
	_event_bus.subscribe_physics_tick(callable)


func unsubscribe_physics_tick(callable: Callable) -> void:
	_event_bus.unsubscribe_physics_tick(callable)


# Get subscriber count (for debugging)
func get_subscriber_count(event_name: String) -> int:
	return _event_bus.get_subscriber_count(event_name)
