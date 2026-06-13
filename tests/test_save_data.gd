extends GdUnitTestSuite
## Tests for [SaveData] serialization, validation, and schema migration (S1-001).


func test_defaults_are_safe() -> void:
	# Arrange / Act
	var data := SaveData.defaults()
	# Assert (SD-01: all five settings defaults, not a subset)
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)
	assert_int(data.current_level).is_equal(1)
	assert_int(int(data.age_band)).is_equal(int(SaveData.AgeBand.UNKNOWN))
	assert_bool(data.settings.sound).is_true()
	assert_bool(data.settings.music).is_true()
	assert_bool(data.settings.haptics).is_true()
	assert_bool(data.settings.reduced_motion).is_false()
	assert_bool(data.settings.colorblind).is_false()


func test_to_dict_from_dict_round_trips() -> void:
	# Arrange (SD-02: exercise all five settings keys so a dropped key is caught)
	var original := SaveData.new()
	original.current_level = 7
	original.age_band = SaveData.AgeBand.ADULT
	original.settings.sound = false
	original.settings.music = false
	original.settings.haptics = false
	original.settings.reduced_motion = true
	original.settings.colorblind = true
	# Act
	var restored := SaveData.from_dict(original.to_dict())
	# Assert
	assert_int(restored.current_level).is_equal(7)
	assert_int(int(restored.age_band)).is_equal(int(SaveData.AgeBand.ADULT))
	assert_bool(restored.settings.sound).is_false()
	assert_bool(restored.settings.music).is_false()
	assert_bool(restored.settings.haptics).is_false()
	assert_bool(restored.settings.reduced_motion).is_true()
	assert_bool(restored.settings.colorblind).is_true()


func test_from_dict_missing_fields_use_defaults() -> void:
	var data := SaveData.from_dict({})
	assert_int(data.current_level).is_equal(1)
	assert_int(int(data.age_band)).is_equal(int(SaveData.AgeBand.UNKNOWN))
	assert_bool(data.settings.haptics).is_true()


func test_from_dict_clamps_current_level_to_minimum() -> void:
	assert_int(SaveData.from_dict({"current_level": 0}).current_level).is_equal(1)
	assert_int(SaveData.from_dict({"current_level": -5}).current_level).is_equal(1)


func test_from_dict_rejects_invalid_age_band() -> void:
	var data := SaveData.from_dict({"age_band": 99})
	assert_int(int(data.age_band)).is_equal(int(SaveData.AgeBand.UNKNOWN))


func test_from_dict_accepts_valid_age_band() -> void:
	var data := SaveData.from_dict({"age_band": int(SaveData.AgeBand.CHILD)})
	assert_int(int(data.age_band)).is_equal(int(SaveData.AgeBand.CHILD))


func test_from_dict_ignores_unknown_settings_keys() -> void:
	var data := SaveData.from_dict({"settings": {"sound": false, "bogus": 123}})
	assert_bool(data.settings.sound).is_false()
	# The typed model only ever serializes the canonical keys — no "bogus".
	assert_bool(data.settings.to_dict().has("bogus")).is_false()


func test_from_dict_normalizes_schema_version() -> void:
	# A pre-versioned (v0) save is upgraded to the current schema version.
	var data := SaveData.from_dict({"current_level": 3})
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)


func test_json_serialization_round_trips() -> void:
	# Regression: age_band/current_level survive a JSON string round-trip even
	# though JSON parses numbers back as floats.
	var original := SaveData.new()
	original.current_level = 4
	original.age_band = SaveData.AgeBand.ADULT
	var text := JSON.stringify(original.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	var restored := SaveData.from_dict(parsed as Dictionary)
	assert_int(restored.current_level).is_equal(4)
	assert_int(int(restored.age_band)).is_equal(int(SaveData.AgeBand.ADULT))


func test_future_schema_version_loads_known_fields() -> void:
	# SD-10: a save from a newer/unknown schema version must load without crashing
	# (no infinite migrate loop), keep its valid known fields, and normalize version.
	var data := SaveData.from_dict({"schema_version": 9999, "current_level": 3})
	assert_int(data.current_level).is_equal(3)
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)


