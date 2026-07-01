# AtomZero: Zero is the cradle of all possibilities. 

_Be a light, not a judge. Be a model, not a critic. — Stephen Covey_

[![Godot Engine](https://img.shields.io/badge/Godot-4.6.3-478CBF?logo=godotengine&logoColor=white)](https://godotengine.org)
[![License](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-lightgrey)](#environment-requirements)

---

## Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture & Tech Stack](#architecture--tech-stack)
- [Environment Requirements](#environment-requirements)
- [Installation](#installation)
- [Usage Guide](#usage-guide)
- [Project Structure](#project-structure)
- [Creating Your Own Mod](#creating-your-own-mod)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)
- [Acknowledgments](#acknowledgments)

---

## Overview

**AtomZero** is a Godot 4-based game framework built on a radical principle: the base game contains **no gameplay whatsoever**. Instead, it provides a robust mod-loading infrastructure — and **everything else** is delivered through mods.

The main scene is an empty `Control` node. The sole autoload is `Bootstrap`, which initializes all core services. From there, mods take over: a Global Mod can provide a main menu, a World Mod can generate terrain, and the framework handles lifecycle, persistence, events, and resource loading.

This architecture enables:
- **Total customization** — every aspect of gameplay is moddable
- **Clean separation** — the engine kernel (`core/`) is never modified; all content lives in `mods/`
- **World-scoped isolation** — World Mods are loaded/unloaded per world, preventing cross-world contamination

## Key Features

### Engine Kernel
- **Single Autoload Design** — Only `Bootstrap` is registered as an autoload; all other services are explicitly instantiated in code, making dependency chains readable and testable
- **Two Mod Types**:
  - **Global Mods** — Process-level, loaded at startup, persist across worlds
  - **World Mods** — World-scoped, loaded on world entry, fully unloaded on exit
- **Dependency Injection** — Each mod receives a `ModAPI` facade providing typed access to 8 sub-APIs
- **Event-Driven Architecture** — `EventBus` with dedicated fast channels for tick/physics_tick dispatch
- **Virtual File System** — `ModVFS` provides `mod://` protocol for cross-mod resource access and overrides
- **Two-Phase World Unload** — Phase 1 saves data; Phase 2 cleans memory only
- **Hash Verification** — TOFU (Trust On First Use) model with SHA256 manifest verification for release mods
- **Two-Level Persistence** — Global config/data and world-scoped config/data, automatically isolated by mod_id and world_id
- **SemVer Dependency Resolution** — Mods declare version ranges; the loader resolves and orders them

### Developer Experience
- **Dev Mode** — Set `MOD_DEV_MODE = true` to load mods directly from `res://mods/`
- **Release Mode** — Mods packaged as `.zip` with `manifest.json`, deployed to runtime directories
- **Packaging Tool** — `tools/pack_mod.py` generates manifests and zips
- **Debug Overlay & Console** — In-editor debug tools
- **Structured Logging** — Tiered logging with mod source tagging, crash log auto-open

## Architecture & Tech Stack

### Technology Stack

| Component | Technology |
|-----------|----------|
| Game Engine | Godot 4.6.3 |
| Renderer | Mobile |
| Mod Packaging | Python 3.8+ |
| Version Scheme | Semantic Versioning |

### Core Modules (10)

| Module | Responsibility |
|--------|---------------|
| **Bootstrap** | Engine entry point; instantiates all services in explicit order; drives tick dispatch |
| **ModLoaderCore** | Mod scanning, dependency resolution, load ordering, load/unload scheduling |
| **EventBus** | Event registration/subscription/dispatch with dedicated fast channels |
| **ModVFS** | `ResourceFormatLoader` on `mod://` protocol; multi-mod resource access/overrides |
| **HashVerifier** | SHA256 whitelist verification (TOFU model) for release-mode mod integrity |
| **StateManager** | Tracks game state (Starting → Main Menu → World Loading → World Running) |
| **PersistenceService** | Read/write isolation of global and world-scoped config/data |
| **Logger** | Tiered logging with mod source tagging and crash log auto-open |
| **RegistrySystem** | Manages block/item/entity/recipe registries |
| **ModAPI** | Unified facade exposed to mods — delegates to 8 sub-APIs |

### ModAPI Sub-APIs

| API | Purpose |
|-----|---------|
| `DevAPI` | Development mode detection, debug features |
| `EventAPI` | Subscribe/emit events, register tick callbacks |
| `LoggerAPI` | Tiered logging scoped to the mod |
| `PersistenceAPI` | Save/load config and runtime data (global or world-scoped) |
| `RegistryAPI` | Register blocks, items, entities, recipes |
| `ResourceAPI` | Load resources via `mod://` protocol |
| `VFSAPI` | Virtual file system access |
| `WorldAPI` | Query world state, seed, current world ID |

### Mod Lifecycle

**Global Mod:**
```
_init_mod(api) → _on_bootstrap() → _on_post_bootstrap()
    → [WORLD_LOAD_COMPLETE] → [WORLD_UNLOAD_COMPLETE] → _on_shutdown()
```

**World Mod:**
```
_init_mod(api) → _on_world_load(world_id) → _on_world_enter(world_id)
    → _on_world_leave(world_id)  ★ last chance to save
    → _on_world_unload(world_id)  cleanup only
```

## Environment Requirements

### Required

- **Godot Engine 4.6.3** — exact version match required

### For Mod Packaging

- **Python 3.8+** — only standard library used

### Supported Platforms

- macOS
- Windows
- Linux
- Android
- iOS

## Installation

### Option A: From Source

```bash
# Clone the repository
git clone https://github.com/SeanHank/AtomZero.git atom-zero
cd atom-zero

# Open in Godot 4.6.3
# File → Open Project → select project.godot
```

### Option B: Pre-built Release

1. Download the latest release archive for your platform
2. Extract to any directory
3. Run:
   - **macOS**: Double-click `AtomZero.app` or run `AtomZero.command`
   - **Windows/Linux**: Run the executable

> The base game ships with no gameplay. You must install mods (see [Usage Guide](#usage-guide)).

## Usage Guide

### Development Mode

1. **Enable dev mode** — Open `core/bootstrap/Bootstrap.gd` and set:
   ```gdscript
   const MOD_DEV_MODE: bool = true
   ```

2. **Place Global Mods** in `mods/`:
   ```
   mods/
   └── your_mod/
       ├── mod.json
       └── mod.gd
   ```

3. **Place World Mods** in the world's save directory:
   ```
   saves/<world_id>/mods/
   └── your_world_mod/
       ├── mod.json
       └── mod.gd
   ```

4. **Run the project** — Run in the Godot editor. Mods are loaded directly from source.

### Release Mode

1. **Keep dev mode off**:
   ```gdscript
   const MOD_DEV_MODE: bool = false
   ```

2. **Package mods** using the packaging tool:
   ```bash
   python3 tools/pack_mod.py mods/your_mod dist
   ```

3. **Deploy** the generated `.zip` files:
   - Global Mods → `<game_root>/mods/your_mod-x.y.z.zip`
   - World Mods → `<game_root>/saves/<world_id>/mods/your_mod-x.y.z.zip`

4. **Run** the exported game. Mods are extracted from zips and loaded at runtime.

## Project Structure

```
atom-zero/
├── core/                           # Engine kernel (do not modify)
│   ├── api/                        # ModAPI facade + 8 sub-APIs
│   ├── bootstrap/                  # Bootstrap.gd (sole autoload)
│   ├── debug/                      # DebugConsole, DebugOverlay
│   ├── event/                      # EventBus, GameEvents
│   ├── loader/                     # ModLoaderCore, DependencyResolver, SemVer
│   ├── logging/                    # Logger (AtomLogger)
│   ├── main/                       # Main.gd, Main.tscn (empty main scene)
│   ├── persistence/                # PersistenceService
│   ├── registry/                   # RegistrySystem
│   ├── security/                   # HashVerifier (TOFU model)
│   ├── state/                      # StateManager, GameState
│   └── vfs/                        # ModVFS, ModResourceFormatLoader
│
├── tools/
│   └── pack_mod.py                 # Mod packaging tool (Python 3)
│
├── doc/                            # Design & development docs
│   └── Mod_Development_Guide.md
│
├── project.godot                   # Godot project configuration
└── icon.svg                        # Project icon
```

## Creating Your Own Mod

See [Mod Development Guide](doc/Mod_Development_Guide.md) for details. 

## Contributing

Contributions are welcomed! This project follows a standard fork-and-PR workflow.

### Getting Started

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/<your-username>/atom-zero.git`
3. **Create a branch**: `git checkout -b feature/my-feature`
4. **Make changes** following the guidelines below
5. **Commit** with clear messages
6. **Open a Pull Request**

### Guidelines

- **Never modify `core/`** — The engine kernel is intentionally read-only. All gameplay belongs in mods.
- **Follow GDScript style** — Use tabs for indentation, follow [Godot's GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- **No `class_name` in mod scripts** — Use `preload()` with relative paths instead
- **Test in both modes** — Verify your mod works in dev mode (`MOD_DEV_MODE = true`) and release mode
- **Document public APIs** — Add comments for non-obvious logic
- **Version your mods** — Follow [Semantic Versioning](https://semver.org/)

### Reporting Issues

- Use the GitHub issue tracker
- Include: Godot version, OS, mod list, error logs (from `logs/`)
- Provide reproduction steps

## License

This project is licensed under the **GNU Affero General Public License v3.0** (AGPLv3).  

Copyright © 2026 AtomLife Studio.

See: [LICENSE](LICENSE)

### Disclaimer

See: [DISCLAIMER.md](DISCLAIMER.md)

> **Note on mods**: Individual mods may declare their own license in their `mod.json` file. The AGPLv3 license applies to the AtomZero engine kernel (`core/`) and project infrastructure. Mod authors are free to choose their own licenses for their mods.

## Contact

- **GitHub Issues**: [Report bugs and request features](https://github.com/SeanHank/AtomZero/issues)
- **GitHub Discussions**: [Ask questions and share mods](https://github.com/SeanHank/AtomZero/discussions)
- **Email**: `xiaohanaus@gmail.com`

For security-related reports, please email directly rather than opening a public issue.

## Acknowledgments

- **[Godot Engine](https://godotengine.org)** — The incredible open-source game engine that powers AtomZero
- All contributors who help build and improve the AtomZero framework
