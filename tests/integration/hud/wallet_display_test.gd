extends GdUnitTestSuite
## Integration test — S5-002 HUD wallet display (coins + gems pills).
##
## Drives the REAL Main scene (full node tree + the WalletService / SettingsService
## autoloads) via gdUnit4's scene_runner and asserts the wallet pills are thin views
## over WalletService: seeded from the live balances and refreshed on every
## economy_event (AC-1). Reduced-motion is forced on so the count-up snaps and the
## assertions stay deterministic (no mid-tween text).
##
## Source: design/ux/monetization-ui.md §3.1 + AC-1; ADR-0001 (model/view seam).

const MAIN := "res://scenes/main/main.tscn"
const COINS := EconomyEnums.Currency.COINS
const GEMS := EconomyEnums.Currency.GEMS
const LEVEL_WIN := EconomyEnums.EarnSource.LEVEL_WIN

var _motion_was: bool = false


func before() -> void:
	# Snapshot reduced-motion; force it on for deterministic (snap, no tween) pills.
	_motion_was = SettingsService.get_value("reduced_motion")
	SettingsService.set_value("reduced_motion", true)


func after() -> void:
	SettingsService.set_value("reduced_motion", _motion_was)


# Loads Main, suppresses the tutorial coach, and settles a few frames.
func _boot() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


func test_wallet_pills_present_and_seeded_from_service() -> void:
	# Arrange
	var runner = await _boot()
	var main = runner.scene()
	var hud = main._hud

	# Assert: both pills exist and read the live balances.
	assert_object(hud._coins_pill_label).is_not_null()
	assert_object(hud._gems_pill_label).is_not_null()
	assert_str(hud._coins_pill_label.text).is_equal("🪙 %d" % WalletService.balance(COINS))
	assert_str(hud._gems_pill_label.text).is_equal("💎 %d" % WalletService.balance(GEMS))


func test_gems_pill_updates_on_economy_event() -> void:
	# Arrange
	var runner = await _boot()
	var main = runner.scene()
	var hud = main._hud

	# Act: an IAP gem grant fires economy_event(CURRENCY_EARNED, GEMS).
	WalletService.grant_iap_currency(GEMS, 50)
	await runner.simulate_frames(2)

	# Assert: the gems pill reflects the new balance (AC-1).
	assert_str(hud._gems_pill_label.text).is_equal("💎 %d" % WalletService.balance(GEMS))


func test_coins_pill_updates_on_earn() -> void:
	# Arrange
	var runner = await _boot()
	var main = runner.scene()
	var hud = main._hud

	# Act: earn coins → economy_event(CURRENCY_EARNED, COINS).
	WalletService.earn(COINS, 25, LEVEL_WIN)
	await runner.simulate_frames(2)

	# Assert: the coins pill reflects the new balance.
	assert_str(hud._coins_pill_label.text).is_equal("🪙 %d" % WalletService.balance(COINS))


func test_tapping_coins_pill_emits_currency_tapped() -> void:
	# Arrange
	var runner = await _boot()
	var main = runner.scene()
	var hud = main._hud
	monitor_signals(hud)

	# Act: press the pill's backing Button (the label's parent).
	var pill_button: Button = hud._coins_pill_label.get_parent()
	assert_object(pill_button).is_not_null()
	pill_button.pressed.emit()
	await runner.simulate_frames(1)

	# Assert: the deep-link intent fires with the tapped currency (Shop wiring, S5-003).
	await assert_signal(hud).is_emitted("currency_tapped", [COINS])
