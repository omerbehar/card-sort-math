extends GdUnitTestSuite
## Unit tests for [SaveData] consent fields and the v5→v6 schema migration (S4-001, ADR-0013).
##
## Covers:
## - v5→v6 migration seeds all consent fields to conservative (denied / not-captured) defaults.
## - Migration is idempotent (re-running on an already-v6 dict never flips a granted consent
##   back to denied).
## - [method from_dict] / [method to_dict] round-trip preserves every consent field.
## - Missing key in any version of save dict → conservative denied default (EC9).
## - Out-of-range / null consent value → treated as denied (mirrors EC7 _parse_age_band).
## - Downgrade-drop protection: a consent field absent from an old/foreign save loads as
##   denied + not-captured, never granted (save-service.md Core Rule 6, Edge Case 9).


# ---------------------------------------------------------------------------
# v5 → v6 migration: consent fields seeded to conservative defaults
# ---------------------------------------------------------------------------

func test_migrate_v5_to_v6_seeds_consent_personalized_ads_denied() -> void:
	# A v5 save dict must gain consent_personalized_ads = false (denied) on migration.
	var v5_dict: Dictionary = {
		"schema_version": 5,
		"current_level": 3,
		"wallet_coins": 100,
		"boosters_picker": 2,
		"boosters_seeded": true,
	}
	var data := SaveData.from_dict(v5_dict)
	assert_bool(data.consent_personalized_ads).is_false()


func test_migrate_v5_to_v6_seeds_consent_analytics_denied() -> void:
	var v5_dict: Dictionary = {"schema_version": 5, "current_level": 1}
	var data := SaveData.from_dict(v5_dict)
	assert_bool(data.consent_analytics).is_false()


func test_migrate_v5_to_v6_seeds_consent_iap_denied() -> void:
	var v5_dict: Dictionary = {"schema_version": 5, "current_level": 1}
	var data := SaveData.from_dict(v5_dict)
	assert_bool(data.consent_iap).is_false()


func test_migrate_v5_to_v6_seeds_consent_captured_false() -> void:
	var v5_dict: Dictionary = {"schema_version": 5, "current_level": 1}
	var data := SaveData.from_dict(v5_dict)
	assert_bool(data.consent_captured).is_false()


func test_migrate_v5_to_v6_seeds_consent_version_zero() -> void:
	var v5_dict: Dictionary = {"schema_version": 5, "current_level": 1}
	var data := SaveData.from_dict(v5_dict)
	assert_int(data.consent_version).is_equal(0)


func test_migrate_v5_to_v6_bumps_schema_version_to_current() -> void:
	var v5_dict: Dictionary = {"schema_version": 5, "current_level": 4}
	var data := SaveData.from_dict(v5_dict)
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)
	assert_int(SaveData.CURRENT_SCHEMA_VERSION).is_equal(6)


func test_migrate_v5_to_v6_preserves_existing_fields() -> void:
	# Migration must not clobber pre-existing fields.
	var v5_dict: Dictionary = {
		"schema_version": 5,
		"current_level": 7,
		"wallet_coins": 250,
		"wallet_gems": 5,
		"wins_today": 2,
		"boosters_picker": 3,
		"boosters_seeded": true,
	}
	var data := SaveData.from_dict(v5_dict)
	assert_int(data.current_level).is_equal(7)
	assert_int(data.wallet_coins).is_equal(250)
	assert_int(data.wallet_gems).is_equal(5)
	assert_int(data.wins_today).is_equal(2)
	assert_int(data.boosters_picker).is_equal(3)
	assert_bool(data.boosters_seeded).is_true()


func test_migrate_v1_flows_through_all_steps_to_v6() -> void:
	# A v1 save must migrate v1→v2→v3→v4→v5→v6; all consent fields default to denied
	# and all wallet / daily / booster fields get their conservative defaults.
	var v1_dict: Dictionary = {
		"schema_version": 1,
		"current_level": 4,
		"age_band": int(SaveData.AgeBand.ADULT),
	}
	var data := SaveData.from_dict(v1_dict)
	assert_int(data.schema_version).is_equal(6)
	assert_bool(data.consent_personalized_ads).is_false()
	assert_bool(data.consent_analytics).is_false()
	assert_bool(data.consent_iap).is_false()
	assert_bool(data.consent_captured).is_false()
	assert_int(data.consent_version).is_equal(0)
	assert_int(data.wallet_coins).is_equal(0)
	assert_int(data.wins_today).is_equal(0)
	assert_int(data.boosters_picker).is_equal(0)
	assert_int(data.current_level).is_equal(4)
	assert_int(int(data.age_band)).is_equal(int(SaveData.AgeBand.ADULT))


# ---------------------------------------------------------------------------
# Migration idempotency (ADR-0013 §1, save-service.md Formulas → migration gate)
# Re-running the v5→v6 step on a dict that already has consent fields must NOT
# overwrite a granted consent back to denied.
# ---------------------------------------------------------------------------

