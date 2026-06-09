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
