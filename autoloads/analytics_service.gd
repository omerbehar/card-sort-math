extends Node
## Autoload: consent-gated analytics seam + monetization funnel events (S4-007, M5 prep).
##
## A vendor-agnostic front door for telemetry. Events are forwarded to an injected
## [AnalyticsSink] [b]only[/b] when [method ComplianceService.can_collect_personal_data] is
## true (ADULT + analytics consent — ADR-0013 §2). When consent is denied, withdrawn, or the
## audience is UNKNOWN/CHILD, [method track] drops the event silently — there is no
## anonymized fallback this sprint (privacy-safe default). The gate is read live on every
## call, so a mid-session consent withdrawal stops emission immediately.
##
## The funnel helpers ([method track_iap_purchase] etc.) are thin wrappers over [method track]
## so the IAP/Ad services (or the deferred monetization UI) emit structured events without
## knowing the vendor. All dependencies are injected via [method configure] (DI, ADR-0014 §1).
##
## Source: ADR-0014 §1; ADR-0013 (consent); production/sprints/sprint-04.md S4-007.

## Preloaded so the sink type resolves regardless of global-class-cache timing.
const AnalyticsSinkClass := preload("res://autoloads/analytics_sink.gd")

## Vendor-agnostic monetization funnel event names.
const EVENT_IAP_PURCHASE := "iap_purchase"        ## An IAP purchase attempt resolved.
const EVENT_AD_IMPRESSION := "ad_impression"      ## An interstitial was presented.
const EVENT_AD_REWARD := "ad_reward"              ## A rewarded ad credited coins.

var _compliance = null   # ComplianceService: can_collect_personal_data()
var _sink: AnalyticsSinkClass = null


func _ready() -> void:
	if _compliance == null:
		_compliance = ComplianceService
	if _sink == null:
		_sink = AnalyticsSinkClass.new()


## Injects dependencies. Intended for tests and the future vendor wiring.
## [param compliance]: ComplianceService-compatible ([method can_collect_personal_data]).
## [param sink]: an [AnalyticsSink]-compatible destination.
func configure(compliance: Object, sink: AnalyticsSinkClass) -> void:
	_compliance = compliance
	_sink = sink


## Returns whether analytics emission is currently permitted (analytics consent × ADULT).
## Read live, so it reflects a consent change made at any point in the session.
func is_enabled() -> bool:
	return _compliance != null and _compliance.can_collect_personal_data()


## Forwards a vendor-agnostic event to the sink IF consent permits; otherwise drops it
## silently. Returns [code]true[/code] when the event was forwarded, [code]false[/code]
## when consent gating suppressed it.
func track(event_name: String, properties: Dictionary = {}) -> bool:
	if not is_enabled():
		return false
	if _sink != null:
		_sink.track(event_name, properties)
	return true


# --- Monetization funnel helpers (consent-gated via track) ------------------

## Tracks an IAP purchase outcome. [param sku] is the catalog SKU; [param success] is the
## resolved result. Returns whether the event was emitted (consent permitting).
func track_iap_purchase(sku: int, success: bool) -> bool:
	return track(EVENT_IAP_PURCHASE, {"sku": sku, "success": success})


## Tracks an interstitial impression. [param ad_type] is an [enum AdService.AdType].
func track_ad_impression(ad_type: int) -> bool:
	return track(EVENT_AD_IMPRESSION, {"ad_type": ad_type})


## Tracks a rewarded-ad payout. [param coins] is the amount actually credited.
func track_ad_reward(coins: int) -> bool:
	return track(EVENT_AD_REWARD, {"coins": coins})
