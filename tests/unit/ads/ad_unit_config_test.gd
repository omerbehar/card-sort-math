extends GdUnitTestSuite
## Unit tests for [AdUnitConfig] — the data-driven per-platform ad-unit ID lookup used by
## [RealAdBackend] (real-ads plan §5). Proves the safety-critical default: test IDs unless a
## release build explicitly flips [member AdUnitConfig.use_test_ad_units] off, and correct
## platform routing either way. No native SDK involved — pure Resource logic.

const CONFIG := preload("res://data/ad_unit_config.gd")


func test_ad_unit_config_defaults_to_test_units() -> void:
	# Arrange
	var config: AdUnitConfig = CONFIG.new()

	# Act / Assert — the default MUST be test units so no dev/CI build hits a production unit.
	assert_bool(config.use_test_ad_units).is_true()


func test_ad_unit_config_test_mode_returns_google_test_ids_per_platform() -> void:
	# Arrange
	var config: AdUnitConfig = CONFIG.new()
	config.use_test_ad_units = true
	# Even with production IDs authored, test mode must ignore them.
	config.android_interstitial = "ca-app-pub-REAL/android-int"
	config.ios_rewarded = "ca-app-pub-REAL/ios-rew"

	# Act / Assert
	assert_str(config.interstitial_unit_id("Android")).is_equal(CONFIG.TEST_ANDROID_INTERSTITIAL)
	assert_str(config.interstitial_unit_id("iOS")).is_equal(CONFIG.TEST_IOS_INTERSTITIAL)
	assert_str(config.rewarded_unit_id("Android")).is_equal(CONFIG.TEST_ANDROID_REWARDED)
	assert_str(config.rewarded_unit_id("iOS")).is_equal(CONFIG.TEST_IOS_REWARDED)


func test_ad_unit_config_production_mode_returns_authored_ids_per_platform() -> void:
	# Arrange
	var config: AdUnitConfig = CONFIG.new()
	config.use_test_ad_units = false
	config.android_interstitial = "ca-app-pub-1/android-int"
	config.android_rewarded = "ca-app-pub-1/android-rew"
	config.ios_interstitial = "ca-app-pub-1/ios-int"
	config.ios_rewarded = "ca-app-pub-1/ios-rew"

	# Act / Assert — production mode routes to the authored ID for the requested platform.
	assert_str(config.interstitial_unit_id("Android")).is_equal("ca-app-pub-1/android-int")
	assert_str(config.rewarded_unit_id("Android")).is_equal("ca-app-pub-1/android-rew")
	assert_str(config.interstitial_unit_id("iOS")).is_equal("ca-app-pub-1/ios-int")
	assert_str(config.rewarded_unit_id("iOS")).is_equal("ca-app-pub-1/ios-rew")


func test_ad_unit_config_non_ios_platform_routes_to_android_ids() -> void:
	# Arrange — any non-"iOS" platform string (incl. desktop names) falls to the Android branch.
	var config: AdUnitConfig = CONFIG.new()
	config.use_test_ad_units = true

	# Act / Assert
	assert_str(config.interstitial_unit_id("Linux")).is_equal(CONFIG.TEST_ANDROID_INTERSTITIAL)
	assert_str(config.rewarded_unit_id("Android")).is_equal(CONFIG.TEST_ANDROID_REWARDED)
