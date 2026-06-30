# AtomZero Mod Loader Core
# Design doc §1.2 and §5 loading flow design
#
# Responsibilities:
#   1. Mod scanning (mods/ and saves/<world>/mods/)
#   2. Hash verification (HashVerifier)
#   3. Dependency resolution and topological sort (DependencyResolver)
#   4. Global Mods load/unload (instantiate in order + callbacks)
#   5. World Mods load/unload (two-phase unload: full save + cleanup)
#   6. VFS mount management
#   7. Registry partition management
#   8. Dependency resolution result cache (mod_cache.json, dependency resolution only, no hash)
class_name ModLoaderCore
extends RefCounted

var _logger: AtomLogger = null
var _hash_verifier: HashVerifier = null
var _event_bus: EventBus = null
var _vfs: ModVFS = null
var _persistence: PersistenceService = null
var _registry: RegistrySystem = null
var _dependency_resolver: DependencyResolver = null
var _mod_api: ModAPI = null
var _state_manager: StateManager = null
var _writable_root: String = ""
var _initialized: bool = false
var _scene_tree: SceneTree = null  # used for await process_frame during phased loading

# Phased loading batch size (design doc §10.1.4: default 10)
const MOD_BATCH_SIZE: int = 10

# Resource extensions preloaded by the background thread (design doc §10.1.6)
const PRELOAD_EXTS: Array[String] = [
	".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tga",
	".wav", ".ogg", ".mp3", ".flac",
	".ttf", ".otf",
	".glb", ".gltf",
	".tres", ".tscn"
]

# Loaded Global Mod instances
var _global_mods: Dictionary = {}  # mod_id -> ModInstance
# Loaded World Mod instances (grouped by world)
var _world_mods: Dictionary = {}   # world_id -> { mod_id -> ModInstance }

# Parent node of all Mod instances (added to the scene tree)
var _mods_container: Node = null

# Dependency resolution cache
var _mod_cache_path: String = ""
var _mod_cache: Dictionary = {}


func init(logger: AtomLogger, hash_verifier: HashVerifier, event_bus: EventBus, vfs: ModVFS, persistence: PersistenceService, registry: RegistrySystem) -> void:
	_logger = logger
	_hash_verifier = hash_verifier
	_event_bus = event_bus
	_vfs = vfs
	_persistence = persistence
	_registry = registry
	_dependency_resolver = DependencyResolver.new()
	_dependency_resolver.init(logger)
	_initialized = true


# Set ModAPI and StateManager references (called by Bootstrap after _init_services)
func set_api_and_state(mod_api: ModAPI, state_manager: StateManager, writable_root: String) -> void:
	_mod_api = mod_api
	_state_manager = state_manager
	_writable_root = writable_root
	_mod_cache_path = writable_root + ".cache/mod_cache.json"


# Set the parent node for Mod instances
func set_mods_container(container: Node) -> void:
	_mods_container = container


# Set the SceneTree reference (used for await process_frame during phased loading)
func set_scene_tree(tree: SceneTree) -> void:
	_scene_tree = tree


# ============================================================
# Bootstrap entry (phased loading, design doc §10.1.4)
# ============================================================

