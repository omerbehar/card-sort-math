class_name IAPBackend
extends RefCounted
## Injectable seam for the IAP store receipt source (S4-002, ADR-0014 §1).
##
## [IAPService] uses an instance of this class to drive the platform purchase
## flow and to query for prior non-consumable receipts (restore-across-reinstall).
## This base class is a deliberate [b]no-op[/b]: [method purchase] always returns
## [constant RESULT_FAILED] and [method restore] returns an empty array — the
## correct "no store connected" behaviour this sprint.
##
## [b]Why a seam:[/b] the native Android/iOS IAP SDKs (Android BillingClient /
## Apple StoreKit) are GDExtensions that cannot run headlessly in the gdUnit4 CI
## (risk M4-R3). A test-double subclass ([MockIAPBackend]) returns configurable
## outcomes so all purchase/restore tests run headlessly and deterministically.
## The native backend is a future subclass injected via [method IAPService.configure],
## with zero changes to the service — exactly the [RemoteConfigSource] pattern
## (ADR-0014 §1).
##
## Source: ADR-0014 §1 (uniform seam), §2 (IAPService), GAME_PLAN §8.


## Result codes returned by [method purchase].
## Kept as a backend-level enum so the service state machine maps result → transition.
enum PurchaseResult {
	SUCCESS,  ## Purchase completed successfully; grant the SKU.
	FAILED,   ## Purchase failed (network, cancel, store error).
	RESTORED, ## Receipt-restore path completed for a prior non-consumable.
}


## Initiates a purchase for [param sku] and returns the synchronous mock outcome.
##
## Real implementations would be asynchronous (await a store callback); the mock
## returns deterministically. [IAPService] treats the return value as the
## final outcome for that purchase attempt.
##
## Implementations MUST be deterministic, synchronous, and safe to call repeatedly
## — the base implementation always returns [constant RESULT_FAILED] (no store).
func purchase(sku: int) -> int:
	return PurchaseResult.FAILED


## Returns the array of non-consumable SKU ints that have prior platform receipts.
##
## Used by [method IAPService.restore] to re-grant entitlements (non-consumables only;
## consumable currency packs are NOT re-granted on restore — ADR-0014 §2).
## The base implementation returns an empty array (no prior receipts).
##
## Implementations MUST be deterministic, synchronous, and safe to call repeatedly.
func restore() -> Array[int]:
	return []


## [b]Mock subclass.[/b] Returns configurable purchase and restore outcomes so
## integration and unit tests can exercise every state-machine path deterministically
## without a native store SDK.
##
## Inject via [method IAPService.configure]:
## [codeblock]
## var backend := IAPBackend.MockIAPBackend.new()
## backend.next_result = IAPBackend.PurchaseResult.SUCCESS
## iap_svc.configure(wallet, compliance, entitlement, backend, catalog)
## [/codeblock]
class MockIAPBackend extends IAPBackend:
	## The outcome returned by the next [method purchase] call.
	## Defaults to [constant PurchaseResult.FAILED] (no-op / safe default).
	var next_result: int = PurchaseResult.FAILED

	## Prior non-consumable SKU receipts returned by [method restore].
	## Add SKU ints here to simulate prior Remove-Ads (or other non-consumable) receipts.
	## Defaults to an empty array (no prior receipts).
	var prior_receipts: Array[int] = []

	## Returns [member next_result] regardless of [param sku].
	## Deterministic, synchronous, and safe to call repeatedly.
	func purchase(_sku: int) -> int:
		return next_result

	## Returns [member prior_receipts], the simulated list of prior non-consumable SKUs.
	func restore() -> Array[int]:
		return prior_receipts
