# SemVer semantic version parsing and constraint matching
# Design doc §4.4.3 version constraint syntax
#
# Supported constraint expressions:
#   1.2.3       exact version
#   >=1.0.0     greater than or equal
#   >=1.0.0,<2.0.0  range (comma separated means AND)
#   ^1.2.3      compatible with 1.x.x, and >=1.2.3
#   ~1.2.3      compatible with 1.2.x, and >=1.2.3
#   *           any version
class_name SemVer
extends RefCounted

# Version number structure: [major, minor, patch, prerelease]
# prerelease being an empty string means a release version
static func parse(version: String) -> Dictionary:
	var v := version.strip_edges()
	# Remove possible 'v' prefix
	if v.begins_with("v"):
		v = v.substr(1)
	# Split prerelease
	var prerelease := ""
	var plus_idx := v.find("+")
	if plus_idx >= 0:
		v = v.substr(0, plus_idx)
	var dash_idx := v.find("-")
	if dash_idx >= 0:
		prerelease = v.substr(dash_idx + 1)
		v = v.substr(0, dash_idx)
	var parts := v.split(".", false)
	var major := 0
	var minor := 0
	var patch := 0
	if parts.size() >= 1:
		major = _to_int_safe(parts[0])
	if parts.size() >= 2:
		minor = _to_int_safe(parts[1])
	if parts.size() >= 3:
		patch = _to_int_safe(parts[2])
	return {
		"major": major,
		"minor": minor,
		"patch": patch,
		"prerelease": prerelease,
		"valid": parts.size() >= 1
	}


# Compare v1 and v2, returns -1 / 0 / 1
static func compare(v1: String, v2: String) -> int:
	var a := parse(v1)
	var b := parse(v2)
	if a.major != b.major:
		return -1 if a.major < b.major else 1
	if a.minor != b.minor:
		return -1 if a.minor < b.minor else 1
	if a.patch != b.patch:
		return -1 if a.patch < b.patch else 1
	# prerelease comparison: empty > non-empty (release takes precedence over prerelease)
	if a.prerelease.is_empty() and not b.prerelease.is_empty():
		return 1
	if not a.prerelease.is_empty() and b.prerelease.is_empty():
		return -1
	if a.prerelease < b.prerelease:
		return -1
	if a.prerelease > b.prerelease:
		return 1
	return 0


# Check whether version satisfies constraint
# constraint can be a comma-separated list of multiple constraints (AND)
static func satisfies(version: String, constraint: String) -> bool:
	var c := constraint.strip_edges()
	if c.is_empty() or c == "*":
		return true
	# Split comma-separated constraints
	var constraints := c.split(",", false)
	for sub in constraints:
		if not _satisfies_single(version, sub.strip_edges()):
			return false
	return true


static func _satisfies_single(version: String, constraint: String) -> bool:
	if constraint.is_empty() or constraint == "*":
		return true
	# ^ compatible version (same major, and >= specified version)
	if constraint.begins_with("^"):
		var target := constraint.substr(1)
		var t := parse(target)
		var v := parse(version)
		if not t.valid or not v.valid:
			return false
		if v.major != t.major:
			return false
		return compare(version, target) >= 0
	# ~ compatible version (same major.minor, and >= specified version)
	if constraint.begins_with("~"):
		var target := constraint.substr(1)
		var t := parse(target)
		var v := parse(version)
		if not t.valid or not v.valid:
			return false
		if v.major != t.major or v.minor != t.minor:
			return false
		return compare(version, target) >= 0
	# >= > <= < operators
	for op in [">=", ">", "<=", "<", "==", "="]:
		if constraint.begins_with(op):
			var target := constraint.substr(op.length()).strip_edges()
			var cmp := compare(version, target)
			match op:
				">=": return cmp >= 0
				">":  return cmp > 0
				"<=": return cmp <= 0
				"<":  return cmp < 0
				"==", "=": return cmp == 0
	# No operator: exact match
	return compare(version, constraint) == 0


static func _to_int_safe(s: String) -> int:
	# Remove non-digit characters
	var result := ""
	for ch in s:
		if ch >= '0' and ch <= '9':
			result += ch
		else:
			break
	if result.is_empty():
		return 0
	return result.to_int()


# Check whether a version string is an Alpha/Beta version (used to skip game_version check, §4.4.1)
static func is_alpha_beta(version: String) -> bool:
	return version.begins_with("Alpha") or version.begins_with("Beta")
