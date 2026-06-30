# Event subscription handle
# Returned by EventBus.subscribe(), can be used to unsubscribe.
# Holds the event name, subscriber Callable, priority, and the source mod_id (used for auto-cleanup on World Mod unload).
class_name EventSubscription
extends RefCounted

var event_name: String = ""
var callable: Callable
var priority: int = 0
var mod_id: String = ""        # Mod the subscriber belongs to (empty means core itself)
var world_id: String = ""      # World ID the World Mod subscription belongs to (empty means global subscription)

func _init(p_event: String = "", p_callable: Callable = Callable(), p_priority: int = 0, p_mod_id: String = "", p_world_id: String = "") -> void:
	event_name = p_event
	callable = p_callable
	priority = p_priority
	mod_id = p_mod_id
	world_id = p_world_id
