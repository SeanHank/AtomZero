# AtomZero Mod Development Guide

> **Engine Version**: Godot 4.6.3  
> **Game Name**: AtomZero  
> **Game Version**: `2026.6.30` (Release version, performs SemVer range matching when loading Mods)  
> **Document Version**: v2026.6.30  
> **Companion Design Document**: [ModLoader_Technical_Design.md](./ModLoader_Technical_Design.md)  

---

## Table of Contents

1. [Overview and Core Concepts](#1-overview-and-core-concepts)
2. [Development Environment Setup](#2-development-environment-setup)
3. [Mod Directory Structure and Metadata Specification](#3-mod-directory-structure-and-metadata-specification)
4. [Development Workflow](#4-development-workflow)
5. [API Reference](#5-api-reference)
6. [Resource File Specification](#6-resource-file-specification)
7. [Event System In Detail](#7-event-system-in-detail)
8. [Data Structures and Persistence](#8-data-structures-and-persistence)
9. [Registry System](#9-registry-system)
10. [Debugging and Testing Methods](#10-debugging-and-testing-methods)
11. [Release Specification](#11-release-specification)
12. [Common Issues and Solutions](#12-common-issues-and-solutions)
13. [Complete Example: Developing a Mod from Scratch](#13-complete-example-developing-a-mod-from-scratch)

---

## 1. Overview and Core Concepts

### 1.1 AtomZero's "Zero" Philosophy

AtomZero adopts an "Empty Shell + fully Mod-driven" architecture. The game shell only provides infrastructure such as the Mod Loader kernel, EventBus, Virtual File System, Registry, Persistence Service, and logging system. **All gameplay, blocks, items, entities, UI, and world generation are provided by Mods**.

This means:

- The "game content" you see is actually the product of one or more Mods.
- Mods are not "patches" or "extensions" — they are the game functionality itself.
- Mods have the same capabilities as the "shell" — because the shell provides no gameplay.

### 1.2 Two Types of Mods

AtomZero divides Mods into two categories, differing in **scope and lifecycle**:

| Type | Scope | Storage Directory | Load Timing | Typical Uses |
|------|---------|---------|---------|---------|
| **Global Mod** | Process-level, effective across all worlds | `mods/` | Game startup Bootstrap phase | Core block library, render layer, UI framework, input system, network protocol |
| **World Mod** | Single world isolation | `saves/<WorldName>/mods/` | When the player enters the corresponding world | World-specific gameplay, custom biomes, story scripts, world rules |

### 1.3 Cross-layer Dependency Rules

- **World Mod can depend on Global Mod**: Allowed. When World Mods load, all Global Mods are already ready.
- **Global Mod cannot depend on World Mod**: Not allowed. Global Mods load before World Mods, at which point World Mods do not yet exist.
- If a Global Mod needs to adjust behavior based on the presence of a World Mod, it should handle this in the `_on_world_load()` callback through runtime detection means such as `ModAPI.world.is_world_loaded()`, **not through static dependency declarations**.

### 1.4 Summary of Design Principles

When developing Mods, keep the following principles in mind (see Design Document §1.4 for details):

1. **Empty Shell Principle**: The shell contains no gameplay logic.
2. **Dependency Injection Principle**: Mods obtain services through `ModAPI` and do not directly access kernel implementations.
3. **Event-driven Principle**: Communication between Mods should preferably go through the EventBus to avoid hard references.
4. **Isolation Principle**: World Mods data is strongly bound to the world save and fully unloaded on world switch.
5. **No Exception Isolation Principle**: Errors in Mod callbacks are not caught and may cause crashes. See §10 and Design Document §8.3.
6. **No Permission Sandbox Principle**: No permission control or code signing is provided; only hash whitelist integrity verification is offered. See Design Document §9.

---

## 2. Development Environment Setup

### 2.1 Required Tools

| Tool | Version Requirement | Use |
|------|---------|------|
| Godot Engine | **4.6.3** (must match exactly) | Editor, runtime, resource import |
| Text editor | Any editor with GDScript support | Writing scripts (VSCode + GDScript plugin recommended) |
| Git | Any version | Version control (strongly recommended) |
| ZIP tool | Any | Release packaging (engine built-in tools also work, see §11) |

> **Version Match Warning**: You must use Godot 4.6.3. Using other versions may cause the resource import cache (`.godot/imported/`) to be incompatible, and release Mods will fail to load.

### 2.2 Obtaining and Configuring the Project

#### 2.2.1 Clone the Shell Project

```bash
git clone https://github.com/SeanHank/AtomZero.git atom-zero
cd atom-zero
```

Project root directory structure (Development Mode):

```
atom-zero/
├── project.godot              # Godot project file
├── core/                      # Game shell kernel (read-only, do not modify)
├── mods/                      # ★ Global Mods directory (your workspace)
├── saves/                     # ★ World save root directory (generated at runtime)
├── doc/                       # Documentation
└── icon.svg
```

#### 2.2.2 Open the Project

Launch Godot 4.6.3, select "Open Project", and locate `atom-zero/project.godot`. When opening for the first time, the editor will perform a resource import scan; wait for it to complete.

#### 2.2.3 Confirm Development Mode Is Enabled

Open `core/bootstrap/Bootstrap.gd` and confirm:

```gdscript
const MOD_DEV_MODE: bool = true
```

In Development Mode, all writable paths point to `res://` for easy debugging directly in the editor. Change to `false` for release builds.

> **Important**: Do not modify any files under `core/`. Modifications to the shell kernel will cause incompatibility with future versions.

### 2.3 Create Your First Mod Directory

Create a directory under `mods/` named after your `mod_id`:

```
mods/my_first_mod/
├── mod.json       # Metadata (required)
└── mod.gd         # Main entry (required)
```

`mod_id` must match `^[a-z][a-z0-9_]*$` (lowercase snake_case) and be globally unique. It is recommended to use an author prefix to avoid conflicts, such as `atom_core_blocks` or `myname_cool_feature`.

### 2.4 Run and Verify

1. Click "Run" in the Godot editor.
2. After Bootstrap starts, it will scan the `mods/` directory.
3. When your Mod is loaded for the first time, the HashVerifier will automatically calculate the file hash and **store it in the whitelist** (TOFU model). If the file is modified, it is marked `HASH_MISMATCH` and loading is refused.
4. On subsequent launches, if the file is unchanged, verification passes automatically.
5. Open the built-in console (press the `/` key) and enter `mods list` to see whether your Mod is loaded.

> If you do not see your Mod, check:
> - Whether `mod.json` conforms to the §3.2 specification
> - Whether there are ERROR logs in the console (see §10)
> - Whether the `game_version` field contains `2026.6.30`

### 2.5 Recommended Editor Configuration

#### 2.5.1 VSCode (Recommended)

Install the following extensions:

- **GDScript** (George Mountcastle or official): Syntax highlighting, auto-completion
- **EditorConfig**: Keep indentation style consistent
- **JSON Language Server**: Validate `mod.json` format

#### 2.5.2 Godot Editor External Editor

Configure the use of an external editor in `Editor → Editor Settings → Text Editor → External`, with the path pointing to VSCode.

### 2.6 Project-level `.gitignore` Recommendations

If your Mod is in a standalone Git repository, it is recommended to ignore the following:

```gitignore
# Godot import cache (in Development Mode it should be kept to speed up startup, but can be cleaned)
.godot/imported/

# Runtime-generated directories
config/
data/

# Hash whitelist
hash_whitelist.json

# Manifest generated by the packaging tool (already included in .zip, see §11.4.1)
manifest.json

# Cache
.cache/
cache/
```

> **Note**: In Development Mode, `.godot/imported/` is the import cache automatically generated by the Godot editor. If your Mod requires others in team collaboration to be able to run by simply pulling the code, you **may commit** this directory; if releasing as a `.zip` (see §11), it will be regenerated by the packaging tool.

---

## 3. Mod Directory Structure and Metadata Specification

### 3.1 Recommended Directory Structure

```
<mod_id>/
├── mod.json                 # Metadata (required)
├── mod.gd                   # Main entry script (required)
├── src/                     # Business scripts
│   ├── blocks/
│   │   └── stone_block.gd
│   ├── items/
│   └── systems/
├── assets/                  # Resources
│   ├── textures/
│   ├── models/
│   ├── sounds/
│   └── scenes/
├── config/                  # Runtime config (generated at runtime, do not create manually)
│   └── settings.json
└── data/                    # Runtime data (generated at runtime, do not create manually)
    └── state.json
```

> The `config/` and `data/` directories are automatically created by the kernel on first write. **Do not commit the contents of these directories to your Mod repository** — they are runtime artifacts and will conflict across different environments.

### 3.2 mod.json Metadata Specification

Each Mod root directory must contain a `mod.json`. The complete fields are as follows:

```json
{
    "mod_id": "atom_core_blocks",
    "name": "AtomZero Core Blocks",
    "version": "1.0.0",
    "game_version": ">=2026.6.30,<2027.0.0",
    "author": "AtomZero Team",
    "description": "Core block definition library, providing basic block types.",
    "url": "https://example.com/atom_core_blocks",
    "license": "MIT",

    "mod_type": "global",

    "entry": "mod.gd",
    "entry_class": "CoreBlocksMod",

    "dependencies": [
        { "id": "atom_rendering", "version": ">=1.0.0" }
    ],
    "soft_dependencies": [
        { "id": "atom_sounds", "version": "*" }
    ],

    "load_order": {
        "priority": 100,
        "load_before": ["atom_world_gen"],
        "load_after": ["atom_rendering"]
    },

    "resource_overrides": [
        {
            "target_mod": "atom_core_blocks",
            "target_path": "assets/textures/stone_diffuse.png",
            "source_path": "assets/overrides/my_stone.png"
        }
    ]
}
```

#### Field Description

| Field | Type | Required | Description |
|------|------|------|------|
| `mod_id` | string | Yes | Globally unique identifier, lowercase snake_case `^[a-z][a-z0-9_]*$` |
| `name` | string | Yes | Display name (human-readable) |
| `version` | string | Yes | SemVer semantic version, e.g. `1.0.0` |
| `game_version` | string | Yes | Compatible game version range (SemVer constraint). Current game version `2026.6.30` is a release version, **strictly checked** |
| `author` | string | No | Author |
| `description` | string | No | Description |
| `url` | string | No | Project homepage URL |
| `license` | string | No | License (e.g. `MIT`, `Apache-2.0`, `GPL-3.0`) |
| `mod_type` | enum | Yes | `global` or `world` |
| `entry` | string | Yes | Main entry script relative path (relative to the Mod root directory) |
| `entry_class` | string | Yes | Main entry class name (must implement `IGlobalMod` or `IWorldMod`, see §4.3) |
| `dependencies` | array | No | Hard Dependency list. **Missing any Hard Dependency will cause this Mod to fail to load** |
| `soft_dependencies` | array | No | Soft Dependency list. If present, loaded in order; if absent, no effect |
| `load_order.priority` | int | No | Smaller value loads earlier, default `1000` |
| `load_order.load_before` | array | No | Must load before the specified Mods |
| `load_order.load_after` | array | No | Must load after the specified Mods |
| `resource_overrides` | array | No | Resource override declarations (see §6.4) |

#### Dependency Object Format

Each object in the `dependencies` and `soft_dependencies` arrays:

```json
{ "id": "<depended-upon mod_id>", "version": "<SemVer constraint>" }
```

#### SemVer Constraint Syntax

| Expression | Meaning |
|--------|------|
| `1.2.3` | Exact version |
| `>=1.0.0` | Greater than or equal to |
| `>=1.0.0,<2.0.0` | Range (comma-separated means AND) |
| `^1.2.3` | Compatible with 1.x.x, and >=1.2.3 |
| `~1.2.3` | Compatible with 1.2.x, and >=1.2.3 |
| `*` | Any version |

> **About `game_version` checking**:
> - Release versions (e.g. `1.0.0`, `1.2.0`): Perform SemVer range matching check. If it does not match, the Mod is marked `INVALID_VERSION` and loading is skipped.
> - Alpha/Beta versions (e.g. `Alpha_29062026`): **Skip checking**; all Mods are considered compatible.
>
> The current game is `2026.6.30` release version. Make sure your `game_version` range includes `2026.6.30`. The most permissive form is `"*"`.

### 3.3 Naming Conventions

| Category | Convention | Example |
|------|------|------|
| Mod ID | lowercase snake_case | `atom_core_blocks` |
| Script files | lowercase snake_case `.gd` | `stone_block.gd` |
| Class names | UpperCamelCase, prefixed with Mod ID abbreviation to avoid conflicts | `ACB_StoneBlock` |
| Resource paths | lowercase snake_case | `assets/textures/stone_diffuse.png` |
| Registration identifiers | `<mod_id>:<name>` | `atom_core_blocks:stone` |
| Event names | lowercase snake_case with namespace | `atom_core_blocks:block_placed` |
| Config keys | lowercase snake_case | `max_stack_size` |

> **class_name Note (Important)**: Mod scripts **should not** declare `class_name`. Reason: In Development Mode, Mod source code resides in `res://`, and its `class_name` will be registered in `.godot/global_script_class_cache.cfg`, which is packaged with the PCK for release. When a release build extracts a script with the same name from a `.zip`, it will cause a "Class hides a global script class" conflict that leads to loading failure. The loader instantiates via path `load()` + `new()` and does not rely on class name lookup, so omitting `class_name` does not affect functionality. The same applies to block/entity classes inside a Mod — `class_name` should be omitted.

### 3.4 Non-existent Fields (Important)

The following fields **do not exist** in `mod.json`; do not add them (even if added, they will be ignored):

- `permissions`: No permission control system
- `signature`: No code signing
- `incompatibilities`: Removed from previous versions
- `min_engine_version` / `max_engine_version`: Use `game_version` instead

---

## 4. Development Workflow

### 4.1 Overall Workflow

```
Requirements analysis → Create Mod directory → Write mod.json → Write main entry → Implement features → Test → Package and release
```

### 4.2 Main Entry Interface

The Mod main entry must implement the `IGlobalMod` (Global Mod) or `IWorldMod` (World Mod) interface. These two interfaces are defined in `core/api/interfaces/IGlobalMod.gd` and `core/api/interfaces/IWorldMod.gd`.

#### 4.2.1 IGlobalMod Callbacks

| Callback | Trigger Timing | Use |
|------|---------|------|
| `_init_mod(api: ModAPI)` | Called immediately after instantiation | Receive `ModAPI` reference, do only lightweight initialization (save reference, read config) |
| `_on_bootstrap()` | Triggered in sequence after all Global Mods are instantiated | Register resources, blocks, recipes, etc. |
| `_on_post_bootstrap()` | Triggered after all Global Mods' `_on_bootstrap` completes | Can reference other Mods' registered content |
| `_on_world_load(world_id: String)` | Triggered when a world loads | Global Mods can also listen to world switches |
| `_on_world_unload(world_id: String)` | Triggered when a world unloads | Clean up world-related temporary state |
| `_on_shutdown()` | Triggered when the process exits | Release resources, save data |
| `_on_data_reloaded()` | Triggered when data hot reload completes (optional) | Re-apply config |

#### 4.2.2 IWorldMod Callbacks

| Callback | Trigger Timing | Use |
|------|---------|------|
| `_init_mod(api: ModAPI)` | Called immediately after instantiation | Receive `ModAPI` reference |
| `_on_world_load(world_id: String)` | Triggered when a world loads | Register world-specific content |
| `_on_world_enter(world_id: String)` | Triggered after the player formally enters the world (player entity has been spawned) | Trigger story, spawn initial entities |
| `_on_world_leave(world_id: String)` | Triggered before the player leaves | **Last chance to save data** |
| `_on_world_unload(world_id: String)` | Triggered during the unload cleanup phase | Do only memory cleanup, **do not save data here** |

> **Two-phase Unload (Key)**: The unloading of a World Mod is divided into two phases:
> - **Phase 1 (Full Save)**: Iterate over all World Mods, calling `_on_world_leave()` and saving their `data/`. At this point, the in-memory state is complete.
> - **Phase 2 (Unload Cleanup)**: After all data is saved, call `_on_world_unload()` for memory cleanup, releasing registry partitions and clearing resource caches.
>
> If a Mod crashes in Phase 2, since Phase 1 has already completed the full save, the save data will not be corrupted.
>
> **Developers must**: organize runtime temporary state into the `data` dictionary in `_on_world_leave()`; `_on_world_unload()` should only do memory cleanup.

### 4.3 Main Entry Script Templates

#### 4.3.1 Global Mod Template

```gdscript
# mods/my_global_mod/mod.gd
# Note: Do not declare class_name (see §3.3)
extends Node

var _api: ModAPI

func _init_mod(api: ModAPI) -> void:
    _api = api
    _api.logger.info("my_global_mod", "Initialization started")

func _on_bootstrap() -> void:
    # Register resources, blocks, recipes, etc.
    _register_content()
    # Subscribe to events
    _api.events.subscribe(GameEvents.WORLD_LOAD_COMPLETE, _on_world_loaded)
    _api.events.subscribe_tick(_on_tick)

func _on_post_bootstrap() -> void:
    # At this point, other Global Mods have completed _on_bootstrap, so their registered content can be safely referenced
    var block_script := _api.registry.get_block("atom_core_blocks:stone")
    if block_script:
        _api.logger.debug("my_global_mod", "Successfully referenced stone block")

func _on_world_loaded(payload: Dictionary) -> void:
    var world_id: String = payload.get("world_id", "")
    _api.logger.info("my_global_mod", "World loaded: %s" % world_id)

func _on_tick(payload: Dictionary) -> void:
    var delta: float = payload.get("delta", 0.0)
    # Per-frame logic

func _on_shutdown() -> void:
    _api.logger.info("my_global_mod", "Unload complete")

func _register_content() -> void:
    # Example: register a block
    var block_script := preload("src/blocks/my_block.gd")
    _api.registry.register_block("my_global_mod:my_block", block_script)
```

#### 4.3.2 World Mod Template

```gdscript
# saves/WorldName1/mods/my_world_mod/mod.gd
# Note: Do not declare class_name (see §3.3)
extends Node

var _api: ModAPI
var _runtime_state: Dictionary = {}  # Runtime temporary state

func _init_mod(api: ModAPI) -> void:
    _api = api

func _on_world_load(world_id: String) -> void:
    # Read persistent data
    var saved := _api.persistence.load_data("progress", {"stage": 0})
    _runtime_state = saved
    _api.logger.info("my_world_mod", "Entered world %s, current stage %d" % [world_id, _runtime_state.get("stage", 0)])

func _on_world_enter(world_id: String) -> void:
    # Player entity has been spawned, story can be triggered
    pass

func _on_world_leave(world_id: String) -> void:
    # ★ Key: save runtime state to the data dictionary
    _api.persistence.save_data("progress", _runtime_state)

func _on_world_unload(world_id: String) -> void:
    # Only do memory cleanup, do not save data here
    _runtime_state.clear()
```

### 4.4 Load Order Control

The load order is determined by three parts, in descending priority:

1. **`load_after` / `load_before` declarations**: Hard constraints that form the edges of the dependency graph.
2. **`dependencies`**: A Hard Dependency implicitly means `load_after` (the depended-upon Mod loads first).
3. **`load_order.priority`**: Fine-tuning for nodes at the same level (without explicit constraint relationships); smaller value loads earlier, default `1000`.

The kernel uses Kahn's algorithm for Topological Sort. If a circular dependency exists, all involved Mods are marked `LOAD_FAILED`.

**Example**: Your Mod depends on blocks provided by `atom_core_blocks` and needs to load before `atom_world_gen` (so that world generation can reference your blocks):

```json
{
    "dependencies": [
        { "id": "atom_core_blocks", "version": ">=1.0.0" }
    ],
    "load_order": {
        "priority": 150,
        "load_before": ["atom_world_gen"]
    }
}
```

### 4.5 Data Hot Reload (Development Phase Only)

In the development environment, **Hot Reload of Global Mod data** is supported — only JSON config, resource override declarations, and registry data items are reloaded; **the `.gd` script itself is not reloaded**.

```gdscript
# Via console command (press / to open the console)
# mods reload my_global_mod

# Or trigger in code
_api.dev.reload_mod_data("my_global_mod")
```

Hot Reload workflow:

1. Trigger the `core:mod_reload_start` event.
2. Re-read the JSON config under that Mod's `config/`.
3. Re-parse the `resource_overrides` declarations in `mod.json` and update the ModVFS override mapping table.
4. Call that Mod's `_on_data_reloaded()` callback.
5. Trigger the `core:mod_reload_complete` event.

```gdscript
# Implement the optional callback in the Mod
func _on_data_reloaded() -> void:
    var cfg := _api.persistence.load_config("settings", {})
    _apply_settings(cfg)
```

> **Limitations**:
> - Does not reload `.gd` scripts. Code logic changes require restarting the game.
> - Does not re-instantiate the Mod main class. The instance remains unchanged; only data is refreshed.
> - Only enabled when `OS.is_debug_build()` is `true`; disabled in production environments.
> - Only supports Global Mods. World Mods do not support Hot Reload (they are loaded all at once when the world loads).

---

## 5. API Reference

### 5.1 ModAPI Overview

`ModAPI` is the unified facade for Mods, aggregating all kernel services. A Mod receives a `ModAPI` instance in `_init_mod(api)` and should save it as a member variable for later use.

```gdscript
class_name ModAPI
extends RefCounted

var logger: LoggerAPI          # Log
var events: EventAPI           # Events
var resources: ResourceAPI     # Resource loading
var registry: RegistryAPI      # Registry
var persistence: PersistenceAPI # Persistence
var vfs: VFSAPI                # Virtual File System
var world: WorldAPI            # World info
var dev: DevAPI                # Dev tools (debug build only)
```

> **Note**: This design **does not include** `PermissionAPI`. All Mods have the same API access capabilities.

### 5.2 LoggerAPI (Log)

```gdscript
class_name LoggerAPI
extends RefCounted

func trace(tag: String, msg: String) -> void   # Value 0, extremely fine-grained
func debug(tag: String, msg: String) -> void   # Value 1, debug info
func info(tag: String, msg: String) -> void    # Value 2, general info
func warn(tag: String, msg: String) -> void    # Value 3, warning
func error(tag: String, msg: String) -> void   # Value 4, error
func fatal(tag: String, msg: String) -> void   # Value 5, fatal error
```

**Usage Example**:

```gdscript
func _on_bootstrap() -> void:
    _api.logger.info("my_mod", "Initialization started")
    _api.logger.debug("my_mod", "Loaded %d blocks" % _block_count)
    if _something_wrong:
        _api.logger.warn("my_mod", "Config missing, using default value")
```

**`tag` Convention**: It is recommended to use your `mod_id` for easy filtering in logs. The log format is:

```
[2026-06-29 12:34:56.789] [INFO ] [my_mod] Initialization started
```

**Output Targets**:

| Target | Enable Condition |
|------|---------|
| Godot editor Output panel | `OS.is_debug_build()` |
| Console stdout | Always |
| Log file `<writable_root>/logs/atomzero.log` | Always (rolls over when exceeding 10MB, keeping 5 archives) |

> **Performance Tip**: `trace` and `debug` are filtered out in production. But even when filtered, the cost of constructing the message string still exists. Avoid string concatenation in high-frequency paths (such as `_on_tick`), or use conditional checks:
>
> ```gdscript
> if _api.logger.is_debug_enabled():  # Assume the interface provides this (confirm in actual use)
>     _api.logger.debug("my_mod", "Frame %d state %s" % [_frame, _state])
> ```

### 5.3 EventAPI (Events)

See §7 Event System In Detail.

### 5.4 ResourceAPI (Resource Loading)

```gdscript
class_name ResourceAPI
extends RefCounted

# Synchronous load (blocking, suitable for small resources or startup)
func load(mod_id: String, relative_path: String) -> Resource

# Async load (non-blocking, suitable for large resources or runtime)
func load_threaded(mod_id: String, relative_path: String) -> void

# Check if a resource exists
func exists(mod_id: String, relative_path: String) -> bool
```

**Usage Example**:

```gdscript
# Load your own Mod's texture
var tex: Texture2D = _api.resources.load("my_mod", "assets/textures/icon.png")

# Load another Mod's texture (requires the other party not to restrict it; this design has no permission control)
var core_tex: Texture2D = _api.resources.load("atom_core_blocks", "assets/textures/stone.png")

# Check if a resource exists
if _api.resources.exists("my_mod", "assets/sounds/break.ogg"):
    _api.logger.info("my_mod", "Sound exists")
```

> **`mod://` Protocol**: `ResourceAPI.load()` internally uses the `mod://` protocol, equivalent to:
> ```gdscript
> ResourceLoader.load("mod://global/my_mod/assets/textures/icon.png")
> ```
> You usually do not need to use the `mod://` protocol directly; `ResourceAPI` already encapsulates it.

### 5.5 RegistryAPI (Registry)

See §9 Registry System.

### 5.6 PersistenceAPI (Persistence)

See §8 Data Structures and Persistence.

### 5.7 WorldAPI (World Info)

```gdscript
class_name WorldAPI
extends RefCounted

func get_current_world_id() -> String   # Current world ID (returns empty string when not loaded)
func is_world_loaded() -> bool          # Whether a world is running
func get_world_seed() -> int            # Current world seed
```

**Usage Example**:

```gdscript
func _on_tick(payload: Dictionary) -> void:
    if not _api.world.is_world_loaded():
        return  # Do not execute world logic in the main menu
    var world_id := _api.world.get_current_world_id()
    # ...
```

### 5.8 DevAPI (Development Tools)

Only available when `OS.is_debug_build()` is `true`. Calls in production environments will return `null` or raise an error.

```gdscript
class_name DevAPI
extends RefCounted

# Data Hot Reload (Global Mod only)
func reload_mod_data(mod_id: String) -> void

# Register a custom debug panel
func register_debug_panel(panel_scene: PackedScene) -> void
```

---

## 6. Resource File Specification

### 6.1 Supported Resource Types

AtomZero is built on Godot and supports all Godot-native resource types:

| Type | Extension | Use |
|------|--------|------|
| Texture | `.png`, `.jpg`, `.webp`, `.svg` | 2D textures, UI icons |
| Compressed Texture | `.ctex`, `.dds` | GPU compressed textures (recommended for release) |
| Model | `.glb`, `.gltf`, `.obj` | 3D models |
| Audio | `.wav`, `.ogg`, `.mp3` | Sound effects, music |
| Font | `.ttf`, `.otf`, `.woff` | Fonts |
| Scene | `.tscn`, `.scn` | Godot scenes |
| Resource | `.tres` | Godot resource files |
| Script | `.gd` | GDScript |
| JSON | `.json` | Config, data |

### 6.2 Resource Loading Mechanism

AtomZero implements the `mod://` protocol through a custom `ResourceFormatLoader`, deeply integrated with the Godot resource system.

#### 6.2.1 Virtual Path Format

| Type | Virtual Path Format | Example |
|------|-------------|------|
| Global Mod resource | `mod://global/<mod_id>/<relative_path>` | `mod://global/my_mod/assets/textures/icon.png` |
| World Mod resource | `mod://world/<world_id>/<mod_id>/<relative_path>` | `mod://world/World1/my_mod/data.json` |

#### 6.2.2 Path Resolution Priority

`ModVFS.resolve_virtual_path()` finds the actual physical path by the following priority:

1. **World Mod override layer**: `saves/<world>/mods/<mod_id>/assets/...`
2. **`resource_overrides` declarations of other Mods**: see §6.4
3. **Mod itself**: `mods/<mod_id>/assets/...`

#### 6.2.3 Cache Strategy

`ResourceFormatLoader._load()` internally uses `real_path` as the cache key (`CACHE_MODE_REUSE`). Multiple `mod://` virtual paths that resolve to the same physical file share the same resource instance, avoiding duplicate loading and doubled memory usage.

### 6.3 Resource Loading Methods

#### 6.3.1 Synchronous Load (Recommended for Startup and Small Resources)

```gdscript
func _on_bootstrap() -> void:
    var tex: Texture2D = _api.resources.load("my_mod", "assets/textures/icon.png")
    var scene: PackedScene = _api.resources.load("my_mod", "assets/scenes/ui_panel.tscn")
```

#### 6.3.2 Async Load (Recommended for Runtime and Large Resources)

```gdscript
var _tex: Texture2D

func _on_bootstrap() -> void:
    # Initiate an async load request
    _api.resources.load_threaded("my_mod", "assets/textures/big_texture.png")

func _on_tick(payload: Dictionary) -> void:
    # Poll the load status in tick
    var status := ResourceLoader.load_threaded_get_status("mod://global/my_mod/assets/textures/big_texture.png")
    if status == ResourceLoader.THREAD_LOAD_LOADED:
        _tex = ResourceLoader.load_threaded_get("mod://global/my_mod/assets/textures/big_texture.png")
        _api.logger.info("my_mod", "Large texture loaded")
```

#### 6.3.3 Using `preload` (Only for Resources Internal to Your Own Mod)

`preload` resolves paths at compile time and has the best performance, but **can only be used for `res://` paths** (Development Mode). In Release Mode, `preload("res://mods/...")` may fail because Mods are not in the PCK.

**Recommended approach**: Use `preload` to load your own Mod scripts during development; use `_api.resources.load()` to load resource files at runtime.

```gdscript
# Load your own Mod's script (preload can be used during development)
const BlockScript := preload("src/blocks/my_block.gd")

# Load your own Mod's resource (use _api.resources.load uniformly)
var tex := _api.resources.load("my_mod", "assets/textures/icon.png")
```

### 6.4 Resource Override Mechanism

A Mod can declare overrides for other Mods' resources in `mod.json`. Mods that load later have higher override priority.

```json
{
    "resource_overrides": [
        {
            "target_mod": "atom_core_blocks",
            "target_path": "assets/textures/stone_diffuse.png",
            "source_path": "assets/overrides/my_stone.png"
        }
    ]
}
```

The above declaration means: when any code requests `mod://global/atom_core_blocks/assets/textures/stone_diffuse.png`, it actually loads `my_mod/assets/overrides/my_stone.png`.

**Use Cases**:

- Resource pack/texture pack: Replace the core block textures
- Localization: Replace UI text resources
- Balance adjustments: Replace recipe data

> **Note**: The override mechanism is global and will affect all Mods' access to that resource. Use it carefully to avoid breaking the expected behavior of other Mods.

### 6.5 Resource Naming and Organization Recommendations

1. **Lowercase snake_case naming**: All file names use lowercase snake_case, e.g. `stone_diffuse.png`, `break_sound.ogg`.
2. **Semantic naming**: Add suffixes to textures to indicate purpose, such as `_diffuse`, `_normal`, `_emission`.
3. **Organize by type in directories**: `textures/`, `models/`, `sounds/`, `scenes/`.
4. **Avoid case-sensitivity issues**: macOS is case-insensitive by default; Linux is case-sensitive. **Always use lowercase** to avoid cross-platform issues (see §12.5 for details).
5. **Do not use spaces or Chinese characters in paths**: Use only `[a-z0-9_/]`.

### 6.6 Resource Size Recommendations

This design **imposes no restrictions on Mod resource size** (see Design Document §10.1.5 for details). Hash verification uses streaming chunked reading (64KB chunks), with constant memory usage regardless of file size.

However, considering startup time, it is recommended:

- The total metadata files (`.gd`, `.json`, `.tres`, `.tscn`) of a single Mod should be kept within tens of MB.
- Binary resources (textures, audio) should use compressed formats:
  - Textures: Use `.ctex` (GPU compressed textures) for the release version, automatically generated by the packaging tool.
  - Audio: Use `.ogg` for sound effects, `.ogg` or `.mp3` for music.
- Trim unused resources: Before release, check the `assets/` directory and remove unreferenced files.

---

## 7. Event System In Detail

### 7.1 Event Model

AtomZero events use a "name + dictionary payload" model to avoid strong typing coupling:

```gdscript
# Emit an event
_api.events.emit("my_mod:something_happened", { "value": 42, "target": "player" })

# Subscribe to an event
_api.events.subscribe("my_mod:something_happened", _on_something)

func _on_something(payload: Dictionary) -> void:
    var value: int = payload.get("value", 0)
    var target: String = payload.get("target", "")
```

### 7.2 Two Types of Event Channels

| Channel | Applicable Scenarios | Performance Characteristics |
|------|---------|---------|
| **General channel** | Low-frequency events (lifecycle, player behavior, custom events) | Dictionary payload, each emit has GC overhead |
| **Dedicated fast channel** | High-frequency events (`core:tick`, `core:physics_tick`) | Pre-allocated payload reuse, zero Dictionary allocation |

**Key difference**: High-frequency events **must** use the dedicated channel to avoid per-frame Dictionary allocation causing GC pressure.

### 7.3 General Event API

```gdscript
class_name EventAPI
extends RefCounted

# Subscribe to an event, returns a subscription handle
# priority: smaller value executes earlier, default 0
func subscribe(event_name: String, callable: Callable, priority: int = 0) -> EventSubscription

# Unsubscribe (can also be done via EventSubscription)
func unsubscribe(subscription: EventSubscription) -> void

# Synchronously emit an event
func emit(event_name: String, payload: Dictionary = {}) -> void

# Defer emitting an event (dispatched next frame)
func emit_deferred(event_name: String, payload: Dictionary = {}) -> void

# Cancel current event propagation (only effective when called within a callback)
func stop_propagation() -> void
```

**Usage Example**:

```gdscript
var _sub: EventSubscription

func _on_bootstrap() -> void:
    # Subscribe, priority -10 (executes earlier than default 0)
    _sub = _api.events.subscribe(GameEvents.WORLD_LOAD_COMPLETE, _on_world_loaded, -10)

func _on_world_loaded(payload: Dictionary) -> void:
    var world_id: String = payload.get("world_id", "")
    _api.logger.info("my_mod", "World loaded: %s" % world_id)
    # To prevent subsequent lower-priority subscribers from receiving this event:
    # _api.events.stop_propagation()

func _on_shutdown() -> void:
    # Actively unsubscribe (optional; the kernel auto-cleans when a World Mod unloads)
    if _sub:
        _api.events.unsubscribe(_sub)
```

### 7.4 Dedicated Fast Channel for High-frequency Events

`core:tick` and `core:physics_tick` are high-frequency events triggered every frame. **You must** use the dedicated API to subscribe; do not use the general `subscribe()`.

```gdscript
# Subscribe to tick (per frame)
_api.events.subscribe_tick(_on_tick)
_api.events.unsubscribe_tick(_on_tick)

# Subscribe to physics_tick (per physics frame)
_api.events.subscribe_physics_tick(_on_physics_tick)
_api.events.unsubscribe_physics_tick(_on_physics_tick)
```

**Dedicated Channel Features**:

1. **Pre-allocated payload**: EventBus internally pre-allocates a single `_tick_payload` Dictionary; each frame it `clear()`s it, then fills in `delta` / `tick` for reuse, with zero allocation.
2. **Dedicated subscriber array**: Iterates and calls directly, with no Dictionary lookup and no priority sorting overhead.
3. **Deferred modification queue**: If you call `subscribe_tick()` / `unsubscribe_tick()` within a tick callback (such as the "unsubscribe after processing one frame" pattern), the modification request does not take effect immediately but is added to a deferred queue and applied uniformly after the current frame's dispatch is complete. **This avoids skipping elements or crashing when modifying the array during iteration**.

**Usage Example**:

```gdscript
func _on_bootstrap() -> void:
    _api.events.subscribe_tick(_on_tick)

func _on_tick(payload: Dictionary) -> void:
    var delta: float = payload.get("delta", 0.0)
    var tick: int = payload.get("tick", 0)
    # Your logic

    # "Unsubscribe after processing one frame" pattern example:
    if _should_stop:
        _api.events.unsubscribe_tick(_on_tick)  # Deferred until after this frame's dispatch completes
```

> **Important**: It is safe to call `subscribe_tick()` or `unsubscribe_tick()` within a tick callback; the kernel will defer applying modifications. But **do not** directly modify the `_tick_subscribers` array within a tick callback (which you cannot access anyway).

### 7.5 Built-in Event List

All built-in events are defined in `core/event/events/GameEvents.gd` accessed via the `GameEvents` class name constants.

#### 7.5.1 Lifecycle Events

| Event Constant | Event Name | Payload | Trigger Timing | Channel |
|---------|--------|------|---------|------|
| `GameEvents.BOOTSTRAP_START` | `core:bootstrap_start` | `{}` | Bootstrap starts | General |
| `GameEvents.GLOBAL_MODS_READY` | `core:global_mods_ready` | `{ count: int, failed: int }` | All Global Mods loaded | General |
| `GameEvents.WORLD_LOAD_START` | `core:world_load_start` | `{ world_id: String, seed: int }` | Start loading a world | General |
| `GameEvents.WORLD_LOAD_COMPLETE` | `core:world_load_complete` | `{ world_id: String }` | World loading complete | General |
| `GameEvents.WORLD_UNLOAD_START` | `core:world_unload_start` | `{ world_id: String }` | Start unloading a world | General |
| `GameEvents.WORLD_UNLOAD_COMPLETE` | `core:world_unload_complete` | `{ world_id: String }` | World unloading complete | General |

#### 7.5.2 Game Loop Events (High-frequency)

| Event Constant | Event Name | Payload | Trigger Timing | Channel |
|---------|--------|------|---------|------|
| `GameEvents.TICK` | `core:tick` | `{ delta: float, tick: int }` | Every frame | **Dedicated fast channel** |
| `GameEvents.PHYSICS_TICK` | `core:physics_tick` | `{ delta: float, tick: int }` | Every physics frame | **Dedicated fast channel** |

> **Note**: The scope of `core:tick` and `core:physics_tick` is **current world only**. Global Mods + the current world's World Mods will receive them; they are not triggered when no world is loaded. Tick is not triggered in the main menu (unless a world is running in the background).

#### 7.5.3 Player Events

| Event Constant | Event Name | Payload | Trigger Timing |
|---------|--------|------|---------|
| `GameEvents.PLAYER_JOIN` | `core:player_join` | `{ player_id: String, world_id: String }` | Player joins |
| `GameEvents.PLAYER_LEAVE` | `core:player_leave` | `{ player_id: String }` | Player leaves |

#### 7.5.4 Mod Lifecycle Events

| Event Constant | Event Name | Payload | Trigger Timing |
|---------|--------|------|---------|
| `GameEvents.MOD_LOADED` | `core:mod_loaded` | `{ mod_id: String, mod_type: String }` | Single Mod load complete |
| `GameEvents.MOD_UNLOADED` | `core:mod_unloaded` | `{ mod_id: String }` | Single Mod unload complete |
| `GameEvents.MOD_RELOAD_START` | `core:mod_reload_start` | `{ mod_id: String }` | Data Hot Reload starts |
| `GameEvents.MOD_RELOAD_COMPLETE` | `core:mod_reload_complete` | `{ mod_id: String }` | Data Hot Reload complete |

### 7.6 Custom Events

A Mod can emit its own events; it is recommended to use the `<mod_id>:` namespace to avoid conflicts:

```gdscript
# Define event name constants (centralized management recommended)
const EVENT_BLOCK_PLACED := "my_mod:block_placed"
const EVENT_QUEST_COMPLETE := "my_mod:quest_complete"

# Emit an event
func _place_block(pos: Vector3, block_id: String) -> void:
    # ... block placement logic
    _api.events.emit(EVENT_BLOCK_PLACED, {
        "position": pos,
        "block_id": block_id,
        "player_id": _api.world.get_current_world_id()  # Example
    })

# Other Mods can subscribe
func _on_bootstrap() -> void:
    _api.events.subscribe("my_mod:block_placed", _on_block_placed)

func _on_block_placed(payload: Dictionary) -> void:
    var pos: Vector3 = payload.get("position", Vector3.ZERO)
    var block_id: String = payload.get("block_id", "")
    _api.logger.info("other_mod", "Detected block placement: %s at %s" % [block_id, pos])
```

### 7.7 Event Scope

| Event Source | Scope | Recipients |
|---------|--------|--------|
| `core:*` lifecycle events | Global | All loaded Mods |
| `core:tick` / `core:physics_tick` | Current world only | Global Mods + current world's World Mods |
| `<mod_id>:*` custom events | Default global; emitted by a World Mod are automatically scoped to its world | Depends on subscriber scope |

When a World Mod unloads, EventBus automatically removes all its subscriptions (based on the mod_id registry), avoiding dangling callbacks.

### 7.8 Subscriber Count Monitoring

EventBus maintains a subscriber count for each event name. When the subscriber count exceeds a threshold (default 256), it logs a WARN log and prominently indicates it in the debug overlay.

```gdscript
const MAX_SUBSCRIBERS_PER_EVENT := 256
```

> This is a monitoring and alerting mechanism and **does not forcibly block subscriptions**. But if your event subscriber count grows abnormally, check whether there is a memory leak (such as repeated subscriptions without unsubscribing).

---

## 8. Data Structures and Persistence

### 8.1 Data Category Overview

| Data Category | Storage Location | Format | Lifecycle | Applicable Mod |
|---------|---------|------|---------|---------|
| Global Mod config | `mods/<mod_id>/config/<key>.json` | JSON | Cross-process | Global Mod |
| Global Mod runtime data | `mods/<mod_id>/data/<key>.json` | JSON / Binary | Cross-process | Global Mod |
| World Mod config | `saves/<WorldName>/mods/<mod_id>/config/<key>.json` | JSON | Bound to world | World Mod |
| World Mod runtime data | `saves/<WorldName>/mods/<mod_id>/data/<key>.json` | JSON / Binary | Bound to world | World Mod |

### 8.2 PersistenceAPI Interface

A Mod accesses persistence services through `ModAPI.persistence` (`PersistenceAPI`). This API **automatically injects mod_id and world_id context** without manual specification.

```gdscript
class_name PersistenceAPI
extends RefCounted

# Config (usually user-adjustable settings)
func save_config(key: String, data: Variant) -> void
func load_config(key: String, default: Variant = null) -> Variant

# Runtime data (usually game progress, state)
func save_data(key: String, data: Variant) -> void
func load_data(key: String, default: Variant = null) -> Variant
```

**Differences between Global Mod and World Mod**:

- When a Global Mod calls the above methods, data is stored under `mods/<mod_id>/`.
- When a World Mod calls the above methods, data is stored under `saves/<current_world>/mods/<mod_id>/` (`world_id` is automatically obtained from the current world context).

### 8.3 Storage Format

All config and data use the **JSON** format (human-readable, easy to debug). Large binary objects use standalone `.bin` files indexed via JSON.

#### 8.3.1 Global Mod Config Storage Example

Location: `mods/atom_core_blocks/config/settings.json`

```json
{
    "mod_id": "atom_core_blocks",
    "mod_version": "1.0.0",
    "created_at": "2026-06-29T10:00:00Z",
    "updated_at": "2026-06-29T12:30:00Z",
    "data": {
        "max_stack_size": 64,
        "enable_physics": true,
        "block_hardness": {
            "stone": 1.5,
            "dirt": 0.5
        }
    }
}
```

#### 8.3.2 World Mod Config Storage Example

Location: `saves/WorldName1/mods/adventure_quest_pack/config/quests.json`

```json
{
    "mod_id": "adventure_quest_pack",
    "mod_version": "1.2.0",
    "world_id": "WorldName1",
    "world_seed": 123456789,
    "created_at": "2026-06-29T10:00:00Z",
    "updated_at": "2026-06-29T12:30:00Z",
    "data": {
        "difficulty": "hard",
        "active_quests": ["main_quest_1", "side_quest_3"],
        "completed_quests": []
    }
}
```

> The kernel automatically fills in meta fields such as `mod_id`, `mod_version`, `world_id`, `world_seed`, `created_at`, and `updated_at`; you only need to care about the `data` part.

### 8.4 Usage Examples

#### 8.4.1 Global Mod Config Read/Write

```gdscript
func _init_mod(api: ModAPI) -> void:
    _api = api
    # Read config, use default value if not present
    var cfg := _api.persistence.load_config("settings", {
        "max_stack_size": 64,
        "enable_physics": true
    })
    _max_stack = cfg.get("max_stack_size", 64)
    _physics_enabled = cfg.get("enable_physics", true)

func _on_shutdown() -> void:
    # Save config
    _api.persistence.save_config("settings", {
        "max_stack_size": _max_stack,
        "enable_physics": _physics_enabled
    })
```

#### 8.4.2 World Mod Data Read/Write

```gdscript
var _quest_progress: Dictionary = {}

func _on_world_load(world_id: String) -> void:
    # Read world data
    _quest_progress = _api.persistence.load_data("quest_progress", {})
    _api.logger.info("my_world_mod", "Loaded %d quest progress entries" % _quest_progress.size())

func _on_world_leave(world_id: String) -> void:
    # ★ Key: save in _on_world_leave, not in _on_world_unload
    _api.persistence.save_data("quest_progress", _quest_progress)
```

#### 8.4.3 Storing Large Binary Objects

JSON is not suitable for storing large binary data (such as screenshots, compressed saves). Recommended approach:

```gdscript
# 1. Save binary data as a .bin file (manually managed)
func _save_screenshot(image: Image) -> void:
    var data := image.save_png_to_buffer()
    var path := _api.vfs.get_mod_data_dir() + "/screenshot.bin"  # Assume VFSAPI provides this
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(data)
    file.close()
    # Record the index in JSON
    _api.persistence.save_data("screenshot_index", {
        "path": "screenshot.bin",
        "size": data.size(),
        "timestamp": Time.get_unix_time_from_system()
    })
```

### 8.5 Save Timing

| Trigger Point | Saved Content | Corresponding Phase |
|--------|---------|---------|
| Mod actively calls `save_*` | Immediate save | Runtime |
| World unload · Phase 1 (after `_on_world_leave()`) | Auto-save all World Mods' `data/` | Two-phase Unload · Full Save phase |
| Before game exit (`_on_shutdown`) | Auto-save all Global Mods' `data/` | Shutdown phase |
| Auto-save timer (default 5 minutes) | Save all Mods' `data/` | Runtime |

> **Key Constraint**: World Mod's auto-save occurs in **Phase 1**, at which point all `_on_world_leave()` callbacks have finished executing and the in-memory state is complete, so the saved data is valid. Phase 2 (`_on_world_unload()` and after) **no longer performs any save operations**; it only does memory cleanup and VRAM release.
>
> **Be sure to organize runtime temporary state into the `data` dictionary in `_on_world_leave()`**, and do not rely on `_on_world_unload()`.

### 8.6 Atomic Write

All save operations use **atomic write**: first write to `<key>.json.tmp`, then `rename` to `<key>.json`, to avoid half-written files due to crashes.

You do not need to worry about this detail; the kernel handles it automatically.

### 8.7 Data Migration (Self-managed)

This design **does not provide** a data migration mechanism or save schema versioning. When a Mod version upgrade causes a storage format change, old version data may not load correctly.

**Recommended approach**: Maintain a version field in `data` yourself and implement migration logic yourself:

```gdscript
const DATA_VERSION := 2

func _on_world_load(world_id: String) -> void:
    var saved := _api.persistence.load_data("progress", {})
    var ver: int = saved.get("_version", 1)

    # Migration logic
    if ver < 2:
        saved = _migrate_v1_to_v2(saved)
        saved["_version"] = 2

    _state = saved

func _migrate_v1_to_v2(old: Dictionary) -> Dictionary:
    var new := {}
    # ... migrate fields
    new["quest_stage"] = old.get("stage", 0)  # Field renamed
    return new
```

---

## 9. Registry System

### 9.1 Overview

`RegistrySystem` uniformly manages registries for blocks, items, entities, recipes, and more. Mods access it through `ModAPI.registry` (`RegistryAPI`).

### 9.2 RegistryAPI Interface

```gdscript
class_name RegistryAPI
extends RefCounted

# Register a block
func register_block(id: String, script: Script) -> void

# Register an item
func register_item(id: String, script: Script) -> void

# Register an entity
func register_entity(id: String, script: Script) -> void

# Register a recipe
func register_recipe(id: String, recipe: Dictionary) -> void

# Query a block script
func get_block(id: String) -> Script

# List all block IDs (can be filtered by prefix)
func list_blocks(prefix: String = "") -> Array[String]
```

### 9.3 Registration Identifier Convention

Registration IDs use the `<mod_id>:<name>` format to ensure global uniqueness:

```gdscript
# Correct
_api.registry.register_block("my_mod:custom_stone", preload("src/blocks/custom_stone.gd"))

# Wrong (no namespace, may conflict)
_api.registry.register_block("custom_stone", preload("src/blocks/custom_stone.gd"))
```

### 9.4 Registration Timing

**Must register in `_on_bootstrap()` or `_on_world_load()`**:

- Global Mod: Register global blocks/items/recipes in `_on_bootstrap()`.
- World Mod: Register world-specific content in `_on_world_load()`.

```gdscript
# Global Mod
func _on_bootstrap() -> void:
    _api.registry.register_block("my_mod:custom_stone", preload("src/blocks/custom_stone.gd"))
    _api.registry.register_item("my_mod:magic_wand", preload("src/items/magic_wand.gd"))
    _api.registry.register_recipe("my_mod:stone_to_dirt", {
        "inputs": [{"id": "atom_core_blocks:stone", "count": 1}],
        "outputs": [{"id": "atom_core_blocks:dirt", "count": 1}]
    })

# World Mod
func _on_world_load(world_id: String) -> void:
    _api.registry.register_entity("my_world_mod:boss_dragon", preload("src/entities/boss_dragon.gd"))
```

### 9.5 Referencing Other Mods' Registered Content

In `_on_post_bootstrap()` (Global Mod) or `_on_world_load()` (World Mod), you can safely reference content registered by other Mods:

```gdscript
# Global Mod
func _on_post_bootstrap() -> void:
    # At this point atom_core_blocks has completed _on_bootstrap, and its blocks are registered
    var stone_script := _api.registry.get_block("atom_core_blocks:stone")
    if stone_script:
        _api.logger.debug("my_mod", "Successfully referenced stone block")
    else:
        _api.logger.warn("my_mod", "atom_core_blocks:stone not found, may not be installed")
```

### 9.6 Registry Partition for World Mods

`RegistrySystem` maintains an independent partition for each world. Resources registered by World Mods are automatically prefixed with `world.<world_id>.` (handled internally, transparent to the outside). When the world unloads, the partition is released as a whole, with no need for manual deregistration.

### 9.7 Query Performance

- The registry uses `Dictionary` directly keyed by string ID, with O(1) lookup.
- `list_blocks(prefix)` iterates over keys and filters using `string.begins_with()`. For <10k entries, it takes <1ms.

---

## 10. Debugging and Testing Methods

### 10.1 Logging System

#### 10.1.1 Log Levels

| Level | Value | Use |
|------|------|------|
| `TRACE` | 0 | Extremely fine-grained tracing (per-frame, per-chunk) |
| `DEBUG` | 1 | Debug info (state changes, load steps) |
| `INFO` | 2 | General info (Mod load complete, world switch) |
| `WARN` | 3 | Warning (missing dependency but can degrade, subscriber over threshold) |
| `ERROR` | 4 | Error (Mod load failed, hash mismatch) |
| `FATAL` | 5 | Fatal error (kernel crash, cannot continue running) |

#### 10.1.2 Log File Location

| Mode | Path |
|------|------|
| Development Mode | `res://logs/atomzero.log` |
| Release Mode | `<user_data_dir>/logs/atomzero.log` |

The log file automatically rolls over when it exceeds 10MB, keeping 5 archives (`atomzero.log.1`, `atomzero.log.2` ...).

#### 10.1.3 Adjusting the Log Level

Adjust the global log level via console command:

```
log level DEBUG
```

Or via `ModAPI.dev` (debug build only).

### 10.2 Built-in Console

In the development environment, press the `/` key to open the built-in console. Common commands:

| Command | Description |
|------|------|
| `mods list` | List all loaded Mods and their status |
| `mods info <mod_id>` | Show details of the specified Mod |
| `mods reload <mod_id>` | Data Hot Reload of the specified Global Mod (data only) |
| `mods enable <mod_id>` | Enable the specified Mod |
| `mods disable <mod_id>` | Disable the specified Mod |
| `events list` | List all current event subscribers and counts |
| `events emit <event_name> [json]` | Manually emit an event |
| `registry list blocks` | List all registered blocks |
| `hash list` | List Mods in the hash whitelist and their hashes |
| `hash reset <mod_id>` | Reset the hash trust of the specified Mod |
| `log level <level>` | Set the global log level |

**Example**:

```
~ mods list
  [LOADED] atom_core_blocks v1.0.0 (global)
  [LOADED] my_mod v0.1.0 (global)
  [FAILED] broken_mod v1.0.0 (global) - HASH_MISMATCH

~ events emit core:world_load_complete {"world_id":"TestWorld"}
~ registry list blocks
  atom_core_blocks:stone
  atom_core_blocks:dirt
  my_mod:custom_stone
```

### 10.3 Debug Overlay

In the development environment, a HUD overlay is displayed, showing in real time:

- Number of loaded Mods and number of failures
- Current FPS, chunk load count, memory usage
- Current world ID and state machine state
- Subscriber count for each event (shown in red when over threshold)
- The last 10 WARN/ERROR logs

### 10.4 Mod-provided Debug Panels

A Mod can register a custom debug panel via `ModAPI.dev.register_debug_panel(panel_scene)`, automatically integrated into the built-in debug window.

```gdscript
func _on_bootstrap() -> void:
    if OS.is_debug_build():
        var panel := preload("assets/scenes/debug_panel.tscn").instantiate()
        _api.dev.register_debug_panel(panel)
```

### 10.5 Error Handling and Crash Mechanism (Important)

#### 10.5.1 Design Stance: No Exception Isolation

Godot 4's GDScript **has no native try/catch mechanism**. This design **explicitly abandons** runtime exception isolation:

1. **Mod load failure** (errors before instantiation, such as invalid metadata, hash mismatch, missing dependencies): Logs an ERROR, skips that Mod, and aggregates into an error report interface for users to view.
2. **Mod runtime error** (errors thrown in callbacks, such as `_on_bootstrap`, `_on_tick`, `_on_world_load`): **Not caught**. The error propagates along the call stack and may cause the game to crash.
3. **Automatically open log on crash**: When the game crashes, the Logger automatically opens the log file (`OS.shell_open()`) for easy troubleshooting.

#### 10.5.2 Development Recommendations

Since there is no exception isolation, you **must** ensure the robustness of Mod callbacks:

```gdscript
# ❌ Dangerous: if _load_data throws an error, _on_bootstrap is interrupted, and the game may crash
func _on_bootstrap() -> void:
    var data := _load_data()  # May throw
    _apply_data(data)

# ✅ Safe: manually validate, avoid error propagation
func _on_bootstrap() -> void:
    var data: Variant = _api.persistence.load_data("my_data", {})
    if not data is Dictionary:
        _api.logger.warn("my_mod", "Data format abnormal, using default value")
        data = {}
    _apply_data(data)
```

**Best Practices**:

1. **Validate external input**: Data read from `load_config`/`load_data`, event payloads, and other Mods' registered content should have their types and fields validated before use.
2. **Use `get` instead of `[]`**: `dict.get("key", default)` will not throw; `dict["key"]` throws when the key is missing.
3. **Avoid null references**: After calling query methods like `get_block()`, check whether the return value is `null`.
4. **Use `preload` carefully**: A `preload` path error is exposed at compile time, but a `load` path error throws at runtime.
5. **Test boundary cases**: Empty data, missing dependencies, rapid world switching, etc.

#### 10.5.3 Crash Report

When the game crashes, a crash report `<writable_root>/logs/crash_<timestamp>.txt` is automatically generated, containing:

- Game version, engine version, platform
- List of loaded Mods and their versions
- The last 100 log entries
- System info (CPU, memory, GPU)

Please attach this file when submitting a bug report.

### 10.6 Testing Strategy

#### 10.6.1 Unit Tests (Internal Mod Logic)

AtomZero does not provide a testing framework, but you can build a simple test scene within your Mod:

```gdscript
# mods/my_mod/src/tests/test_block.gd
extends Node

func run_tests() -> void:
    _test_block_creation()
    _test_block_hardness()
    _api.logger.info("my_mod:test", "All tests passed")

func _test_block_creation() -> void:
    var block := preload("src/blocks/custom_stone.gd").new()
    assert(block.hardness > 0, "Block hardness should be greater than 0")
```

Trigger tests in `_on_post_bootstrap()` (debug build only):

```gdscript
func _on_post_bootstrap() -> void:
    if OS.is_debug_build():
        var tester := preload("src/tests/test_block.gd").new()
        add_child(tester)
        tester.run_tests()
```

#### 10.6.2 Integration Tests

1. **Minimal dependency test**: Load only your Mod and necessary dependencies to verify core functionality.
2. **Full dependency test**: Load all Mods expected to coexist to verify no conflicts.
3. **World switching test**: Repeatedly enter/exit different worlds to verify that World Mods unload correctly with no memory leaks.
4. **Long-running test**: Run continuously for more than 30 minutes, observing whether FPS drops or memory keeps growing.

#### 10.6.3 Performance Profiling

Use Godot's built-in Monitor panel (`Debugger → Monitors`) to observe:

- Memory usage (`Object`, `Node`, `Resource` counts)
- FPS and frame time
- Resource load count

### 10.7 Common Debugging Tips

#### 10.7.1 Check Whether a Mod Is Loaded

```
~ mods list
~ mods info my_mod
```

#### 10.7.2 Check Event Subscriptions

```
~ events list
```

If your event callback is not triggered, check whether the subscriber list contains your callback.

#### 10.7.3 Manually Emit an Event

```
~ events emit my_mod:test_event {"value":42}
```

#### 10.7.4 Reset Hash Trust

Frequent file modifications during development will cause hash mismatches. Reset trust:

```
~ hash reset my_mod
```

The next launch will recalculate the hash and store it in the whitelist.

#### 10.7.5 Hot Reload Data

After modifying `config/settings.json`, no restart is needed:

```
~ mods reload my_mod
```

Only data is reloaded, not code.

---

## 11. Release Specification

### 11.1 Release Mode Overview

In Release Mode, Mods must be packaged as `.zip` archives containing **pre-imported resources** (`.godot/imported/` cache). This is to bypass the issue of Godot export packages missing the `.import` pipeline — release Mod resources are located in `user_data_dir` (not in the PCK), and Godot does not run the import pipeline on them during export; directly calling `ResourceLoader.load()` to load the raw files will fail.

### 11.2 .zip Package Structure

```
my_mod-1.0.0.zip
├── mod.json
├── mod.gd
├── src/
│   └── blocks/
│       └── my_block.gd
├── assets/
│   └── textures/
│       ├── my_texture.png
│       └── my_texture.png.import       # ★ Import config (Godot-generated)
├── .godot/
│   └── imported/                        # ★ Pre-import cache
│       └── my_texture.ctex              # Compressed texture cache
└── manifest.json                        # ★ Resource manifest (generated by the packaging tool)
```

### 11.3 manifest.json Format

`manifest.json` is automatically generated by the packaging tool and records the `size` + `sha256` of each binary file, used for O(1) stat checks during hash verification (see Design Document §9.2.3 for details).

```json
{
    "mod_id": "my_mod",
    "mod_version": "1.0.0",
    "generated_at": "2026-06-29T10:00:00Z",
    "binary_files": {
        "assets/textures/my_texture.png": { "size": 1048576, "sha256": "abc123..." },
        "assets/sounds/break.ogg": { "size": 32768, "sha256": "ghi789..." }
    }
}
```

> **Do not manually edit `manifest.json`**. It is regenerated by the tool each time it is packaged.

### 11.4 Packaging Workflow

#### 11.4.1 Using the Packaging Tool (Recommended)

AtomZero provides the `tools/pack_mod.py` command-line tool, which automatically:

1. Scans the Mod directory to identify binary resource files (images, audio, models, fonts, etc.).
2. Generates `manifest.json` (containing the `size` + `sha256` of each binary file, used for runtime integrity verification).
3. Packages as `<mod_id>-<version>.zip` (excludes `config/`, `data/`, `.cache/` runtime state directories; keeps the `.godot/` pre-import resource cache).

This script is a pure Python standard library implementation and **does not require Godot to be installed** (requires Python 3.8+).

**Usage**:

```bash
# Basic usage (outputs to the parent directory of the Mod directory)
python3 tools/pack_mod.py mods/my_mod

# Specify the output directory
python3 tools/pack_mod.py mods/my_mod ./output

# Supports res:// prefix
python3 tools/pack_mod.py res://mods/my_mod
```

> **Parameter Description**:
> - `mod_dir` (required): Mod directory path; supports `res://` prefix, relative paths, and absolute paths.
> - `output_dir` (optional): Output directory; defaults to the parent directory of `mod_dir`.

**Prerequisite**: Before packaging, you must first open the project with the Godot editor and scan the Mod directory to generate the `.godot/imported/` pre-import resource cache (the `.zip` will include this directory). If the Mod has no binary resources, this step can be skipped.

> **Packaging Output**: The `.zip` contains `mod.json`, source code, resources, `.godot/imported/`, and `manifest.json`; it does not contain `config/`, `data/`, `.cache/`, or `.DS_Store`. After packaging, `manifest.json` will also be left in the Mod source directory (already included in the `.zip`); you can manually delete it or add it to `.gitignore`.

#### 11.4.2 Manual Packaging (Not Recommended)

If you must package manually, the steps are as follows:

1. **Open the project in the Godot editor**, letting the editor scan your Mod directory and generate `.import` files and the `.godot/imported/` cache.
2. **Generate `manifest.json`**: Manually write or use a script to compute the size and sha256 of each binary file.
3. **Package as .zip**:

```bash
cd mods/my_mod
zip -r ../my_mod-1.0.0.zip . \
    -x "config/*" \
    -x "data/*" \
    -x ".git/*"
```

> **Note**: Do not package the `config/` and `data/` directories — they are runtime artifacts.

### 11.5 Release Checklist

Before releasing a Mod, check the following:

- [ ] `mod.json` fields are complete and valid
- [ ] `mod_id` matches `^[a-z][a-z0-9_]*$`
- [ ] `version` conforms to SemVer
- [ ] `game_version` includes `2026.6.30` (e.g. `>=2026.6.30,<2027.0.0`)
- [ ] `entry` and `entry_class` are correct
- [ ] `dependencies` lists all Hard Dependencies
- [ ] Class names have a Mod ID prefix to avoid conflicts
- [ ] Resource paths are all lowercase snake_case
- [ ] The `.zip` contains `.godot/imported/` and `manifest.json`
- [ ] The `.zip` does not contain `config/`, `data/`, or `.git/`
- [ ] Tested loading in a clean Godot project
- [ ] Long-running test shows no memory leaks
- [ ] Documentation (README) explains dependencies, features, and config items

### 11.6 Distribution

- **Global Mod**: Place the `.zip` in `<writable_root>/mods/`. On the user's first game launch, the ModLoader extracts it to `.cache/<mod_id>/` and automatically stores the hash in the whitelist (no confirmation dialog is shown).
- **World Mod**: Place the `.zip` in `<writable_root>/saves/<WorldName>/mods/`.

> **Special Nature of World Mod Distribution**: World Mods are bound to the world save. If you release a World Mod for others to use, users need to:
> 1. Create a new world (or use an existing world)
> 2. Place the `.zip` in that world's `mods/` directory
> 3. It will be automatically loaded when entering the world

### 11.7 Version Management Recommendations

Follow [SemVer](https://semver.org/):

- `MAJOR`: Incompatible API changes (such as modifying registration IDs, deleting blocks)
- `MINOR`: Backward-compatible feature additions
- `PATCH`: Backward-compatible bug fixes

Example: `1.0.0` → `1.0.1` (bug fix) → `1.1.0` (add new blocks) → `2.0.0` (rename all block IDs)

---

## 12. Common Issues and Solutions

### 12.1 Mod Not Loaded

**Symptom**: Your Mod is not visible in `mods list`, or shows `[FAILED]`.

**Troubleshooting Steps**:

1. **Check whether `mod.json` is valid**:
   ```
   ~ mods info my_mod
   ```
   If it says "invalid mod.json", check the JSON format (use a JSON validator) and whether all required fields are present.

2. **Check whether `game_version` includes `2026.6.30`**:
   ```json
   "game_version": ">=2026.6.30,<2027.0.0"  // ✅
   "game_version": ">=2027.0.0"              // ❌ Does not include 2026.6.30
   ```

3. **Check whether Hard Dependencies are satisfied**:
   ```
   ~ mods list
   ```
   If it shows `MISSING_DEP`, it means a Mod declared in `dependencies` is not installed or its version does not satisfy.

4. **Check hash verification**:
   If it shows `HASH_MISMATCH`, it means the file has been modified but not re-trusted. During development, when files are frequently modified, reset trust:
   ```
   ~ hash reset my_mod
   ```

5. **View the log**:
   Open `<writable_root>/logs/atomzero.log`, search for your `mod_id`, and check the specific error.

### 12.2 Hash Verification Failure

**Symptom**: The log shows `Mod my_mod hash mismatch, refused to load`.

**Cause**: The Mod file has been modified and is inconsistent with the hash recorded in the whitelist.

**Solution**:

- **During development**: This is normal (it is triggered every time you modify code). Use `~ hash reset my_mod` to reset trust; the next launch will recalculate and store it in the whitelist.
- **During release**: It means the Mod file has been tampered with or corrupted. Re-download the official version.

### 12.3 Event Callback Not Triggered

**Symptom**: Subscribed to an event but the callback is never executed.

**Troubleshooting Steps**:

1. **Check the subscriber list**:
   ```
   ~ events list
   ```
   If your event is not in the list, it means `subscribe()` was not called or was called at the wrong time. Make sure to subscribe in `_on_bootstrap()` or `_on_world_load()`.

2. **Check the event name spelling**:
   ```gdscript
   # ❌ Typo
   _api.events.subscribe("core:world_load_complte", _on_loaded)
   # ✅ Use a constant
   _api.events.subscribe(GameEvents.WORLD_LOAD_COMPLETE, _on_loaded)
   ```

3. **Check the event scope**:
   - `core:tick` is only triggered when a world is running; it is not triggered in the main menu.
   - Events subscribed to by a World Mod are automatically unsubscribed when its world unloads.

4. **Manually trigger a test**:
   ```
   ~ events emit core:world_load_complete {"world_id":"TestWorld"}
   ```

### 12.4 tick Callback Causing Crash or Lag

**Symptom**: Game frame rate drops sharply or crashes; the log points to your `_on_tick` callback.

**Cause**:

- The callback performs heavy computation or synchronous I/O.
- The callback modifies a collection being iterated.
- The callback throws an uncaught error.

**Solution**:

1. **Avoid heavy computation in tick**: Spread heavy computation across multiple frames, or move it to a background thread.
2. **Avoid synchronous resource loading in tick**: Use `load_threaded`.
3. **Avoid `emit`-ing high-frequency events in tick**: It will cause cascading overhead.
4. **Validate payload fields**:
   ```gdscript
   func _on_tick(payload: Dictionary) -> void:
       var delta: float = payload.get("delta", 0.0)  # ✅ Has default value
       # ❌ var delta: float = payload["delta"]  # Crashes when key is missing
   ```
5. **Use `unsubscribe_tick` as an exit condition**:
   ```gdscript
   func _on_tick(payload: Dictionary) -> void:
       if _work_done:
           _api.events.unsubscribe_tick(_on_tick)  # Safe, takes effect deferred
   ```

### 12.5 Cross-platform Path Case Issues

**Symptom**: The Mod loads fine on macOS, but Linux reports "resource not found".

**Cause**: macOS file systems are case-insensitive by default; Linux is case-sensitive. This design **does not perform path case normalization** (see Design Document Appendix D.15 for details).

**Solution**:

- **Always use lowercase** for all files and directories.
- **The paths in `mod.json` must match the actual file name case**.
- Test your Mod on Linux.

```gdscript
# ✅ Correct
_api.resources.load("my_mod", "assets/textures/icon.png")

# ❌ Dangerous (loads on macOS, fails on Linux)
_api.resources.load("my_mod", "assets/Textures/Icon.PNG")
```

### 12.6 Class Name Conflict

**Symptom**: Loading reports an error `Class "XXX" already exists`.

**Cause**: Different Mods have the same `class_name`.

**Solution**:

- Use the Mod ID abbreviation as a prefix: `atom_core_blocks` → `ACB_`, `my_mod` → `MM_`.
- Avoid overly generic class names (such as `Block`, `Item`, `Manager`).

```gdscript
# ❌ Dangerous
class_name Block

# ✅ Safe
class_name MM_CustomBlock
```

### 12.7 Memory Continuously Growing

**Symptom**: Memory usage keeps rising after long running.

**Troubleshooting Steps**:

1. **Check for un-unsubscribed event subscriptions**: Unsubscribe in `_on_world_leave()` or `_on_shutdown()`.
2. **Check for unreleased resource references**: Cached Resource references are held without being released. A World Mod's resources are automatically cleaned up when the world unloads, but a Global Mod's resources must be managed by you.
3. **Check for circular references**: If GDScript RefCounted objects form a circular reference, they must be manually broken.
4. **Use the Monitor panel**: Observe changes in `Object`, `Node`, and `Resource` counts.

### 12.8 World Mod Data Loss

**Symptom**: After exiting the world and re-entering, the data is not saved.

**Cause**:

- Data was saved in `_on_world_unload()` (wrong timing; Phase 2 does not save).
- `save_data()` was not called.

**Solution**:

- **Save in `_on_world_leave()`** (Phase 1, full save).
- `_on_world_unload()` should only do memory cleanup.

```gdscript
# ✅ Correct
func _on_world_leave(world_id: String) -> void:
    _api.persistence.save_data("progress", _state)

# ❌ Wrong (Phase 2 does not save)
func _on_world_unload(world_id: String) -> void:
    _api.persistence.save_data("progress", _state)  # Will not take effect
```

### 12.9 Release Mod Resource Loading Failure

**Symptom**: Works fine in Development Mode, but the release version reports `Failed to load resource`.

**Cause**: Release Mods must be packaged as `.zip` and contain pre-imported resources (`.godot/imported/`).

**Solution**:

- Use the `tools/pack_mod.py` tool to package, ensuring that `.godot/imported/` and `manifest.json` are included.
- Do not manually zip the source file directory (it will be missing the import cache).
- See §11 Release Specification for details.

### 12.10 Circular Dependency

**Symptom**: The log shows `CIRCULAR_DEP`; multiple Mods fail to load.

**Cause**: Mod A's `load_after` points to Mod B, and Mod B's `load_after` points to Mod A.

**Solution**:

- Check the `load_after` and `dependencies` declarations to eliminate the cycle.
- If A and B truly need to reference each other, refactor to event-driven communication, or merge into a single Mod.

### 12.11 `preload` Fails in Release Version

**Symptom**: Works fine in Development Mode; in the release version, `preload("res://mods/...")` reports an error.

**Cause**: Release Mods are not in the PCK; the `res://mods/` path does not exist.

**Solution**:

- **Scripts**: Use a relative path `preload("src/blocks/my_block.gd")` (relative to the current script file); do not use the absolute path `res://mods/`.
- **Resource files**: Use `_api.resources.load("my_mod", "assets/...")`.

```gdscript
# ❌ Works during development, fails in release
const Script := preload("res://mods/my_mod/src/blocks/my_block.gd")

# ✅ Always works (relative path)
const Script := preload("src/blocks/my_block.gd")

# ✅ Always works (API load)
var tex := _api.resources.load("my_mod", "assets/textures/icon.png")
```

### 12.12 How to Communicate with Other Mods

**Recommended approach: Event-driven**

```gdscript
# Mod A emits an event
_api.events.emit("mod_a:something_happened", { "value": 42 })

# Mod B subscribes
func _on_bootstrap() -> void:
    _api.events.subscribe("mod_a:something_happened", _on_a_happened)

func _on_a_happened(payload: Dictionary) -> void:
    var value := payload.get("value", 0)
```

**Not recommended approach: Directly referencing Mod instances**

Do not attempt to access another Mod's internal state via `get_node("/root/...")` or global variables. This creates hard coupling, and the kernel does not guarantee the node paths of Mod instances.

---

## 13. Complete Example: Developing a Mod from Scratch

This section demonstrates the complete Mod development workflow through a full example. We will develop a Global Mod named `atom_demo_blocks` that registers two custom blocks and implements a simple placement count feature.

### 13.1 Create the Directory Structure

```
mods/atom_demo_blocks/
├── mod.json
├── mod.gd
├── src/
│   └── blocks/
│       ├── ruby_block.gd
│       └── sapphire_block.gd
└── assets/
    └── textures/
        ├── ruby_block.png
        └── sapphire_block.png
```

### 13.2 Write mod.json

```json
{
    "mod_id": "atom_demo_blocks",
    "name": "AtomZero Demo Blocks",
    "version": "1.0.0",
    "game_version": ">=2026.6.30,<2027.0.0",
    "author": "Demo Author",
    "description": "Demo Mod, adds ruby and sapphire blocks.",
    "license": "MIT",
    "mod_type": "global",
    "entry": "mod.gd",
    "entry_class": "ADB_DemoBlocksMod",
    "dependencies": [],
    "load_order": {
        "priority": 200
    }
}
```

### 13.3 Write Block Scripts

`src/blocks/ruby_block.gd`:

```gdscript
extends Resource
class_name ADB_RubyBlock

var id: String = "atom_demo_blocks:ruby"
var display_name: String = "Ruby Block"
var hardness: float = 3.0
var texture_path: String = "assets/textures/ruby_block.png"
```

`src/blocks/sapphire_block.gd`:

```gdscript
extends Resource
class_name ADB_SapphireBlock

var id: String = "atom_demo_blocks:sapphire"
var display_name: String = "Sapphire Block"
var hardness: float = 2.5
var texture_path: String = "assets/textures/sapphire_block.png"
```

### 13.4 Write the Main Entry

`mod.gd`:

```gdscript
extends Node
class_name ADB_DemoBlocksMod

var _api: ModAPI
var _place_count: Dictionary = {}  # { "ruby": int, "sapphire": int }

const EVENT_BLOCK_PLACED := "atom_demo_blocks:block_placed"

func _init_mod(api: ModAPI) -> void:
    _api = api
    _api.logger.info("atom_demo_blocks", "Initialization started")

func _on_bootstrap() -> void:
    # Register blocks
    _api.registry.register_block("atom_demo_blocks:ruby", preload("src/blocks/ruby_block.gd"))
    _api.registry.register_block("atom_demo_blocks:sapphire", preload("src/blocks/sapphire_block.gd"))
    _api.logger.info("atom_demo_blocks", "Registered 2 blocks")

    # Subscribe to events
    _api.events.subscribe(GameEvents.WORLD_LOAD_COMPLETE, _on_world_loaded)
    _api.events.subscribe(GameEvents.WORLD_UNLOAD_COMPLETE, _on_world_unloaded)

func _on_post_bootstrap() -> void:
    # Verify that blocks are registered
    var blocks := _api.registry.list_blocks("atom_demo_blocks:")
    _api.logger.debug("atom_demo_blocks", "Number of blocks in registry: %d" % blocks.size())

func _on_world_loaded(payload: Dictionary) -> void:
    var world_id: String = payload.get("world_id", "")
    # Read the placement count for this world (World Mod data example; here a Global Mod only demonstrates)
    _place_count = _api.persistence.load_data("place_count_%s" % world_id, {
        "ruby": 0,
        "sapphire": 0
    })
    _api.logger.info("atom_demo_blocks", "World %s loaded, history placements: %s" % [world_id, _place_count])

func _on_world_unloaded(payload: Dictionary) -> void:
    var world_id: String = payload.get("world_id", "")
    # Save the placement count for this world
    _api.persistence.save_data("place_count_%s" % world_id, _place_count)
    _place_count.clear()

func _on_shutdown() -> void:
    _api.logger.info("atom_demo_blocks", "Unload complete")

# Public method: for other Mods to call to increment the placement count
func increment_place_count(block_name: String) -> void:
    _place_count[block_name] = _place_count.get(block_name, 0) + 1
    # Emit a custom event
    _api.events.emit(EVENT_BLOCK_PLACED, {
        "block": block_name,
        "total": _place_count[block_name]
    })
```

### 13.5 Testing

1. Launch the game (F5).
2. On first load, the hash is automatically calculated and stored in the whitelist (no confirmation dialog is shown).
3. Open the console (`` ` ``), enter `mods list`, and you should see `[LOADED] atom_demo_blocks v1.0.0 (global)`.
4. Enter `registry list blocks`, and you should see `atom_demo_blocks:ruby` and `atom_demo_blocks:sapphire`.
5. Enter a world and observe the log output "World XXX loaded".
6. Exit the world and observe the log output "history placements" data.
7. Re-enter the same world and verify that the count has been persisted.

### 13.6 Package and Release

1. Package using the `tools/pack_mod.py` tool:
   ```bash
   python3 tools/pack_mod.py mods/atom_demo_blocks
   ```
2. Generates `atom_demo_blocks-1.0.0.zip`.
3. Test in a clean Godot project: place the `.zip` in `mods/`, launch the game, and verify loading.

### 13.7 Distribution

Upload `atom_demo_blocks-1.0.0.zip` to a Mod repository or share it directly with users. Users can place it in the `<writable_root>/mods/` directory.

---

## Appendix A: Quick Reference Card

### A.1 Main Entry Callback Quick Reference

| Callback | Global Mod | World Mod | Use |
|------|:---:|:---:|------|
| `_init_mod(api)` | ✅ | ✅ | Receive API reference |
| `_on_bootstrap()` | ✅ | ❌ | Register resources, blocks |
| `_on_post_bootstrap()` | ✅ | ❌ | Reference other Mods' content |
| `_on_world_load(world_id)` | ✅ | ✅ | World load callback |
| `_on_world_enter(world_id)` | ❌ | ✅ | Player enters world |
| `_on_world_leave(world_id)` | ❌ | ✅ | ★ Save data |
| `_on_world_unload(world_id)` | ✅ | ✅ | Memory cleanup |
| `_on_shutdown()` | ✅ | ❌ | Process exit |
| `_on_data_reloaded()` | ✅ | ❌ | Data Hot Reload |

### A.2 Common API Quick Reference

```gdscript
# Log
_api.logger.info("mod_id", "message")
_api.logger.warn("mod_id", "message")
_api.logger.error("mod_id", "message")

# Events
_api.events.subscribe(GameEvents.WORLD_LOAD_COMPLETE, _on_loaded)
_api.events.subscribe_tick(_on_tick)
_api.events.emit("mod_id:event_name", { "key": "value" })

# Resources
var tex := _api.resources.load("mod_id", "assets/textures/icon.png")
_api.resources.exists("mod_id", "assets/sounds/x.ogg")

# Registry
_api.registry.register_block("mod_id:stone", preload("src/blocks/stone.gd"))
var script := _api.registry.get_block("mod_id:stone")

# Persistence
_api.persistence.save_config("settings", { "key": "value" })
var cfg := _api.persistence.load_config("settings", {})
_api.persistence.save_data("progress", { "stage": 1 })

# World
var world_id := _api.world.get_current_world_id()
if _api.world.is_world_loaded(): ...
```

### A.3 Console Command Quick Reference

```
mods list                    # List loaded Mods
mods info <mod_id>           # Mod details
mods reload <mod_id>         # Data Hot Reload
events list                  # Event subscribers
events emit <name> [json]    # Emit an event
registry list blocks         # List blocks
hash reset <mod_id>          # Reset hash trust
log level <level>            # Set log level
```

### A.4 Status Code Quick Reference

| Status Code | Meaning |
|--------|------|
| `OK` | Normal |
| `LOAD_FAILED` | Load failed |
| `INVALID_VERSION` | Game version mismatch |
| `MISSING_DEP` | Missing Hard Dependency |
| `CIRCULAR_DEP` | Circular Dependency |
| `HASH_MISMATCH` | Hash verification failed |
| `UNTRUSTED` | Reserved status, currently unused (auto-trusted on first load) |

---

## Appendix B: Features Explicitly Not Implemented (Developer Notice)

When developing Mods, note that the following features **do not exist**; do not attempt to use them:

| Feature | Decision | Alternative |
|------|------|---------|
| Runtime exception isolation (try/catch) | Not implemented | Manually validate input, avoid error propagation |
| Code Hot Reload | Not implemented | Data Hot Reload (data only); code changes require restart |
| Permission control system | Not implemented | All Mods have the same API access capabilities |
| Code signing | Not implemented | Hash whitelist (TOFU) verifies integrity |
| Data migration mechanism | Not implemented | Mod maintains its own `_version` field and migrates |
| Save schema versioning | Not implemented | JSON lenient parsing; Mod handles compatibility itself |
| Reverse cross-layer dependency (Global→World) | Not implemented | Global Mod probes at runtime via `_on_world_load` |
| `incompatibilities` mutual exclusion detection | Not implemented | Removed from previous versions |
| `mod://` protocol integration in editor | Not implemented | Use the real path `res://mods/<mod_id>/` during development |
| TOFU trust confirmation dialog | Not implemented | Auto-trust on first load, no user confirmation dialog is shown |
| Path case normalization | Not implemented | Always use lowercase naming |
| Static scanning for dangerous APIs | Not implemented | Without a sandbox, static scanning can be bypassed |
