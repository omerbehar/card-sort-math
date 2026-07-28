extends GdUnitTestSuite
## Integration tests — SaveService compliance integrity (M4-R2, ADR-0013 §4).
##
## A signed save round-trips the protected fields intact; a tampered or unsigned save fails
## closed on load — the protected fields (age_band + consent + Remove-Ads) reset to
## conservative defaults while non-protected progress (level, wallet) is kept, and
## `integrity_failed` fires.

const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")

var _temp: Array[String] = []


func after_test() -> void:
	for path: String in _temp:
		if FileAccess.file_exists(path):
			DirAccess.open("user://").remove(path.get_file())
		var tmp: String = path + ".tmp"
		if FileAccess.file_exists(tmp):
			DirAccess.open("user://").remove(tmp.get_file())
	_temp.clear()


func test_signed_save_roundtrips_protected_fields() -> void:
	var path := "user://test_integrity_roundtrip.json"
	_temp.append(path)

	var writer = auto_free(SAVE_SCRIPT.new())
	writer.configure(path)
	writer.data.age_band = SaveData.AgeBand.ADULT
	writer.data.consent_analytics = true
	writer.data.consent_captured = true
	writer.data.remove_ads_owned = true
	writer.save_game()   # signs

	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(path)
	reader.load_game()

	# Valid signature → protected fields survive the reload.
	assert_int(reader.data.age_band).is_equal(SaveData.AgeBand.ADULT)
	assert_bool(reader.data.consent_analytics).is_true()
	assert_bool(reader.data.remove_ads_owned).is_true()


func test_unsigned_tampered_save_resets_protected_but_keeps_progress() -> void:
	var path := "user://test_integrity_unsigned.json"
	_temp.append(path)

	# Hand-crafted "hacked" save: adult + Remove-Ads owned + progress, but NO signature.
	var d := SaveData.new()
	d.current_level = 7
	d.wallet_coins = 500
	var dict := d.to_dict()
	dict["age_band"] = SaveData.AgeBand.ADULT
	dict["remove_ads_owned"] = true
	dict["consent_personalized_ads"] = true
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(dict))
	f.close()

	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(path)
	var failed: Array = [false]
	svc.integrity_failed.connect(func() -> void: failed[0] = true)
	svc.load_game()

	# Fail-closed: protected fields reset; progress preserved; signal fired.
	assert_bool(failed[0]).is_true()
	assert_int(svc.data.age_band).is_equal(SaveData.AgeBand.UNKNOWN)
	assert_bool(svc.data.remove_ads_owned).is_false()
	assert_bool(svc.data.consent_personalized_ads).is_false()
	assert_int(svc.data.current_level).is_equal(7)
	assert_int(svc.data.wallet_coins).is_equal(500)


func test_forged_signature_is_rejected() -> void:
	var path := "user://test_integrity_forged.json"
	_temp.append(path)

	var dict := SaveData.new().to_dict()
	dict["age_band"] = SaveData.AgeBand.ADULT
	dict[SaveIntegrity.SIG_KEY] = "deadbeef"   # a bogus signature, no secret
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(dict))
	f.close()

	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(path)
	svc.load_game()

	assert_int(svc.data.age_band).is_equal(SaveData.AgeBand.UNKNOWN)
