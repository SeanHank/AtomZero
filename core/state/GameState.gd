# AtomZero status codes and game state enum
# Design doc appendix C and §5.3.1

# Mod status codes (design doc appendix C)
class_name GameState
extends RefCounted

const OK := "OK"
const LOAD_FAILED := "LOAD_FAILED"
const INVALID_VERSION := "INVALID_VERSION"
const MISSING_DEP := "MISSING_DEP"
const CIRCULAR_DEP := "CIRCULAR_DEP"
const HASH_MISMATCH := "HASH_MISMATCH"
const UNTRUSTED := "UNTRUSTED"

# State machine states (design doc §5.3.1)
enum State {
	BOOTSTRAP,        # Bootstrapping
	MAIN_MENU,        # Main menu
	WORLD_LOADING,    # World loading
	WORLD_RUNNING,    # World running
	WORLD_UNLOADING,  # World unloading
	CRASH             # Crash
}

# State name mapping (for log and debug display)
static func state_name(state: int) -> String:
	match state:
		State.BOOTSTRAP: return "BOOTSTRAP"
		State.MAIN_MENU: return "MAIN_MENU"
		State.WORLD_LOADING: return "WORLD_LOADING"
		State.WORLD_RUNNING: return "WORLD_RUNNING"
		State.WORLD_UNLOADING: return "WORLD_UNLOADING"
		State.CRASH: return "CRASH"
		_: return "UNKNOWN"
