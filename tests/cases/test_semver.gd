extends "res://tests/runner/TestCase.gd"


func test_parse_basic() -> void:
	var v: Dictionary = SemVer.parse("1.2.3")
	assert_eq(v.major, 1)
	assert_eq(v.minor, 2)
	assert_eq(v.patch, 3)
	assert_eq(v.prerelease, "")
	assert_true(v.valid)


func test_parse_v_prefix_and_whitespace() -> void:
	var v: Dictionary = SemVer.parse("  v10.20.30  ")
	assert_eq(v.major, 10)
	assert_eq(v.minor, 20)
	assert_eq(v.patch, 30)


func test_parse_prerelease_and_build() -> void:
	var v: Dictionary = SemVer.parse("1.2.3-beta.1+build42")
	assert_eq(v.major, 1)
	assert_eq(v.minor, 2)
	assert_eq(v.patch, 3)
	assert_eq(v.prerelease, "beta.1")


func test_parse_short_and_empty() -> void:
	var v: Dictionary = SemVer.parse("2.5")
	assert_eq(v.major, 2)
	assert_eq(v.minor, 5)
	assert_eq(v.patch, 0)
	assert_true(v.valid)
	var empty: Dictionary = SemVer.parse("")
	assert_eq(empty.major, 0)
	assert_false(empty.valid)


func test_parse_non_numeric_coerced() -> void:
	var v: Dictionary = SemVer.parse("1.x.3")
	# leading digits become the major: "1" then non-digit stops -> 1
	assert_eq(v.major, 1)
	assert_true(v.valid)


func test_parse_major_only() -> void:
	var v: Dictionary = SemVer.parse("0")
	assert_eq(v.major, 0)
	assert_true(v.valid)


func test_compare_equal() -> void:
	assert_eq(SemVer.compare("1.2.3", "1.2.3"), 0)
	assert_eq(SemVer.compare("1.2.3", "v1.2.3"), 0)


func test_compare_ordering() -> void:
	assert_eq(SemVer.compare("1.2.3", "1.2.4"), -1)
	assert_eq(SemVer.compare("1.2.4", "1.2.3"), 1)
	assert_eq(SemVer.compare("1.2.3", "1.3.0"), -1)
	assert_eq(SemVer.compare("2.0.0", "1.9.9"), 1)


func test_compare_prerelease_behavior() -> void:
	assert_eq(SemVer.compare("1.0.0", "1.0.0-beta"), 1)
	assert_eq(SemVer.compare("1.0.0-beta", "1.0.0"), -1)
	assert_eq(SemVer.compare("1.0.0-beta", "1.0.0-alpha"), 1)
	assert_eq(SemVer.compare("1.0.0-alpha", "1.0.0-beta"), -1)
	assert_eq(SemVer.compare("1.0.0-alpha", "1.0.0-alpha"), 0)


func test_satisfies_any() -> void:
	assert_true(SemVer.satisfies("1.2.3", "*"))
	assert_true(SemVer.satisfies("1.2.3", ""))
	assert_true(SemVer.satisfies("anything", "*"))


func test_satisfies_comma_and() -> void:
	assert_true(SemVer.satisfies("1.5.0", ">=1.0.0,<2.0.0"))
	assert_false(SemVer.satisfies("2.5.0", ">=1.0.0,<2.0.0"))
	assert_false(SemVer.satisfies("0.5.0", ">=1.0.0,<2.0.0"))


func test_satisfies_caret() -> void:
	assert_true(SemVer.satisfies("1.5.0", "^1.2.3"))
	assert_false(SemVer.satisfies("2.0.0", "^1.2.3"))
	assert_false(SemVer.satisfies("1.0.0", "^1.2.3"))
	assert_true(SemVer.satisfies("1.2.3", "^1.2.3"))


func test_satisfies_tilde() -> void:
	assert_true(SemVer.satisfies("1.2.9", "~1.2.3"))
	assert_false(SemVer.satisfies("1.3.0", "~1.2.3"))
	assert_false(SemVer.satisfies("1.2.2", "~1.2.3"))


func test_satisfies_operators() -> void:
	assert_true(SemVer.satisfies("2.0.0", ">=1.0.0"))
	assert_false(SemVer.satisfies("0.9.0", ">=1.0.0"))
	assert_true(SemVer.satisfies("2.0.0", ">1.0.0"))
	assert_false(SemVer.satisfies("1.0.0", ">1.0.0"))
	assert_true(SemVer.satisfies("1.0.0", "<=1.0.0"))
	assert_false(SemVer.satisfies("1.1.0", "<=1.0.0"))
	assert_true(SemVer.satisfies("0.5.0", "<1.0.0"))
	assert_false(SemVer.satisfies("1.0.0", "<1.0.0"))
	assert_true(SemVer.satisfies("1.2.3", "==1.2.3"))
	assert_true(SemVer.satisfies("1.2.3", "=1.2.3"))
	assert_false(SemVer.satisfies("1.2.4", "==1.2.3"))


func test_satisfies_exact() -> void:
	assert_true(SemVer.satisfies("3.2.1", "3.2.1"))
	assert_false(SemVer.satisfies("3.2.1", "3.2.2"))


func test_satisfies_invalid_target() -> void:
	assert_false(SemVer.satisfies("1.0.0", "^not-a-version"))
	assert_false(SemVer.satisfies("1.0.0", "~not-a-version"))


func test_to_int_safe() -> void:
	assert_eq(SemVer._to_int_safe("007"), 7)
	assert_eq(SemVer._to_int_safe("12abc"), 12)
	assert_eq(SemVer._to_int_safe("abc"), 0)
	assert_eq(SemVer._to_int_safe(""), 0)


func test_is_alpha_beta() -> void:
	assert_true(SemVer.is_alpha_beta("Alpha 0.1.0"))
	assert_true(SemVer.is_alpha_beta("Beta"))
	assert_false(SemVer.is_alpha_beta("2026.9.0"))
	assert_false(SemVer.is_alpha_beta("1.0.0-alpha"))