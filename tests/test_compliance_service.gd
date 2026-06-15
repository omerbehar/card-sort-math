extends GdUnitTestSuite
## Tests for [ComplianceService] — the ADR-0005 age-gate + ADR-0013 consent chokepoint.
##
## These verify the load-bearing invariants:
## 1. UNKNOWN and CHILD are BOTH restricted; only ADULT is ever permissive.
## 2. Even a declared ADULT requires the relevant consent for each verdict.
## The permissive verdict is the conjunction: is_adult() AND <consent granted>.
##
## This is the real chokepoint, not an abstract enum comparison — AdService / IAPService /
## Analytics call these methods and inherit the correct behaviour for free.

const COMPLIANCE_SCRIPT := preload("res://autoloads/compliance_service.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")


# Builds a ComplianceService backed by an in-memory SaveService at the given band,
# with all consent fields set to denied (conservative default). Use _make_service_with_consent
# when a test needs to grant consent alongside the age band.
func _make_service(band: SaveData.AgeBand):
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = band
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	svc.configure(save)
	return svc


# Builds a ComplianceService with the given age band AND explicit consent flags.
func _make_service_with_consent(band: SaveData.AgeBand,
		personalized_ads: bool, analytics: bool, iap: bool):
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = band
	save.data.consent_personalized_ads = personalized_ads
	save.data.consent_analytics = analytics
	save.data.consent_iap = iap
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	svc.configure(save)
	return svc


func test_unknown_is_restricted_treated_as_child() -> void:
	# AG-08: the core invariant. UNKNOWN must NOT be permissive — even with all
	# consent flags granted, UNKNOWN is restricted (is_adult() gates everything).
	var svc = _make_service_with_consent(SaveData.AgeBand.UNKNOWN, true, true, true)
	assert_bool(svc.is_adult()).is_false()
	assert_bool(svc.is_restricted()).is_true()
	assert_bool(svc.can_collect_personal_data()).is_false()
	assert_bool(svc.can_show_targeted_ads()).is_false()
	assert_bool(svc.can_use_advertising_id()).is_false()
	assert_bool(svc.can_process_iap()).is_false()


func test_child_is_restricted() -> void:
	# Even with consent granted, CHILD is always restricted.
	var svc = _make_service_with_consent(SaveData.AgeBand.CHILD, true, true, true)
	assert_bool(svc.is_adult()).is_false()
	assert_bool(svc.is_restricted()).is_true()
	assert_bool(svc.can_collect_personal_data()).is_false()
	assert_bool(svc.can_show_targeted_ads()).is_false()
	assert_bool(svc.can_process_iap()).is_false()


func test_unknown_and_child_yield_identical_verdicts() -> void:
	# AG-08: UNKNOWN must be indistinguishable from CHILD at every gate — this is
	# exactly the case a `== CHILD` guard would leak.
	# Both UNKNOWN and CHILD are non-adult → all consent-conjunctive verdicts are false
	# regardless of consent state, so they always agree.
	var unknown = _make_service_with_consent(SaveData.AgeBand.UNKNOWN, true, true, true)
	var child = _make_service_with_consent(SaveData.AgeBand.CHILD, true, true, true)
	assert_bool(unknown.can_collect_personal_data()).is_equal(child.can_collect_personal_data())
	assert_bool(unknown.can_show_targeted_ads()).is_equal(child.can_show_targeted_ads())
	assert_bool(unknown.can_use_advertising_id()).is_equal(child.can_use_advertising_id())
	assert_bool(unknown.can_process_iap()).is_equal(child.can_process_iap())
	assert_bool(unknown.is_restricted()).is_equal(child.is_restricted())


func test_adult_with_all_consent_granted_is_permissive() -> void:
	# ADR-0013 §2: ADULT + all consent granted → all verdicts permissive.
	var svc = _make_service_with_consent(SaveData.AgeBand.ADULT, true, true, true)
	assert_bool(svc.is_adult()).is_true()
	assert_bool(svc.is_restricted()).is_false()
	assert_bool(svc.can_collect_personal_data()).is_true()
	assert_bool(svc.can_show_targeted_ads()).is_true()
	assert_bool(svc.can_use_advertising_id()).is_true()
	assert_bool(svc.can_process_iap()).is_true()


func test_adult_without_consent_is_restricted_per_capability() -> void:
	# ADR-0013 §2: ADULT with all consent denied → all capability verdicts restricted.
	# is_adult() / is_restricted() are age-only; the capability gates add consent.
	var svc = _make_service(SaveData.AgeBand.ADULT)  # all consent defaults to false
	assert_bool(svc.is_adult()).is_true()
	assert_bool(svc.is_restricted()).is_false()  # age-only verdict: adult is not restricted
	assert_bool(svc.can_collect_personal_data()).is_false()
	assert_bool(svc.can_show_targeted_ads()).is_false()
	assert_bool(svc.can_use_advertising_id()).is_false()
	assert_bool(svc.can_process_iap()).is_false()
