extends GdUnitTestSuite
## Unit tests — SaveIntegrity (M4-R2, ADR-0013 §4). HMAC over the compliance/entitlement
## protected fields; tamper on any protected field (or a missing signature) fails verify,
## while edits to non-protected fields do not.


func _protected_dict() -> Dictionary:
	var d := SaveData.new()
	d.age_band = SaveData.AgeBand.ADULT
	d.consent_personalized_ads = true
	d.consent_analytics = true
	d.consent_iap = true
	d.consent_captured = true
	d.remove_ads_owned = true
	return d.to_dict()


func test_sign_verify_roundtrip() -> void:
	var signed := SaveIntegrity.signed(_protected_dict())
	assert_bool(SaveIntegrity.verify(signed)).is_true()


func test_signature_is_deterministic() -> void:
	var dict := _protected_dict()
	assert_str(SaveIntegrity.signature(dict)).is_equal(SaveIntegrity.signature(dict))


func test_tampered_age_band_fails_verify() -> void:
	# Attacker flips a CHILD save to ADULT without the secret.
	var signed := SaveIntegrity.signed(_protected_dict())
	signed["age_band"] = SaveData.AgeBand.CHILD
	assert_bool(SaveIntegrity.verify(signed)).is_false()


func test_tampered_consent_fails_verify() -> void:
	var signed := SaveIntegrity.signed(_protected_dict())
	signed["consent_personalized_ads"] = false
	assert_bool(SaveIntegrity.verify(signed)).is_false()


func test_tampered_remove_ads_fails_verify() -> void:
	# Grant Remove-Ads for free by editing the flag → detected.
	var dict := _protected_dict()
	dict["remove_ads_owned"] = false
	var signed := SaveIntegrity.signed(dict)
	signed["remove_ads_owned"] = true
	assert_bool(SaveIntegrity.verify(signed)).is_false()


func test_missing_signature_fails_verify() -> void:
	# An unsigned (or signature-stripped) save is untrusted.
	assert_bool(SaveIntegrity.verify(_protected_dict())).is_false()


func test_non_protected_field_change_keeps_signature_valid() -> void:
	# Only the compliance/entitlement fields are signed — progress can change freely.
	var signed := SaveIntegrity.signed(_protected_dict())
	signed["current_level"] = 42
	signed["wallet_coins"] = 99999
	assert_bool(SaveIntegrity.verify(signed)).is_true()
