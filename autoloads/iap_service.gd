extends Node
## Autoload: IAP purchase state machine and receipt restore (S4-002, ADR-0014 §2).
##
## Owns the deterministic purchase state machine (IDLE → PENDING → SUCCESS / FAILED)
## and the restore path for non-consumable entitlements (Remove-Ads). On a verified
## successful purchase, currency packs are credited via [method WalletService.grant_iap_currency]
## (the uncapped IAP credit path) and Remove-Ads via [method EntitlementService.grant_remove_ads].
## No wallet mutation lives here — all economy outcomes go through those service call-ins
## (ADR-0008, ADR-0014 §2).
##
## All dependencies are injected via [method configure] (DI seam, ADR-0014 §1) so this
## service is fully unit-testable headlessly. In normal play they resolve to the autoloads
## in [method _ready], mirroring [WalletService] and [ComplianceService].
##
## [b]Catalog:[/b] the injected catalog maps SKU token → [IAPCatalogEntry] (kind + grant
## amounts). The default placeholder catalog is marked "S4-006 will replace this". Tests
## always inject their own catalog to remain data-independent of the placeholder.
##
## [b]State machine rules:[/b]
## - Only one purchase may be in-flight at a time (PENDING blocks new purchases).
## - Success is idempotent within one purchase cycle — the grant fires exactly once.
## - Failed mid-flight returns the service to IDLE with the wallet unchanged.
## - Restore re-grants non-consumables only; consumable SKUs are silently ignored.
##
## Usage (normal play — autoloads auto-resolved):
## [codeblock]
## IAPService.purchase(IAPService.SKU_REMOVE_ADS)
## [/codeblock]
##
## Usage (tests — inject a mock):
## [codeblock]
## var backend := IAPBackend.MockIAPBackend.new()
## backend.next_result = IAPBackend.PurchaseResult.SUCCESS
## iap_svc.configure(wallet_svc, compliance_svc, entitlement_svc, backend, catalog)
## var ok: bool = iap_svc.purchase(IAPService.SKU_REMOVE_ADS)
## [/codeblock]
##
## Source: ADR-0014 §1 (uniform seam), §2 (state machine + restore), GAME_PLAN §8.

## Placeholder SKU tokens (S4-006 authors the real catalog resource).
## These constants let tests and normal play reference SKUs symbolically so no
## magic integer is scattered across callers.
const SKU_REMOVE_ADS: int = 1     ## Non-consumable: suppresses interstitials, keeps rewarded.
const SKU_COINS_SMALL: int = 100  ## Consumable: small coin pack.
const SKU_COINS_MEDIUM: int = 101 ## Consumable: medium coin pack.
const SKU_GEMS_SMALL: int = 200   ## Consumable: small gem pack.

## Preloaded so the type resolves at autoload parse time (global class cache is not
## yet stable when autoloads parse — explicit preload is the reliable pattern).
const IAPBackendClass := preload("res://autoloads/iap_backend.gd")


# ---------------------------------------------------------------------------
# Inner types
# ---------------------------------------------------------------------------

## Describes one entry in the IAP catalog: what kind of product, and what to
## grant on success. S4-006 will load this from a .tres resource; for now it is
## a plain RefCounted so tests can build it in-memory without file I/O.
class IAPCatalogEntry extends RefCounted:
	## Whether this SKU is a consumable (currency pack) or non-consumable (entitlement).
	var kind: ProductKind = ProductKind.CONSUMABLE_CURRENCY
	## [EconomyEnums.Currency] value — valid only when [member kind] is [constant CONSUMABLE_CURRENCY].
	var currency: int = EconomyEnums.Currency.COINS
	## Amount to credit — valid only when [member kind] is [constant CONSUMABLE_CURRENCY].
	var amount: int = 0

	## Factory: build a consumable-currency entry.
	static func make_currency(p_currency: int, p_amount: int) -> IAPCatalogEntry:
		var e := IAPCatalogEntry.new()
		e.kind = ProductKind.CONSUMABLE_CURRENCY
		e.currency = p_currency
		e.amount = p_amount
		return e

	## Factory: build a non-consumable (entitlement) entry.
	static func make_entitlement() -> IAPCatalogEntry:
		var e := IAPCatalogEntry.new()
		e.kind = ProductKind.NON_CONSUMABLE_ENTITLEMENT
		return e


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

