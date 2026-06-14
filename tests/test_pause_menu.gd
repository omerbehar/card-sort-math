extends GdUnitTestSuite
## Interaction tests for [PauseMenu] binding (S1-011).
##
## The visual "look" is verified manually (see production/qa/evidence); these
## cover the deterministic contract: round audio toggles and pill switches both
## drive [method SettingsService.toggle] (mutating the persisted setting), the
## controls reflect the current value and refresh on external change, and the
## Continue / Home actions emit their signals. Backed by a temp-file
## SettingsService so the menu owns no state of its own.

const MENU_SCRIPT := preload("res://scenes/ui/pause_menu.gd")
const SETTINGS_SCRIPT := preload("res://autoloads/settings_service.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const TEST_PATH := "user://test_pause_menu.json"

const ON_TINT := Color(0.36, 0.78, 0.45)
const OFF_TINT := Color(0.52, 0.55, 0.62)


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
func _make_menu(settings) -> PauseMenu:
	var menu: PauseMenu = auto_free(MENU_SCRIPT.new())
	menu.configure(settings)
	add_child(menu)
	return menu


func test_audio_toggle_reflects_initial_setting() -> void:
	var settings = _make_settings()
	settings.set_value("music", false)  # sound on, music off
	var menu := _make_menu(settings)

	assert_object(menu._round_bg["sound"].self_modulate).is_equal(ON_TINT)
	assert_object(menu._round_bg["music"].self_modulate).is_equal(OFF_TINT)


func test_tapping_audio_toggle_mutates_persisted_setting() -> void:
	var settings = _make_settings()
	var menu := _make_menu(settings)
	assert_bool(settings.get_value("haptics")).is_true()

	menu._buttons["haptics"].pressed.emit()

	assert_bool(settings.get_value("haptics")).is_false()
	assert_object(menu._round_bg["haptics"].self_modulate).is_equal(OFF_TINT)


func test_switch_row_toggles_colorblind_setting() -> void:
	var settings = _make_settings()
	var menu := _make_menu(settings)
	assert_bool(settings.get_value("colorblind")).is_false()

	menu._buttons["colorblind"].pressed.emit()

	assert_bool(settings.get_value("colorblind")).is_true()
	assert_object(menu._switch_track["colorblind"].self_modulate).is_equal(ON_TINT)


func test_switch_knob_moves_right_when_on() -> void:
	var settings = _make_settings()
	var menu := _make_menu(settings)
	var track: NinePatchRect = menu._switch_track["reduced_motion"]
	var knob: Sprite2D = menu._switch_knob["reduced_motion"]
	var off_x: float = knob.position.x

	menu._buttons["reduced_motion"].pressed.emit()  # off -> on

	assert_float(knob.position.x).is_greater(off_x)
	assert_float(knob.position.x).is_less(track.position.x + track.size.x)


func test_external_change_refreshes_control() -> void:
	var settings = _make_settings()
	var menu := _make_menu(settings)

	settings.set_value("sound", false)  # flipped elsewhere

	assert_object(menu._round_bg["sound"].self_modulate).is_equal(OFF_TINT)


func test_continue_emits_resumed() -> void:
	var settings = _make_settings()
	var menu := _make_menu(settings)
	var got := [false]
	menu.resumed.connect(func() -> void: got[0] = true)

	menu._resume()

	assert_bool(got[0]).is_true()


func test_home_emits_home_pressed() -> void:
	var settings = _make_settings()
	var menu := _make_menu(settings)
	var got := [false]
	menu.home_pressed.connect(func() -> void: got[0] = true)

	menu._go_home()

	assert_bool(got[0]).is_true()


func test_restart_from_first_button_is_present() -> void:
	var settings = _make_settings()
	var menu := _make_menu(settings)
	assert_bool(menu._buttons.has("restart_level1")).is_true()


func test_restart_from_first_button_emits_signal() -> void:
	var settings = _make_settings()
	var menu := _make_menu(settings)
	var got := [false]
	menu.restart_from_first_pressed.connect(func() -> void: got[0] = true)

	menu._buttons["restart_level1"].pressed.emit()

	assert_bool(got[0]).is_true()
