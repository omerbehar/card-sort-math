extends GdUnitTestSuite
## Tests for [GameManager] progression persistence via SaveService (S1-002).
##
## GameManager and SaveService are instantiated directly (not via autoloads) and
## the save service is pointed at a temp file, so these are isolated and
## self-cleaning. Signals are verified with lambda capture for determinism.

const GM_SCRIPT := preload("res://autoloads/game_manager.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const TEST_PATH := "user://test_game_manager.json"


func before_test() -> void:
	_remove_test_file()


func after_test() -> void:
	_remove_test_file()


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(TEST_PATH.get_file())


# Builds a SaveService pointed at the temp file, optionally seeded to a level.
func _make_save(seed_level: int = 0):
	var save = auto_free(SAVE_SCRIPT.new())
	save.configure(TEST_PATH)
	save.load_game()
	if seed_level > 0:
		save.set_current_level(seed_level)
	return save


func test_loads_current_level_from_save() -> void:
	# Arrange: a save that already records progress at level 3
	var save = _make_save(3)
	# Act
	var gm = auto_free(GM_SCRIPT.new())
	gm.configure(save)
	# Assert
	assert_int(gm.current_level).is_equal(3)


func test_defaults_to_level_one_with_empty_save() -> void:
	var gm = auto_free(GM_SCRIPT.new())
	gm.configure(_make_save())
	assert_int(gm.current_level).is_equal(1)


func test_complete_level_advances_and_persists_to_disk() -> void:
	# Arrange
	var save = _make_save()
	var gm = auto_free(GM_SCRIPT.new())
	gm.configure(save)
	assert_int(gm.current_level).is_equal(1)
	# Act
	gm.complete_level()
	# Assert: advanced in memory ...
	assert_int(gm.current_level).is_equal(2)
	# ... and persisted (a fresh service reads it back from disk)
	var reader = auto_free(SAVE_SCRIPT.new())
	reader.configure(TEST_PATH)
	reader.load_game()
	assert_int(reader.data.current_level).is_equal(2)


func test_complete_level_advances_past_authored_set_endlessly() -> void:
	# Progression is endless (S2-004): levels beyond the authored set are
	# generated, so completing the last authored level advances into generated
	# territory rather than capping.
	var last: int = LevelData.level_count()
	var gm = auto_free(GM_SCRIPT.new())
	gm.configure(_make_save(last))
	gm.complete_level()
	assert_int(gm.current_level).is_equal(last + 1)


func test_complete_level_emits_completed_with_finished_level() -> void:
	var gm = auto_free(GM_SCRIPT.new())
	gm.configure(_make_save())  # current_level == 1
	var captured: Array[int] = [-1]
	gm.level_completed.connect(func(level: int) -> void: captured[0] = level)
	gm.complete_level()
	# The signal reports the level that was finished (before advancing)
	assert_int(captured[0]).is_equal(1)
	assert_int(gm.current_level).is_equal(2)


func test_fail_level_emits_game_over_and_keeps_progress() -> void:
	var gm = auto_free(GM_SCRIPT.new())
	gm.configure(_make_save(2))
	var captured: Array[int] = [-1]
	gm.game_over.connect(func(level: int) -> void: captured[0] = level)
	gm.fail_level()
	assert_int(captured[0]).is_equal(2)
	assert_int(gm.current_level).is_equal(2)


func test_start_level_sets_current_and_emits() -> void:
	var gm = auto_free(GM_SCRIPT.new())
	gm.configure(_make_save())
	var captured: Array[int] = [-1]
	gm.level_started.connect(func(level: int) -> void: captured[0] = level)
	gm.start_level(2)
	assert_int(gm.current_level).is_equal(2)
	assert_int(captured[0]).is_equal(2)