## Product kind — drives the grant path on success and the restore-eligibility check.
enum ProductKind {
	CONSUMABLE_CURRENCY,       ## Currency pack: grant via WalletService.grant_iap_currency(); not restored.
	NON_CONSUMABLE_ENTITLEMENT ## Remove-Ads: grant via EntitlementService.grant_remove_ads(); restorable.
}

## Explicit purchase state machine states (ADR-0014 §2).
## Only IDLE may begin a new purchase; only PENDING may succeed or fail.
enum State {
	IDLE,    ## No purchase in-flight; ready to accept a new purchase request.
	PENDING, ## A purchase is in-flight with the backend.
	SUCCESS, ## The most recent purchase completed successfully (grant has been issued).
	FAILED,  ## The most recent purchase failed or was cancelled.
}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when a purchase completes (success or failure) or a restore runs.
## The deferred monetization UI subscribes to this signal (model/view seam, ADR-0001).
## [param sku]: the SKU token that was purchased/restored/failed.
## [param outcome]: a [enum State] value (SUCCESS, FAILED) indicating the result.
signal purchase_completed(sku: int, outcome: int)

## Emitted when a restore run completes.
## [param restored_count]: number of non-consumable SKUs that were re-granted.
signal restore_completed(restored_count: int)


# ---------------------------------------------------------------------------
# Injected dependencies (resolve to autoloads in _ready() if not configured)
# ---------------------------------------------------------------------------

var _wallet = null           # WalletService: grant_iap_currency(currency, amount) + economy_event
var _compliance = null       # ComplianceService: can_process_iap()
var _entitlement = null      # EntitlementService: grant_remove_ads()
# Typed via the preloaded const (not the global class_name) so the type resolves at
# autoload parse time AND purchase()/restore() are compile-time checked.
var _backend: IAPBackendClass = null
## The active catalog: maps SKU int → [IAPCatalogEntry]. Injected via [method configure];
## defaults to the placeholder catalog in [method _ready].
var _catalog: Dictionary = {}


# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

## Current state of the purchase machine. Read-only externally; only internal
## methods transition it.
var _state: State = State.IDLE


func _ready() -> void:
	if _wallet == null:
		_wallet = WalletService
	if _compliance == null:
		_compliance = ComplianceService
	if _entitlement == null:
		_entitlement = EntitlementService
	if _backend == null:
		_backend = IAPBackendClass.new()
	if _catalog.is_empty():
		_catalog = _build_placeholder_catalog()


## Injects all dependencies. Intended for tests; call before any other method.
## [param wallet]: WalletService-compatible (must expose [method grant_iap_currency] and
## the [signal economy_event] signal). [param compliance]: ComplianceService-compatible
## ([method can_process_iap]). [param entitlement]: EntitlementService-compatible
## ([method grant_remove_ads]). [param backend]: [IAPBackend]-compatible.
## [param catalog]: Dictionary[int, IAPCatalogEntry] mapping SKU → entry; pass an
## empty dict to use the placeholder catalog (not recommended for tests).
##
## Example:
## [codeblock]
## var backend := IAPBackend.MockIAPBackend.new()
## backend.next_result = IAPBackend.PurchaseResult.SUCCESS
## iap_svc.configure(wallet, compliance, entitlement, backend, catalog)
## [/codeblock]
func configure(
		wallet: Object,
		compliance: Object,
		entitlement: Object,
		backend: IAPBackendClass,
		catalog: Dictionary,
) -> void:
	_wallet = wallet
	_compliance = compliance
	_entitlement = entitlement
	_backend = backend
	_catalog = catalog if not catalog.is_empty() else _build_placeholder_catalog()
	_state = State.IDLE


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

