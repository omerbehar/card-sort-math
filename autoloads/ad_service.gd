extends Node
## Autoload: ad presentation — rewarded earn-in + interstitial frequency cap (S4-004a, ADR-0014 §"AdService").
##
## Two ad surfaces, both behind an injectable [AdBackend] (no native SDK this sprint):
##
## [b]Rewarded[/b] — an opt-in upside. [method show_rewarded] presents a rewarded ad and,
## on a completed view, routes the reward through [method WalletService._earn_rewarded_ad]
## (the existing economy chokepoint that owns the compliance + daily-cap policy — this
## service does NOT re-implement it). The reward amount comes from
## [member EconomyConfig.coins_rewarded_ad] (never hardcoded).
##
## [b]Interstitial[/b] — frequency-capped via [method maybe_show_interstitial]: shown no more
## often than every [member EconomyConfig.interstitial_every_n_levels] level completions AND
## at least [member EconomyConfig.interstitial_min_seconds] apart, the interval measured via
## the injected [TimeProvider] (deterministic, never [code]Time.*[/code] — ADR-0009). Suppressed
## entirely while the Remove-Ads entitlement is owned (S4-003), and never presented during
## active arithmetic (GAME_PLAN §9 "no ad mid-puzzle").
##
## [b]Triple gate (S4-004a + S4-004b):[/b] interstitials are gated by Remove-Ads entitlement
## (suppress, S4-003) + the frequency cap, and targeted by the audience × consent verdict —
## personalized only for an ADULT with personalized-ads consent, contextual for everyone else
## (ADR-0013 / ADR-0005). All dependencies are injected via [method configure] (DI, ADR-0014 §1).
##
## Source: ADR-0014 §1/§"AdService", GAME_PLAN §9, design/gdd/deck-economy.md Rule 15/Formula 8.

## Preloaded so the backend type resolves at autoload parse time (the global class cache
## is not yet stable when autoloads parse — explicit preload is the reliable pattern).
const AdBackendClass := preload("res://autoloads/ad_backend.gd")

## Path used by [method _ready] to resolve the tuning config when not injected.
const DEFAULT_CONFIG_PATH := "res://assets/data/economy_config.tres"


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

## Outcome of an interstitial request — richer than a bool so callers/tests can
## distinguish why an ad was not shown.
enum InterstitialOutcome {
	SHOWN,                  ## An interstitial was presented; counters reset.
	SUPPRESSED_PUZZLE,      ## A puzzle is active — never interrupt arithmetic (GAME_PLAN §9).
	SUPPRESSED_ENTITLEMENT, ## Remove-Ads is owned — interstitials suppressed (S4-003).
	SUPPRESSED_FREQUENCY,   ## The every-N-levels / min-seconds frequency cap is not yet satisfied.
	NO_FILL,                ## All gates passed but the backend reported no ad available.
}

## How an ad request may be targeted (S4-004b triple gate, ADR-0013 consent × ADR-0005 audience).
enum AdType {
	PERSONALIZED, ## Behavioural targeting — permitted only for ADULT + personalized-ads consent.
	CONTEXTUAL,   ## Non-personalized — the privacy-safe default for everyone else.
}


# ---------------------------------------------------------------------------
# Signals (the deferred monetization UI subscribes — model/view seam, ADR-0001)
# ---------------------------------------------------------------------------

## Emitted when an interstitial is actually presented.
## [param ad_type]: the [enum AdType] requested (personalized vs contextual).
signal interstitial_shown(ad_type: int)

## Emitted when a rewarded ad is completed and the reward credited.
## [param coins]: coins actually credited (after WalletService's compliance + daily caps).
signal rewarded_earned(coins: int)


# ---------------------------------------------------------------------------
# Injected dependencies (resolve to autoloads in _ready() if not configured)
# ---------------------------------------------------------------------------

var _wallet = null        # WalletService: is_ad_earn_available() + _earn_rewarded_ad(amount)
var _compliance = null    # ComplianceService: can_show_targeted_ads() (personalized vs contextual)
var _entitlement = null   # EntitlementService: should_suppress_interstitials() + is_rewarded_available()
var _time: TimeProvider = null
var _config: EconomyConfig = null
# Typed via the preloaded const (not the global class_name) so it resolves at autoload
# parse time AND the backend calls are compile-time checked.
var _backend: AdBackendClass = null


# ---------------------------------------------------------------------------
# Frequency-cap state (in-memory; session-scoped — no save migration this story)
# ---------------------------------------------------------------------------

## Level completions counted since the last interstitial was shown.
var _levels_since_interstitial: int = 0
## Unix timestamp of the last shown interstitial; -1 means "none shown yet".
var _last_interstitial_unix: int = -1
## True while a puzzle is being played — interstitials are refused (no mid-puzzle ads).
var _puzzle_active: bool = false


func _ready() -> void:
	if _wallet == null:
		_wallet = WalletService
	if _compliance == null:
		_compliance = ComplianceService
	if _entitlement == null:
		_entitlement = EntitlementService
	if _time == null:
		_time = TimeProvider.new()
	if _config == null:
		var loader: Node = get_node_or_null("/root/EconomyConfigLoader")
		_config = loader.get_config() if loader != null else load(DEFAULT_CONFIG_PATH)
	if _backend == null:
		_backend = AdBackendClass.new()


