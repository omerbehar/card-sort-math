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
	_remove(TEST_PATH)
	_remove(TEST_PATH + ".tmp")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(path.get_file())


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


func test_set_age_band_adult_persists() -> void:
	# AG-03b: the compliance-critical ADULT value must survive a disk round-trip,
	# not just CHILD (parity with test_set_age_band_persists).
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	svc.set_age_band(SaveData.AgeBand.ADULT)

	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(TEST_PATH)
	reader.load_game()
	assert_int(int(reader.data.age_band)).is_equal(int(SaveData.AgeBand.ADULT))


func test_age_band_unknown_persists_as_unknown() -> void:
	# AG-07: a persisted UNKNOWN must reload as UNKNOWN (never silently upgraded).
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	svc.set_age_band(SaveData.AgeBand.UNKNOWN)

	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(TEST_PATH)
	reader.load_game()
	assert_int(int(reader.data.age_band)).is_equal(int(SaveData.AgeBand.UNKNOWN))


func test_set_current_level_zero_clamps_to_one() -> void:
	# SV-06
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	svc.set_current_level(0)

	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(TEST_PATH)
	reader.load_game()
	assert_int(reader.data.current_level).is_equal(1)


func test_loaded_signal_emitted_once_on_missing_file() -> void:
	# SV-07a: no file → `loaded` fires exactly once (counter, not a bool); no load_failed.
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)  # before_test guarantees absence
	var count: Array[int] = [0]
	var failed: Array[int] = [0]
	svc.loaded.connect(func() -> void: count[0] += 1)
	svc.load_failed.connect(func() -> void: failed[0] += 1)
	svc.load_game()
	assert_int(count[0]).is_equal(1)
	assert_int(failed[0]).is_equal(0)


func test_loaded_signal_emitted_once_on_success() -> void:
	# SV-07b: valid file → `loaded` fires exactly once.
	var writer = auto_free(SAVE_SCRIPT.new())
	writer.configure(TEST_PATH)
	writer.save_game()

	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	var count: Array[int] = [0]
	svc.loaded.connect(func() -> void: count[0] += 1)
	svc.load_game()
	assert_int(count[0]).is_equal(1)


func test_load_failed_signal_on_corrupt_file() -> void:
	# SV-08: corrupt JSON → `load_failed` fires once, `loaded` does NOT.
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ this is not valid json ")
	file.close()

	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	var loaded_count: Array[int] = [0]
	var failed_count: Array[int] = [0]
	svc.loaded.connect(func() -> void: loaded_count[0] += 1)
	svc.load_failed.connect(func() -> void: failed_count[0] += 1)
	svc.load_game()
	assert_int(failed_count[0]).is_equal(1)
	assert_int(loaded_count[0]).is_equal(0)
	assert_int(svc.data.current_level).is_equal(1)


func test_saved_signal_emitted_once_on_success() -> void:
	# SV-09
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	var count: Array[int] = [0]
	svc.saved.connect(func() -> void: count[0] += 1)
	svc.save_game()
	assert_int(count[0]).is_equal(1)


func test_rapid_saves_last_write_wins() -> void:
	# SV-10: three back-to-back synchronous saves; the final value must win.
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	svc.set_current_level(2)
	svc.set_current_level(3)
	svc.set_current_level(4)

	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(TEST_PATH)
	reader.load_game()
	assert_int(reader.data.current_level).is_equal(4)


func test_configure_redirects_io() -> void:
	# SV-11: configure(B) after writing A → save/reload uses B; A is untouched.
	var path_a := "user://test_save_service_a.json"
	var path_b := "user://test_save_service_b.json"
	_remove(path_a)
	_remove(path_a + ".tmp")
	_remove(path_b)
	_remove(path_b + ".tmp")

	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(path_a)
	svc.set_current_level(7)  # writes A
	svc.configure(path_b)
	svc.set_current_level(8)  # writes B

	var reader_b = auto_free(SAVE_SCRIPT.new())
	reader_b.configure(path_b)
	reader_b.load_game()
	assert_int(reader_b.data.current_level).is_equal(8)

	var reader_a = auto_free(SAVE_SCRIPT.new())
	reader_a.configure(path_a)
	reader_a.load_game()
	assert_int(reader_a.data.current_level).is_equal(7)

	_remove(path_a)
	_remove(path_b)


func test_write_is_atomic_via_temp_rename() -> void:
	# SV-14: a successful save leaves a single valid file and no leftover .tmp.
	var svc = auto_free(SAVE_SCRIPT.new())
	svc.configure(TEST_PATH)
	svc.set_current_level(5)
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_true()
	assert_bool(FileAccess.file_exists(TEST_PATH + ".tmp")).is_false()


# SV-12 (EC2: file exists but open() returns null) and SV-13 (EC4: write failure)
# are intentionally NOT automated here: triggering a null FileAccess.open() requires
# a FileAccess DI seam (tracked with the atomic-write follow-up) or platform-level
# permission manipulation. They are marked manual-platform-verified in the GDD.
