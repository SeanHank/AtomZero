# Mod main entry interface
# Base class for all Mod main entries (IGlobalMod / IWorldMod)
# Design doc §1.2 and Mod development guide §4.2
#
# This interface only declares methods that the Mod main entry should implement; it does not force
# implementation (GDScript has no true interfaces).
# The Mod main entry should extend Node and implement the following methods:
#   - _init_mod(api: ModAPI)        # Must implement
class_name IMod
extends RefCounted

# Mod initialization (receives a ModAPI reference, only does lightweight initialization)
# Subclasses should implement this method
func _init_mod(api: ModAPI) -> void:
	pass