# Called during the Bootstrap phase: scan and load Global Mods
# Uses await to execute in phases, rendering a frame between each phase to avoid long stalls
func bootstrap() -> void:
	if not _initialized:
		push_error("ModLoaderCore not initialized")
		return
	_logger.info("ModLoaderCore", "Bootstrap started")
	# Trigger the BootstrapStart event
	_event_bus.emit(GameEvents.BOOTSTRAP_START, {})
	# Load the dependency resolution cache
	_load_mod_cache()

	# Frame 1: scan Global Mods in order
	var descs := scan_global_mods()
	if _scene_tree != null:
		await _scene_tree.process_frame
	if descs.is_empty():
		_logger.info("ModLoaderCore", "No Global Mods to load")
		_state_manager.transition_to_main_menu()
		_event_bus.emit(GameEvents.GLOBAL_MODS_READY, {"count": 0, "failed": 0})
		return

	# Frame 2: dependency resolution and sorting (hash verification already done during scanning)
	# Try to reuse from cache first (§10.1.3): if version and dependencies are unchanged, skip topological sort
	var resolved_list: Array = []
	var failed_list: Array = []
	var cache_hit: bool = false
	if not _mod_cache.is_empty():
		var cached := _try_resolve_from_cache(descs)
		if cached["hit"]:
			resolved_list = cached["resolved"]
			cache_hit = true
			_logger.info("ModLoaderCore", "Dependency resolution cache hit, skipping topological sort (%d Mods)" % resolved_list.size())
	if not cache_hit:
		var resolved := _dependency_resolver.resolve(descs)
		resolved_list = resolved["resolved"]
		failed_list = resolved["failed"]
		if not failed_list.is_empty():
			_logger.warn("ModLoaderCore", "Dependency resolution failed for %d Mods" % failed_list.size())
	if _scene_tree != null:
		await _scene_tree.process_frame

	# Frame 3-N: instantiate Global Mods in batches (MOD_BATCH_SIZE per batch, design doc §10.1.4)
	var loaded_count := 0
	var batch_start := 0
	while batch_start < resolved_list.size():
		var batch_end := mini(batch_start + MOD_BATCH_SIZE, resolved_list.size())
		for i in range(batch_start, batch_end):
			if _load_global_mod(resolved_list[i]):
				loaded_count += 1
		batch_start = batch_end
		# Render a frame between batches
		if batch_start < resolved_list.size() and _scene_tree != null:
			await _scene_tree.process_frame

	# Frame N+1: trigger _on_post_bootstrap (after all _on_bootstrap complete)
	for mod_id in _global_mods.keys():
		var inst: ModInstance = _global_mods[mod_id]
		inst.call_if_exists("_on_post_bootstrap")
	# Cache dependency resolution results (only written on cache miss, to avoid unnecessary IO)
	if not cache_hit:
		_save_mod_cache(resolved_list)
	# State transition + trigger GlobalModsReady
	_state_manager.transition_to_main_menu()
	_event_bus.emit(GameEvents.GLOBAL_MODS_READY, {"count": loaded_count, "failed": failed_list.size()})
	_logger.info("ModLoaderCore", "Bootstrap complete, loaded %d Global Mods" % loaded_count)


# ============================================================
# Global Mods scanning
# ============================================================

# Scan the mods/ directory, read mod.json, verify hash
# Design doc §5.1, §4.3.3 (release .zip extracted to .cache/)
func scan_global_mods() -> Array[ModDescriptor]:
	var mods_dir := Bootstrap.get_global_mods_dir()
	var descs: Array[ModDescriptor] = []
	if not DirAccess.dir_exists_absolute(mods_dir):
		_logger.info("ModLoaderCore", "Global Mods directory does not exist: %s" % mods_dir)
		return descs
	var dir := DirAccess.open(mods_dir)
	if dir == null:
		_logger.error("ModLoaderCore", "Unable to open Mods directory: %s" % mods_dir)
		return descs
	# .zip extraction root directory (design doc §3.2: .cache/ is a sibling of mods/)
	var cache_root := Bootstrap.get_cache_dir()
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == ".." or name == ".cache":
			name = dir.get_next()
			continue
		if dir.dir_exists(name):
			# Loose directory (Development Mode)
			var mod_dir := "%s/%s" % [mods_dir.rstrip("/"), name]
			var meta_path := mod_dir + "/mod.json"
			if FileAccess.file_exists(meta_path):
				var desc := ModDescriptor.from_file(meta_path)
				if desc.valid:
					# Hash verification (cannot be skipped by cache, §10.1.3)
					if _hash_verifier.verify(desc.mod_id, mod_dir, desc.version):
						descs.append(desc)
					else:
						desc.status = GameState.HASH_MISMATCH
						_logger.error("ModLoaderCore", "Hash verification failed: %s" % desc.mod_id)
				else:
					_logger.error("ModLoaderCore", "Invalid mod.json: %s (%s)" % [meta_path, desc.error_msg])
		elif name.ends_with(".zip"):
			# Release .zip (design doc §4.3.3): extract to .cache/<mod_id>/ then load
			var zip_path := "%s/%s" % [mods_dir.rstrip("/"), name]
			var extract_dir := _extract_mod_zip(zip_path, cache_root)
			if not extract_dir.is_empty():
				descs.append_array(_scan_mod_dir(extract_dir, "global"))
		name = dir.get_next()
	dir.list_dir_end()
	_logger.info("ModLoaderCore", "Scanned %d valid Global Mods" % descs.size())
	return descs


# Scan an extracted Mod directory and return descriptors
# mod_type_filter: "global" or "world", empty string means no restriction
func _scan_mod_dir(mod_dir: String, mod_type_filter: String) -> Array[ModDescriptor]:
	var descs: Array[ModDescriptor] = []
	var meta_path := mod_dir + "/mod.json"
	if not FileAccess.file_exists(meta_path):
		_logger.error("ModLoaderCore", "Extracted directory has no mod.json: %s" % mod_dir)
		return descs
	var desc := ModDescriptor.from_file(meta_path)
	if not desc.valid:
		_logger.error("ModLoaderCore", "Invalid mod.json: %s (%s)" % [meta_path, desc.error_msg])
		return descs
	if not mod_type_filter.is_empty() and desc.mod_type != mod_type_filter:
		_logger.warn("ModLoaderCore", "mod_type mismatch (expected %s, got %s): %s" % [mod_type_filter, desc.mod_type, desc.mod_id])
		return descs
	if _hash_verifier.verify(desc.mod_id, mod_dir, desc.version):
		descs.append(desc)
	else:
		desc.status = GameState.HASH_MISMATCH
		_logger.error("ModLoaderCore", "Hash verification failed: %s" % desc.mod_id)
	return descs


