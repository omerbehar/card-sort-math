extends GdUnitTestSuite
## Unit tests for [AdService] — interstitial frequency cap + rewarded earn-in (S4-004a).
##
## Drives a real [AdService] with injected stubs (wallet / entitlement), a
## [FixedTimeProvider] for deterministic interval math, an in-memory [EconomyConfig], and a
## [AdBackend.MockAdBackend]. No native SDK, no real clock.

const AD_SCRIPT := preload("res://autoloads/ad_service.gd")
const AD_BACKEND := preload("res://autoloads/ad_backend.gd")


# --- Local test doubles -----------------------------------------------------

class StubWallet extends RefCounted:
	var ad_available: bool = true
	var rewarded_amounts: Array = []  # amounts passed to _earn_rewarded_ad()
	var rewarded_return: int = 60
	func is_ad_earn_available() -> bool:
		return ad_available
	func _earn_rewarded_ad(amount: int) -> int:
		rewarded_amounts.append(amount)
		return rewarded_return


class StubEntitlement extends RefCounted:
	var suppress: bool = false
	var rewarded_ok: bool = true
	func should_suppress_interstitials() -> bool:
		return suppress
	func is_rewarded_available() -> bool:
		return rewarded_ok


class StubCompliance extends RefCounted:
	var targeted_ok: bool = true  # can_show_targeted_ads() — ADULT + personalized consent
	func can_show_targeted_ads() -> bool:
		return targeted_ok


# --- Fixture members (set by _make) -----------------------------------------

var _wallet: StubWallet
var _compliance: StubCompliance
var _entitlement: StubEntitlement
var _time: FixedTimeProvider
var _config: EconomyConfig
var _backend  # AdBackend.MockAdBackend (untyped: inner-class access yields Variant)
var _shown_count: int = 0
var _shown_types: Array = []
var _rewarded_coins: Array = []


func _on_interstitial_shown(ad_type: int) -> void:
	_shown_count += 1
	_shown_types.append(ad_type)


func _on_rewarded_earned(coins: int) -> void:
	_rewarded_coins.append(coins)


func _make(every_n: int = 2, min_seconds: int = 60):
	_wallet = StubWallet.new()
	_compliance = StubCompliance.new()
	_entitlement = StubEntitlement.new()
	_time = FixedTimeProvider.new()
	_time.now_seconds = 1000
	_config = EconomyConfig.new()
	_config.interstitial_every_n_levels = every_n
	_config.interstitial_min_seconds = min_seconds
	_config.coins_rewarded_ad = 60
	_backend = AD_BACKEND.MockAdBackend.new()
	_shown_count = 0
	_shown_types = []
	_rewarded_coins = []
	var svc = auto_free(AD_SCRIPT.new())
	svc.configure(_wallet, _compliance, _entitlement, _time, _config, _backend)
	return svc


# Completes `n` levels so the every-N-levels window is satisfied.
func _complete_levels(svc, n: int) -> void:
	for _i in n:
		svc.notify_level_completed()


# ---------------------------------------------------------------------------
# Interstitial frequency cap
# ---------------------------------------------------------------------------

func test_levels_since_interstitial_increments_on_completion() -> void:
	var svc = _make()
	assert_int(svc.levels_since_interstitial()).is_equal(0)
	_complete_levels(svc, 2)
	assert_int(svc.levels_since_interstitial()).is_equal(2)


func test_interstitial_shown_when_both_windows_satisfied() -> void:
	var svc = _make(2, 60)
	svc.interstitial_shown.connect(_on_interstitial_shown)
	_complete_levels(svc, 2)
	var outcome: int = svc.maybe_show_interstitial()
	assert_int(outcome).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)
	assert_int(_backend.interstitial_calls).is_equal(1)
	assert_int(_shown_count).is_equal(1)
	# Counter resets after a presentation.
	assert_int(svc.levels_since_interstitial()).is_equal(0)


func test_interstitial_suppressed_before_level_window() -> void:
	var svc = _make(3, 60)
	_complete_levels(svc, 2)  # one short of the every-3 window
	var outcome: int = svc.maybe_show_interstitial()
	assert_int(outcome).is_equal(AD_SCRIPT.InterstitialOutcome.SUPPRESSED_FREQUENCY)
	assert_int(_backend.interstitial_calls).is_equal(0)


func test_second_interstitial_suppressed_inside_min_interval() -> void:
	var svc = _make(2, 60)
	_complete_levels(svc, 2)
	assert_int(svc.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)
	# Level window satisfied again, but only 30s have passed (< 60s min).
	_complete_levels(svc, 2)
	_time.now_seconds = 1030
	var outcome: int = svc.maybe_show_interstitial()
	assert_int(outcome).is_equal(AD_SCRIPT.InterstitialOutcome.SUPPRESSED_FREQUENCY)
	assert_int(_backend.interstitial_calls).is_equal(1)  # backend not re-invoked


func test_interstitial_shown_again_after_min_interval_elapses() -> void:
	var svc = _make(2, 60)
	_complete_levels(svc, 2)
	assert_int(svc.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)
	_complete_levels(svc, 2)
	_time.now_seconds = 1060  # exactly 60s later → interval satisfied
	assert_int(svc.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)
	assert_int(_backend.interstitial_calls).is_equal(2)


func test_interstitial_suppressed_while_puzzle_active() -> void:
	var svc = _make(2, 60)
	_complete_levels(svc, 2)
	svc.notify_level_started()  # a new puzzle began
	var outcome: int = svc.maybe_show_interstitial()
	assert_int(outcome).is_equal(AD_SCRIPT.InterstitialOutcome.SUPPRESSED_PUZZLE)
	assert_int(_backend.interstitial_calls).is_equal(0)


