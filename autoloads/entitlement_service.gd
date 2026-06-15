extends Node
## Autoload: Remove-Ads entitlement ownership and interstitial suppression (S4-003, ADR-0014 §3).
##
## This is the ONLY code permitted to read [member SaveData.remove_ads_owned]. Every
## ad-surface decision about whether interstitials are suppressed must call
## [method should_suppress_interstitials] — never read the field directly — so the
## entitlement gating is enforced in exactly one place. This mirrors the chokepoint
## invariant that [ComplianceService] establishes for [member SaveData.age_band] and the
## consent fields (ADR-0013 §2, ADR-0014 §3).
##
## [b]Entitlement semantics:[/b] once owned, Remove-Ads is permanent for the session
## and persisted across restarts. Owned is owned — the entitlement is NEVER silently
## revoked mid-session, even if a save-write fails (QA EC4/EC15).
##
## [b]Rewarded ads:[/b] rewarded ads remain available even when Remove-Ads is owned
## (GAME_PLAN §8). Only interstitials are suppressed.
##
## [b]Restore-across-reinstall:[/b] [method restore] queries the injected
## [EntitlementBackend] for a prior platform receipt and calls [method grant_remove_ads]
## if found. The base [EntitlementBackend] is a no-op (returns false); tests and the
## future native backend inject a subclass via [method configure].
##
## Dependencies injected via [method configure] (DI seam, ADR-0014 §1):
## - [SaveService]-compatible object: must expose [code]data: SaveData[/code] and
##   [code]save_game() -> void[/code].
## - [EntitlementBackend]: receipt-restore query (mock default, native backend deferred).
##
## Usage (IAPService grants on Remove-Ads SKU purchase, S4-002):
## [codeblock]
## EntitlementService.grant_remove_ads()
## [/codeblock]
##
## Usage (AdService gate, S4-004):
## [codeblock]
## if EntitlementService.should_suppress_interstitials():
##     return  # skip interstitial
## [/codeblock]
##
## Source: ADR-0014 §1 (uniform seam), §3 (EntitlementService), GAME_PLAN §8.

# Preloaded so the type is available at parse time (autoloads parse before the global
# class DB stabilises; explicit preload is the reliable pattern here).
const EntitlementBackendClass := preload("res://autoloads/entitlement_backend.gd")

## Emitted when the Remove-Ads entitlement transitions from not-owned to owned.
## [param owned] is always [code]true[/code] on this signal — entitlement never revokes
## mid-session, so the signal fires at most once per session (on grant or restore).
## Consumers (deferred monetization UI) listen here to hide interstitial surfaces.
signal remove_ads_changed(owned: bool)

# --- injected dependencies ---
# Resolves to the SaveService autoload and a no-op EntitlementBackend in _ready()
# if configure() was not called first (normal play).
var _save = null       # SaveService-compatible: .data (SaveData) + save_game()
var _backend = null    # EntitlementBackend — untyped to avoid parse-time resolution issues;
                       # runtime type checked via duck-typing (has_prior_receipt())


func _ready() -> void:
	if _save == null:
		_save = SaveService
	if _backend == null:
		_backend = EntitlementBackendClass.new()


## Injects dependencies. Intended for tests; call before any other method.
##
## [param save] must expose [code]data: SaveData[/code] and [code]save_game() -> void[/code]
## (matches the [SaveService] interface). [param backend] must expose
## [code]has_prior_receipt() -> bool[/code] (matches [EntitlementBackend]).
## Use [code]EntitlementBackend.MockEntitlementBackend.new()[/code] in tests.
##
## Example:
## [codeblock]
## var backend := EntitlementBackend.MockEntitlementBackend.new()
## backend.receipt_present = true
## entitlement_svc.configure(save_svc, backend)
## [/codeblock]
func configure(save: Object, backend: Object) -> void:
	_save = save
	_backend = backend


# --- queries ---

## Returns [code]true[/code] if the player owns the Remove-Ads entitlement.
##
## This is the SOLE reader of [member SaveData.remove_ads_owned] outside [SaveData]
## itself. Reads the live [SaveData] field so the value is always current — no
## caching, no stale state. Returns [code]false[/code] when no save is wired
## (fail-closed / not-owned default, ADR-0014 §3).
func is_remove_ads_owned() -> bool:
	if _save == null or _save.data == null:
		return false
	return _save.data.remove_ads_owned


## Returns [code]true[/code] when interstitials should be suppressed.
##
## True when and only when the player owns Remove-Ads. [AdService] (S4-004) calls this
## as part of the triple gate (compliance × consent × entitlement) before showing an
## interstitial. Rewarded ads are NOT suppressed — call [method is_rewarded_available]
## separately for those (GAME_PLAN §8).
func should_suppress_interstitials() -> bool:
	return is_remove_ads_owned()


## Returns [code]true[/code]: rewarded ads are ALWAYS available, even when Remove-Ads
## is owned (GAME_PLAN §8: "Remove-Ads keeps optional rewarded").
##
## Availability of the actual ad placement is further gated by
## [method WalletService.is_ad_earn_available] (daily cap + compliance). This method
## captures only the entitlement policy: Remove-Ads does NOT suppress rewarded.
func is_rewarded_available() -> bool:
	return true


# --- mutations ---

## Grants the Remove-Ads entitlement: sets [member SaveData.remove_ads_owned] to
## [code]true[/code] and persists. Idempotent — if already owned, the call is a no-op
## (no redundant save, no duplicate signal).
##
## On a save-write failure, the in-memory field is still set to [code]true[/code] so
## the player retains the entitlement for the remainder of the session. The next launch
## will re-present the restore flow (QA EC4/EC15: "owned is owned mid-session").
##
## Called by [IAPService] (S4-002) on a successful Remove-Ads SKU purchase, and by
## [method restore] when a prior receipt is found.
func grant_remove_ads() -> void:
	if _save == null or _save.data == null:
		return
	if _save.data.remove_ads_owned:
		return  # Idempotent: already owned — no write, no signal
	_save.data.remove_ads_owned = true
	# Attempt to persist. On failure, in-memory value remains true (EC4/EC15).
	# save_game() logs its own error; we do not propagate it.
	_save.save_game()
	remove_ads_changed.emit(true)


## Attempts to restore the Remove-Ads entitlement from a prior purchase receipt.
##
## Queries the injected [EntitlementBackend] for a prior platform receipt. If one is
## found, calls [method grant_remove_ads] (idempotent — already-owned is a safe no-op).
## Returns [code]true[/code] if the restore resulted in (or confirmed) the entitlement
## being owned; [code]false[/code] if no prior receipt was found.
##
## This is the stub for the S4-003 restore-across-reinstall requirement (ADR-0014 §3).
## The [EntitlementBackend] base always returns [code]false[/code]; the native backend
## (future GDExtension) queries the platform receipt store. Tests inject a
## [EntitlementBackend.MockEntitlementBackend] with [code]receipt_present = true[/code].
func restore() -> bool:
	if _backend == null:
		return false
	if not _backend.has_prior_receipt():
		return false
	grant_remove_ads()
	return true