func test_migration_idempotent_does_not_overwrite_granted_personalized_ads() -> void:
	# Simulate a v6 dict that already has personalized_ads granted.
	# The _migrate step must skip the field (it already exists) — idempotent.
	var v6_dict: Dictionary = {
		"schema_version": 6,
		"current_level": 1,
		"consent_personalized_ads": true,
		"consent_analytics": false,
		"consent_iap": false,
		"consent_captured": true,
		"consent_version": 0,
	}
	var data := SaveData.from_dict(v6_dict)
	assert_bool(data.consent_personalized_ads).is_true()


func test_migration_idempotent_does_not_overwrite_granted_analytics() -> void:
	var v6_dict: Dictionary = {
		"schema_version": 6,
		"current_level": 1,
		"consent_personalized_ads": false,
		"consent_analytics": true,
		"consent_iap": false,
		"consent_captured": true,
		"consent_version": 0,
	}
	var data := SaveData.from_dict(v6_dict)
	assert_bool(data.consent_analytics).is_true()


func test_migration_idempotent_does_not_overwrite_granted_iap() -> void:
	var v6_dict: Dictionary = {
		"schema_version": 6,
		"current_level": 1,
		"consent_personalized_ads": false,
		"consent_analytics": false,
		"consent_iap": true,
		"consent_captured": true,
		"consent_version": 0,
	}
	var data := SaveData.from_dict(v6_dict)
	assert_bool(data.consent_iap).is_true()


func test_migration_idempotent_preserves_all_grants_together() -> void:
	# All three consents granted in a v6 dict must all survive.
	var v6_dict: Dictionary = {
		"schema_version": 6,
		"current_level": 2,
		"consent_personalized_ads": true,
		"consent_analytics": true,
		"consent_iap": true,
		"consent_captured": true,
		"consent_version": 1,
	}
	var data := SaveData.from_dict(v6_dict)
	assert_bool(data.consent_personalized_ads).is_true()
	assert_bool(data.consent_analytics).is_true()
	assert_bool(data.consent_iap).is_true()
	assert_bool(data.consent_captured).is_true()
	assert_int(data.consent_version).is_equal(1)


# ---------------------------------------------------------------------------
# from_dict conservative defaults (EC5, EC9) — missing keys must never be permissive
# ---------------------------------------------------------------------------

func test_from_dict_empty_dict_consent_personalized_ads_denied() -> void:
	# EC5/EC9: from_dict({}) must default all consent fields to denied.
	var data := SaveData.from_dict({})
	assert_bool(data.consent_personalized_ads).is_false()


func test_from_dict_empty_dict_consent_analytics_denied() -> void:
	var data := SaveData.from_dict({})
	assert_bool(data.consent_analytics).is_false()


func test_from_dict_empty_dict_consent_iap_denied() -> void:
	var data := SaveData.from_dict({})
	assert_bool(data.consent_iap).is_false()


func test_from_dict_empty_dict_consent_captured_false() -> void:
	var data := SaveData.from_dict({})
	assert_bool(data.consent_captured).is_false()


func test_from_dict_empty_dict_consent_version_zero() -> void:
	var data := SaveData.from_dict({})
	assert_int(data.consent_version).is_equal(0)


# ---------------------------------------------------------------------------
# Out-of-range / null consent value → denied (mirrors EC7 _parse_age_band)
# ---------------------------------------------------------------------------

func test_from_dict_null_consent_personalized_ads_treated_as_denied() -> void:
	var data := SaveData.from_dict({"schema_version": 6, "consent_personalized_ads": null})
	assert_bool(data.consent_personalized_ads).is_false()


func test_from_dict_null_consent_analytics_treated_as_denied() -> void:
	var data := SaveData.from_dict({"schema_version": 6, "consent_analytics": null})
	assert_bool(data.consent_analytics).is_false()


func test_from_dict_null_consent_iap_treated_as_denied() -> void:
	var data := SaveData.from_dict({"schema_version": 6, "consent_iap": null})
	assert_bool(data.consent_iap).is_false()


func test_from_dict_null_consent_captured_treated_as_false() -> void:
	var data := SaveData.from_dict({"schema_version": 6, "consent_captured": null})
	assert_bool(data.consent_captured).is_false()


func test_from_dict_int_non_one_consent_treated_as_denied() -> void:
	# An int value that is not 1 must not be interpreted as granted.
	var data := SaveData.from_dict({"schema_version": 6, "consent_personalized_ads": 99})
	assert_bool(data.consent_personalized_ads).is_false()


func test_from_dict_string_consent_treated_as_denied() -> void:
	# A string "true" is not a valid bool value — must default to denied.
	var data := SaveData.from_dict({"schema_version": 6, "consent_personalized_ads": "true"})
	assert_bool(data.consent_personalized_ads).is_false()


