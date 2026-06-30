# World Mod interface
# Design doc §1.2 and §5.3.2 World Mod initialization callback order
# Mod development guide §4.2.2 IWorldMod callbacks
#
# A World Mod main entry should extend Node and implement the following callbacks:
#   _init_mod(api: ModAPI)              # Inject API reference
#   _on_world_load(world_id: String)     # Register world-specific content
#   _on_world_enter(world_id: String)    # Triggered after the player formally enters the world
#   _on_world_leave(world_id: String)    # Triggered before the player leaves (the last chance to save data)
#   _on_world_unload(world_id: String)   # Unload cleanup (only do memory cleanup, do not save data)
class_name IWorldMod
extends IMod
