extends GdUnitTestSuite
## Integration tests — S6-003 Settings → Privacy (view / withdraw / re-manage consent).
##
## Drives the real main.tscn: the pause menu exposes a Privacy row that opens the consent
## sheet pre-filled with the current choices; turning a toggle off and saving withdraws that
## consent, and the ComplianceService verdict flips live.

const MAIN := "res://scenes/main/main.tscn"

var _motion_was: bool = false


func before() -> void:
	_motion_was = SettingsService.get_value("reduced_motion")
	SettingsService.set_value("reduced_motion", true)


func after() -> void:
	SettingsService.set_value("reduced_motion", _motion_was)


func after_test() -> void:
	var save = get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.age_band = SaveData.AgeBand.ADULT
		save.data.consent_personalized_ads = false
		save.data.consent_analytics = false
		save.data.consent_iap = false
		save.data.consent_captured = false


# Boots as an adult who has already granted all three consents.
func _boot_adult_all_granted() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
		save.data.age_band = SaveData.AgeBand.ADULT
		save.data.consent_personalized_ads = true
		save.data.consent_analytics = true
		save.data.consent_iap = true
		save.data.consent_captured = true
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


func _open_privacy(main) -> void:
	main._open_pause()
	main._pause_menu._buttons["privacy"].pressed.emit()


func test_pause_menu_exposes_a_privacy_row() -> void:
	var runner = await _boot_adult_all_granted()
	var main = runner.scene()
	main._open_pause()
	await runner.simulate_frames(2)
	assert_bool(main._pause_menu._buttons.has("privacy")).is_true()


func test_privacy_opens_consent_sheet_prefilled_with_current_choices() -> void:
	var runner = await _boot_adult_all_granted()
	var main = runner.scene()

	_open_privacy(main)
	await runner.simulate_frames(2)

	# The sheet reflects the current (all-granted) state.
	assert_object(main._consent_sheet).is_not_null()
	assert_bool(main._consent_sheet._consent["personalized_ads"]).is_true()
	assert_bool(main._consent_sheet._consent["analytics"]).is_true()
	assert_bool(main._consent_sheet._consent["iap"]).is_true()


func test_withdrawing_analytics_from_settings_flips_the_verdict() -> void:
	var runner = await _boot_adult_all_granted()
	var main = runner.scene()
	var compliance = get_tree().root.get_node("ComplianceService")
	assert_bool(compliance.can_collect_personal_data()).is_true()   # granted at boot

	# Act: open privacy, turn Analytics off, Save.
	_open_privacy(main)
	await runner.simulate_frames(2)
	main._consent_sheet._toggles["analytics"].pressed.emit()
	main._consent_sheet._save_button.pressed.emit()
	await runner.simulate_frames(2)

	# Assert: analytics withdrawn (verdict flipped live); the others still granted.
	assert_bool(compliance.can_collect_personal_data()).is_false()
	assert_bool(compliance.can_show_targeted_ads()).is_true()
	assert_bool(compliance.can_process_iap()).is_true()