## Injects all dependencies. Intended for tests; call before any other method.
## [param wallet]: WalletService-compatible ([method is_ad_earn_available] +
## [method _earn_rewarded_ad]). [param compliance]: ComplianceService-compatible
## ([method can_show_targeted_ads]). [param entitlement]: EntitlementService-compatible
## ([method should_suppress_interstitials] + [method is_rewarded_available]).
## [param time]: a [TimeProvider] (inject a [FixedTimeProvider] in tests).
## [param config]: an [EconomyConfig] supplying the ad tuning knobs.
## [param backend]: an [AdBackend]-compatible presenter.
func configure(
		wallet: Object,
		compliance: Object,
		entitlement: Object,
		time: TimeProvider,
		config: EconomyConfig,
		backend: AdBackendClass,
) -> void:
	_wallet = wallet
	_compliance = compliance
	_entitlement = entitlement
	_time = time
	_config = config
	_backend = backend
	_levels_since_interstitial = 0
	_last_interstitial_unix = -1
	_puzzle_active = false


# ---------------------------------------------------------------------------
# Level lifecycle (drives the frequency cap + the no-mid-puzzle guard)
# ---------------------------------------------------------------------------

## Marks a puzzle as in-progress. While active, [method maybe_show_interstitial] refuses
## to present an ad (GAME_PLAN §9: never interrupt active arithmetic).
func notify_level_started() -> void:
	_puzzle_active = true


## Marks the current puzzle as finished and counts it toward the every-N-levels cadence.
## Call this at the level-complete boundary, then [method maybe_show_interstitial].
func notify_level_completed() -> void:
	_puzzle_active = false
	_levels_since_interstitial += 1


# ---------------------------------------------------------------------------
# Interstitial (triple gate: compliance × consent × entitlement, + frequency cap)
# ---------------------------------------------------------------------------

## Considers presenting an interstitial at a between-levels boundary and returns the
## [enum InterstitialOutcome]. Gates, in order: puzzle-active → entitlement suppression →
## frequency cap (every-N-levels AND min-seconds). When all pass, the request is targeted
## per [method resolve_ad_type] (the audience × consent half of the triple gate, S4-004b):
## [constant AdType.PERSONALIZED] only for an ADULT with personalized-ads consent, else
## [constant AdType.CONTEXTUAL]. A [constant InterstitialOutcome.NO_FILL] result leaves the
## counters untouched so the next boundary retries. Emits [signal interstitial_shown] with
## the requested [enum AdType] only on an actual presentation.
func maybe_show_interstitial() -> int:
	if _puzzle_active:
		return InterstitialOutcome.SUPPRESSED_PUZZLE
	if _entitlement != null and _entitlement.should_suppress_interstitials():
		return InterstitialOutcome.SUPPRESSED_ENTITLEMENT
	if not _frequency_allows():
		return InterstitialOutcome.SUPPRESSED_FREQUENCY

	var ad_type: int = resolve_ad_type()
	if _backend.show_interstitial(ad_type) != AdBackendClass.InterstitialResult.SHOWN:
		return InterstitialOutcome.NO_FILL  # no-fill: do not reset the cap, retry next boundary

	_last_interstitial_unix = _time.unix_seconds()
	_levels_since_interstitial = 0
	interstitial_shown.emit(ad_type)
	return InterstitialOutcome.SHOWN


## Resolves how an ad request may be targeted (the audience × consent half of the triple
## gate, S4-004b). Returns [constant AdType.PERSONALIZED] only when
## [method ComplianceService.can_show_targeted_ads] is true (ADULT + personalized-ads
## consent — ADR-0013 §2 / ADR-0005); otherwise [constant AdType.CONTEXTUAL]. Fails safe to
## CONTEXTUAL when no compliance service is wired (privacy-safe default).
func resolve_ad_type() -> int:
	if _compliance != null and _compliance.can_show_targeted_ads():
		return AdType.PERSONALIZED
	return AdType.CONTEXTUAL


# True when BOTH the every-N-levels and the min-seconds windows are satisfied.
# interstitial_every_n_levels <= 0 disables interstitials entirely (config switch).
func _frequency_allows() -> bool:
	if _config.interstitial_every_n_levels <= 0:
		return false
	if _levels_since_interstitial < _config.interstitial_every_n_levels:
		return false
	if _last_interstitial_unix >= 0:
		var elapsed: int = _time.unix_seconds() - _last_interstitial_unix
		if elapsed < _config.interstitial_min_seconds:
			return false
	return true


# ---------------------------------------------------------------------------
# Rewarded (opt-in earn-in — routes through the WalletService chokepoint)
# ---------------------------------------------------------------------------

## Returns whether a rewarded ad can currently earn: the wallet's daily/compliance gate
## ([method WalletService.is_ad_earn_available]) allows it AND the entitlement layer keeps
## rewarded available (Remove-Ads keeps rewarded — S4-003).
func is_rewarded_available() -> bool:
	if _wallet == null or not _wallet.is_ad_earn_available():
		return false
	if _entitlement != null and not _entitlement.is_rewarded_available():
		return false
	return true


## Presents a rewarded ad; on a completed view, credits the configured reward through
## [method WalletService._earn_rewarded_ad] (which owns the compliance + daily-cap policy).
## Returns the coins actually credited — [code]0[/code] when unavailable, abandoned, or
## fully capped (no view is "spent" for nothing; the wallet refuses past the cap). Emits
## [signal rewarded_earned] only when coins were credited.
func show_rewarded() -> int:
	if not is_rewarded_available():
		return 0
	if not _backend.show_rewarded():
		return 0  # dismissed / abandoned / no-fill — no earn
	var credited: int = _wallet._earn_rewarded_ad(_config.coins_rewarded_ad)
	if credited > 0:
		rewarded_earned.emit(credited)
	return credited


# ---------------------------------------------------------------------------
# Queries (tests / UI)
# ---------------------------------------------------------------------------

## Level completions counted since the last interstitial (frequency-cap introspection).
func levels_since_interstitial() -> int:
	return _levels_since_interstitial
