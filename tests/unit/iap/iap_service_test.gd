extends GdUnitTestSuite
## Unit tests for [IAPService] — purchase state machine + grant routing (S4-002, ADR-0014 §2).
##
## Drives a real [IAPService] with injected stub collaborators (wallet / compliance /
## entitlement) and a [IAPBackend.MockIAPBackend] so every state-machine path and grant
## route runs deterministically and headlessly. Catalog is injected (no dependency on the
## placeholder or the S4-006 resource).

const IAP_SCRIPT := preload("res://autoloads/iap_service.gd")
const IAP_BACKEND := preload("res://autoloads/iap_backend.gd")


# --- Local test doubles -----------------------------------------------------

class StubWallet extends RefCounted:
	signal economy_event(event: EconomyEvent)
	var earn_calls: Array = []  # each entry: [currency, amount, source]
	func earn(currency: int, amount: int, source: int) -> int:
		earn_calls.append([currency, amount, source])
		return amount


class StubCompliance extends RefCounted:
	var iap_ok: bool = true  # can_process_iap() result (consent x age)
	func can_process_iap() -> bool:
		return iap_ok


class StubEntitlement extends RefCounted:
	var grant_calls: int = 0
	func grant_remove_ads() -> void:
		grant_calls += 1


# --- Fixture members (set by _make) -----------------------------------------

var _wallet: StubWallet
var _compliance: StubCompliance
var _entitlement: StubEntitlement
var _backend  # IAPBackend.MockIAPBackend (untyped: inner-class access yields Variant)
var _captured_events: Array = []


func _capture_event(e) -> void:
	_captured_events.append(e)


# A two-SKU catalog: a consumable coin pack and the non-consumable Remove-Ads entitlement.
func _catalog() -> Dictionary:
	var cat: Dictionary = {}
	cat[IAP_SCRIPT.SKU_COINS_SMALL] = IAP_SCRIPT.IAPCatalogEntry.make_currency(
			EconomyEnums.Currency.COINS, 500)
	cat[IAP_SCRIPT.SKU_REMOVE_ADS] = IAP_SCRIPT.IAPCatalogEntry.make_entitlement()
	return cat


# Builds an IAPService wired to fresh stubs; backend returns `result`, compliance permits
# IAP unless `iap_ok` is false.
func _make(result: int, iap_ok: bool = true):
	_wallet = StubWallet.new()
	_compliance = StubCompliance.new()
	_compliance.iap_ok = iap_ok
	_entitlement = StubEntitlement.new()
	_backend = IAP_BACKEND.MockIAPBackend.new()
	_backend.next_result = result
	_captured_events = []
	var svc = auto_free(IAP_SCRIPT.new())
	svc.configure(_wallet, _compliance, _entitlement, _backend, _catalog())
	return svc


# --- State machine ----------------------------------------------------------

func test_initial_state_is_idle() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.FAILED)
	assert_int(svc.current_state()).is_equal(IAP_SCRIPT.State.IDLE)


func test_purchase_success_returns_service_to_idle() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.SUCCESS)
	svc.purchase(IAP_SCRIPT.SKU_COINS_SMALL)
	# After a SUCCESS the machine resets to IDLE so a new purchase may begin.
	assert_int(svc.current_state()).is_equal(IAP_SCRIPT.State.IDLE)


func test_purchase_failure_returns_service_to_idle() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.FAILED)
	svc.purchase(IAP_SCRIPT.SKU_COINS_SMALL)
	assert_int(svc.current_state()).is_equal(IAP_SCRIPT.State.IDLE)


# --- Grant routing on success ----------------------------------------------