func test_to_dict_contains_canonical_keys() -> void:
	# SD-11: the canonical keys must be PRESENT (superset assertion, so adding a
	# future field like tutorial_seen does not turn this into a failing test).
	var keys: Array = SaveData.new().to_dict().keys()
	for key: String in ["schema_version", "current_level", "age_band", "settings"]:
		assert_bool(keys.has(key)).is_true()


func test_age_band_ordinals_are_stable() -> void:
	# SD-12: the integer ordinals are a persisted contract — reordering the enum
	# would silently reclassify every existing save.
	assert_int(int(SaveData.AgeBand.UNKNOWN)).is_equal(0)
	assert_int(int(SaveData.AgeBand.ADULT)).is_equal(1)
	assert_int(int(SaveData.AgeBand.CHILD)).is_equal(2)


func test_age_band_zero_coerces_to_unknown() -> void:
	# AG-02
	assert_int(int(SaveData.from_dict({"age_band": 0}).age_band)).is_equal(int(SaveData.AgeBand.UNKNOWN))


func test_age_band_one_coerces_to_adult() -> void:
	# AG-03: direct coercion (not via a serialization round-trip)
	assert_int(int(SaveData.from_dict({"age_band": 1}).age_band)).is_equal(int(SaveData.AgeBand.ADULT))


func test_negative_age_band_coerces_to_unknown() -> void:
	# AG-05
	assert_int(int(SaveData.from_dict({"age_band": -1}).age_band)).is_equal(int(SaveData.AgeBand.UNKNOWN))


func test_null_age_band_coerces_to_unknown() -> void:
	# AG-06: an explicit JSON null must NOT crash (int(null) raises) — _parse_age_band
	# guards the type before coercion and falls back to UNKNOWN.
	assert_int(int(SaveData.from_dict({"age_band": null}).age_band)).is_equal(int(SaveData.AgeBand.UNKNOWN))


# ---------------------------------------------------------------------------
# AC6 — tutorial_seen serialization (design/gdd/first-time-tutorial.md §8)
# ---------------------------------------------------------------------------

func test_to_dict_contains_tutorial_seen_key() -> void:
	# AC6: to_dict() must contain the key "tutorial_seen"
	var keys: Array = SaveData.new().to_dict().keys()
	assert_bool(keys.has("tutorial_seen")).is_true()


func test_from_dict_tutorial_seen_true_round_trips() -> void:
	# AC6: from_dict({"tutorial_seen":true}).tutorial_seen == true
	var data := SaveData.from_dict({"tutorial_seen": true})
	assert_bool(data.tutorial_seen).is_true()


func test_from_dict_missing_tutorial_seen_defaults_to_false() -> void:
	# AC6: from_dict({}).tutorial_seen == false  (missing-key default — no schema bump)
	var data := SaveData.from_dict({})
	assert_bool(data.tutorial_seen).is_false()


func test_from_dict_tutorial_seen_false_round_trips() -> void:
	# AC6: from_dict({"tutorial_seen":false}).tutorial_seen == false
	var data := SaveData.from_dict({"tutorial_seen": false})
	assert_bool(data.tutorial_seen).is_false()


func test_tutorial_seen_does_not_bump_schema_version() -> void:
	# AC6: schema_version must still equal CURRENT_SCHEMA_VERSION after a round-trip
	# that includes tutorial_seen — no schema bump was performed.
	var data := SaveData.from_dict({"tutorial_seen": true})
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)


# ---------------------------------------------------------------------------
# S3-002 — wallet fields (schema v2 migration)
# design/gdd/deck-economy.md §Dependencies → Save Service
# ---------------------------------------------------------------------------

func test_schema_version_is_4() -> void:
	# Bumped 2 → 3 (S3-005 daily cap counters), then 3 → 4 (S3-008 daily win counter).
	assert_int(SaveData.CURRENT_SCHEMA_VERSION).is_equal(4)


func test_defaults_include_wallet_fields_at_zero() -> void:
	# A fresh save must have both wallet fields defaulted to 0.
	var data := SaveData.defaults()
	assert_int(data.wallet_coins).is_equal(0)
	assert_int(data.wallet_gems).is_equal(0)


func test_to_dict_contains_wallet_coins_key() -> void:
	var keys: Array = SaveData.new().to_dict().keys()
	assert_bool(keys.has("wallet_coins")).is_true()


func test_to_dict_contains_wallet_gems_key() -> void:
	var keys: Array = SaveData.new().to_dict().keys()
	assert_bool(keys.has("wallet_gems")).is_true()


