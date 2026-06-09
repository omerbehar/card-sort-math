extends Node
## Autoload: the single compliance chokepoint for audience-gated behaviour (ADR-0005).
##
## This is the ONLY code permitted to read [member SaveData.age_band]. Every
## ad / analytics / data-collection decision must call this service — never read
## [code]age_band[/code] directly — so the rule "UNKNOWN is treated as CHILD
## (restrictive)" is enforced in exactly one place and cannot be forgotten by a
## future consumer. See design/gdd/save-service.md Core Rule 9.
##
## The permissive path is keyed on [code]== ADULT[/code], so both UNKNOWN and
## CHILD fall through to the restricted verdict. Writing [code]== CHILD[/code]
## anywhere would silently leak the UNKNOWN cohort into the adult path — which is
## exactly the mistake this chokepoint exists to prevent.
##
## Usage:
## [codeblock]
## if ComplianceService.can_show_targeted_ads():
##     _request_personalised_ad()
## else:
##     _request_contextual_ad()
## [/codeblock]
##
## NOTE (M1): plain-JSON [code]age_band[/code] is tamperable; an HMAC/signature is
## a required prerequisite before the first AdService/Analytics ships (GDD Open
## Questions). This service is the seam that fix will live behind.

# SaveService dependency; resolves to the autoload at runtime, injectable in tests.
var _save = null


func _ready() -> void:
	if _save == null:
		_save = SaveService


## Injects the save service. Intended for tests.
func configure(save: Object) -> void:
	_save = save


# The resolved audience band. Internal — consumers call the can_* / is_* helpers.
func _band() -> SaveData.AgeBand:
	return _save.data.age_band


## True only for a player who has declared ADULT. UNKNOWN and CHILD are NOT adults.
func is_adult() -> bool:
	return _band() == SaveData.AgeBand.ADULT


## True when the player must be treated as a child (restrictive). Covers UNKNOWN.
func is_restricted() -> bool:
	return not is_adult()


## May personal data be collected? Only for a declared adult.
func can_collect_personal_data() -> bool:
	return is_adult()


## May targeted (behavioural) ads be shown? Only for a declared adult.
func can_show_targeted_ads() -> bool:
	return is_adult()


## May a device advertising identifier be used? Only for a declared adult.
func can_use_advertising_id() -> bool:
	return is_adult()
