extends GdUnitTestSuite
## Tests for [SaveData] serialization, validation, and schema migration (S1-001).


func test_defaults_are_safe() -> void:
	# Arrange / Act
	var data := SaveData.defaults()
	# Assert
	assert_int(data.schema_version).is_equal(SaveData.CURRENT_SCHEMA_VERSION)
	assert_int(data.current_level).is_equal(1)
	assert_int(int(data.age_band)).is_equal(int(SaveData.AgeBand.UNKNOWN))
	assert_bool(data.settings["sound"]).is_true()
	assert_bool(data.settings["reduced_motion"]).is_false()


func test_to_dict_from_dict_round_trips() -> void:
	# Arrange
	var original := SaveData.new()
	original.current_level = 7
	original.age_band = SaveData.AgeBand.ADULT
	original.settings["music"] = false
	# Act
	var restored := SaveData.from_dict(original.to_dict())
	# Assert
	assert_int(restored.current_level).is_equal(7)
	assert_int(int(restored.age_band)).is_equal(int(SaveData.AgeBand.ADULT))
	assert_bool(restored.settings["music"]).is_false()
	assert_bool(restored.settings["sound"]).is_true()


func test_from_dict_missing_fields_use_defaults() -> void:
	var data := SaveData.from_dict({})
	assert_int(data.current_level).is_equal(1)
	assert_int(int(data.age_band)).is_equal(int(SaveData.AgeBand.UNKNOWN))
	assert_bool(data.settings["haptics"]).is_true()


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
	assert_bool(data.settings["sound"]).is_false()
	assert_bool(data.settings.has("bogus")).is_false()


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
