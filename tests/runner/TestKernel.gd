# Shared wiring helpers for functional tests (NOT a test case itself).
# Lives under tests/runner/ so it is never instrumented or auto-discovered.
class_name TestKernel
extends RefCounted

# Build a fully-wired, isolated core service stack rooted at `root`
# (an absolute path to a writable dir, e.g. res://.test_tmp/kernel_<x>/).
# Returns {logger, hash, event, vfs, persistence, registry, sm, api, loader, root}.
static func make_stack(root: String) -> Dictionary:
	var logger := AtomLogger.new()
	logger.init(root + "logs/", null)
	var hash := HashVerifier.new()
	hash.init(logger, root)
	var event := EventBus.new()
	event.init(logger)
	var vfs := ModVFS.new()
	vfs.init(logger)
	var persistence := PersistenceService.new()
	persistence.init(logger, root)
	var registry := RegistrySystem.new()
	registry.init(logger)
	var loader := ModLoaderCore.new()
	loader.init(logger, hash, event, vfs, persistence, registry)
	var sm := StateManager.new()
	sm.init(logger, event)
	var api := ModAPI.new()
	api.init(logger, event, vfs, persistence, registry, sm, loader)
	return {
		"logger": logger,
		"hash": hash,
		"event": event,
		"vfs": vfs,
		"persistence": persistence,
		"registry": registry,
		"sm": sm,
		"api": api,
		"loader": loader,
		"root": root,
	}


# Recursively copy a directory's contents into dst (FileAccess byte copy).
# Both src and dst must be absolute paths that already exist (dst is created).
static func copy_dir_into(src_abs: String, dst_abs: String) -> void:
	if not DirAccess.dir_exists_absolute(src_abs):
		return
	var src := ProjectSettings.globalize_path(src_abs)
	var dst := ProjectSettings.globalize_path(dst_abs)
	_do_copy(src, dst)


static func _do_copy(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var dir := DirAccess.open(src)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == ".." or name.begins_with(".gd.tmp"):
			name = dir.get_next()
			continue
		var full_src := src + "/" + name
		if dir.current_is_dir():
			_do_copy(full_src, dst + "/" + name)
		else:
			var f := FileAccess.open(full_src, FileAccess.READ)
			if f != null:
				var out := FileAccess.open(dst + "/" + name, FileAccess.WRITE)
				if out != null:
					out.store_buffer(f.get_buffer(f.get_length()))
					out.close()
				f.close()
		name = dir.get_next()
	dir.list_dir_end()


# Recursively remove a directory tree (works on any absolute path).
static func remove_tree_abs(path_abs: String) -> void:
	if not DirAccess.dir_exists_absolute(path_abs):
		return
	var abs := ProjectSettings.globalize_path(path_abs)
	_recursive_delete(abs)


static func _recursive_delete(dir_abs: String) -> void:
	var dir := DirAccess.open(dir_abs)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full := dir_abs + "/" + name
		if dir.current_is_dir():
			_recursive_delete(full)
			DirAccess.remove_absolute(full)
		else:
			DirAccess.remove_absolute(full)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_abs)