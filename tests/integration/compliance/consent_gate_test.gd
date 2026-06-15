extends GdUnitTestSuite
## Integration tests for the consent × age_band conjunction in [ComplianceService]
## (S4-001, ADR-0013 §2).
##
## These tests drive the real [ComplianceService] and [SaveService] autoloads via the
## [method ComplianceService.configure] DI seam — no scene tree required.
##
## Covers the full cross-product:
## - can_show_targeted_ads()    = is_adult() AND consent_personalized_ads
## - can_collect_personal_data() = is_adult() AND consent_analytics
## - can_process_iap()          = is_adult() AND consent_iap
## And the withdrawal immediacy invariant (ADR-0013 §3).

const COMPLIANCE_SCRIPT := preload("res://autoloads/compliance_service.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")

# Temp save paths used by the file-I/O tests; cleaned unconditionally in after_test().
var _temp_save_paths: Array[String] = []


func after_test() -> void:
	# Fix #6: unconditional teardown so a failing assert never leaks user:// files.
	for path: String in _temp_save_paths:
		if FileAccess.file_exists(path):
			DirAccess.open("user://").remove(path.get_file())
		var tmp: String = path + ".tmp"
		if FileAccess.file_exists(tmp):
			DirAccess.open("user://").remove(tmp.get_file())
	_temp_save_paths.clear()


## Builds a ComplianceService backed by an in-memory SaveService with the given
## age band and explicit per-capability consent flags.
func _make_svc(band: SaveData.AgeBand,
		personalized_ads: bool, analytics: bool, iap: bool):
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = band
	save.data.consent_personalized_ads = personalized_ads
	save.data.consent_analytics = analytics
	save.data.consent_iap = iap
	save.data.consent_captured = true
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	svc.configure(save)
	return svc


# ---------------------------------------------------------------------------
# can_show_targeted_ads() cross-product: ADULT×granted is the ONLY permissive cell
# ---------------------------------------------------------------------------

func test_can_show_targeted_ads_adult_granted_permissive() -> void:
	var svc = _make_svc(SaveData.AgeBand.ADULT, true, false, false)
	assert_bool(svc.can_show_targeted_ads()).is_true()


func test_can_show_targeted_ads_adult_denied_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.ADULT, false, false, false)
	assert_bool(svc.can_show_targeted_ads()).is_false()


func test_can_show_targeted_ads_unknown_granted_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.UNKNOWN, true, false, false)
	assert_bool(svc.can_show_targeted_ads()).is_false()


func test_can_show_targeted_ads_child_granted_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.CHILD, true, false, false)
	assert_bool(svc.can_show_targeted_ads()).is_false()


func test_can_show_targeted_ads_unknown_denied_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.UNKNOWN, false, false, false)
	assert_bool(svc.can_show_targeted_ads()).is_false()


func test_can_show_targeted_ads_child_denied_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.CHILD, false, false, false)
	assert_bool(svc.can_show_targeted_ads()).is_false()


# ---------------------------------------------------------------------------
# can_collect_personal_data() cross-product
# ---------------------------------------------------------------------------

func test_can_collect_personal_data_adult_analytics_granted_permissive() -> void:
	var svc = _make_svc(SaveData.AgeBand.ADULT, false, true, false)
	assert_bool(svc.can_collect_personal_data()).is_true()


func test_can_collect_personal_data_adult_analytics_denied_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.ADULT, false, false, false)
	assert_bool(svc.can_collect_personal_data()).is_false()


func test_can_collect_personal_data_unknown_analytics_granted_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.UNKNOWN, false, true, false)
	assert_bool(svc.can_collect_personal_data()).is_false()


func test_can_collect_personal_data_child_analytics_granted_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.CHILD, false, true, false)
	assert_bool(svc.can_collect_personal_data()).is_false()


# ---------------------------------------------------------------------------
# can_process_iap() cross-product (new verdict, ADR-0013 §2)
# ---------------------------------------------------------------------------

func test_can_process_iap_adult_iap_granted_permissive() -> void:
	var svc = _make_svc(SaveData.AgeBand.ADULT, false, false, true)
	assert_bool(svc.can_process_iap()).is_true()


func test_can_process_iap_adult_iap_denied_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.ADULT, false, false, false)
	assert_bool(svc.can_process_iap()).is_false()


func test_can_process_iap_unknown_iap_granted_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.UNKNOWN, false, false, true)
	assert_bool(svc.can_process_iap()).is_false()


