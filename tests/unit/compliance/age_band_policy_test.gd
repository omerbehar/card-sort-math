extends GdUnitTestSuite
## Unit tests — the pure neutral-age-gate policy (S6-001, ADR-0005).
## `ComplianceService.age_band_for_birth_year(birth_year, current_year)` maps a self-declared
## birth year to an AgeBand at the 13+ threshold. Deterministic; a fixed reference year is used.

const COMPLIANCE := preload("res://autoloads/compliance_service.gd")
const NOW := 2026   # fixed reference year (deterministic; no system clock)


func test_exactly_thirteen_is_adult() -> void:
	# Boundary: turns 13 this year → ADULT (the threshold value is the point).
	assert_int(COMPLIANCE.age_band_for_birth_year(NOW - 13, NOW)).is_equal(SaveData.AgeBand.ADULT)


func test_twelve_is_child() -> void:
	# Boundary: one below the threshold → CHILD.
	assert_int(COMPLIANCE.age_band_for_birth_year(NOW - 12, NOW)).is_equal(SaveData.AgeBand.CHILD)


func test_clear_adult() -> void:
	assert_int(COMPLIANCE.age_band_for_birth_year(NOW - 30, NOW)).is_equal(SaveData.AgeBand.ADULT)


func test_young_child() -> void:
	assert_int(COMPLIANCE.age_band_for_birth_year(NOW - 5, NOW)).is_equal(SaveData.AgeBand.CHILD)


func test_born_this_year_is_child() -> void:
	assert_int(COMPLIANCE.age_band_for_birth_year(NOW, NOW)).is_equal(SaveData.AgeBand.CHILD)


func test_policy_never_returns_unknown() -> void:
	# A submitted year always resolves to a concrete band (ADULT or CHILD).
	for offset in [0, 5, 12, 13, 14, 40, 99]:
		var band: int = COMPLIANCE.age_band_for_birth_year(NOW - offset, NOW)
		assert_bool(band == SaveData.AgeBand.ADULT or band == SaveData.AgeBand.CHILD).is_true()
