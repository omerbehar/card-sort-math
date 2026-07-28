class_name AdBackend
extends RefCounted
## Injectable seam for the ad-network SDK (S4-004a, ADR-0014 §1).
##
## [AdService] uses an instance of this class to present interstitial and rewarded ads.
## This base class is a deliberate [b]no-op[/b]: it reports no fill for interstitials and a
## non-completed rewarded view — the correct "no ad network connected" behaviour.
##
## [b]Async contract (real-ads plan §2).[/b] Real ad SDKs are load → (wait for fill) → show →
## (wait for the user to dismiss/complete) → callback. So presentation is [b]asynchronous[/b]:
## [method show_interstitial] / [method show_rewarded] return nothing and report their outcome
## later via [signal interstitial_finished] / [signal rewarded_finished]. [AdService] runs its
## (synchronous) gates, calls show, then [code]await[/code]s the result signal. Preloading
## ([method preload_interstitial] / [method has_interstitial_ready], mirrored for rewarded) lets
## a real backend fetch fill ahead of the boundary so [code]show[/code] resolves promptly; the
## base + mock treat it as a no-op.
##
## [b]Why a seam:[/b] the native Android/iOS ad SDKs (AdMob / etc.) are GDExtensions that
## cannot run headlessly in the gdUnit4 CI (risk M4-R3). A test-double subclass
## ([MockAdBackend]) emits configurable outcomes deterministically so all frequency-cap and
## rewarded tests run headlessly. The native backend ([code]RealAdBackend[/code]) is a future
## subclass injected via [method AdService.configure], with zero changes to the service.
##
## Source: ADR-0014 §1 (uniform seam); GAME_PLAN §9; docs/architecture/real-ads-integration-plan.md §2.


## Result codes carried by [signal interstitial_finished].
enum InterstitialResult {
	SHOWN,    ## An interstitial was filled and presented.
	NO_FILL,  ## No ad available to present (network/no-fill/error).
}

## Emitted once a [method show_interstitial] request resolves (dismissed or failed).
## [param outcome] is an [enum InterstitialResult].
signal interstitial_finished(outcome: int)

## Emitted once a [method show_rewarded] request resolves. [param completed] is true only when
## the player watched to the reward threshold (else dismissed/abandoned/no-fill — no reward).
signal rewarded_finished(completed: bool)


## Requests the backend fetch an interstitial ahead of time (real SDKs preload). No-op here.
## [param ad_type] is an [enum AdService.AdType] the native backend maps to targeting/consent.
func preload_interstitial(_ad_type: int) -> void:
	pass


## True when a preloaded interstitial is ready to show without a network round-trip. Always
## false for the base (no SDK); a real backend tracks its own "loaded" flag.
func has_interstitial_ready(_ad_type: int) -> bool:
	return false


## Presents an interstitial ad of the requested targeting type. The outcome arrives via
## [signal interstitial_finished] (deferred, so an [code]await[/code] set up right after the
## call still catches it). The base reports [constant InterstitialResult.NO_FILL] (no SDK).
## [codeblock]
## backend.show_interstitial(AdService.AdType.CONTEXTUAL)
## var outcome: int = await backend.interstitial_finished
## [/codeblock]
func show_interstitial(_ad_type: int) -> void:
	interstitial_finished.emit.call_deferred(InterstitialResult.NO_FILL)


## Requests the backend fetch a rewarded ad ahead of time. No-op here.
func preload_rewarded() -> void:
	pass


## True when a preloaded rewarded ad is ready. Always false for the base (no SDK).
func has_rewarded_ready() -> bool:
	return false


## Presents a rewarded ad. The outcome arrives via [signal rewarded_finished] (deferred). The
## base reports [code]false[/code] (not completed — no SDK).
func show_rewarded() -> void:
	rewarded_finished.emit.call_deferred(false)


## [b]Mock subclass.[/b] Emits configurable interstitial and rewarded outcomes (deferred) so
## frequency-cap and rewarded-earn tests can exercise every path deterministically without a
## native ad SDK.
##
## Inject via [method AdService.configure]:
## [codeblock]
## var backend := AdBackend.MockAdBackend.new()
## backend.interstitial_result = AdBackend.InterstitialResult.SHOWN
## backend.rewarded_completes = true
## ad_svc.configure(wallet, entitlement, time, config, backend)
## [/codeblock]
class MockAdBackend extends AdBackend:
	## The outcome emitted by the next [method show_interstitial] call.
	## Defaults to [constant InterstitialResult.SHOWN] (fill available).
	var interstitial_result: int = InterstitialResult.SHOWN

	## Whether the next [method show_rewarded] call reports a completed view.
	## Defaults to [code]true[/code] (player watched to reward).
	var rewarded_completes: bool = true

	## Number of [method show_interstitial] calls — lets tests assert the backend was
	## (or was not) actually invoked after the frequency/suppression gates.
	var interstitial_calls: int = 0

	## The [enum AdService.AdType] of the most recent [method show_interstitial] call
	## ([code]-1[/code] until first called) — lets tests assert personalized vs contextual.
	var last_ad_type: int = -1

	## Records the request and emits [member interstitial_result] via
	## [signal interstitial_finished] (deferred). Deterministic and repeatable.
	func show_interstitial(ad_type: int) -> void:
		interstitial_calls += 1
		last_ad_type = ad_type
		interstitial_finished.emit.call_deferred(interstitial_result)

	## Emits [member rewarded_completes] via [signal rewarded_finished] (deferred).
	func show_rewarded() -> void:
		rewarded_finished.emit.call_deferred(rewarded_completes)
