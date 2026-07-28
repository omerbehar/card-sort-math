class_name AdUnitConfig
extends Resource
## Per-platform ad-unit IDs for [RealAdBackend] (real-ads plan §5). Test IDs by default so no
## dev / debug / CI build ever requests a PRODUCTION ad unit (which would pollute real
## fill/impression metrics). Never hardcode an ad-unit ID in gameplay code — drive from here.
##
## Authored as [code]assets/data/ad_unit_config.tres[/code] (create it with your real IDs and
## set [member use_test_ad_units] = false in signed release builds). If the resource is absent
## [AdService] falls back to a fresh instance — i.e. Google TEST ads.
##
## [b]VERIFY[/b] the Google test-ad-unit ID constants below against current AdMob docs before
## relying on them — they are stable per-format but must be confirmed, not trusted from memory.

# Google's official sample/TEST ad-unit IDs (per format, per platform). VERIFY current values.
const TEST_ANDROID_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"
const TEST_ANDROID_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_IOS_INTERSTITIAL := "ca-app-pub-3940256099942544/4411468910"
const TEST_IOS_REWARDED := "ca-app-pub-3940256099942544/1712485313"

## When true (the default), every lookup returns a Google TEST ad unit. Flip to false ONLY in
## a signed release export — never in editor/debug/CI.
@export var use_test_ad_units: bool = true

@export_group("Android (production)")
@export var android_interstitial: String = ""
@export var android_rewarded: String = ""

@export_group("iOS (production)")
@export var ios_interstitial: String = ""
@export var ios_rewarded: String = ""


## The interstitial ad-unit ID for [param platform] ("Android" / "iOS"). Test ID unless
## [member use_test_ad_units] is false, in which case the authored production ID is returned.
func interstitial_unit_id(platform: String) -> String:
	if use_test_ad_units:
		return TEST_IOS_INTERSTITIAL if platform == "iOS" else TEST_ANDROID_INTERSTITIAL
	return ios_interstitial if platform == "iOS" else android_interstitial


## The rewarded ad-unit ID for [param platform]. See [method interstitial_unit_id].
func rewarded_unit_id(platform: String) -> String:
	if use_test_ad_units:
		return TEST_IOS_REWARDED if platform == "iOS" else TEST_ANDROID_REWARDED
	return ios_rewarded if platform == "iOS" else android_rewarded
