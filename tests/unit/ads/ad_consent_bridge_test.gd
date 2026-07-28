extends GdUnitTestSuite
## Unit tests for [AdConsentBridge] fail-closed behaviour (real-ads plan §4). With no native CMP
## plugin (CI/desktop), the bridge must record NO personalized-ads consent and return false —
## never leak targeting without a verified grant. Routes through a stub sink so no autoload state
## is touched (the sink mirrors SaveService.capture_ad_personalization_consent).

const BRIDGE := preload("res://autoloads/ad_consent_bridge.gd")


# Stub sink mirroring the narrow SaveService chokepoint the bridge writes through.
class StubSink extends RefCounted:
	var captured: Array = []  # every capture_ad_personalization_consent(bool) call
	func capture_ad_personalization_consent(personalized_ads: bool) -> void:
		captured.append(personalized_ads)


func test_ad_consent_bridge_fails_closed_without_plugin() -> void:
	# Arrange — no UMP/ATT plugin exists on CI, so the bridge should deny personalization.
	var bridge: AdConsentBridge = BRIDGE.new()
	var sink := StubSink.new()
	bridge.configure(sink)

	# Act
	var may_personalize: bool = await bridge.request_consent()

	# Assert — returns false AND records exactly one contextual-only (false) consent.
	assert_bool(may_personalize).is_false()
	assert_array(sink.captured).is_equal([false])


func test_ad_consent_bridge_returns_false_when_no_sink() -> void:
	# Arrange — sink missing the required method (defensive path).
	var bridge: AdConsentBridge = BRIDGE.new()
	bridge.configure(RefCounted.new())

	# Act
	var may_personalize: bool = await bridge.request_consent()

	# Assert — no sink to record through → deny, no crash.
	assert_bool(may_personalize).is_false()
