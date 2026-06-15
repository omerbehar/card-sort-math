extends GdUnitTestSuite
## Unit tests for [AnalyticsService] — consent-gated event forwarding (S4-007).
##
## Drives a real [AnalyticsService] with a stub compliance verdict and a
## [AnalyticsSink.MockAnalyticsSink]. No vendor SDK, no real consent store.

const ANALYTICS_SCRIPT := preload("res://autoloads/analytics_service.gd")
const SINK := preload("res://autoloads/analytics_sink.gd")


class StubCompliance extends RefCounted:
	var can_collect: bool = true
	func can_collect_personal_data() -> bool:
		return can_collect


var _compliance: StubCompliance
var _sink  # AnalyticsSink.MockAnalyticsSink (untyped: inner-class access yields Variant)


func _make(consent: bool = true):
	_compliance = StubCompliance.new()
	_compliance.can_collect = consent
	_sink = SINK.MockAnalyticsSink.new()
	var svc = auto_free(ANALYTICS_SCRIPT.new())
	svc.configure(_compliance, _sink)
	return svc


func test_is_enabled_reflects_compliance_verdict() -> void:
	var svc = _make(true)
	assert_bool(svc.is_enabled()).is_true()
	_compliance.can_collect = false
	assert_bool(svc.is_enabled()).is_false()


func test_track_forwards_event_when_consent_granted() -> void:
	var svc = _make(true)
	var emitted: bool = svc.track("custom_event", {"k": 1})
	assert_bool(emitted).is_true()
	assert_int(_sink.events.size()).is_equal(1)
	assert_str(_sink.events[0]["name"]).is_equal("custom_event")
	assert_int(_sink.events[0]["props"]["k"]).is_equal(1)


func test_track_dropped_when_consent_denied() -> void:
	var svc = _make(false)
	var emitted: bool = svc.track("custom_event")
	assert_bool(emitted).is_false()
	assert_int(_sink.events.size()).is_equal(0)


func test_consent_withdrawn_mid_session_stops_emission() -> void:
	var svc = _make(true)
	assert_bool(svc.track("e1")).is_true()
	_compliance.can_collect = false  # withdrawn mid-session
	assert_bool(svc.track("e2")).is_false()
	# Only the pre-withdrawal event reached the sink.
	assert_int(_sink.events.size()).is_equal(1)
	assert_str(_sink.events[0]["name"]).is_equal("e1")


func test_funnel_helpers_forward_structured_events_when_enabled() -> void:
	var svc = _make(true)
	assert_bool(svc.track_iap_purchase(100, true)).is_true()
	assert_bool(svc.track_ad_impression(1)).is_true()
	assert_bool(svc.track_ad_reward(60)).is_true()
	assert_int(_sink.events.size()).is_equal(3)
	assert_str(_sink.events[0]["name"]).is_equal(ANALYTICS_SCRIPT.EVENT_IAP_PURCHASE)
	assert_int(_sink.events[0]["props"]["sku"]).is_equal(100)
	assert_str(_sink.events[2]["name"]).is_equal(ANALYTICS_SCRIPT.EVENT_AD_REWARD)
	assert_int(_sink.events[2]["props"]["coins"]).is_equal(60)


func test_funnel_helpers_dropped_when_consent_denied() -> void:
	var svc = _make(false)
	assert_bool(svc.track_iap_purchase(100, true)).is_false()
	assert_bool(svc.track_ad_reward(60)).is_false()
	assert_int(_sink.events.size()).is_equal(0)


func test_track_with_null_sink_is_safe() -> void:
	# Consent granted but no sink wired → reports enabled/forwarded without crashing.
	var compliance = StubCompliance.new()
	var svc = auto_free(ANALYTICS_SCRIPT.new())
	svc.configure(compliance, null)
	assert_bool(svc.track("e")).is_true()
