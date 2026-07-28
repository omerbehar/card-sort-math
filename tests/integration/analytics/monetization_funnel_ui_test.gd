extends GdUnitTestSuite
## Integration test — S5-007 monetization funnel wiring.
##
## Proves the UI flows emit the funnel events through the REAL AnalyticsService → sink,
## consent permitting. This suite covers the interstitial `ad_impression` (the event whose
## flow uses the AnalyticsService autoload directly); the `iap_purchase` (S5-003) and
## `ad_reward` (S5-004) flow emissions are asserted in their own suites via an injected
## analytics fake. The consent × audience gate itself is covered by
## tests/integration/analytics/funnel_consent_test.gd (S4-007).

const MAIN := "res://scenes/main/main.tscn"
const SINK := preload("res://autoloads/analytics_sink.gd")

var _sink = null


func after_test() -> void:
	# Restore the autoload AnalyticsService to a no-op sink + the real compliance autoload
	# so the injected recording sink / granted consent don't leak into other suites.
	var svc = get_tree().root.get_node_or_null("AnalyticsService")
	var compliance = get_tree().root.get_node_or_null("ComplianceService")
	if svc != null:
		svc.configure(compliance, SINK.new())


func _boot() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
		# S6-005: establish audience + consent through the real SaveService setters (the same
		# APIs the age gate / consent sheet now call) instead of poking protected fields.
		save.set_age_band(SaveData.AgeBand.ADULT)
		save.capture_consent(false, true, false)   # analytics granted
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


func _has_event(name: String) -> bool:
	for e in _sink.events:
		if e.get("name", "") == name:
			return true
	return false


func test_interstitial_flow_emits_ad_impression_through_analytics() -> void:
	# Arrange: boot with analytics consent, then inject a recording sink into the real
	# AnalyticsService (its consent gate reads the same save).
	var runner = await _boot()
	var main = runner.scene()
	_sink = SINK.MockAnalyticsSink.new()
	AnalyticsService.configure(get_tree().root.get_node("ComplianceService"), _sink)

	# Act: drive the interstitial presentation flow (S5-005).
	main._present_interstitial(get_tree().root.get_node("AdService"))
	await runner.simulate_frames(2)

	# Assert: the impression funnel event reached the sink (S5-007, AC-7).
	assert_bool(_has_event(AnalyticsService.EVENT_AD_IMPRESSION)).is_true()


func test_no_funnel_event_without_analytics_consent() -> void:
	# Arrange: revoke analytics consent → the AnalyticsService gate must drop the event.
	var runner = await _boot()
	var main = runner.scene()
	get_tree().root.get_node("SaveService").withdraw_consent("analytics")   # S6-005: real withdrawal API
	_sink = SINK.MockAnalyticsSink.new()
	AnalyticsService.configure(get_tree().root.get_node("ComplianceService"), _sink)

	# Act
	main._present_interstitial(get_tree().root.get_node("AdService"))
	await runner.simulate_frames(2)

	# Assert: consent-gated — nothing reached the sink (AC-7).
	assert_int(_sink.events.size()).is_equal(0)
