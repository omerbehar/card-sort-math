extends GdUnitTestSuite
## Integration tests for [AdService] (S4-004a).
##
## One test boots the real [code]scenes/main/main.tscn[/code] + autoloads via scene_runner
## to prove AdService registers and resolves its deps (CLAUDE.md mandatory validation). The
## others drive the REAL AdService + WalletService + EntitlementService + ComplianceService
## together over a fresh in-memory SaveService (rewarded earn end-to-end; entitlement
## suppression of interstitials), so no autoload-singleton state is mutated. File I/O is
## confined to the wallet/entitlement persistence and cleaned up in [method after_test].

const MAIN := "res://scenes/main/main.tscn"
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


# Builds a fresh, fully-configured real economy stack sharing one SaveService (adult).
# Returns [save, wallet, entitlement, ad_service]; the AdService uses a mock backend whose
# outcomes the caller sets before acting.
func _build_stack(path: String):
	_temp_save_paths.append(path)
	var save = auto_free(SAVE_SCRIPT.new())
	save.configure(path)
	save.data.age_band = SaveData.AgeBand.ADULT  # not restricted → rewarded permitted

	var compliance = auto_free(COMPLIANCE_SCRIPT.new())
	compliance.configure(save)

	var config := EconomyConfig.new()
	var time := TimeProvider.new()
	var wallet = auto_free(WALLET_SCRIPT.new())
	wallet.configure(save, compliance, time, config)

	var entitlement = auto_free(ENTITLEMENT_SCRIPT.new())
	entitlement.configure(save, ENT_BACKEND.MockEntitlementBackend.new())

	var backend = AD_BACKEND.MockAdBackend.new()
	var ad = auto_free(AD_SCRIPT.new())
	ad.configure(wallet, compliance, entitlement, time, config, backend)
	return {"save": save, "wallet": wallet, "compliance": compliance,
			"entitlement": entitlement, "ad": ad, "backend": backend, "config": config}


# ---------------------------------------------------------------------------
# Real scene-tree boot: AdService registers and resolves its config + deps.
# ---------------------------------------------------------------------------

func test_ad_service_boots_as_autoload_and_resolves_deps() -> void:
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	var root := get_tree().root

	var ad := root.get_node_or_null("AdService")
	assert_object(ad).is_not_null()
	assert_object(root.get_node_or_null("WalletService")).is_not_null()
	assert_object(root.get_node_or_null("EntitlementService")).is_not_null()

	# Live autoload instance with clean in-memory cap state.
	assert_int(ad.levels_since_interstitial()).is_equal(0)
	# The no-mid-puzzle gate is the first, in-memory check — deterministic regardless of any
	# persisted save/entitlement state — proving the live autoload processes requests.
	ad.notify_level_started()
	assert_int(ad.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SUPPRESSED_PUZZLE)


# ---------------------------------------------------------------------------
# End-to-end rewarded earn through the real WalletService chokepoint.
# ---------------------------------------------------------------------------

func test_rewarded_completion_credits_real_wallet() -> void:
	var stack = _build_stack("user://test_ad_rewarded_earn.json")
	stack.backend.rewarded_completes = true
	var coins := EconomyEnums.Currency.COINS

	assert_int(stack.wallet.balance(coins)).is_equal(0)
	var credited: int = stack.ad.show_rewarded()

	# Reward flowed through WalletService._earn_rewarded_ad and landed in the real balance.
	assert_int(credited).is_equal(stack.config.coins_rewarded_ad)
	assert_int(stack.wallet.balance(coins)).is_equal(stack.config.coins_rewarded_ad)


func test_rewarded_abandoned_leaves_real_wallet_unchanged() -> void:
	var stack = _build_stack("user://test_ad_rewarded_abandon.json")
	stack.backend.rewarded_completes = false  # dismissed before completion
	var coins := EconomyEnums.Currency.COINS

	var credited: int = stack.ad.show_rewarded()

	assert_int(credited).is_equal(0)
	assert_int(stack.wallet.balance(coins)).is_equal(0)


# ---------------------------------------------------------------------------
# Entitlement suppression of interstitials through the real EntitlementService.
# ---------------------------------------------------------------------------

func test_remove_ads_entitlement_suppresses_interstitial_end_to_end() -> void:
	var stack = _build_stack("user://test_ad_interstitial_suppress.json")
	# Satisfy the frequency window first so only the entitlement gate can differ.
	stack.ad.notify_level_completed()
	stack.ad.notify_level_completed()
	stack.ad.notify_level_completed()
	assert_int(stack.ad.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)

	# Now own Remove-Ads via the real EntitlementService — interstitials must suppress.
	stack.entitlement.grant_remove_ads()
	stack.ad.notify_level_completed()
	stack.ad.notify_level_completed()
	stack.ad.notify_level_completed()
	assert_int(stack.ad.maybe_show_interstitial()).is_equal(
			AD_SCRIPT.InterstitialOutcome.SUPPRESSED_ENTITLEMENT)