func test_purchase_currency_success_credits_wallet_exactly_once() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.SUCCESS)
	var ok: bool = svc.purchase(IAP_SCRIPT.SKU_COINS_SMALL)
	assert_bool(ok).is_true()
	# Exactly one earn() call — no double-grant.
	assert_int(_wallet.earn_calls.size()).is_equal(1)
	var call: Array = _wallet.earn_calls[0]
	assert_int(call[0]).is_equal(EconomyEnums.Currency.COINS)
	assert_int(call[1]).is_equal(500)
	assert_int(call[2]).is_equal(EconomyEnums.EarnSource.IAP)
	# Currency pack must NOT touch the entitlement.
	assert_int(_entitlement.grant_calls).is_equal(0)


func test_purchase_remove_ads_success_grants_entitlement_not_currency() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.SUCCESS)
	var ok: bool = svc.purchase(IAP_SCRIPT.SKU_REMOVE_ADS)
	assert_bool(ok).is_true()
	assert_int(_entitlement.grant_calls).is_equal(1)
	assert_int(_wallet.earn_calls.size()).is_equal(0)


func test_purchase_failed_leaves_wallet_and_entitlement_unchanged() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.FAILED)
	var ok: bool = svc.purchase(IAP_SCRIPT.SKU_COINS_SMALL)
	assert_bool(ok).is_false()
	assert_int(_wallet.earn_calls.size()).is_equal(0)
	assert_int(_entitlement.grant_calls).is_equal(0)


# --- Gates ------------------------------------------------------------------

func test_purchase_unknown_sku_rejected_no_grant() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.SUCCESS)
	var ok: bool = svc.purchase(99999)  # not in the catalog
	assert_bool(ok).is_false()
	assert_int(_wallet.earn_calls.size()).is_equal(0)
	assert_int(_entitlement.grant_calls).is_equal(0)
	assert_int(svc.current_state()).is_equal(IAP_SCRIPT.State.IDLE)


func test_purchase_compliance_denied_blocked_emits_iap_blocked() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.SUCCESS, false)  # can_process_iap() false
	_wallet.economy_event.connect(_capture_event)
	var ok: bool = svc.purchase(IAP_SCRIPT.SKU_COINS_SMALL)
	assert_bool(ok).is_false()
	# Blocked before any grant.
	assert_int(_wallet.earn_calls.size()).is_equal(0)
	assert_int(_entitlement.grant_calls).is_equal(0)
	# An IAP_BLOCKED economy event was emitted with the compliance reason.
	assert_int(_captured_events.size()).is_equal(1)
	assert_int(_captured_events[0].reason).is_equal(EconomyEnums.FailReason.COMPLIANCE_RESTRICTED)


func test_is_valid_sku_known_and_unknown() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.SUCCESS)
	assert_bool(svc.is_valid_sku(IAP_SCRIPT.SKU_REMOVE_ADS)).is_true()
	assert_bool(svc.is_valid_sku(99999)).is_false()


# --- Restore (non-consumables only) ----------------------------------------

func test_restore_with_remove_ads_receipt_regrants_entitlement_only() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.FAILED)
	var receipts: Array[int] = [IAP_SCRIPT.SKU_REMOVE_ADS]
	_backend.prior_receipts = receipts
	var did: bool = svc.restore()
	assert_bool(did).is_true()
	assert_int(_entitlement.grant_calls).is_equal(1)
	# Restore must never re-credit currency.
	assert_int(_wallet.earn_calls.size()).is_equal(0)


func test_restore_ignores_consumable_currency_receipts() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.FAILED)
	var receipts: Array[int] = [IAP_SCRIPT.SKU_COINS_SMALL]  # consumable — not restorable
	_backend.prior_receipts = receipts
	var did: bool = svc.restore()
	assert_bool(did).is_false()
	assert_int(_wallet.earn_calls.size()).is_equal(0)
	assert_int(_entitlement.grant_calls).is_equal(0)


func test_restore_no_prior_receipts_no_grant_no_error() -> void:
	var svc = _make(IAP_BACKEND.PurchaseResult.FAILED)
	var did: bool = svc.restore()
	assert_bool(did).is_false()
	assert_int(_entitlement.grant_calls).is_equal(0)