func test_v2_wallet_round_trips_coins() -> void:
	# A v2 save with wallet values must survive a to_dict/from_dict round-trip losslessly.
	var original := SaveData.new()
	original.wallet_coins = 420
	original.wallet_gems = 8
	var restored := SaveData.from_dict(original.to_dict())
	assert_int(restored.wallet_coins).is_equal(420)


func test_v2_wallet_round_trips_gems() -> void:
	var original := SaveData.new()
	original.wallet_coins = 100
	original.wallet_gems = 33
	var restored := SaveData.from_dict(original.to_dict())
	assert_int(restored.wallet_gems).is_equal(33)


func test_migrate_v1_to_v2_sets_wallet_coins_to_zero() -> void:
	# GDD canonical migration: if version == 1: out["wallet_coins"] = 0; version = 2.
	# Existing fields must be preserved.
	var v1_dict: Dictionary = {
		"schema_version": 1,
		"current_level": 5,
		"age_band": int(SaveData.AgeBand.ADULT),
	}
	var data := SaveData.from_dict(v1_dict)
	assert_int(data.wallet_coins).is_equal(0)


func test_migrate_v1_to_v2_sets_wallet_gems_to_zero() -> void:
	var v1_dict: Dictionary = {
		"schema_version": 1,
		"current_level": 5,
	}
	var data := SaveData.from_dict(v1_dict)
	assert_int(data.wallet_gems).is_equal(0)


func test_migrate_v1_to_v2_schema_version_becomes_current() -> void:
	# A v1 save flows v1→v2→v3; the stored schema_version must match CURRENT.
	var v1_dict: Dictionary = {"schema_version": 1, "current_level": 3}
	var data := SaveData.from_dict(v1_dict)
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)


func test_migrate_v1_to_v2_preserves_current_level() -> void:
	# Migration must not clobber existing fields.
	var v1_dict: Dictionary = {"schema_version": 1, "current_level": 7}
	var data := SaveData.from_dict(v1_dict)
	assert_int(data.current_level).is_equal(7)


func test_migrate_v1_to_v2_preserves_age_band() -> void:
	var v1_dict: Dictionary = {
		"schema_version": 1,
		"age_band": int(SaveData.AgeBand.CHILD),
	}
	var data := SaveData.from_dict(v1_dict)
	assert_int(int(data.age_band)).is_equal(int(SaveData.AgeBand.CHILD))


func test_migrate_v0_unversioned_sets_wallet_fields_to_zero() -> void:
	# Pre-versioned (v0) saves arrive as version 0 and flow through _migrate unchanged;
	# from_dict must still default the missing wallet keys to 0.
	var v0_dict: Dictionary = {"current_level": 2}
	var data := SaveData.from_dict(v0_dict)
	assert_int(data.wallet_coins).is_equal(0)
	assert_int(data.wallet_gems).is_equal(0)


func test_migrate_v0_unversioned_schema_version_normalized() -> void:
	var data := SaveData.from_dict({"current_level": 2})
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)


func test_from_dict_missing_wallet_coins_defaults_to_zero() -> void:
	# A v2 dict that somehow lacks wallet_coins must not crash and must default to 0.
	var data := SaveData.from_dict({"schema_version": 2, "wallet_gems": 5})
	assert_int(data.wallet_coins).is_equal(0)


func test_from_dict_missing_wallet_gems_defaults_to_zero() -> void:
	var data := SaveData.from_dict({"schema_version": 2, "wallet_coins": 10})
	assert_int(data.wallet_gems).is_equal(0)


func test_from_dict_null_wallet_coins_clamped_to_zero() -> void:
	# null wallet values must not crash and must default to 0.
	var data := SaveData.from_dict({"schema_version": 2, "wallet_coins": null, "wallet_gems": 0})
	assert_int(data.wallet_coins).is_equal(0)


func test_from_dict_null_wallet_gems_clamped_to_zero() -> void:
	var data := SaveData.from_dict({"schema_version": 2, "wallet_coins": 0, "wallet_gems": null})
	assert_int(data.wallet_gems).is_equal(0)


func test_from_dict_negative_wallet_coins_clamped_to_zero() -> void:
	var data := SaveData.from_dict({"schema_version": 2, "wallet_coins": -500, "wallet_gems": 0})
	assert_int(data.wallet_coins).is_equal(0)


