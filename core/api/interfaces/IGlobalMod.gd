# Global Mod interface
# Design doc §1.2 and §5.2 Global Mod initialization callback order
# Mod development guide §4.2.1 IGlobalMod callbacks
#
# A Global Mod main entry should extend Node and implement the following callbacks:
#   _init_mod(api: ModAPI)              # Inject API reference
#   _on_bootstrap()                     # Register resources, blocks, recipes
#   _on_post_bootstrap()                # Triggered after all _on_bootstrap complete, can reference other Mods' registered content
#   _on_world_load(world_id: String)    # Callback on world load (Global Mods can also listen)
#   _on_world_unload(world_id: String)   # Callback on world unload
#   _on_shutdown()                       # Callback on process exit
#   _on_data_reloaded()                  # Callback on data hot reload complete (optional)
class_name IGlobalMod
extends IMod
