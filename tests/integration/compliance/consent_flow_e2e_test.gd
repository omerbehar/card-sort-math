extends GdUnitTestSuite
## Integration test — S6-005 end-to-end consent flow.
##
## Proves the first-run compliance UI drives the compliance verdicts through the REAL setter
## path — age gate → consent sheet → SaveService.capture_consent — with NO direct poking of
## the protected consent fields. This is the flow the monetization surfaces now sit behind.

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


func _this_year() -> int:
	return int(Time.get_date_dict_from_system().get("year", 2026))


func test_first_run_ui_grants_consent_and_flips_all_verdicts() -> void:
	# Arrange: a genuine first run — undeclared band, nothing captured (the precondition, not
	# a faked consent state).
	var save := get_tree().root.get_node("SaveService")
	save.data.tutorial_seen = true
	save.data.age_band = SaveData.AgeBand.UNKNOWN
	save.data.consent_captured = false
	var compliance = get_tree().root.get_node("ComplianceService")
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	var main = runner.scene()

	# Act 1: clear the age gate as an adult → the consent sheet appears.
	assert_object(main._age_gate).is_not_null()
	main._age_gate._set_year(_this_year() - 30)
	main._age_gate._on_confirm()
	await runner.simulate_frames(2)
	assert_object(main._consent_sheet).is_not_null()

	# Act 2: grant everything via the real toggles + Save (→ SaveService.capture_consent).
	var sheet = main._consent_sheet
	sheet._toggles["personalized_ads"].pressed.emit()
	sheet._toggles["analytics"].pressed.emit()
	sheet._toggles["iap"].pressed.emit()
	sheet._save_button.pressed.emit()
	await runner.simulate_frames(2)

	# Assert: every verdict is now permissive — established purely through the UI, with no
	# direct writes to the protected consent fields.
	assert_bool(save.data.consent_captured).is_true()
	assert_bool(compliance.can_show_targeted_ads()).is_true()
	assert_bool(compliance.can_collect_personal_data()).is_true()
	assert_bool(compliance.can_process_iap()).is_true()