func test_from_dict_negative_wallet_gems_clamped_to_zero() -> void:
	var data := SaveData.from_dict({"schema_version": 2, "wallet_coins": 0, "wallet_gems": -1})
	assert_int(data.wallet_gems).is_equal(0)


# ---------------------------------------------------------------------------
# S3-005 — daily cap counters (schema v3 migration)
# design/gdd/deck-economy.md Rule 15 / Rule 21 / Formula 7 / Formula 8
# ---------------------------------------------------------------------------

func test_schema_v3_defaults_include_daily_fields_at_zero() -> void:
	# A fresh SaveData must have all four v3 fields defaulted to 0.
	var data := SaveData.defaults()
	assert_int(data.daily_key).is_equal(0)
	assert_int(data.ad_coins_today).is_equal(0)
	assert_int(data.ads_watched_today).is_equal(0)
	assert_int(data.gems_converted_today).is_equal(0)


func test_to_dict_contains_all_four_v3_keys() -> void:
	var keys: Array = SaveData.new().to_dict().keys()
	for key: String in ["daily_key", "ad_coins_today", "ads_watched_today", "gems_converted_today"]:
		assert_bool(keys.has(key)).is_true()


func test_v3_dict_round_trips_all_daily_fields() -> void:
	# A v3 save with non-zero daily counters must survive a to_dict/from_dict round-trip.
	var original := SaveData.new()
	original.daily_key = 20000
	original.ad_coins_today = 120
	original.ads_watched_today = 2
	original.gems_converted_today = 30
	original.wallet_coins = 500
	original.wallet_gems = 10
	var restored := SaveData.from_dict(original.to_dict())
	assert_int(restored.daily_key).is_equal(20000)
	assert_int(restored.ad_coins_today).is_equal(120)
	assert_int(restored.ads_watched_today).is_equal(2)
	assert_int(restored.gems_converted_today).is_equal(30)
	assert_int(restored.wallet_coins).is_equal(500)
	assert_int(restored.wallet_gems).is_equal(10)


func test_migrate_v2_to_v3_sets_daily_fields_to_zero() -> void:
	# A v2 dict with wallet values migrates to v3; daily fields default to 0,
	# and existing wallet + level fields are preserved.
	var v2_dict: Dictionary = {
		"schema_version": 2,
		"current_level": 9,
		"wallet_coins": 420,
		"wallet_gems": 8,
	}
	var data := SaveData.from_dict(v2_dict)
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)
	assert_int(data.daily_key).is_equal(0)
	assert_int(data.ad_coins_today).is_equal(0)
	assert_int(data.ads_watched_today).is_equal(0)
	assert_int(data.gems_converted_today).is_equal(0)
	# Existing fields preserved.
	assert_int(data.wallet_coins).is_equal(420)
	assert_int(data.wallet_gems).is_equal(8)
	assert_int(data.current_level).is_equal(9)


func test_migrate_v1_flows_all_the_way_to_v3() -> void:
	# A v1 save must migrate v1→v2→v3 in sequence; all four daily fields == 0,
	# wallet fields == 0, and the existing level field is preserved (AC-SD chain).
	var v1_dict: Dictionary = {
		"schema_version": 1,
		"current_level": 4,
		"age_band": int(SaveData.AgeBand.ADULT),
	}
	var data := SaveData.from_dict(v1_dict)
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)
	assert_int(data.wallet_coins).is_equal(0)
	assert_int(data.wallet_gems).is_equal(0)
	assert_int(data.daily_key).is_equal(0)
	assert_int(data.ad_coins_today).is_equal(0)
	assert_int(data.ads_watched_today).is_equal(0)
	assert_int(data.gems_converted_today).is_equal(0)
	assert_int(data.current_level).is_equal(4)
	assert_int(int(data.age_band)).is_equal(int(SaveData.AgeBand.ADULT))


func test_from_dict_missing_daily_fields_default_to_zero() -> void:
	# A v3 dict that lacks any of the four daily keys must not crash and must default 0.
	var data := SaveData.from_dict({"schema_version": 3, "wallet_coins": 10})
	assert_int(data.daily_key).is_equal(0)
	assert_int(data.ad_coins_today).is_equal(0)
	assert_int(data.ads_watched_today).is_equal(0)
	assert_int(data.gems_converted_today).is_equal(0)