# ---------------------------------------------------------------------------
# Downgrade-drop protection (Edge Case 9, save-service.md Core Rule 6)
# A future-schema save missing a consent key must load as denied + not-captured.
# ---------------------------------------------------------------------------

func test_downgrade_drop_missing_consent_personalized_ads_treated_as_denied() -> void:
	# Simulates a save written by an older binary that dropped the field on write.
	# Must load as denied — never granted.
	var dict_missing_key: Dictionary = {
		"schema_version": 6,
		"current_level": 5,
		# consent_personalized_ads deliberately absent
		"consent_analytics": false,
		"consent_iap": false,
		"consent_captured": false,
		"consent_version": 0,
	}
	var data := SaveData.from_dict(dict_missing_key)
	assert_bool(data.consent_personalized_ads).is_false()


func test_downgrade_drop_missing_consent_captured_treated_as_not_captured() -> void:
	# An absent consent_captured must load as false (not-captured, triggers re-presentation).
	var dict_missing_captured: Dictionary = {
		"schema_version": 6,
		"current_level": 3,
		"consent_personalized_ads": true,
		"consent_analytics": true,
		"consent_iap": true,
		# consent_captured absent — must not be treated as captured
		"consent_version": 0,
	}
	var data := SaveData.from_dict(dict_missing_captured)
	assert_bool(data.consent_captured).is_false()


# ---------------------------------------------------------------------------
# to_dict / from_dict round-trip preserves every consent field (SD-02 discipline)
# ---------------------------------------------------------------------------

func test_round_trip_preserves_consent_personalized_ads_true() -> void:
	var original := SaveData.new()
	original.consent_personalized_ads = true
	var restored := SaveData.from_dict(original.to_dict())
	assert_bool(restored.consent_personalized_ads).is_true()


func test_round_trip_preserves_consent_analytics_true() -> void:
	var original := SaveData.new()
	original.consent_analytics = true
	var restored := SaveData.from_dict(original.to_dict())
	assert_bool(restored.consent_analytics).is_true()


func test_round_trip_preserves_consent_iap_true() -> void:
	var original := SaveData.new()
	original.consent_iap = true
	var restored := SaveData.from_dict(original.to_dict())
	assert_bool(restored.consent_iap).is_true()


func test_round_trip_preserves_consent_captured_true() -> void:
	var original := SaveData.new()
	original.consent_captured = true
	var restored := SaveData.from_dict(original.to_dict())
	assert_bool(restored.consent_captured).is_true()


func test_round_trip_preserves_consent_version() -> void:
	var original := SaveData.new()
	original.consent_version = 3
	var restored := SaveData.from_dict(original.to_dict())
	assert_int(restored.consent_version).is_equal(3)


func test_round_trip_all_consent_fields_together() -> void:
	# All five consent fields survive a to_dict/from_dict round-trip simultaneously.
	var original := SaveData.new()
	original.consent_personalized_ads = true
	original.consent_analytics = true
	original.consent_iap = true
	original.consent_captured = true
	original.consent_version = 2
	var restored := SaveData.from_dict(original.to_dict())
	assert_bool(restored.consent_personalized_ads).is_true()
	assert_bool(restored.consent_analytics).is_true()
	assert_bool(restored.consent_iap).is_true()
	assert_bool(restored.consent_captured).is_true()
	assert_int(restored.consent_version).is_equal(2)


func test_to_dict_contains_all_consent_keys() -> void:
	# All five consent keys must be present in to_dict() output.
	var keys: Array = SaveData.new().to_dict().keys()
	for key: String in ["consent_personalized_ads", "consent_analytics",
			"consent_iap", "consent_captured", "consent_version"]:
		assert_bool(keys.has(key)).is_true()


func test_defaults_consent_fields_are_conservative() -> void:
	# A fresh SaveData.defaults() must have all consent fields at denied/not-captured.
	var data := SaveData.defaults()
	assert_bool(data.consent_personalized_ads).is_false()
	assert_bool(data.consent_analytics).is_false()
	assert_bool(data.consent_iap).is_false()
	assert_bool(data.consent_captured).is_false()
	assert_int(data.consent_version).is_equal(0)


# JSON string round-trip (booleans may come back as int 1/0 from some parsers)
func test_json_string_round_trip_preserves_granted_consent() -> void:
	var original := SaveData.new()
	original.consent_personalized_ads = true
	original.consent_analytics = true
	original.consent_iap = true
	original.consent_captured = true
	original.consent_version = 1
	var text := JSON.stringify(original.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	var restored := SaveData.from_dict(parsed as Dictionary)
	assert_bool(restored.consent_personalized_ads).is_true()
	assert_bool(restored.consent_analytics).is_true()
	assert_bool(restored.consent_iap).is_true()
	assert_bool(restored.consent_captured).is_true()
	assert_int(restored.consent_version).is_equal(1)
