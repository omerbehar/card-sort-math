extends GdUnitTestSuite
## Integration tests — S6-002 consent capture sheet (ADR-0013, design/ux/compliance-ui.md §3.2).
##
##  - Component: the ConsentSheet writes the toggled choices via capture_consent (default-off;
##    Save captures the toggle state, "Not now" declines all).
##  - Real scene: a declared adult is offered the sheet after the age gate; a child skips it.

const MAIN := "res://scenes/main/main.tscn"

var _motion_was: bool = false


class FakeSave extends Object:
	var captured = null   # [personalized_ads, analytics, iap]
	func capture_consent(personalized_ads: bool, analytics: bool, iap: bool) -> void:
		captured = [personalized_ads, analytics, iap]


func before() -> void:
	_motion_was = SettingsService.get_value("reduced_motion")
	SettingsService.set_value("reduced_motion", true)


func after() -> void:
	SettingsService.set_value("reduced_motion", _motion_was)


func after_test() -> void:
	var save = get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.age_band = SaveData.AgeBand.ADULT
		save.data.consent_captured = false


func _sheet_with(save: Object) -> ConsentSheet:
	var sheet: ConsentSheet = auto_free(ConsentSheet.new())
	add_child(sheet)
	sheet.configure(save)
	sheet.setup()
	return sheet


# ---------------------------------------------------------------------------
# Component — capture semantics
# ---------------------------------------------------------------------------

func test_defaults_off_save_captures_all_denied() -> void:
	var save := FakeSave.new()
	var sheet := _sheet_with(save)

	# No toggles touched → Save writes all denied (protected-field defaults).
	sheet._save_button.pressed.emit()

	assert_array(save.captured).is_equal([false, false, false])


func test_toggling_personalized_then_save_captures_it() -> void:
	var save := FakeSave.new()
	var sheet := _sheet_with(save)
	var got: Array = [null]
	sheet.consent_saved.connect(func(pa, an, iap) -> void: got[0] = [pa, an, iap])

	# Act: enable personalized ads, leave the rest off, Save.
	sheet._toggles["personalized_ads"].pressed.emit()
	sheet._save_button.pressed.emit()

	# Assert: exactly that choice is captured + reported.
	assert_array(save.captured).is_equal([true, false, false])
	assert_array(got[0]).is_equal([true, false, false])


func test_decline_captures_all_denied() -> void:
	var save := FakeSave.new()
	var sheet := _sheet_with(save)

	# Even after toggling something on, "Not now" declines all.
	sheet._toggles["analytics"].pressed.emit()
	sheet._decline_button.pressed.emit()

	assert_array(save.captured).is_equal([false, false, false])


# ---------------------------------------------------------------------------
# Real scene — adult is offered the sheet, child is not
# ---------------------------------------------------------------------------

func _boot_unknown() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
		save.data.age_band = SaveData.AgeBand.UNKNOWN
		save.data.consent_captured = false
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


func _this_year() -> int:
	return int(Time.get_date_dict_from_system().get("year", 2026))


func test_adult_is_offered_consent_sheet_after_age_gate() -> void:
	var runner = await _boot_unknown()
	var main = runner.scene()

	# Act: declare an adult birth year.
	main._age_gate._set_year(_this_year() - 30)
	main._age_gate._on_confirm()
	await runner.simulate_frames(2)

	# Assert: the consent sheet is presented.
	assert_object(main._consent_sheet).is_not_null()


func test_child_skips_the_consent_sheet() -> void:
	var runner = await _boot_unknown()
	var main = runner.scene()

	# Act: declare an under-13 birth year.
	main._age_gate._set_year(_this_year() - 8)
	main._age_gate._on_confirm()
	await runner.simulate_frames(2)

	# Assert: no consent sheet for a child (child-safe by construction).
	assert_object(main._consent_sheet).is_null()
