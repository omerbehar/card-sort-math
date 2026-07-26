extends GdUnitTestSuite
## Integration tests — S6-001 first-run neutral age gate (ADR-0005).
##
## Drives the real scenes/main/main.tscn + autoloads: a first run (age_band == UNKNOWN)
## presents the gate; submitting a birth year maps to a band via ComplianceService, persists
## it via SaveService (flipping the live compliance verdict), and dismisses the gate; a
## returning player (band already set) sees no gate.

const MAIN := "res://scenes/main/main.tscn"

var _motion_was: bool = false


func before() -> void:
	# Force reduced-motion so the gate's close() resolves synchronously.
	_motion_was = SettingsService.get_value("reduced_motion")
	SettingsService.set_value("reduced_motion", true)


func after() -> void:
	SettingsService.set_value("reduced_motion", _motion_was)


func after_test() -> void:
	# Leave a known (adult) band so the UNKNOWN this suite forces doesn't leak into others.
	var save = get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.age_band = SaveData.AgeBand.ADULT


func _boot(band: int) -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
		save.data.age_band = band   # set BEFORE the scene boots so _ready sees it
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


func _this_year() -> int:
	return int(Time.get_date_dict_from_system().get("year", 2026))


func test_first_run_presents_the_age_gate() -> void:
	# Arrange + Act: boot with an undeclared band.
	var runner = await _boot(SaveData.AgeBand.UNKNOWN)
	var main = runner.scene()

	# Assert: the gate is up (first-run).
	assert_object(main._age_gate).is_not_null()


func test_returning_player_sees_no_gate() -> void:
	# Arrange + Act: boot with a band already declared.
	var runner = await _boot(SaveData.AgeBand.ADULT)
	var main = runner.scene()

	# Assert: no gate.
	assert_object(main._age_gate).is_null()


func test_submitting_adult_year_sets_adult_and_dismisses() -> void:
	# Arrange
	var runner = await _boot(SaveData.AgeBand.UNKNOWN)
	var main = runner.scene()
	assert_object(main._age_gate).is_not_null()

	# Act: declare a clearly-adult birth year and confirm.
	main._age_gate._set_year(_this_year() - 30)
	main._age_gate._on_confirm()
	await runner.simulate_frames(2)

	# Assert: band persisted to ADULT, verdict flipped live, gate dismissed.
	assert_int(get_tree().root.get_node("SaveService").data.age_band).is_equal(SaveData.AgeBand.ADULT)
	assert_bool(get_tree().root.get_node("ComplianceService").is_adult()).is_true()
	assert_object(main._age_gate).is_null()


func test_submitting_child_year_sets_child_band() -> void:
	# Arrange
	var runner = await _boot(SaveData.AgeBand.UNKNOWN)
	var main = runner.scene()

	# Act: declare an under-13 birth year.
	main._age_gate._set_year(_this_year() - 8)
	main._age_gate._on_confirm()
	await runner.simulate_frames(2)

	# Assert: CHILD band → restricted compliance verdict.
	assert_int(get_tree().root.get_node("SaveService").data.age_band).is_equal(SaveData.AgeBand.CHILD)
	assert_bool(get_tree().root.get_node("ComplianceService").is_restricted()).is_true()