func test_from_dict_null_daily_fields_clamped_to_zero() -> void:
	# Explicit null on any daily field must not crash (int(null) raises in GDScript).
	var data := SaveData.from_dict({
		"schema_version": 3,
		"daily_key": null,
		"ad_coins_today": null,
		"ads_watched_today": null,
		"gems_converted_today": null,
	})
	assert_int(data.daily_key).is_equal(0)
	assert_int(data.ad_coins_today).is_equal(0)
	assert_int(data.ads_watched_today).is_equal(0)
	assert_int(data.gems_converted_today).is_equal(0)


func test_from_dict_negative_daily_fields_clamped_to_zero() -> void:
	# Negative values on daily counters must be clamped to 0 (maxi guard).
	var data := SaveData.from_dict({
		"schema_version": 3,
		"daily_key": -1,
		"ad_coins_today": -100,
		"ads_watched_today": -5,
		"gems_converted_today": -50,
	})
	assert_int(data.daily_key).is_equal(0)
	assert_int(data.ad_coins_today).is_equal(0)
	assert_int(data.ads_watched_today).is_equal(0)
	assert_int(data.gems_converted_today).is_equal(0)


# ---------------------------------------------------------------------------
# S3-008 — daily win counter (schema v4 migration)
# design/gdd/deck-economy.md Formula 1 / AC-EF01 / AC-EF02
# ---------------------------------------------------------------------------

func test_defaults_include_wins_today_at_zero() -> void:
	assert_int(SaveData.defaults().wins_today).is_equal(0)


func test_to_dict_contains_wins_today_key() -> void:
	assert_bool(SaveData.new().to_dict().keys().has("wins_today")).is_true()


func test_v4_dict_round_trips_wins_today() -> void:
	var original := SaveData.new()
	original.wins_today = 3
	var restored := SaveData.from_dict(original.to_dict())
	assert_int(restored.wins_today).is_equal(3)


func test_migrate_v3_to_v4_sets_wins_today_to_zero() -> void:
	# A v3 dict with daily counters migrates to v4; wins_today defaults to 0 and
	# the existing v3 fields are preserved.
	var v3_dict: Dictionary = {
		"schema_version": 3,
		"current_level": 6,
		"wallet_coins": 200,
		"daily_key": 19000,
		"ad_coins_today": 120,
	}
	var data := SaveData.from_dict(v3_dict)
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)
	assert_int(data.wins_today).is_equal(0)
	# Existing fields preserved.
	assert_int(data.wallet_coins).is_equal(200)
	assert_int(data.daily_key).is_equal(19000)
	assert_int(data.ad_coins_today).is_equal(120)
	assert_int(data.current_level).is_equal(6)


func test_migrate_v1_flows_all_the_way_to_v4() -> void:
	# A v1 save must migrate v1→v2→v3→v4; wallet + all daily fields default to 0,
	# wins_today == 0, and the existing level/age fields are preserved.
	var v1_dict: Dictionary = {
		"schema_version": 1,
		"current_level": 4,
		"age_band": int(SaveData.AgeBand.ADULT),
	}
	var data := SaveData.from_dict(v1_dict)
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)
	assert_int(data.wallet_coins).is_equal(0)
	assert_int(data.wallet_gems).is_equal(0)
	assert_int(data.daily_key).is_equal(0)
	assert_int(data.ad_coins_today).is_equal(0)
	assert_int(data.ads_watched_today).is_equal(0)
	assert_int(data.gems_converted_today).is_equal(0)
	assert_int(data.wins_today).is_equal(0)
	assert_int(data.current_level).is_equal(4)
	assert_int(int(data.age_band)).is_equal(int(SaveData.AgeBand.ADULT))


func test_from_dict_missing_wins_today_defaults_to_zero() -> void:
	var data := SaveData.from_dict({"schema_version": 4, "wallet_coins": 10})
	assert_int(data.wins_today).is_equal(0)


func test_from_dict_null_wins_today_clamped_to_zero() -> void:
	var data := SaveData.from_dict({"schema_version": 4, "wins_today": null})
	assert_int(data.wins_today).is_equal(0)


func test_from_dict_negative_wins_today_clamped_to_zero() -> void:
	var data := SaveData.from_dict({"schema_version": 4, "wins_today": -3})
	assert_int(data.wins_today).is_equal(0)
