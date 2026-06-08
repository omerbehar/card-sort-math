extends GdUnitTestSuite
## Interaction tests for [SettingsPanel] binding (S1-011).
##
## The visual "look" is verified manually; these cover the deterministic
## contract: each row reflects the current [Settings] value, tapping a row drives
## [method SettingsService.toggle] (mutating the persisted setting), and an
## external change refreshes the row. Backed by a temp-file SettingsService so the
## panel owns no state of its own.

const PANEL_SCRIPT := preload("res://scenes/ui/settings_panel.gd")
const SETTINGS_SCRIPT := preload("res://autoloads/settings_service.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const TEST_PATH := "user://test_settings_panel.json"

const DOT_FULL := "res://assets/ui/kenney/dot_full.png"
const DOT_EMPTY := "res://assets/ui/kenney/dot_empty.png"


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


# configure() must run before _ready(), so inject before adding to the tree.
func _make_panel(settings) -> SettingsPanel:
	var panel: SettingsPanel = auto_free(PANEL_SCRIPT.new())
	panel.configure(settings)
	add_child(panel)
	return panel


func test_row_dot_reflects_initial_setting() -> void:
	var settings = _make_settings()
	settings.set_value("music", false)  # sound defaults on, music now off
	var panel := _make_panel(settings)

	var sound_dot: Sprite2D = panel._dots["sound"]
	var music_dot: Sprite2D = panel._dots["music"]
	assert_str(sound_dot.texture.resource_path).is_equal(DOT_FULL)
	assert_str(music_dot.texture.resource_path).is_equal(DOT_EMPTY)


func test_tapping_row_toggles_persisted_setting() -> void:
	var settings = _make_settings()
	var panel := _make_panel(settings)
	assert_bool(settings.get_value("haptics")).is_true()  # default on

	panel._row_buttons["haptics"].pressed.emit()

	assert_bool(settings.get_value("haptics")).is_false()


func test_tapping_row_refreshes_its_dot() -> void:
	var settings = _make_settings()
	var panel := _make_panel(settings)

	panel._row_buttons["sound"].pressed.emit()  # on -> off

	var sound_dot: Sprite2D = panel._dots["sound"]
	assert_str(sound_dot.texture.resource_path).is_equal(DOT_EMPTY)


func test_external_change_refreshes_dot() -> void:
	var settings = _make_settings()
	var panel := _make_panel(settings)

	# Flip via the service directly (as if changed from elsewhere).
	settings.set_value("reduced_motion", true)  # default off -> on

	var rm_dot: Sprite2D = panel._dots["reduced_motion"]
	assert_str(rm_dot.texture.resource_path).is_equal(DOT_FULL)


func test_dismiss_emits_closed() -> void:
	var settings = _make_settings()
	var panel := _make_panel(settings)
	var emitted := [false]
	panel.closed.connect(func() -> void: emitted[0] = true)

	panel._dismiss()

	assert_bool(emitted[0]).is_true()