## Returns the current state machine state. Useful for tests and UI polling.
func current_state() -> State:
	return _state


## Returns true if [param sku] is a known, valid SKU in the catalog.
func is_valid_sku(sku: int) -> bool:
	return _catalog.has(sku)


# ---------------------------------------------------------------------------
# Purchase flow (ADR-0014 §2)
# ---------------------------------------------------------------------------

## Initiates an IAP purchase for [param sku].
##
## Gate order (all gates checked before transitioning to PENDING):
## 1. Compliance gate: [method ComplianceService.can_process_iap] must be true;
##    if false, emits [code]IAP_BLOCKED(sku, COMPLIANCE_RESTRICTED)[/code] via
##    [WalletService.economy_event] and returns [code]false[/code] (state stays IDLE).
## 2. Unknown/invalid SKU: returns [code]false[/code] immediately, no state change.
## 3. Already PENDING: returns [code]false[/code] (one purchase at a time).
##
## On SUCCESS: grants exactly once — consumable → [method WalletService.grant_iap_currency];
## non-consumable → [method EntitlementService.grant_remove_ads]. State → SUCCESS,
## then immediately resets to IDLE so the service accepts a new purchase.
##
## On FAILED: wallet unchanged, state returns to IDLE.
##
## Returns [code]true[/code] if the backend reported success and the grant was issued;
## [code]false[/code] on any gate failure or backend failure.
##
## Source: ADR-0014 §2; design/gdd/deck-economy.md Rule 5/6, AC-CL01.
func purchase(sku: int) -> bool:
	# --- Gate 1: compliance (fail-closed — a missing/unresolved compliance dep blocks) ---
	if _compliance == null or not _compliance.can_process_iap():
		if _wallet != null:
			_wallet.economy_event.emit(
					EconomyEvent.iap_blocked(sku, EconomyEnums.FailReason.COMPLIANCE_RESTRICTED))
		purchase_completed.emit(sku, State.FAILED)
		return false

	# --- Gate 2: valid SKU ---
	if not _catalog.has(sku):
		purchase_completed.emit(sku, State.FAILED)
		return false

	# --- Gate 3: not already PENDING ---
	if _state == State.PENDING:
		purchase_completed.emit(sku, State.FAILED)
		return false

	# --- Gate 4: the grant dependency for this SKU's kind must be wired ---
	# Refuse before charging the backend rather than reporting a false SUCCESS with no
	# grant when a required service was never injected (fail-closed; review S4-002 #2).
	var entry: IAPCatalogEntry = _catalog[sku]
	if entry.kind == ProductKind.CONSUMABLE_CURRENCY and _wallet == null:
		purchase_completed.emit(sku, State.FAILED)
		return false
	if entry.kind == ProductKind.NON_CONSUMABLE_ENTITLEMENT and _entitlement == null:
		purchase_completed.emit(sku, State.FAILED)
		return false

	# --- Transition: IDLE → PENDING ---
	_state = State.PENDING

	# --- Drive the backend ---
	var result: int = _backend.purchase(sku)

	# --- Handle result (State.SUCCESS/FAILED are transient outcome codes carried by
	# purchase_completed; the machine itself only ever rests in IDLE or PENDING) ---
	_state = State.IDLE
	if result == IAPBackendClass.PurchaseResult.SUCCESS:
		_apply_grant(sku)
		purchase_completed.emit(sku, State.SUCCESS)
		return true
	# FAILED or CANCELLED — wallet/entitlement unchanged
	purchase_completed.emit(sku, State.FAILED)
	return false


# ---------------------------------------------------------------------------
# Restore flow (ADR-0014 §2: non-consumables only)
# ---------------------------------------------------------------------------

