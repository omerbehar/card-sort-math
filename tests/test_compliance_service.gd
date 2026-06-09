extends GdUnitTestSuite
## Tests for [ComplianceService] — the ADR-0005 age-gate chokepoint (S1-001 / S1-003).
##
## These verify the load-bearing invariant: UNKNOWN and CHILD are BOTH restricted;
## only a declared ADULT is permissive. This is the real chokepoint, not an abstract
## enum comparison — a future AdService/Analytics calls these methods and inherits
## the correct UNKNOWN=CHILD behaviour for free.

const COMPLIANCE_SCRIPT := preload("res://autoloads/compliance_service.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")


# Builds a ComplianceService backed by an in-memory SaveService at the given band.
func _make_service(band: SaveData.AgeBand):
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = band
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	svc.configure(save)
	return svc


func test_unknown_is_restricted_treated_as_child() -> void:
	# AG-08: the core invariant. UNKNOWN must NOT be permissive.
	var svc = _make_service(SaveData.AgeBand.UNKNOWN)
	assert_bool(svc.is_adult()).is_false()
	assert_bool(svc.is_restricted()).is_true()
	assert_bool(svc.can_collect_personal_data()).is_false()
	assert_bool(svc.can_show_targeted_ads()).is_false()
	assert_bool(svc.can_use_advertising_id()).is_false()


func test_child_is_restricted() -> void:
	var svc = _make_service(SaveData.AgeBand.CHILD)
	assert_bool(svc.is_adult()).is_false()
	assert_bool(svc.is_restricted()).is_true()
	assert_bool(svc.can_collect_personal_data()).is_false()
	assert_bool(svc.can_show_targeted_ads()).is_false()


func test_unknown_and_child_yield_identical_verdicts() -> void:
	# AG-08: UNKNOWN must be indistinguishable from CHILD at every gate — this is
	# exactly the case a `== CHILD` guard would leak.
	var unknown = _make_service(SaveData.AgeBand.UNKNOWN)
	var child = _make_service(SaveData.AgeBand.CHILD)
	assert_bool(unknown.can_collect_personal_data()).is_equal(child.can_collect_personal_data())
	assert_bool(unknown.can_show_targeted_ads()).is_equal(child.can_show_targeted_ads())
	assert_bool(unknown.can_use_advertising_id()).is_equal(child.can_use_advertising_id())
	assert_bool(unknown.is_restricted()).is_equal(child.is_restricted())


func test_adult_is_permissive() -> void:
	var svc = _make_service(SaveData.AgeBand.ADULT)
	assert_bool(svc.is_adult()).is_true()
	assert_bool(svc.is_restricted()).is_false()
	assert_bool(svc.can_collect_personal_data()).is_true()
	assert_bool(svc.can_show_targeted_ads()).is_true()
	assert_bool(svc.can_use_advertising_id()).is_true()
