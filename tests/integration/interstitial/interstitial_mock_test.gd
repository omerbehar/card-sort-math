extends GdUnitTestSuite
## Integration tests — S5-005 mock interstitial (design/ux/monetization-ui.md §3.4, AC-6).
##
##  - Component: the InterstitialMock hides its close affordance until the ad beat, then
##    closing emits `closed`.
##  - Real scene (scenes/main/main.tscn + autoloads): the win → advance boundary presents
##    an interstitial ONLY when AdService returns SHOWN (never mid-puzzle); on any
##    suppression / no-fill it advances with no UI; a shown interstitial advances the level
##    once it closes.

const MAIN := "res://scenes/main/main.tscn"

var _motion_was: bool = false


func before() -> void:
	# Force reduced-motion so PopupBase.close() resolves synchronously (deterministic
	# signal timing), mirroring the other UI-flow suites.
	_motion_was = SettingsService.get_value("reduced_motion")
	SettingsService.set_value("reduced_motion", true)


func after() -> void:
	SettingsService.set_value("reduced_motion", _motion_was)


func after_test() -> void:
	# Reset the process-global AdService frequency counters this suite mutates (via the
	# real win-advance boundary), so no state leaks into other suites' clean-boot asserts.
	var ad = get_tree().root.get_node_or_null("AdService")
	if ad != null:
		ad._levels_since_interstitial = 0
		ad._last_interstitial_unix = -1
		ad._puzzle_active = false


class FakeAd extends Node:
	var ad_type: int = 0
	func resolve_ad_type() -> int:
		return ad_type


func _boot() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


# ---------------------------------------------------------------------------
# Component
# ---------------------------------------------------------------------------

func test_close_affordance_hidden_until_beat_then_close_emits_closed() -> void:
	# Arrange
	var mock: InterstitialMock = auto_free(InterstitialMock.new())
	add_child(mock)
	mock.setup()

	# Assert: close is hidden during the "ad" beat (can't skip immediately).
	assert_object(mock._close_btn).is_not_null()
	assert_bool(mock._close_btn.visible).is_false()

	# Act: the beat elapses (forced), then the player closes.
	mock._reveal_close()
	assert_bool(mock._close_btn.visible).is_true()
	var closed_seen: Array = [false]
	mock.closed.connect(func() -> void: closed_seen[0] = true)
	mock._close_btn.pressed.emit()

	# Assert: reduced-motion → close() emits `closed` synchronously.
	assert_bool(closed_seen[0]).is_true()


# ---------------------------------------------------------------------------
# Real scene — win → advance boundary
# ---------------------------------------------------------------------------

func test_win_advance_without_fill_advances_with_no_interstitial() -> void:
	# Arrange: fresh run → the frequency cap (every 3 levels) isn't satisfied on the first
	# win, and the mock-first backend reports NO_FILL — so no interstitial should show.
	var runner = await _boot()
	var main = runner.scene()

	# Act
	main._on_win_advance()
	await runner.simulate_frames(3)

	# Assert: proceeded with no UI (AC-6: shown only on SHOWN).
	assert_object(main._interstitial).is_null()


func test_present_interstitial_shows_mock_and_advances_on_close() -> void:
	# Arrange
	var runner = await _boot()
	var main = runner.scene()
	var fake = auto_free(FakeAd.new())

	# Act: present the interstitial (the SHOWN path).
	main._present_interstitial(fake)
	await runner.simulate_frames(2)

	# Assert: the mock full-screen ad is up.
	assert_object(main._interstitial).is_not_null()
	assert_bool(main._interstitial is InterstitialMock).is_true()

	# Act: close it → advances to the next level and clears the ref.
	main._interstitial.close()
	await runner.simulate_frames(20)

	# Assert
	assert_object(main._interstitial).is_null()
