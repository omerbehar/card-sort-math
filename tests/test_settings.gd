extends GdUnitTestSuite
## Tests for the [Settings] model serialization and validation (S1-003).


func test_defaults_are_sane() -> void:
	var s := Settings.defaults()
	assert_bool(s.sound).is_true()
	assert_bool(s.music).is_true()
	assert_bool(s.haptics).is_true()
	assert_bool(s.reduced_motion).is_false()
	assert_bool(s.colorblind).is_false()


func test_colorblind_round_trips_and_sets_by_key() -> void:
	var s := Settings.new()
	assert_bool(s.set_value("colorblind", true)).is_true()
	assert_bool(s.get_value("colorblind")).is_true()
	var restored := Settings.from_dict(s.to_dict())
	assert_bool(restored.colorblind).is_true()


func test_from_dict_missing_colorblind_defaults_false() -> void:
	# Saves written before the colorblind key existed must load safely.
	var s := Settings.from_dict({"sound": true, "music": true, "haptics": true, "reduced_motion": false})
	assert_bool(s.colorblind).is_false()


func test_to_dict_from_dict_round_trips() -> void:
	var original := Settings.new()
	original.sound = false
	original.reduced_motion = true
	var restored := Settings.from_dict(original.to_dict())
	assert_bool(restored.sound).is_false()
	assert_bool(restored.reduced_motion).is_true()
	assert_bool(restored.music).is_true()


func test_from_dict_missing_keys_use_defaults() -> void:
	var s := Settings.from_dict({"sound": false})
	assert_bool(s.sound).is_false()
	assert_bool(s.music).is_true()
	assert_bool(s.haptics).is_true()


func test_from_dict_ignores_unknown_keys() -> void:
	var s := Settings.from_dict({"music": false, "bogus": 42})
	assert_bool(s.music).is_false()
	assert_bool(s.to_dict().has("bogus")).is_false()


func test_from_dict_non_dictionary_yields_defaults() -> void:
	var s := Settings.from_dict("not a dict")
	assert_bool(s.sound).is_true()
	assert_bool(s.reduced_motion).is_false()


func test_get_and_set_value_by_key() -> void:
	var s := Settings.new()
	assert_bool(s.set_value("haptics", false)).is_true()
	assert_bool(s.haptics).is_false()
	assert_bool(s.get_value("haptics")).is_false()


func test_set_unknown_key_returns_false() -> void:
	var s := Settings.new()
	assert_bool(s.set_value("bogus", true)).is_false()


func test_keys_constant_matches_serialized_shape() -> void:
	var keys: Array = Settings.new().to_dict().keys()
	for key: String in Settings.KEYS:
		assert_bool(keys.has(key)).is_true()
	assert_int(keys.size()).is_equal(Settings.KEYS.size())
