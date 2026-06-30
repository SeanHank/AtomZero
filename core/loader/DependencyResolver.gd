# AtomZero Dependency Resolver
# Design doc §4.4 Dependency handling mechanism
#
# Algorithm (§4.4.2): Topological sort based on Kahn's algorithm
#   1. Verify game_version (Alpha/Beta skips, release does SemVer match)
#   2. Verify all dependencies exist and versions are satisfied; otherwise mark LOAD_FAILED
#   3. Build the directed graph: load_after and dependencies form edges A -> B (A before B)
#   4. Detect cycles: if a cycle exists, all involved Mods are marked LOAD_FAILED
#   5. Same-level nodes are sorted by load_order.priority ascending
#   6. Output the final load order list
class_name DependencyResolver
extends RefCounted

const CURRENT_GAME_VERSION: String = "2026.6.30"

var _logger: AtomLogger = null


func init(logger: AtomLogger) -> void:
	_logger = logger


# Check game_version compatibility (§4.4.1)
# Alpha/Beta versions skip the check; release versions do SemVer range matching
func check_game_version(mod_game_version: String, current_game_version: String = CURRENT_GAME_VERSION) -> bool:
	if current_game_version.begins_with("Alpha") or current_game_version.begins_with("Beta"):
		return true
	return SemVer.satisfies(current_game_version, mod_game_version)


# Resolve dependencies and sort
# descriptors: candidate Mod list
# Returns: { resolved: Array[ModDescriptor], failed: Array[{descriptor, reason}] }
func resolve(descriptors: Array) -> Dictionary:
	var result := {
		"resolved": [],
		"failed": []
	}

	# 1. Verify game_version
	var candidates: Array[ModDescriptor] = []
	for d in descriptors:
		var desc: ModDescriptor = d
		if not desc.valid:
			desc.status = GameState.LOAD_FAILED
			result["failed"].append({"descriptor": desc, "reason": "INVALID_META: %s" % desc.error_msg})
			continue
		if not check_game_version(desc.game_version, CURRENT_GAME_VERSION):
			desc.status = GameState.INVALID_VERSION
			result["failed"].append({"descriptor": desc, "reason": "INVALID_VERSION: game_version=%s does not include %s" % [desc.game_version, CURRENT_GAME_VERSION]})
			if _logger:
				_logger.error("DependencyResolver", "Mod %s's game_version '%s' does not match the current version %s" % [desc.mod_id, desc.game_version, CURRENT_GAME_VERSION])
			continue
		candidates.append(desc)

	# 2. Build mod_id -> descriptor mapping
	var by_id: Dictionary = {}
	for desc in candidates:
		by_id[desc.mod_id] = desc

	# 3. Verify hard dependencies (missing or version not satisfied -> MISSING_DEP)
	var valid_candidates: Array[ModDescriptor] = []
	for desc in candidates:
		var dep_ok := true
		for dep in desc.dependencies:
			var dep_id: String = dep.get("id", "")
			var dep_ver: String = dep.get("version", "*")
			if not by_id.has(dep_id):
				desc.status = GameState.MISSING_DEP
				result["failed"].append({"descriptor": desc, "reason": "MISSING_DEP: %s" % dep_id})
				if _logger:
					_logger.warn("DependencyResolver", "Mod %s is missing hard dependency %s" % [desc.mod_id, dep_id])
				dep_ok = false
				break
			var dep_desc: ModDescriptor = by_id[dep_id]
			if not SemVer.satisfies(dep_desc.version, dep_ver):
				desc.status = GameState.MISSING_DEP
				result["failed"].append({"descriptor": desc, "reason": "MISSING_DEP: %s v%s does not satisfy %s" % [dep_id, dep_desc.version, dep_ver]})
				if _logger:
					_logger.warn("DependencyResolver", "Mod %s's dependency %s v%s does not satisfy constraint %s" % [desc.mod_id, dep_id, dep_desc.version, dep_ver])
				dep_ok = false
				break
		if dep_ok:
			valid_candidates.append(desc)

	# 4. Build dependency graph: A -> B means A must load before B
	#    - dependencies: depended-on before depender (depended-on -> depender)
	#    - load_after: declarer must load after the specified Mod (specified Mod -> declarer)
	#    - load_before: declarer must load before the specified Mod (declarer -> specified Mod)
	var graph: Dictionary = {}  # mod_id -> Array[mod_id] (successors)
	var in_degree: Dictionary = {}  # mod_id -> int
	for desc in valid_candidates:
		graph[desc.mod_id] = []
		in_degree[desc.mod_id] = 0

	for desc in valid_candidates:
		# dependencies: depended-on -> current Mod
		for dep in desc.dependencies:
			var dep_id: String = dep.get("id", "")
			if graph.has(dep_id) and graph.has(desc.mod_id):
				if not graph[dep_id].has(desc.mod_id):
					graph[dep_id].append(desc.mod_id)
					in_degree[desc.mod_id] += 1
		# load_after: specified Mod -> current Mod
		for before_id in desc.load_after:
			if graph.has(before_id) and graph.has(desc.mod_id):
				if not graph[before_id].has(desc.mod_id):
					graph[before_id].append(desc.mod_id)
					in_degree[desc.mod_id] += 1
		# load_before: current Mod -> specified Mod
		for after_id in desc.load_before:
			if graph.has(desc.mod_id) and graph.has(after_id):
				if not graph[desc.mod_id].has(after_id):
					graph[desc.mod_id].append(after_id)
					in_degree[after_id] += 1

	# 5. Kahn's algorithm topological sort (same level sorted by priority ascending)
	var resolved_list: Array[ModDescriptor] = []
	var queue: Array[ModDescriptor] = []
	# Initialize: nodes with in-degree 0 are enqueued
	for desc in valid_candidates:
		if in_degree[desc.mod_id] == 0:
			queue.append(desc)
	# Sort the initial queue by priority ascending
	queue.sort_custom(func(a, b): return a.load_priority < b.load_priority)

	var processed_count := 0
	while not queue.is_empty():
		# Pop the one with the smallest priority (already sorted, take the first)
		var current: ModDescriptor = queue.pop_front()
		resolved_list.append(current)
		processed_count += 1
		# Remove all out-edges of this node
		var successors: Array = graph[current.mod_id]
		var new_zero_degree: Array[ModDescriptor] = []
		for succ_id in successors:
			in_degree[succ_id] -= 1
			if in_degree[succ_id] == 0:
				var succ_desc: ModDescriptor = by_id[succ_id]
				new_zero_degree.append(succ_desc)
		# Newly in-degree-0 nodes are sorted by priority and added to the queue
		new_zero_degree.sort_custom(func(a, b): return a.load_priority < b.load_priority)
		# Insert into the queue and keep sorted by priority (simplified: just append then sort the whole)
		for d in new_zero_degree:
			queue.append(d)
		queue.sort_custom(func(a, b): return a.load_priority < b.load_priority)

	# 6. Detect cycles: if processed_count < candidate count, a cycle exists
	if processed_count < valid_candidates.size():
		# Find Mods in the cycle (in-degree > 0)
		var in_cycle: Array[String] = []
		for desc in valid_candidates:
			if in_degree[desc.mod_id] > 0:
				in_cycle.append(desc.mod_id)
				desc.status = GameState.CIRCULAR_DEP
				result["failed"].append({"descriptor": desc, "reason": "CIRCULAR_DEP"})
		if _logger:
			_logger.error("DependencyResolver", "Circular dependency detected: %s" % ", ".join(in_cycle))

	result["resolved"] = resolved_list
	return result
