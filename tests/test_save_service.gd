extends GdUnitTestSuite
## Integration tests for [SaveService] disk persistence (S1-001).
##
## These touch the filesystem (under `user://`) and clean up after themselves, so
## they are integration tests rather than pure unit tests. The service is
## instantiated directly (not via the autoload) and pointed at a temp file.

const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const TEST_PATH := "user://test_save_service.json"


func before_test() -> void:
	_remove_test_file()


func after_test() -> void:
	_remove_test_file()


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(TEST_PATH.get_file())


func test_save_then_load_round_trips_to_disk() -> void:
	# Arrange
	var writer = auto_free(SAVE_SCRIPT.new())
	writer.configure(TEST_PATH)
	writer.data.current_level = 5
	writer.data.age_band = SaveData.AgeBand.ADULT
	writer.data.settings.music = false
	# Act
	writer.save_game()
	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(TEST_PATH)
	reader.load_game()
	# Assert
	assert_int(reader.data.current_level).is_equal(5)
	assert_int(int(reader.data.age_band)).is_equal(int(SaveData.AgeBand.ADULT))
	assert_bool(reader.data.settings.music).is_false()


func test_load_missing_file_uses_defaults() -> void:
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)  # before_test guarantees the file is absent
	svc.load_game()
	assert_int(svc.data.current_level).is_equal(1)
	assert_int(int(svc.data.age_band)).is_equal(int(SaveData.AgeBand.UNKNOWN))


func test_load_corrupt_file_uses_defaults() -> void:
	# Arrange: write garbage that is not valid JSON
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ this is not valid json ")
	file.close()
	# Act
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	svc.load_game()
	# Assert
	assert_int(svc.data.current_level).is_equal(1)


func test_set_current_level_persists() -> void:
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	svc.set_current_level(9)

	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(TEST_PATH)
	reader.load_game()
	assert_int(reader.data.current_level).is_equal(9)


func test_set_age_band_persists() -> void:
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	svc.set_age_band(SaveData.AgeBand.CHILD)

	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(TEST_PATH)
	reader.load_game()
	assert_int(int(reader.data.age_band)).is_equal(int(SaveData.AgeBand.CHILD))