# ============================================================
# .zip extraction (design doc §4.3.3 Release Mode)
# ============================================================

# Extract a release .zip Mod to a .cache/ subdirectory
# zip_path: .zip file path
# cache_root: extraction root directory (.cache/ or .cache/world/<world_id>/)
# Returns the extracted Mod directory path (<cache_root>/<mod_id>/), or empty string on failure
# Cache strategy (design doc §3.2): if .cache/<mod_id>/mod.json already exists and is not older than the .zip, reuse it directly
func _extract_mod_zip(zip_path: String, cache_root: String) -> String:
	var reader := ZIPReader.new()
	var err: int = reader.open(zip_path)
	if err != OK:
		_logger.error("ModLoaderCore", "Unable to open zip: %s (err=%d)" % [zip_path, err])
		return ""
	var files: PackedStringArray = reader.get_files()
	if files.is_empty():
		reader.close()
		_logger.error("ModLoaderCore", "zip is empty: %s" % zip_path)
		return ""
	# Find mod.json inside the zip (path may be mod.json or ./mod.json)
	var mod_json_zip_path := ""
	for fpath in files:
		if fpath == "mod.json" or fpath == "./mod.json":
			mod_json_zip_path = fpath
			break
	if mod_json_zip_path.is_empty():
		reader.close()
		_logger.error("ModLoaderCore", "No root-level mod.json inside zip: %s" % zip_path)
		return ""
	var mod_json_bytes: PackedByteArray = reader.read_file(mod_json_zip_path)
	var mod_meta: Variant = JSON.parse_string(mod_json_bytes.get_string_from_utf8())
	if mod_meta == null or not (mod_meta is Dictionary):
		reader.close()
		_logger.error("ModLoaderCore", "mod.json parse failed inside zip: %s" % zip_path)
		return ""
	var mod_id: String = mod_meta.get("mod_id", "")
	if mod_id.is_empty():
		reader.close()
		_logger.error("ModLoaderCore", "mod.json inside zip is missing mod_id: %s" % zip_path)
		return ""
	# Extraction target directory: <cache_root>/<mod_id>/
	var extract_dir := cache_root + "/" + mod_id
	# Cache check: if already extracted and not older than .zip, skip (design doc §3.2)
	var cached_meta := extract_dir + "/mod.json"
	if FileAccess.file_exists(cached_meta):
		var zip_mtime := FileAccess.get_modified_time(zip_path)
		var cache_mtime := FileAccess.get_modified_time(cached_meta)
		if cache_mtime >= zip_mtime:
			reader.close()
			_logger.info("ModLoaderCore", "zip already extracted and up to date, reusing cache: %s" % extract_dir)
			return extract_dir
		# .zip was updated, clean old cache then re-extract
		_remove_dir_recursive(extract_dir)
	# Ensure the extraction root directory exists
	DirAccess.make_dir_recursive_absolute(cache_root)
	var file_count: int = 0
	for path in files:
		# Skip directory entries (ending with /)
		if path.ends_with("/"):
			continue
		# Normalize path prefix (strip ./ prefix)
		var clean_path := path
		if clean_path.begins_with("./"):
			clean_path = clean_path.substr(2)
		var target := extract_dir + "/" + clean_path
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			_logger.warn("ModLoaderCore", "Unable to write extracted file: %s" % target)
			continue
		f.store_buffer(reader.read_file(path))
		f.close()
		file_count += 1
	reader.close()
	_logger.info("ModLoaderCore", "Extracted zip %s -> %s (%d files)" % [zip_path, extract_dir, file_count])
	return extract_dir


