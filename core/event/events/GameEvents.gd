# AtomZero built-in event list (design doc appendix B)
# All built-in events use the `core:` namespace, to avoid conflicts with Mod custom events.
class_name GameEvents

# ===== Lifecycle events (general channel) =====
const BOOTSTRAP_START := "core:bootstrap_start"
const GLOBAL_MODS_READY := "core:global_mods_ready"
const WORLD_LOAD_START := "core:world_load_start"
const WORLD_LOAD_PROGRESS := "core:world_load_progress"
const WORLD_LOAD_COMPLETE := "core:world_load_complete"
const WORLD_UNLOAD_START := "core:world_unload_start"
const WORLD_UNLOAD_COMPLETE := "core:world_unload_complete"

# ===== Game loop events (high-frequency, use the dedicated fast channel, do not go through the general EventBus) =====
const TICK := "core:tick"
const PHYSICS_TICK := "core:physics_tick"

# ===== Player events =====
const PLAYER_JOIN := "core:player_join"
const PLAYER_LEAVE := "core:player_leave"

# ===== Mod lifecycle events =====
const MOD_LOADED := "core:mod_loaded"
const MOD_UNLOADED := "core:mod_unloaded"
const MOD_RELOAD_START := "core:mod_reload_start"
const MOD_RELOAD_COMPLETE := "core:mod_reload_complete"