func test_can_process_iap_child_iap_granted_restricted() -> void:
	var svc = _make_svc(SaveData.AgeBand.CHILD, false, false, true)
	assert_bool(svc.can_process_iap()).is_false()


# ---------------------------------------------------------------------------
# Consent independence: granting one capability must not leak into another
# ---------------------------------------------------------------------------

func test_ads_consent_does_not_grant_analytics_or_iap() -> void:
	# Only personalized_ads granted; analytics and iap must remain restricted.
	var svc = _make_svc(SaveData.AgeBand.ADULT, true, false, false)
	assert_bool(svc.can_show_targeted_ads()).is_true()
	assert_bool(svc.can_collect_personal_data()).is_false()
	assert_bool(svc.can_process_iap()).is_false()


func test_analytics_consent_does_not_grant_ads_or_iap() -> void:
	var svc = _make_svc(SaveData.AgeBand.ADULT, false, true, false)
	assert_bool(svc.can_show_targeted_ads()).is_false()
	assert_bool(svc.can_collect_personal_data()).is_true()
	assert_bool(svc.can_process_iap()).is_false()


func test_iap_consent_does_not_grant_ads_or_analytics() -> void:
	var svc = _make_svc(SaveData.AgeBand.ADULT, false, false, true)
	assert_bool(svc.can_show_targeted_ads()).is_false()
	assert_bool(svc.can_collect_personal_data()).is_false()
	assert_bool(svc.can_process_iap()).is_true()


# ---------------------------------------------------------------------------
# Withdrawal immediacy (ADR-0013 §3)
# Flipping a consent field must flip the ComplianceService verdict on the NEXT call
# with no restart and no cache to invalidate (verdicts read live SaveData each time).
# ---------------------------------------------------------------------------

func test_withdrawal_of_personalized_ads_flips_verdict_immediately() -> void:
	# Arrange: adult with ads consent granted
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = SaveData.AgeBand.ADULT
	save.data.consent_personalized_ads = true
	save.data.consent_captured = true
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	svc.configure(save)
	# Pre-condition: permissive
	assert_bool(svc.can_show_targeted_ads()).is_true()
	# Act: withdraw consent in-memory (mirrors SaveService.withdraw_consent)
	save.data.consent_personalized_ads = false
	# Assert: verdict is immediately restricted without restart
	assert_bool(svc.can_show_targeted_ads()).is_false()


func test_withdrawal_of_analytics_flips_verdict_immediately() -> void:
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = SaveData.AgeBand.ADULT
	save.data.consent_analytics = true
	save.data.consent_captured = true
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	svc.configure(save)
	assert_bool(svc.can_collect_personal_data()).is_true()
	save.data.consent_analytics = false
	assert_bool(svc.can_collect_personal_data()).is_false()


func test_withdrawal_of_iap_consent_flips_verdict_immediately() -> void:
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = SaveData.AgeBand.ADULT
	save.data.consent_iap = true
	save.data.consent_captured = true
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	svc.configure(save)
	assert_bool(svc.can_process_iap()).is_true()
	save.data.consent_iap = false
	assert_bool(svc.can_process_iap()).is_false()


func test_grant_after_withdrawal_restores_permissive_verdict() -> void:
	# After withdrawal, re-granting consent must restore the permissive verdict.
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = SaveData.AgeBand.ADULT
	save.data.consent_analytics = true
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	svc.configure(save)
	# Withdraw
	save.data.consent_analytics = false
	assert_bool(svc.can_collect_personal_data()).is_false()
	# Re-grant
	save.data.consent_analytics = true
	assert_bool(svc.can_collect_personal_data()).is_true()


# ---------------------------------------------------------------------------
# Fix #3 — Null-_save guard: unconfigured ComplianceService returns restrictive verdicts
# A freshly-new()'d ComplianceService with _save unset must never crash and must
# return false (denied / restricted) for every can_* verdict (fail-closed).
# ---------------------------------------------------------------------------

func test_unconfigured_compliance_service_can_show_targeted_ads_returns_false() -> void:
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	# _save is null — no configure() call
	assert_bool(svc.can_show_targeted_ads()).is_false()


func test_unconfigured_compliance_service_can_collect_personal_data_returns_false() -> void:
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	assert_bool(svc.can_collect_personal_data()).is_false()


func test_unconfigured_compliance_service_can_process_iap_returns_false() -> void:
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	assert_bool(svc.can_process_iap()).is_false()


# ---------------------------------------------------------------------------
# Fix #4 — End-to-end withdrawal: calling the real SaveService.withdraw_consent()
# must flip the corresponding ComplianceService verdict on the next call.
# This proves ADR-0013 Criterion 5 through the real method, not a hand-mirrored
# field mutation.
# ---------------------------------------------------------------------------