# Recursively delete a directory and its contents
func _remove_dir_recursive(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full := dir_path + "/" + name
		if dir.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


# ============================================================
# Global Mod loading
# ============================================================

# Load a single Global Mod
func _load_global_mod(desc: ModDescriptor) -> bool:
	if _global_mods.has(desc.mod_id):
		_logger.warn("ModLoaderCore", "Global Mod already loaded, skipping: %s" % desc.mod_id)
		return false
	# 1. VFS mount
	_vfs.mount_global(desc.mod_id, desc.mod_dir, desc.resource_overrides)
	# 2. Persistence service registration
	_persistence.register_global_mod(desc.mod_id, desc.version)
	# 3. Instantiate the Mod entry script
	var script_path := desc.mod_dir + "/" + desc.entry
	if not ResourceLoader.has_cached(script_path):
		if not FileAccess.file_exists(script_path):
			_logger.error("ModLoaderCore", "Mod entry script does not exist: %s" % script_path)
			_vfs.unmount_global(desc.mod_id)
			_persistence.unregister_global_mod(desc.mod_id)
			return false
	var script: Script = load(script_path)
	if script == null:
		_logger.error("ModLoaderCore", "Unable to load Mod entry script: %s" % script_path)
		_vfs.unmount_global(desc.mod_id)
		_persistence.unregister_global_mod(desc.mod_id)
		return false
	var instance: Node = script.new()
	if instance == null:
		_logger.error("ModLoaderCore", "Unable to instantiate Mod: %s" % desc.mod_id)
		_vfs.unmount_global(desc.mod_id)
		_persistence.unregister_global_mod(desc.mod_id)
		return false
	# 4. Add to the scene tree
	if _mods_container != null:
		_mods_container.add_child(instance)
	# 5. Create ModInstance and ModAPI
	var mod_api := _mod_api.create_for_mod(desc.mod_id, "global", "", 0, desc.version)
	var mod_instance := ModInstance.new(desc)
	mod_instance.set_instance(instance, mod_api)
	# 6. Call _init_mod and _on_bootstrap (design doc §5.2)
	instance.callv("_init_mod", [mod_api])
	_global_mods[desc.mod_id] = mod_instance
	# Call _on_bootstrap
	if instance.has_method("_on_bootstrap"):
		instance.callv("_on_bootstrap", [])
	# 7. Trigger the ModLoaded event
	_event_bus.emit(GameEvents.MOD_LOADED, {"mod_id": desc.mod_id, "mod_type": "global"})
	_logger.info("ModLoaderCore", "Loaded Global Mod: %s v%s" % [desc.mod_id, desc.version])
	return true


# ============================================================
# World Mods load/unload (design doc §2.5 and §5.3)
# ============================================================

# Load all World Mods for the specified world
# Coroutine: preloads resources in a background thread via await (design doc §10.1.6)
func load_world_mods(world_id: String, world_seed: int) -> void:
	_logger.info("ModLoaderCore", "Start loading World Mods for world %s" % world_id)
	# 1. State transition + trigger WorldLoadStart
	_state_manager.transition_to_world_loading(world_id, world_seed)
	_event_bus.on_world_load(world_id)
	_event_bus.emit(GameEvents.WORLD_LOAD_START, {"world_id": world_id, "seed": world_seed})
	# 2. VFS creates the world mount point (done indirectly by mount_world)
	# 3. Scan World Mods
	var descs := scan_world_mods(world_id)
	# 4. Persistence service registers world info
	for desc in descs:
		_persistence.register_world_mod(world_id, world_seed, desc.mod_id, desc.version)
	# 5. Dependency resolution and sorting
	var resolved := _dependency_resolver.resolve(descs)
	var resolved_list: Array = resolved["resolved"]
	# 6. Open registry partition
	_registry.open_world_partition(world_id)
	_world_mods[world_id] = {}
	# 7. Background thread resource preload (design doc §10.1.6)
	# The main thread only does registry writes and event subscriptions, to avoid blocking rendering
	# This step makes load_world_mods a coroutine; callers must await
	await _preload_world_mod_resources(world_id, resolved_list)
	# 8. Load World Mods in order (report progress after each load, design doc §10.1.6)
	var total: int = resolved_list.size()
	for i in range(resolved_list.size()):
		_load_world_mod(world_id, world_seed, resolved_list[i])
		# Report loading progress in real time (for UI progress bar)
		_event_bus.emit(GameEvents.WORLD_LOAD_PROGRESS, {
			"world_id": world_id,
			"loaded": i + 1,
			"total": total,
			"current_mod": resolved_list[i].mod_id
		})
	# 9. Trigger WorldLoadComplete
	_state_manager.transition_to_world_running()
	_event_bus.emit(GameEvents.WORLD_LOAD_COMPLETE, {"world_id": world_id})
	_logger.info("ModLoaderCore", "World %s loading complete, loaded %d World Mods" % [world_id, resolved_list.size()])


# ============================================================
# Background thread resource preload (design doc §10.1.6)
# ============================================================

# Preload all World Mod resource files (textures/audio/fonts/scenes etc.) in a background thread
# After preload completes, the main thread calls load() which hits the cache, avoiding blocking rendering
# Coroutine: polls background load status via await _scene_tree.process_frame
func _preload_world_mod_resources(world_id: String, resolved_list: Array) -> void:
	if _scene_tree == null:
		# Skip preload when there is no SceneTree (cannot await)
		_logger.warn("ModLoaderCore", "No SceneTree, skipping background resource preload")
		return
	# Collect resource paths that need preloading from all World Mod directories
	var paths_to_preload: Array[String] = []
	for desc in resolved_list:
		var d: ModDescriptor = desc
		_scan_resource_files(d.mod_dir, "", paths_to_preload)
	if paths_to_preload.is_empty():
		_logger.debug("ModLoaderCore", "World %s has no resources to preload" % world_id)
		return
	_logger.info("ModLoaderCore", "World %s starting background thread preload of %d resources" % [world_id, paths_to_preload.size()])
	# Issue a background load request for each resource (skip already cached)
	var pending: Dictionary = {}  # path -> whether done
	for path in paths_to_preload:
		if ResourceLoader.has_cached(path):
			# Already cached, skip (avoid duplicate loading)
			continue
		var err: int = ResourceLoader.load_threaded_request(path)
		if err == OK:
			pending[path] = false
		else:
			_logger.warn("ModLoaderCore", "Unable to issue background load request: %s (err=%d)" % [path, err])
			pending[path] = true  # mark as done to avoid infinite wait
	if pending.is_empty():
		_logger.debug("ModLoaderCore", "All resources for world %s are already cached" % world_id)
		return
	# Poll until all background loads complete (with a timeout limit, to avoid hanging)
	var progress: Array = [0.0]
	var max_poll_iters: int = 1800  # upper limit 30 seconds (~16ms per frame)
	var poll_iter: int = 0
	while poll_iter < max_poll_iters:
		var all_done: bool = true
		for path in pending.keys():
			if pending[path]:
				continue
			var status: int = ResourceLoader.load_threaded_get_status(path, progress)
			match status:
				ResourceLoader.THREAD_LOAD_LOADED:
					pending[path] = true
				ResourceLoader.THREAD_LOAD_FAILED:
					_logger.warn("ModLoaderCore", "Background load failed: %s" % path)
					pending[path] = true
				ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					_logger.warn("ModLoaderCore", "Invalid resource path (may not be imported): %s" % path)
					pending[path] = true
				ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					all_done = false
		if all_done:
			break
		await _scene_tree.process_frame
		poll_iter += 1
	if poll_iter >= max_poll_iters:
		_logger.warn("ModLoaderCore", "World %s background resource preload timed out, %d still pending" % [world_id, pending.size()])
	else:
		_logger.info("ModLoaderCore", "World %s background thread preload complete (took %d frames)" % [world_id, poll_iter])


# Recursively scan resource files in a Mod directory (only files matching PRELOAD_EXTS)
# Skips .gd/.cs scripts (loaded by the main thread) and hidden files/directories
func _scan_resource_files(base_dir: String, rel_path: String, out_paths: Array) -> void:
	var full_dir: String = base_dir if rel_path.is_empty() else (base_dir + "/" + rel_path)
	var dir := DirAccess.open(full_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		# Skip . and .. and all hidden files/directories (.godot, .git, .DS_Store, etc.)
		if name == "." or name == ".." or name.begins_with("."):
			name = dir.get_next()
			continue
		var rel: String = name if rel_path.is_empty() else (rel_path + "/" + name)
		if dir.dir_exists(name):
			# Recursively scan subdirectories
			_scan_resource_files(base_dir, rel, out_paths)
		else:
			# Only collect files matching PRELOAD_EXTS (scripts are loaded by the main thread)
			var lower: String = name.to_lower()
			for ext in PRELOAD_EXTS:
				if lower.ends_with(ext):
					out_paths.append(full_dir + "/" + name)
					break
		name = dir.get_next()
	dir.list_dir_end()


# Scan World Mods for the specified world
# Design doc §5.1, §3.2 (World Mod .zip extracted to .cache/world/<world_id>/)
func scan_world_mods(world_id: String) -> Array[ModDescriptor]:
	var descs: Array[ModDescriptor] = []
	var world_mods_dir := Bootstrap.get_world_mods_dir(world_id)
	if not DirAccess.dir_exists_absolute(world_mods_dir):
		_logger.info("ModLoaderCore", "World %s has no World Mods directory" % world_id)
		return descs
	var dir := DirAccess.open(world_mods_dir)
	if dir == null:
		return descs
	# World Mod .zip extraction root directory (design doc §3.2: .cache/world/<world_id>/<mod_id>/)
	var cache_root := Bootstrap.get_cache_dir() + "world/" + world_id
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == ".." or name == ".cache":
			name = dir.get_next()
			continue
		if dir.dir_exists(name):
			var mod_dir := "%s/%s" % [world_mods_dir.rstrip("/"), name]
			var meta_path := mod_dir + "/mod.json"
			if FileAccess.file_exists(meta_path):
				var desc := ModDescriptor.from_file(meta_path)
				if desc.valid and desc.mod_type == "world":
					if _hash_verifier.verify(desc.mod_id, mod_dir, desc.version):
						descs.append(desc)
					else:
						desc.status = GameState.HASH_MISMATCH
						_logger.error("ModLoaderCore", "World Mod hash verification failed: %s" % desc.mod_id)
		elif name.ends_with(".zip"):
			# Release .zip (design doc §4.3.3): extract to .cache/world/<world_id>/<mod_id>/
			var zip_path := "%s/%s" % [world_mods_dir.rstrip("/"), name]
			var extract_dir := _extract_mod_zip(zip_path, cache_root)
			if not extract_dir.is_empty():
				descs.append_array(_scan_mod_dir(extract_dir, "world"))
		name = dir.get_next()
	dir.list_dir_end()
	_logger.info("ModLoaderCore", "World %s scanned %d valid World Mods" % [world_id, descs.size()])
	return descs


# Load a single World Mod
func _load_world_mod(world_id: String, world_seed: int, desc: ModDescriptor) -> bool:
	if _world_mods[world_id].has(desc.mod_id):
		return false
	# 1. VFS mount
	_vfs.mount_world(world_id, desc.mod_id, desc.mod_dir, desc.resource_overrides)
	# 2. Instantiate
	var script_path := desc.mod_dir + "/" + desc.entry
	if not FileAccess.file_exists(script_path):
		_logger.error("ModLoaderCore", "World Mod entry script does not exist: %s" % script_path)
		return false
	var script: Script = load(script_path)
	if script == null:
		_logger.error("ModLoaderCore", "Unable to load World Mod script: %s" % script_path)
		return false
	var instance: Node = script.new()
	if instance == null:
		_logger.error("ModLoaderCore", "Unable to instantiate World Mod: %s" % desc.mod_id)
		return false
	if _mods_container != null:
		_mods_container.add_child(instance)
	# 3. Create ModInstance and ModAPI (World Mod context carries world_id)
	var mod_api := _mod_api.create_for_mod(desc.mod_id, "world", world_id, world_seed, desc.version)
	var mod_instance := ModInstance.new(desc)
	mod_instance.set_instance(instance, mod_api)
	# 4. Call _init_mod + _on_world_load
	instance.callv("_init_mod", [mod_api])
	_world_mods[world_id][desc.mod_id] = mod_instance
	if instance.has_method("_on_world_load"):
		instance.callv("_on_world_load", [world_id])
	# 5. Trigger _on_world_enter (player formally enters the world)
	if instance.has_method("_on_world_enter"):
		instance.callv("_on_world_enter", [world_id])
	# 6. Trigger the ModLoaded event
	_event_bus.emit(GameEvents.MOD_LOADED, {"mod_id": desc.mod_id, "mod_type": "world"})
	_logger.info("ModLoaderCore", "Loaded World Mod: %s v%s (world=%s)" % [desc.mod_id, desc.version, world_id])
	return true


# ============================================================
# World Mods unload (two-phase unload, design doc §2.5)
# ============================================================

func unload_world_mods(world_id: String) -> void:
	if not _world_mods.has(world_id):
		_logger.warn("ModLoaderCore", "World %s has no loaded World Mods" % world_id)
		return
	_logger.info("ModLoaderCore", "Start unloading World Mods for world %s (two-phase)" % world_id)
	# State transition + trigger WorldUnloadStart
	_state_manager.transition_to_world_unloading()
	_event_bus.emit(GameEvents.WORLD_UNLOAD_START, {"world_id": world_id})

	# ===== Phase 1: full save (design doc §2.5) =====
	# Before calling any unload callbacks, first iterate all World Mods to call
	# _on_world_leave() and save their runtime data
	# At this point the in-memory state is intact, so the saved data is valid
	var world_mods: Dictionary = _world_mods[world_id]
	var mod_ids := world_mods.keys()
	for mod_id in mod_ids:
		var inst: ModInstance = world_mods[mod_id]
		if inst.script_instance != null:
			if inst.script_instance.has_method("_on_world_leave"):
				inst.script_instance.callv("_on_world_leave", [world_id])

	# ===== Phase 2: unload callbacks + resource cleanup =====
	# After all data is saved, call _on_world_unload() to do memory cleanup
	# Iterate in reverse order (opposite of load order)
	mod_ids.reverse()
	for mod_id in mod_ids:
		var inst: ModInstance = world_mods[mod_id]
		if inst.script_instance != null:
			if inst.script_instance.has_method("_on_world_unload"):
				inst.script_instance.callv("_on_world_unload", [world_id])
		# Remove event subscriptions (based on mod_id registry)
		_event_bus.remove_mod_subscriptions(mod_id, world_id)
		# VFS unload
		_vfs.unmount_world(world_id, mod_id)
		# Persistence unregister
		_persistence.unregister_world_mod(world_id, mod_id)
		# Remove from the scene tree and release
		if _mods_container != null and inst.script_instance != null:
			_mods_container.remove_child(inst.script_instance)
			inst.script_instance.queue_free()
		_event_bus.emit(GameEvents.MOD_UNLOADED, {"mod_id": mod_id})
	# Release registry partition
	_registry.release_world_partition(world_id)
	# Clear event context (remove all subscriptions for this world)
	_event_bus.on_world_unload(world_id)
	# VFS clears mod://world/<world_id>/ prefix resource cache (release VRAM)
	_vfs.unmount_world_all(world_id)
	# Clean up .cache/world/<world_id>/ (design doc §3.2: cleared together with VRAM cache on world unload)
	var world_cache := Bootstrap.get_cache_dir() + "world/" + world_id
	_remove_dir_recursive(world_cache)
	# Persistence unregister the entire world
	_persistence.unregister_world(world_id)
	# Remove world Mod records
	_world_mods.erase(world_id)
	# State transition + trigger WorldUnloadComplete
	_state_manager.transition_to_main_menu_after_unload()
	_event_bus.emit(GameEvents.WORLD_UNLOAD_COMPLETE, {"world_id": world_id})
	_logger.info("ModLoaderCore", "World %s unload complete" % world_id)


# ============================================================
# Global Mod unload (called on process exit)
# ============================================================

func unload_all_global_mods() -> void:
	_logger.info("ModLoaderCore", "Start unloading all Global Mods")
	# Unload in reverse order (opposite of load order)
	var mod_ids := _global_mods.keys()
	mod_ids.reverse()
	for mod_id in mod_ids:
		var inst: ModInstance = _global_mods[mod_id]
		# Call _on_shutdown (save data)
		if inst.script_instance != null:
			if inst.script_instance.has_method("_on_shutdown"):
				inst.script_instance.callv("_on_shutdown", [])
		# Remove subscriptions
		_event_bus.remove_mod_subscriptions(mod_id, "")
		# VFS unload
		_vfs.unmount_global(mod_id)
		# Persistence unregister
		_persistence.unregister_global_mod(mod_id)
		# Remove from the scene tree
		# Note: this method is only called during the Bootstrap._exit_tree() exit phase.
		# On exit the frame loop has stopped, queue_free() will not run; use free() to release
		# immediately, otherwise detached mod nodes become orphans and leak until process end.
		if _mods_container != null and inst.script_instance != null:
			_mods_container.remove_child(inst.script_instance)
			inst.script_instance.free()
			inst.script_instance = null
		_event_bus.emit(GameEvents.MOD_UNLOADED, {"mod_id": mod_id})
	_global_mods.clear()
	# Break the circular reference with ModAPI: ModLoaderCore._mod_api <-> ModAPI._mod_loader_service
	# Both are RefCounted, reference counting cannot reclaim the cycle, on exit this would cause
	# the service objects and the scripts/sub-API resources they hold to all leak
	# ("resources still in use at exit").
	_mod_api = null
	_logger.info("ModLoaderCore", "Global Mods unload complete")


# ============================================================
# Data hot reload (Global Mod data only, §5.4)
# ============================================================

func reload_mod_data(mod_id: String) -> void:
	if not OS.is_debug_build():
		_logger.warn("ModLoaderCore", "Data hot reload is disabled in release environment")
		return
	if not _global_mods.has(mod_id):
		_logger.warn("ModLoaderCore", "Global Mod not loaded: %s" % mod_id)
		return
	_logger.info("ModLoaderCore", "Start hot reloading Mod data: %s" % mod_id)
	_event_bus.emit(GameEvents.MOD_RELOAD_START, {"mod_id": mod_id})
	var inst: ModInstance = _global_mods[mod_id]
	# Call the _on_data_reloaded callback again (Mod re-reads config/ internally)
	if inst.script_instance != null and inst.script_instance.has_method("_on_data_reloaded"):
		inst.script_instance.callv("_on_data_reloaded", [])
	_event_bus.emit(GameEvents.MOD_RELOAD_COMPLETE, {"mod_id": mod_id})
	_logger.info("ModLoaderCore", "Mod data hot reload complete: %s" % mod_id)


# ============================================================
# Debug query interface
# ============================================================

# List all loaded Mods (for console `mods list`)
func list_all_mods() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mod_id in _global_mods.keys():
		var inst: ModInstance = _global_mods[mod_id]
		result.append({
			"mod_id": mod_id,
			"name": inst.descriptor.name,
			"version": inst.descriptor.version,
			"mod_type": "global",
			"status": GameState.OK
		})
	for world_id in _world_mods.keys():
		var mods: Dictionary = _world_mods[world_id]
		for mod_id in mods.keys():
			var inst: ModInstance = mods[mod_id]
			result.append({
				"mod_id": mod_id,
				"name": inst.descriptor.name,
				"version": inst.descriptor.version,
				"mod_type": "world",
				"world_id": world_id,
				"status": GameState.OK
			})
	return result


# Get Mod details
func get_mod_info(mod_id: String) -> Dictionary:
	if _global_mods.has(mod_id):
		var inst: ModInstance = _global_mods[mod_id]
		return {
			"mod_id": mod_id,
			"name": inst.descriptor.name,
			"version": inst.descriptor.version,
			"mod_type": "global",
			"author": inst.descriptor.author,
			"description": inst.descriptor.description,
			"mod_dir": inst.descriptor.mod_dir,
			"status": inst.descriptor.status
		}
	for world_id in _world_mods.keys():
		var mods: Dictionary = _world_mods[world_id]
		if mods.has(mod_id):
			var inst: ModInstance = mods[mod_id]
			return {
				"mod_id": mod_id,
				"name": inst.descriptor.name,
				"version": inst.descriptor.version,
				"mod_type": "world",
				"world_id": world_id,
				"author": inst.descriptor.author,
				"description": inst.descriptor.description,
				"mod_dir": inst.descriptor.mod_dir,
				"status": inst.descriptor.status
			}
	return {}


# ============================================================
# Dependency resolution cache (§10.1.3)
# ============================================================

func _load_mod_cache() -> void:
	if not FileAccess.file_exists(_mod_cache_path):
		_mod_cache = {}
		return
	var text := FileAccess.get_file_as_string(_mod_cache_path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		_mod_cache = {}
		return
	_mod_cache = parsed


func _save_mod_cache(resolved_list: Array) -> void:
	var cache_data: Dictionary = {}
	for i in range(resolved_list.size()):
		var desc: ModDescriptor = resolved_list[i]
		cache_data[desc.mod_id] = {
			"version": desc.version,
			"load_order_index": i,
			"resolved_deps": desc.get_dependency_ids(),
			"cached_at": Time.get_datetime_string_from_system(false, true)
		}
	var dir_path := _mod_cache_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var tmp_path := _mod_cache_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(cache_data, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp_path, _mod_cache_path)
	_mod_cache = cache_data


# Try to reuse a dependency resolution result from cache (design doc §10.1.3)
# Only hits when all Mods' version and dependencies are unchanged
# Returns {hit: bool, resolved: Array, failed: Array}
func _try_resolve_from_cache(descs: Array[ModDescriptor]) -> Dictionary:
	var miss: Dictionary = {"hit": false, "resolved": [], "failed": []}
	if _mod_cache.is_empty():
		return miss
	if descs.size() != _mod_cache.size():
		return miss
	# Verify each Mod's version and dependencies match the cache
	var indexed_descs: Array = []  # [load_order_index, desc]
	for desc in descs:
		if not _mod_cache.has(desc.mod_id):
			return miss
		var cached: Dictionary = _mod_cache[desc.mod_id]
		# version must match
		if String(cached.get("version", "")) != desc.version:
			return miss
		# dependencies must match (compared by dependency ID set, order irrelevant)
		var cached_deps: Array = cached.get("resolved_deps", [])
		var current_deps: Array[String] = desc.get_dependency_ids()
		if not _string_arrays_equal(cached_deps, current_deps):
			return miss
		var idx: int = int(cached.get("load_order_index", -1))
		if idx < 0:
			return miss
		indexed_descs.append([idx, desc])
	# Sort ascending by load_order_index to get the load order
	indexed_descs.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var result: Array = []
	for entry in indexed_descs:
		result.append(entry[1])
	return {"hit": true, "resolved": result, "failed": []}


# Compare whether two string arrays have the same contents (set semantics, order irrelevant)
func _string_arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for s in a:
		if not b.has(s):
			return false
	return true


# ============================================================
# Custom debug panel registration (design doc §8.2.3)
# ============================================================

# List of custom debug panel nodes registered by Mods
var _custom_debug_panels: Array = []


# Register a custom debug panel (forwarded by DevAPI.register_debug_panel)
# DebugOverlay will periodically pull and attach these panels to the debug window
func register_debug_panel(panel: Node) -> void:
	if panel == null:
		return
	_custom_debug_panels.append(panel)
	if _logger != null:
		_logger.debug("ModLoaderCore", "Registered custom debug panel: %s" % (panel.name if panel != null else "<null>"))


# Get registered custom debug panels (for DebugOverlay to pull and attach)
func get_custom_debug_panels() -> Array:
	return _custom_debug_panels
