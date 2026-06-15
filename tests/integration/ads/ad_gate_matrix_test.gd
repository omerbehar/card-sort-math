extends GdUnitTestSuite
## Integration matrix for the [AdService] triple gate (S4-004b): audience × consent ×
## entitlement, driven through the REAL ComplianceService + EntitlementService + WalletService
## over a fresh in-memory SaveService (no autoload-state mutation). Each row sets a save state,
## arms the frequency cap, and asserts the interstitial outcome / targeting and rewarded
## availability. File I/O is confined to the persistence path and cleaned up in after_test.

const AD_SCRIPT := preload("res://autoloads/ad_service.gd")
const AD_BACKEND := preload("res://autoloads/ad_backend.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const WALLET_SCRIPT := preload("res://autoloads/wallet_service.gd")
const COMPLIANCE_SCRIPT := preload("res://autoloads/compliance_service.gd")
const ENTITLEMENT_SCRIPT := preload("res://autoloads/entitlement_service.gd")
const ENT_BACKEND := preload("res://autoloads/entitlement_backend.gd")

var _temp_save_paths: Array[String] = []


func after_test() -> void:
	for path: String in _temp_save_paths:
		if FileAccess.file_exists(path):
			DirAccess.open("user://").remove(path.get_file())
		var tmp: String = path + ".tmp"
		if FileAccess.file_exists(tmp):
			DirAccess.open("user://").remove(tmp.get_file())
	_temp_save_paths.clear()


# Builds a real AdService over real Compliance/Entitlement/Wallet for the given audience,
# personalized-ads consent, and Remove-Ads ownership.
func _stack(age_band: int, personalized: bool, owned: bool):
	var path: String = "user://test_ad_matrix_%d.json" % _temp_save_paths.size()
	_temp_save_paths.append(path)
	var save = auto_free(SAVE_SCRIPT.new())
	save.configure(path)
	save.data.age_band = age_band
	save.data.consent_personalized_ads = personalized
	save.data.remove_ads_owned = owned

	var compliance = auto_free(COMPLIANCE_SCRIPT.new())
	compliance.configure(save)
	var entitlement = auto_free(ENTITLEMENT_SCRIPT.new())
	entitlement.configure(save, ENT_BACKEND.MockEntitlementBackend.new())
	var config := EconomyConfig.new()
	var time := TimeProvider.new()
	var wallet = auto_free(WALLET_SCRIPT.new())
	wallet.configure(save, compliance, time, config)
	var backend = AD_BACKEND.MockAdBackend.new()
	var ad = auto_free(AD_SCRIPT.new())
	ad.configure(wallet, compliance, entitlement, time, config, backend)
	return {"ad": ad, "backend": backend, "wallet": wallet, "entitlement": entitlement,
			"config": config}


# Completes enough levels to satisfy the default every-N-levels window (EconomyConfig=3).
func _arm(ad) -> void:
	for _i in 3:
		ad.notify_level_completed()


# ---------------------------------------------------------------------------
# Audience × consent → personalized vs contextual targeting
# ---------------------------------------------------------------------------

func test_adult_with_personalized_consent_shows_personalized() -> void:
	var s = _stack(SaveData.AgeBand.ADULT, true, false)
	_arm(s.ad)
	assert_int(s.ad.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)
	assert_int(s.backend.last_ad_type).is_equal(AD_SCRIPT.AdType.PERSONALIZED)


func test_adult_consent_denied_shows_contextual_never_personalized() -> void:
	var s = _stack(SaveData.AgeBand.ADULT, false, false)
	_arm(s.ad)
	assert_int(s.ad.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)
	assert_int(s.backend.last_ad_type).is_equal(AD_SCRIPT.AdType.CONTEXTUAL)


func test_unknown_audience_shows_contextual_regardless_of_consent() -> void:
	# UNKNOWN age can never receive personalized ads even with the consent flag set.
	var s = _stack(SaveData.AgeBand.UNKNOWN, true, false)
	_arm(s.ad)
	assert_int(s.ad.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)
	assert_int(s.backend.last_ad_type).is_equal(AD_SCRIPT.AdType.CONTEXTUAL)


func test_child_audience_shows_contextual_regardless_of_consent() -> void:
	var s = _stack(SaveData.AgeBand.CHILD, true, false)
	_arm(s.ad)
	assert_int(s.ad.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)
	assert_int(s.backend.last_ad_type).is_equal(AD_SCRIPT.AdType.CONTEXTUAL)


# ---------------------------------------------------------------------------
# Entitlement × rewarded interplay
# ---------------------------------------------------------------------------

func test_remove_ads_owned_suppresses_interstitial_but_rewarded_still_earns() -> void:
	var s = _stack(SaveData.AgeBand.ADULT, true, true)  # owns Remove-Ads
	_arm(s.ad)
	# Interstitials suppressed despite a satisfied frequency window and personalized eligibility.
	assert_int(s.ad.maybe_show_interstitial()).is_equal(
			AD_SCRIPT.InterstitialOutcome.SUPPRESSED_ENTITLEMENT)
	# Rewarded stays available and still credits (GAME_PLAN §8: Remove-Ads keeps rewarded).
	assert_bool(s.ad.is_rewarded_available()).is_true()
	assert_int(s.ad.show_rewarded()).is_equal(s.config.coins_rewarded_ad)


func test_restricted_audience_blocks_rewarded_earn() -> void:
	# UNKNOWN/CHILD are restricted → WalletService.is_ad_earn_available() is false, so the
	# rewarded surface is closed even though entitlement keeps rewarded "available" in policy.
	var s = _stack(SaveData.AgeBand.UNKNOWN, false, false)
	assert_bool(s.ad.is_rewarded_available()).is_false()
	assert_int(s.ad.show_rewarded()).is_equal(0)
