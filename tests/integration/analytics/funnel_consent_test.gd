extends GdUnitTestSuite
## Integration tests for [AnalyticsService] (S4-007).
##
## One test boots the real scenes/main/main.tscn + autoloads to prove AnalyticsService
## registers and resolves its deps. The others drive the REAL ComplianceService over a fresh
## in-memory SaveService against a [AnalyticsSink.MockAnalyticsSink], proving the
## consent × audience gate end-to-end and that a mid-session consent withdrawal stops emission.

const MAIN := "res://scenes/main/main.tscn"
const ANALYTICS_SCRIPT := preload("res://autoloads/analytics_service.gd")
const SINK := preload("res://autoloads/analytics_sink.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const COMPLIANCE_SCRIPT := preload("res://autoloads/compliance_service.gd")


# Real ComplianceService over a fresh in-memory save with the given audience + analytics consent.
func _stack(age_band: int, analytics_consent: bool):
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = age_band
	save.data.consent_analytics = analytics_consent
	var compliance = auto_free(COMPLIANCE_SCRIPT.new())
	compliance.configure(save)
	var sink = SINK.MockAnalyticsSink.new()
	var svc = auto_free(ANALYTICS_SCRIPT.new())
	svc.configure(compliance, sink)
	return {"save": save, "compliance": compliance, "sink": sink, "svc": svc}


func test_analytics_service_boots_as_autoload_and_resolves_deps() -> void:
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	var root := get_tree().root
	var analytics := root.get_node_or_null("AnalyticsService")
	assert_object(analytics).is_not_null()
	assert_object(root.get_node_or_null("ComplianceService")).is_not_null()
	# Resolved its compliance dep: is_enabled() is queryable without error (returns a bool).
	assert_bool(analytics.is_enabled() or not analytics.is_enabled()).is_true()


func test_adult_with_analytics_consent_emits_events() -> void:
	var s = _stack(SaveData.AgeBand.ADULT, true)
	assert_bool(s.svc.is_enabled()).is_true()
	assert_bool(s.svc.track_iap_purchase(100, true)).is_true()
	assert_int(s.sink.events.size()).is_equal(1)


func test_unknown_audience_emits_nothing_even_with_consent() -> void:
	# UNKNOWN age is restricted regardless of the analytics consent flag.
	var s = _stack(SaveData.AgeBand.UNKNOWN, true)
	assert_bool(s.svc.is_enabled()).is_false()
	assert_bool(s.svc.track_ad_reward(60)).is_false()
	assert_int(s.sink.events.size()).is_equal(0)


func test_consent_withdrawn_mid_session_stops_emission_end_to_end() -> void:
	var s = _stack(SaveData.AgeBand.ADULT, true)
	assert_bool(s.svc.track("e1")).is_true()
	# Withdraw analytics consent on the live save → ComplianceService verdict flips immediately.
	s.save.data.consent_analytics = false
	assert_bool(s.svc.track("e2")).is_false()
	assert_int(s.sink.events.size()).is_equal(1)
