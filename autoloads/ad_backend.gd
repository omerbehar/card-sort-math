class_name AdBackend
extends RefCounted
## Injectable seam for the ad-network SDK (S4-004a, ADR-0014 §1).
##
## [AdService] uses an instance of this class to present interstitial and rewarded ads.
## This base class is a deliberate [b]no-op[/b]: [method show_interstitial] reports
## [constant InterstitialResult.NO_FILL] and [method show_rewarded] reports
## [code]false[/code] (not completed) — the correct "no ad network connected" behaviour
## this sprint.
##
## [b]Why a seam:[/b] the native Android/iOS ad SDKs (AdMob / etc.) are GDExtensions that
## cannot run headlessly in the gdUnit4 CI (risk M4-R3). A test-double subclass
## ([MockAdBackend]) returns configurable outcomes so all frequency-cap and rewarded
## tests run headlessly and deterministically. The native backend is a future subclass
## injected via [method AdService.configure], with zero changes to the service — the same
## pattern as [IAPBackend] and [RemoteConfigSource] (ADR-0014 §1).
##
## Source: ADR-0014 §1 (uniform seam), §"AdService" (rewarded + interstitial), GAME_PLAN §9.


## Result codes returned by [method show_interstitial].
enum InterstitialResult {
	SHOWN,    ## An interstitial was filled and presented.
	NO_FILL,  ## No ad available to present (network/no-fill/error).
}


## Presents an interstitial ad of the requested targeting type and returns the synchronous
## mock outcome. [param ad_type] is an [enum AdService.AdType] (personalized vs contextual);
## the native backend maps it to the SDK's targeting/consent flags.
##
## Real implementations would be asynchronous (await an SDK callback); the mock returns
## deterministically. [AdService] treats the return value as the final outcome.
## Implementations MUST be deterministic, synchronous, and safe to call repeatedly —
## the base implementation always returns [constant InterstitialResult.NO_FILL] (no SDK).
func show_interstitial(_ad_type: int) -> int:
	return InterstitialResult.NO_FILL


## Presents a rewarded ad and returns whether the player completed it (watched to the
## reward threshold). [code]false[/code] means dismissed/abandoned/no-fill — no reward.
##
## Implementations MUST be deterministic, synchronous, and safe to call repeatedly —
## the base implementation always returns [code]false[/code] (no SDK).
func show_rewarded() -> bool:
	return false


## [b]Mock subclass.[/b] Returns configurable interstitial and rewarded outcomes so
## frequency-cap and rewarded-earn tests can exercise every path deterministically
## without a native ad SDK.
##
## Inject via [method AdService.configure]:
## [codeblock]
## var backend := AdBackend.MockAdBackend.new()
## backend.interstitial_result = AdBackend.InterstitialResult.SHOWN
## backend.rewarded_completes = true
## ad_svc.configure(wallet, entitlement, time, config, backend)
## [/codeblock]
class MockAdBackend extends AdBackend:
	## The outcome returned by the next [method show_interstitial] call.
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

	## Returns [member interstitial_result]; records the requested [param ad_type] and counts
	## the call. Deterministic and repeatable.
	func show_interstitial(ad_type: int) -> int:
		interstitial_calls += 1
		last_ad_type = ad_type
		return interstitial_result

	## Returns [member rewarded_completes]. Deterministic and repeatable.
	func show_rewarded() -> bool:
		return rewarded_completes
