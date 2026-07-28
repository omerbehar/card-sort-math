extends GdUnitTestSuite
## Integration tests — S6-004 child-safe mode (ADR-0005, design/ux/compliance-ui.md §3.4).
##
## An under-13 (restricted) player's shop purchases sit behind a parental gate: tapping Buy
## surfaces a calm "ask a grown-up" cue, IAPService is never driven, and the wallet is
## untouched. Covered at the component level (injected fake compliance) and end-to-end on the
## real scene with a declared CHILD band.

const MAIN := "res://scenes/main/main.tscn"
const CATALOG_PATH := "res://assets/data/iap_catalog.tres"
const COINS := EconomyEnums.Currency.COINS
const SKU_COINS_SMALL: int = 100

var _motion_was: bool = false


class FakeIap extends Node:
	signal purchase_completed(sku: int, outcome: int)
	signal restore_completed(restored_count: int)
	var purchased: Array[int] = []
	func purchase(sku: int) -> bool:
		purchased.append(sku)
		return false
	func restore() -> bool:
		return false
	func current_state() -> int:
		return 0


class FakeEntitlement extends Node:
	signal remove_ads_changed(owned: bool)
	func should_suppress_interstitials() -> bool:
		return false


class FakeCompliance extends RefCounted:
	var restricted: bool = true
	func is_restricted() -> bool:
		return restricted


func before() -> void:
	_motion_was = SettingsService.get_value("reduced_motion")
	SettingsService.set_value("reduced_motion", true)


func after() -> void:
	SettingsService.set_value("reduced_motion", _motion_was)


func after_test() -> void:
	var save = get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.age_band = SaveData.AgeBand.ADULT


func _catalog() -> IAPCatalog:
	return load(CATALOG_PATH) as IAPCatalog


func _shop_child(iap: Object) -> ShopScreen:
	var shop: ShopScreen = auto_free(ShopScreen.new())
	add_child(shop)
	shop.configure(iap, auto_free(FakeEntitlement.new()), null, _catalog(), FakeCompliance.new())
	shop.setup()
	return shop


# ---------------------------------------------------------------------------
# Component
# ---------------------------------------------------------------------------

func test_child_buy_is_parental_gated_and_never_purchases() -> void:
	var iap = auto_free(FakeIap.new())
	var shop := _shop_child(iap)

	# Act: a restricted player taps Buy.
	shop._buy_buttons[SKU_COINS_SMALL].pressed.emit()

	# Assert: parental-gate cue, no purchase attempted.
	assert_str(shop._toast_label.text).is_equal("Ask a grown-up to buy this")
	assert_array(iap.purchased).is_empty()


func test_restricted_player_is_flagged_child_safe() -> void:
	var shop := _shop_child(auto_free(FakeIap.new()))
	assert_bool(shop._is_child_restricted()).is_true()


# ---------------------------------------------------------------------------
# Real scene — a declared CHILD
# ---------------------------------------------------------------------------

func _boot_child() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
		save.data.age_band = SaveData.AgeBand.CHILD
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


func test_real_child_shop_purchase_is_parental_gated_wallet_untouched() -> void:
	var runner = await _boot_child()
	var main = runner.scene()
	main._hud.currency_tapped.emit(COINS)
	await runner.simulate_frames(3)
	var shop = main._shop_screen
	var coins_before: int = WalletService.balance(COINS)

	# Act
	shop._buy_buttons[SKU_COINS_SMALL].pressed.emit()
	await runner.simulate_frames(2)

	# Assert: parental gate, wallet untouched.
	assert_str(shop._toast_label.text).is_equal("Ask a grown-up to buy this")
	assert_int(WalletService.balance(COINS)).is_equal(coins_before)