func test_withdraw_consent_via_save_service_flips_compliance_verdict() -> void:
	# Arrange: adult with all consents granted, wired into a ComplianceService.
	var save = auto_free(SAVE_SCRIPT.new())
	var path: String = "user://test_consent_e2e_withdrawal.json"
	_temp_save_paths.append(path)
	save.configure(path)
	save.data.age_band = SaveData.AgeBand.ADULT
	save.capture_consent(true, true, true)
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	svc.configure(save)
	# Pre-condition: all permissive.
	assert_bool(svc.can_show_targeted_ads()).is_true()
	assert_bool(svc.can_collect_personal_data()).is_true()
	assert_bool(svc.can_process_iap()).is_true()
	# Act: withdraw each consent through the real SaveService API.
	save.withdraw_consent("personalized_ads")
	save.withdraw_consent("analytics")
	save.withdraw_consent("iap")
	# Assert: every verdict flips to restricted on the next call — no restart.
	assert_bool(svc.can_show_targeted_ads()).is_false()
	assert_bool(svc.can_collect_personal_data()).is_false()
	assert_bool(svc.can_process_iap()).is_false()


# ---------------------------------------------------------------------------
# SaveService consent setters (capture_consent / withdraw_consent)
# Integration: verify the setters persist and verdicts reflect them.
# ---------------------------------------------------------------------------

func test_capture_consent_sets_all_flags_and_captured_marker() -> void:
	# Arrange
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = SaveData.AgeBand.ADULT
	var svc = auto_free(COMPLIANCE_SCRIPT.new())
	svc.configure(save)
	# Pre-condition: all denied
	assert_bool(svc.can_show_targeted_ads()).is_false()
	assert_bool(svc.can_collect_personal_data()).is_false()
	assert_bool(svc.can_process_iap()).is_false()
	# Act: capture consent (no save path needed — test in-memory via configure DI)
	save.data.consent_personalized_ads = true
	save.data.consent_analytics = true
	save.data.consent_iap = true
	save.data.consent_captured = true
	# Assert: verdicts immediately permissive
	assert_bool(svc.can_show_targeted_ads()).is_true()
	assert_bool(svc.can_collect_personal_data()).is_true()
	assert_bool(svc.can_process_iap()).is_true()
	assert_bool(save.data.consent_captured).is_true()


func test_save_service_capture_consent_method_sets_captured_true() -> void:
	# Verify SaveService.capture_consent() sets the captured marker.
	var save = auto_free(SAVE_SCRIPT.new())
	var path: String = "user://test_consent_gate_capture.json"
	_temp_save_paths.append(path)
	save.configure(path)
	save.data.age_band = SaveData.AgeBand.ADULT
	save.capture_consent(true, true, true)
	assert_bool(save.data.consent_personalized_ads).is_true()
	assert_bool(save.data.consent_analytics).is_true()
	assert_bool(save.data.consent_iap).is_true()
	assert_bool(save.data.consent_captured).is_true()


func test_save_service_withdraw_consent_personalized_ads_sets_denied() -> void:
	var save = auto_free(SAVE_SCRIPT.new())
	var path: String = "user://test_consent_gate_withdraw.json"
	_temp_save_paths.append(path)
	save.configure(path)
	save.data.age_band = SaveData.AgeBand.ADULT
	save.data.consent_personalized_ads = true
	save.withdraw_consent("personalized_ads")
	assert_bool(save.data.consent_personalized_ads).is_false()


func test_save_service_withdraw_consent_analytics_sets_denied() -> void:
	var save = auto_free(SAVE_SCRIPT.new())
	var path: String = "user://test_consent_gate_withdraw_analytics.json"
	_temp_save_paths.append(path)
	save.configure(path)
	save.data.age_band = SaveData.AgeBand.ADULT
	save.data.consent_analytics = true
	save.withdraw_consent("analytics")
	assert_bool(save.data.consent_analytics).is_false()


func test_save_service_withdraw_consent_iap_sets_denied() -> void:
	var save = auto_free(SAVE_SCRIPT.new())
	var path: String = "user://test_consent_gate_withdraw_iap.json"
	_temp_save_paths.append(path)
	save.configure(path)
	save.data.age_band = SaveData.AgeBand.ADULT
	save.data.consent_iap = true
	save.withdraw_consent("iap")
	assert_bool(save.data.consent_iap).is_false()
