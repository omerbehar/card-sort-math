extends GdUnitTestSuite
## Integration tests for [SettingsService] persistence + change signals (S1-003).
##
## Backed by a temp-file SaveService; self-cleaning.

const SETTINGS_SCRIPT := preload("res://autoloads/settings_service.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const TEST_PATH := "user://test_settings_service.json"


func before_test() -> void:
	_remove_test_file()


func after_test() -> void:
	_remove_test_file()


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(TEST_PATH.get_file())


func _make_save():
	var save = auto_free(SAVE_SCRIPT.new())
	save.configure(TEST_PATH)
	save.load_game()
	return save


func test_get_value_reads_defaults() -> void:
	var svc = auto_free(SETTINGS_SCRIPT.new())
	svc.configure(_make_save())
	assert_bool(svc.get_value("sound")).is_true()
	assert_bool(svc.get_value("reduced_motion")).is_false()


func test_set_value_persists_to_disk() -> void:
	# Arrange
	var save = _make_save()
	var svc = auto_free(SETTINGS_SCRIPT.new())
	svc.configure(save)
	# Act
	svc.set_value("music", false)
	# Assert: a fresh service reads the change back from disk
	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(TEST_PATH)
	reader.load_game()
	assert_bool(reader.data.settings.music).is_false()


func test_set_value_emits_changed_signal() -> void:
	var svc = auto_free(SETTINGS_SCRIPT.new())
	svc.configure(_make_save())
	var captured: Array = ["", true]
	svc.changed.connect(func(key: String, value: bool) -> void:
		captured[0] = key
		captured[1] = value)
	svc.set_value("haptics", false)
	assert_str(captured[0]).is_equal("haptics")
	assert_bool(captured[1]).is_false()


func test_toggle_flips_and_persists() -> void:
	var save = _make_save()
	var svc = auto_free(SETTINGS_SCRIPT.new())
	svc.configure(save)
	assert_bool(svc.get_value("sound")).is_true()
	svc.toggle("sound")
	assert_bool(svc.get_value("sound")).is_false()

	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(TEST_PATH)
	reader.load_game()
	assert_bool(reader.data.settings.sound).is_false()


func test_set_unknown_key_does_not_emit() -> void:
	var svc = auto_free(SETTINGS_SCRIPT.new())
	svc.configure(_make_save())
	var emitted: Array[bool] = [false]
	svc.changed.connect(func(_key: String, _value: bool) -> void: emitted[0] = true)
	svc.set_value("bogus", true)
	assert_bool(emitted[0]).is_false()
