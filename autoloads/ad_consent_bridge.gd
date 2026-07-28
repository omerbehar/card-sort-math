class_name AdConsentBridge
extends RefCounted
## Native consent bridge (real-ads plan §4) — turns the platform CMP verdicts into the app's own
## consent record. It is the ONLY place that translates the AdMob UMP (GDPR/EEA) form result and
## the iOS ATT (App Tracking Transparency) prompt into a call to
## [method SaveService.capture_ad_personalization_consent]; from there [ComplianceService] (the sole
## reader of the consent fields, ADR-0013) decides personalized-vs-contextual for [AdService]. This
## bridge NEVER reads or writes consent fields directly — it owns only the ad-personalization
## dimension and routes it through the SaveService chokepoint, so the single-reader invariant
## (ADR-0013 Criterion 6) is preserved. Analytics/IAP consent stay with the in-app CMP sheet (S6).
##
## [b]Fail-closed.[/b] If the CMP is unavailable, errors, or the platform prompt is declined, the
## bridge records [b]no[/b] personalized-ads consent (contextual ads only) — never the reverse. This
## matches the conservative defaults [ComplianceService] already applies, so a broken bridge can only
## make ads less targeted, never leak targeting without consent.
##
## [b]This is SCAFFOLDING.[/b] The UMP / ATT plugin surface below is marked [b]VERIFY[/b]. Until the
## plugin is installed and wired, [method request_consent] resolves immediately with the fail-closed
## record and no native prompt is shown. See docs/architecture/real-ads-setup-guide.md §Consent.
##
## Source: docs/architecture/real-ads-integration-plan.md §4; ADR-0013 (consent CMP); ADR-0005 (audience).

## VERIFY: singleton names exposed by the consent plugins you install. The UMP form ships inside
## most AdMob plugins; ATT is often a separate small plugin.
const UMP_SINGLETON := "AdMob"           # VERIFY — UMP is usually part of the AdMob plugin surface.
const ATT_SINGLETON := "AppTracking"     # VERIFY — iOS ATT plugin singleton (App Tracking Transparency).

## The SaveService-compatible sink for the resolved consent (injected for testability; resolves to
## the autoload otherwise). Must expose [method capture_ad_personalization_consent].
var _save: Object = null


## Injects the consent sink (a [SaveService]-compatible object). Call before [method request_consent].
func configure(save: Object) -> void:
	_save = save


func _resolve_save() -> Object:
	if _save == null:
		_save = Engine.get_main_loop().root.get_node_or_null(^"/root/SaveService") if Engine.get_main_loop() != null else null
	return _save


## Runs the platform consent flow (UMP form on EEA/GDPR; ATT prompt on iOS) and records the verdict
## via [method SaveService.capture_ad_personalization_consent]. Returns whether personalized ads may
## be served (true only when BOTH the CMP granted ad-personalization AND, on iOS, ATT was authorized).
##
## [b]Fail-closed:[/b] any missing plugin, error, or declined prompt records contextual-only consent
## and returns false. Async — [code]await[/code] it during app start, after the age gate.
func request_consent() -> bool:
	var save := _resolve_save()
	if save == null or not save.has_method("capture_ad_personalization_consent"):
		push_warning("AdConsentBridge: no SaveService sink — cannot record consent.")
		return false

	# --- UMP (GDPR/EEA ad-personalization consent) ------------------------------------------------
	# VERIFY plugin API. Typical shape:
	#   ump.request_consent_info_update()   ; await ump.consent_info_updated
	#   if ump.is_consent_form_available(): ump.show_consent_form() ; await ump.consent_form_dismissed
	#   personalized = ump.can_request_personalized_ads()
	# Until wired, fail closed:
	var personalized_ok := false

	# --- iOS ATT (App Tracking Transparency) ------------------------------------------------------
	# On iOS, personalized ads additionally require ATT "authorized". VERIFY plugin API:
	#   var status = att.request_tracking_authorization() ; await att.tracking_authorization_result
	#   att_ok = (status == att.AUTHORIZED)
	# Non-iOS platforms skip ATT (att_ok stays true so UMP alone governs).
	var att_ok := true
	if OS.get_name() == "iOS":
		att_ok = false  # fail closed until the ATT plugin is wired

	var may_personalize := personalized_ok and att_ok
	# Record ONLY the ad-personalization dimension through the narrow SaveService chokepoint; the
	# analytics/IAP flags are owned by the in-app CMP sheet (ConsentSheet, S6) and left untouched.
	# This bridge deliberately never reads or writes SaveData consent fields directly (single-reader
	# invariant, ADR-0013 Criterion 6).
	save.capture_ad_personalization_consent(may_personalize)
	return may_personalize
