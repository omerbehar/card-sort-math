extends GdUnitTestSuite
## Tests for [JuiceService] settings gating (S1-005).
##
## The visual/haptic "feel" is verified manually; these cover the deterministic
## contract: reduced_motion disables visual juice and haptics gates vibration —
## and disabling juice never throws. Backed by a temp-file SettingsService.

const JUICE_SCRIPT := preload("res://autoloads/juice_service.gd")
const SETTINGS_SCRIPT := preload("res://autoloads/settings_service.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const TEST_PATH := "user://test_juice_service.json"


func before_test() -> void:
	_remove_test_file()


func after_test() -> void:
	_remove_test_file()


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(TEST_PATH.get_file())


func _make_settings():
	var save = auto_free(SAVE_SCRIPT.new())
	save.configure(TEST_PATH)
	save.load_game()
	var settings = auto_free(SETTINGS_SCRIPT.new())
	settings.configure(save)
	return settings


func _make_juice(settings):
	var juice = auto_free(JUICE_SCRIPT.new())
	juice.configure(settings)
	return juice


func test_motion_enabled_reflects_reduced_motion_setting() -> void:
	var settings = _make_settings()
	var juice = _make_juice(settings)
	assert_bool(juice.is_motion_enabled()).is_true()  # reduced_motion defaults false
	settings.set_value("reduced_motion", true)
	assert_bool(juice.is_motion_enabled()).is_false()


func test_haptics_enabled_reflects_setting() -> void:
	var settings = _make_settings()
	var juice = _make_juice(settings)
	assert_bool(juice.is_haptics_enabled()).is_true()  # defaults true
	settings.set_value("haptics", false)
	assert_bool(juice.is_haptics_enabled()).is_false()


func test_burst_returns_null_when_motion_disabled() -> void:
	var settings = _make_settings()
	settings.set_value("reduced_motion", true)
	var juice = _make_juice(settings)
	var parent: Node2D = auto_free(Node2D.new())
	assert_object(juice.burst(parent, Vector2.ZERO)).is_null()
	assert_int(parent.get_child_count()).is_equal(0)


func test_burst_emits_when_motion_enabled() -> void:
	var juice = _make_juice(_make_settings())
	var parent: Node2D = auto_free(Node2D.new())
	var emitter = juice.burst(parent, Vector2(10, 20))
	assert_object(emitter).is_not_null()
	assert_int(parent.get_child_count()).is_equal(1)


func test_punch_is_noop_when_motion_disabled() -> void:
	var settings = _make_settings()
	settings.set_value("reduced_motion", true)
	var juice = _make_juice(settings)
	var node: Node2D = auto_free(Node2D.new())
	node.scale = Vector2.ONE
	juice.punch(node)  # must not start a tween or change scale
	assert_vector(node.scale).is_equal(Vector2.ONE)


func test_haptic_with_haptics_off_does_not_throw() -> void:
	var settings = _make_settings()
	settings.set_value("haptics", false)
	var juice = _make_juice(settings)
	juice.haptic(20)  # gated off — no vibration, no error
	assert_bool(juice.is_haptics_enabled()).is_false()
