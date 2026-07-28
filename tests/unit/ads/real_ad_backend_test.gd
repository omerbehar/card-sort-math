extends GdUnitTestSuite
## Unit tests for [RealAdBackend] safe-degradation (real-ads plan §3). The suite runs on Linux/CI
## where no native ad plugin exists, so these tests pin the load-bearing safety guarantee: with no
## plugin the backend is INERT and every presentation still RESOLVES its async signal exactly once
## (no-fill / not-completed) — never hanging the win flow. The plugin-present path is device-only
## and covered by the manual runbook (docs/architecture/real-ads-setup-guide.md).

const REAL_BACKEND := preload("res://autoloads/real_ad_backend.gd")
const AD_BACKEND := preload("res://autoloads/ad_backend.gd")


func test_real_ad_backend_is_inert_without_plugin() -> void:
	# Arrange / Act — constructed on CI (no AdMob singleton).
	var backend: RealAdBackend = REAL_BACKEND.new()

	# Assert — no plugin resolved, so it reports itself inactive (base-backend behaviour).
	assert_bool(backend.is_active()).is_false()
	assert_bool(backend.has_interstitial_ready(0)).is_false()
	assert_bool(backend.has_rewarded_ready()).is_false()


func test_real_ad_backend_interstitial_resolves_no_fill_when_inert() -> void:
	# Arrange
	var backend: RealAdBackend = REAL_BACKEND.new()

	# Act — drive show, then await the async outcome (deferred emit).
	backend.show_interstitial(0)
	var outcome: int = await backend.interstitial_finished

	# Assert — resolves (no hang) as NO_FILL, so AdService reports no ad.
	assert_int(outcome).is_equal(AD_BACKEND.InterstitialResult.NO_FILL)


func test_real_ad_backend_rewarded_resolves_not_completed_when_inert() -> void:
	# Arrange
	var backend: RealAdBackend = REAL_BACKEND.new()

	# Act
	backend.show_rewarded()
	var completed: bool = await backend.rewarded_finished

	# Assert — resolves (no hang) as not-completed, so no reward is granted without a real view.
	assert_bool(completed).is_false()