func test_interstitial_suppressed_when_remove_ads_owned() -> void:
	var svc = _make(2, 60)
	_entitlement.suppress = true
	_complete_levels(svc, 2)
	var outcome: int = svc.maybe_show_interstitial()
	assert_int(outcome).is_equal(AD_SCRIPT.InterstitialOutcome.SUPPRESSED_ENTITLEMENT)
	assert_int(_backend.interstitial_calls).is_equal(0)


func test_interstitial_no_fill_does_not_reset_cap() -> void:
	var svc = _make(2, 60)
	_backend.interstitial_result = AD_BACKEND.InterstitialResult.NO_FILL
	_complete_levels(svc, 2)
	var outcome: int = svc.maybe_show_interstitial()
	assert_int(outcome).is_equal(AD_SCRIPT.InterstitialOutcome.NO_FILL)
	assert_int(_backend.interstitial_calls).is_equal(1)
	# Counter NOT reset — the boundary retries next time rather than restarting the window.
	assert_int(svc.levels_since_interstitial()).is_equal(2)


func test_interstitial_disabled_when_every_n_is_zero() -> void:
	var svc = _make(0, 60)  # 0 disables interstitials
	_complete_levels(svc, 5)
	var outcome: int = svc.maybe_show_interstitial()
	assert_int(outcome).is_equal(AD_SCRIPT.InterstitialOutcome.SUPPRESSED_FREQUENCY)
	assert_int(_backend.interstitial_calls).is_equal(0)


# ---------------------------------------------------------------------------
# Rewarded earn-in
# ---------------------------------------------------------------------------

func test_rewarded_completed_credits_config_amount_once() -> void:
	var svc = _make()
	svc.rewarded_earned.connect(_on_rewarded_earned)
	var credited: int = svc.show_rewarded()
	assert_int(credited).is_equal(60)
	# Routed through WalletService._earn_rewarded_ad with the config amount, exactly once.
	assert_int(_wallet.rewarded_amounts.size()).is_equal(1)
	assert_int(_wallet.rewarded_amounts[0]).is_equal(60)  # EconomyConfig.coins_rewarded_ad
	assert_int(_rewarded_coins.size()).is_equal(1)
	assert_int(_rewarded_coins[0]).is_equal(60)


func test_rewarded_dismissed_before_completion_no_earn() -> void:
	var svc = _make()
	_backend.rewarded_completes = false  # player abandoned the ad
	var credited: int = svc.show_rewarded()
	assert_int(credited).is_equal(0)
	assert_int(_wallet.rewarded_amounts.size()).is_equal(0)


func test_rewarded_unavailable_does_not_consume_or_earn() -> void:
	var svc = _make()
	_wallet.ad_available = false  # daily cap reached / restricted (wallet's verdict)
	var credited: int = svc.show_rewarded()
	assert_int(credited).is_equal(0)
	assert_int(_wallet.rewarded_amounts.size()).is_equal(0)


func test_rewarded_credited_zero_when_wallet_caps_it_no_signal() -> void:
	var svc = _make()
	svc.rewarded_earned.connect(_on_rewarded_earned)
	_wallet.rewarded_return = 0  # wallet credited nothing (hit a cap inside _earn_rewarded_ad)
	var credited: int = svc.show_rewarded()
	assert_int(credited).is_equal(0)
	assert_int(_rewarded_coins.size()).is_equal(0)  # no rewarded_earned emitted for a 0 credit


func test_is_rewarded_available_reflects_wallet_and_entitlement() -> void:
	var svc = _make()
	assert_bool(svc.is_rewarded_available()).is_true()
	_wallet.ad_available = false
	assert_bool(svc.is_rewarded_available()).is_false()
	_wallet.ad_available = true
	_entitlement.rewarded_ok = false
	assert_bool(svc.is_rewarded_available()).is_false()


# ---------------------------------------------------------------------------
# Ad-type resolution (audience × consent half of the triple gate — S4-004b)
# ---------------------------------------------------------------------------

func test_interstitial_personalized_when_targeted_ads_allowed() -> void:
	var svc = _make(2, 60)
	svc.interstitial_shown.connect(_on_interstitial_shown)
	_compliance.targeted_ok = true  # ADULT + personalized consent
	_complete_levels(svc, 2)
	assert_int(svc.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)
	assert_int(_backend.last_ad_type).is_equal(AD_SCRIPT.AdType.PERSONALIZED)
	assert_array(_shown_types).is_equal([AD_SCRIPT.AdType.PERSONALIZED])


func test_interstitial_contextual_when_targeted_ads_denied() -> void:
	var svc = _make(2, 60)
	svc.interstitial_shown.connect(_on_interstitial_shown)
	_compliance.targeted_ok = false  # non-adult OR personalized consent denied
	_complete_levels(svc, 2)
	assert_int(svc.maybe_show_interstitial()).is_equal(AD_SCRIPT.InterstitialOutcome.SHOWN)
	assert_int(_backend.last_ad_type).is_equal(AD_SCRIPT.AdType.CONTEXTUAL)
	assert_array(_shown_types).is_equal([AD_SCRIPT.AdType.CONTEXTUAL])


func test_resolve_ad_type_reflects_compliance_verdict() -> void:
	var svc = _make()
	_compliance.targeted_ok = true
	assert_int(svc.resolve_ad_type()).is_equal(AD_SCRIPT.AdType.PERSONALIZED)
	_compliance.targeted_ok = false
	assert_int(svc.resolve_ad_type()).is_equal(AD_SCRIPT.AdType.CONTEXTUAL)