## Attempts to restore prior non-consumable purchases (Remove-Ads) from the
## platform receipt store via the injected [IAPBackend].
##
## Re-grants [b]non-consumables only[/b] (Remove-Ads → [method EntitlementService.grant_remove_ads]).
## Consumable currency packs in the catalog are silently ignored — they were already
## spent/credited and must NOT be re-granted (ADR-0014 §2).
##
## Returns [code]true[/code] if at least one non-consumable was re-granted;
## [code]false[/code] if no prior receipts were found (no grant, no error).
## Emits [signal restore_completed] with the count of re-granted SKUs.
func restore() -> bool:
	var prior_skus: Array[int] = _backend.restore()
	var granted: int = 0
	for sku: int in prior_skus:
		if not _catalog.has(sku):
			continue
		var entry: IAPCatalogEntry = _catalog[sku]
		# Consumable SKUs are never restored (already spent/credited — ADR-0014 §2).
		if entry.kind != ProductKind.NON_CONSUMABLE_ENTITLEMENT:
			continue
		# Count only entitlements actually NEWLY granted: the grant call returns false when
		# it no-ops (already owned, or no save wired), so re-restoring must not inflate the
		# restored count or the return value (review S4-002 #3).
		if _apply_entitlement_grant(sku):
			granted += 1
	restore_completed.emit(granted)
	return granted > 0


# ---------------------------------------------------------------------------
# Grant helpers (called only on verified SUCCESS — ADR-0014 §2)
# ---------------------------------------------------------------------------

# Dispatches the grant to the appropriate path based on the catalog entry kind.
# Called exactly once per SUCCESS transition.
func _apply_grant(sku: int) -> void:
	var entry: IAPCatalogEntry = _catalog[sku]
	match entry.kind:
		ProductKind.CONSUMABLE_CURRENCY:
			_apply_currency_grant(sku, entry)
		ProductKind.NON_CONSUMABLE_ENTITLEMENT:
			_apply_entitlement_grant(sku)


# Credits the currency pack amount via WalletService.grant_iap_currency() — the uncapped
# IAP credit path, so a player near the wallet cap still receives the full paid pack
# (review S4-002 #1). grant_iap_currency() guards amount <= 0 internally.
func _apply_currency_grant(_sku: int, entry: IAPCatalogEntry) -> void:
	if _wallet != null:
		_wallet.grant_iap_currency(entry.currency, entry.amount)


# Grants the Remove-Ads (non-consumable) entitlement. Idempotent — safe to call on
# restore when the entitlement is already owned. Returns true only when this call newly
# granted it (false on a no-op), so restore() can count real grants.
func _apply_entitlement_grant(_sku: int) -> bool:
	if _entitlement != null:
		return _entitlement.grant_remove_ads()
	return false


# ---------------------------------------------------------------------------
# Placeholder catalog (S4-006 authors the real .tres — this is a temp stub)
# ---------------------------------------------------------------------------

## [b]Placeholder catalog — replaced by S4-006.[/b]
## Provides enough structure for the service to function (autoload, smoke tests)
## without hardcoding grant amounts in purchase logic. S4-006 will load this
## from an injected IAPCatalog resource; until then these sane defaults serve CI.
func _build_placeholder_catalog() -> Dictionary:
	var cat: Dictionary = {}
	cat[SKU_REMOVE_ADS] = IAPCatalogEntry.make_entitlement()
	cat[SKU_COINS_SMALL] = IAPCatalogEntry.make_currency(EconomyEnums.Currency.COINS, 500)
	cat[SKU_COINS_MEDIUM] = IAPCatalogEntry.make_currency(EconomyEnums.Currency.COINS, 1500)
	cat[SKU_GEMS_SMALL] = IAPCatalogEntry.make_currency(EconomyEnums.Currency.GEMS, 50)
	return cat
