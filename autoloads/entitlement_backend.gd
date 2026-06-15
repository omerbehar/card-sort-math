class_name EntitlementBackend
extends RefCounted
## Injectable seam for the Remove-Ads entitlement receipt source (S4-003, ADR-0014 §3).
##
## [EntitlementService] uses an instance of this class to query the platform for a
## prior Remove-Ads purchase receipt (restore-across-reinstall). This base class is a
## deliberate [b]no-op[/b]: [method has_prior_receipt] returns [code]false[/code], so
## [method EntitlementService.restore] finds nothing and leaves the entitlement unset
## — the correct "no prior purchase" behaviour this sprint.
##
## [b]Why a seam:[/b] the actual native IAP receipt query (Android BillingClient /
## Apple StoreKit) is a GDExtension that cannot run headlessly in the gdUnit4 CI
## (risk M4-R3). A test-double subclass ([MockEntitlementBackend]) returns configurable
## receipt state so all restore-path tests run headlessly and deterministically.
## The native backend is a future subclass injected via [method EntitlementService.configure],
## with zero changes to the service — exactly the [RemoteConfigSource] pattern (ADR-0014 §1).
##
## Source: ADR-0014 §1 (uniform seam), §3 (EntitlementService), GAME_PLAN §8.


## Returns [code]true[/code] if the platform receipt store contains a prior Remove-Ads
## purchase that should be restored; [code]false[/code] otherwise.
##
## Implementations MUST be deterministic, synchronous, and safe to call repeatedly —
## the service calls this at most once per [method EntitlementService.restore] invocation.
## The base implementation always returns [code]false[/code] (no receipt found).
func has_prior_receipt() -> bool:
	return false


## [b]Mock subclass.[/b] Returns a configurable receipt-present flag so integration tests
## can exercise the restore path deterministically without a native store SDK.
##
## Inject via [method EntitlementService.configure]:
## [codeblock]
## var backend := MockEntitlementBackend.new()
## backend.receipt_present = true
## entitlement_svc.configure(save_svc, backend)
## [/codeblock]
class MockEntitlementBackend extends EntitlementBackend:
	## When [code]true[/code], [method has_prior_receipt] returns [code]true[/code]
	## (simulating a prior Remove-Ads purchase on the platform receipt store).
	## Defaults to [code]false[/code] (no prior purchase).
	var receipt_present: bool = false

	func has_prior_receipt() -> bool:
		return receipt_present
