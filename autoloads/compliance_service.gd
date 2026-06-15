extends Node
## Autoload: the single compliance chokepoint for audience-gated and consent-gated behaviour
## (ADR-0005 extended by ADR-0013).
##
## This is the ONLY code permitted to read [member SaveData.age_band] or the consent fields
## ([member SaveData.consent_personalized_ads], [member SaveData.consent_analytics],
## [member SaveData.consent_iap]). Every ad / analytics / IAP data-processing decision must
## call this service — never read a consent field directly — so the conjunctive rule
## "ADULT AND consent-granted is permissive; everything else is restricted" is enforced in
## exactly one place and cannot be forgotten by any consumer. See ADR-0013 §2 and
## design/gdd/save-service.md Core Rule 9.
##
## The permissive path is [code]is_adult() AND <consent granted>[/code], so UNKNOWN, CHILD,
## or a denied/absent consent each independently flip the verdict to restricted. The guard is
## [code]AND consent_granted[/code] (never [code]AND NOT consent_denied[/code]) so that an
## absent or unknown consent can never leak into the permissive path — the same reasoning
## that makes the age guard [code]== ADULT[/code] and never [code]!= CHILD[/code].
##
## Verdicts are computed from the live [SaveData] on every call — no cached bool — so
## consent withdrawal immediately flips the corresponding verdict on the next query
## (ADR-0013 §3, "withdrawal immediacy").
##
## Usage:
## [codeblock]
## if ComplianceService.can_show_targeted_ads():
##     _request_personalised_ad()
## else:
##     _request_contextual_ad()
## [/codeblock]
##
## NOTE (M4-R2, OPEN-DEFERRED): plain-JSON [code]age_band[/code] is tamperable; an
## HMAC/signature is a required prerequisite before the first real AdService/Analytics ships
## (ADR-0013 §4, ADR-0005). This service is the seam that fix will live behind.

# SaveService dependency; resolves to the autoload at runtime, injectable in tests.
var _save = null


func _ready() -> void:
	if _save == null:
		_save = SaveService


## Injects the save service. Intended for tests.
func configure(save: Object) -> void:
	_save = save


# The resolved audience band. Internal — consumers call the can_* / is_* helpers.
# Returns UNKNOWN (restrictive) when _save has not been configured.
func _band() -> SaveData.AgeBand:
	if _save == null:
		return SaveData.AgeBand.UNKNOWN
	return _save.data.age_band


## True only for a player who has declared ADULT. UNKNOWN and CHILD are NOT adults.
func is_adult() -> bool:
	return _band() == SaveData.AgeBand.ADULT


## True when the player must be treated as a child (restrictive). Covers UNKNOWN.
func is_restricted() -> bool:
	return not is_adult()


# --- Consent helpers (ADR-0013 §2) ---
# These are the SOLE readers of the consent fields in SaveData.
# Each helper returns false (denied) when _save is null — fail-closed guard for
# a service queried before configure() is called (e.g. in tests or early boot).

## True only when personalized-ads consent has been explicitly granted.
## Reads the live field from SaveData; conservative coercion (null/non-bool → denied)
## is performed by SaveData.from_dict, not by this helper.
## Returns false (denied) when _save has not been configured.
func _consent_personalized_ads() -> bool:
	if _save == null:
		return false
	return _save.data.consent_personalized_ads


## True only when analytics consent has been explicitly granted.
## Returns false (denied) when _save has not been configured.
func _consent_analytics() -> bool:
	if _save == null:
		return false
	return _save.data.consent_analytics


## True only when IAP data-processing consent has been explicitly granted.
## Returns false (denied) when _save has not been configured.
func _consent_iap() -> bool:
	if _save == null:
		return false
	return _save.data.consent_iap


# --- Verdict methods (consent × age_band conjunction, ADR-0013 §2) ---

## May personal data be collected? Permissive only for ADULT + analytics consent granted.
## UNKNOWN, CHILD, or denied/absent analytics consent each independently → restricted.
func can_collect_personal_data() -> bool:
	return is_adult() and _consent_analytics()


## May targeted (behavioural) ads be shown? Permissive only for ADULT + personalized-ads
## consent granted. UNKNOWN, CHILD, or denied consent → restricted (contextual ads only).
func can_show_targeted_ads() -> bool:
	return is_adult() and _consent_personalized_ads()


## May a device advertising identifier be used? Gated on personalized-ads consent (the
## advertising ID is a personalisation signal). Permissive only for ADULT + ads consent.
func can_use_advertising_id() -> bool:
	return is_adult() and _consent_personalized_ads()


## May IAP data processing proceed? New verdict added for S4-002 (ADR-0013 §2).
## Permissive only for ADULT + IAP consent granted. S4-002 wires this into
## WalletService.initiate_iap(); see that story for the call-site integration.
func can_process_iap() -> bool:
	return is_adult() and _consent_iap()
