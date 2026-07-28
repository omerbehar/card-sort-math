extends GdUnitTestSuite
## Integration tests — S5-003 Shop screen (design/ux/monetization-ui.md §3.2, AC-2/3/4/7).
##
## Two layers, both integration-level:
##  - REAL scene (scenes/main/main.tscn + autoloads): a wallet-pill tap deep-links the
##    Shop and it renders the authored catalog; a purchase through the real (mock-first,
##    always-FAILED) IAP backend surfaces the failure toast and leaves the wallet untouched.
##  - Injected fakes: the ShopScreen view driven against controllable fake IAP / Entitlement
##    / Analytics seams, proving the success → Owned, restore-count, and analytics paths
##    deterministically (the autoload backend can't succeed until a real SDK is wired).

const MAIN := "res://scenes/main/main.tscn"
const CATALOG_PATH := "res://assets/data/iap_catalog.tres"
const IAP_SCRIPT := preload("res://autoloads/iap_service.gd")
const COINS := EconomyEnums.Currency.COINS
const SKU_REMOVE_ADS: int = 1
const SKU_COINS_SMALL: int = 100


# --- Controllable fakes for the injected layer -----------------------------

class FakeIap extends Node:
	signal purchase_completed(sku: int, outcome: int)
	signal restore_completed(restored_count: int)
	var next_outcome: int = 2   # IAP_SCRIPT.State.SUCCESS
	var restored: int = 0
	var purchased: Array[int] = []
	func purchase(sku: int) -> bool:
		purchased.append(sku)
		purchase_completed.emit(sku, next_outcome)
		return next_outcome == 2
	func restore() -> bool:
		restore_completed.emit(restored)
		return restored > 0
	func current_state() -> int:
		return 0


class FakeEntitlement extends Node:
	signal remove_ads_changed(owned: bool)
	var owned: bool = false
	func should_suppress_interstitials() -> bool:
		return owned


class FakeAnalytics extends RefCounted:
	var calls: Array = []   # [[sku, success], ...]
	func track_iap_purchase(sku: int, success: bool) -> bool:
		calls.append([sku, success])
		return true


func _catalog() -> IAPCatalog:
	return load(CATALOG_PATH) as IAPCatalog


# Builds a ShopScreen wired to the given fakes, in the tree, ready to drive.
func _shop_with(iap: Object, entitlement: Object, analytics: Object) -> ShopScreen:
	var shop: ShopScreen = auto_free(ShopScreen.new())
	add_child(shop)
	shop.configure(iap, entitlement, analytics, _catalog())
	shop.setup()
	return shop


# ---------------------------------------------------------------------------
# Layer 1 — real scene tree
# ---------------------------------------------------------------------------

func _boot() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
		save.data.age_band = SaveData.AgeBand.ADULT   # these cases test an adult (not child-gated, S6-004)
		save.data.consent_iap = true                  # …with IAP consent (not the consent-off branch)
		save.data.consent_captured = true
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


func test_currency_tap_opens_shop_and_renders_full_catalog() -> void:
	# Arrange
	var runner = await _boot()
	var main = runner.scene()

	# Act: the wallet-pill deep-link (S5-002) opens the Shop.
	main._hud.currency_tapped.emit(COINS)
	await runner.simulate_frames(3)

	# Assert: one buy button per authored SKU, incl. the Remove-Ads anchor.
	assert_object(main._shop_screen).is_not_null()
	var shop = main._shop_screen
	assert_int(shop._buy_buttons.size()).is_equal(_catalog().entries.size())
	assert_bool(shop._buy_buttons.has(SKU_REMOVE_ADS)).is_true()
	assert_bool(shop._buy_buttons.has(SKU_COINS_SMALL)).is_true()


func test_real_backend_purchase_fails_and_leaves_wallet_untouched() -> void:
	# Arrange: open the shop over the real autoloads (mock-first backend always FAILS).
	var runner = await _boot()
	var main = runner.scene()
	main._hud.currency_tapped.emit(COINS)
	await runner.simulate_frames(3)
	var shop = main._shop_screen
	var coins_before: int = WalletService.balance(COINS)

	# Act: tap a currency pack's buy button.
	shop._buy_buttons[SKU_COINS_SMALL].pressed.emit()
	await runner.simulate_frames(2)

	# Assert: failure toast shown, wallet untouched (AC-2 failure path).
	assert_str(shop._toast_label.text).is_equal("Purchase didn't go through")
	assert_int(WalletService.balance(COINS)).is_equal(coins_before)


# ---------------------------------------------------------------------------
# Layer 2 — injected fakes (deterministic success / owned / restore / analytics)
# ---------------------------------------------------------------------------

func test_successful_purchase_marks_remove_ads_owned_and_tracks_analytics() -> void:
	# Arrange
	var iap = auto_free(FakeIap.new())
	iap.next_outcome = IAP_SCRIPT.State.SUCCESS
	var ent = auto_free(FakeEntitlement.new())
	var analytics := FakeAnalytics.new()
	var shop := _shop_with(iap, ent, analytics)

	# Act: buy Remove-Ads.
	shop._buy_buttons[SKU_REMOVE_ADS].pressed.emit()

	# Assert: card flips to Owned (disabled), analytics recorded the success (AC-3/AC-7).
	var btn: Button = shop._buy_buttons[SKU_REMOVE_ADS]
	assert_str(btn.text).is_equal("Owned ✓")
	assert_bool(btn.disabled).is_true()
	assert_array(analytics.calls).contains([[SKU_REMOVE_ADS, true]])


func test_failed_purchase_toasts_and_tracks_without_owning() -> void:
	# Arrange
	var iap = auto_free(FakeIap.new())
	iap.next_outcome = IAP_SCRIPT.State.FAILED
	var ent = auto_free(FakeEntitlement.new())
	var analytics := FakeAnalytics.new()
	var shop := _shop_with(iap, ent, analytics)

	# Act
	shop._buy_buttons[SKU_COINS_SMALL].pressed.emit()

	# Assert: error toast, card re-enabled, analytics recorded the failure (AC-2/AC-7).
	assert_str(shop._toast_label.text).is_equal("Purchase didn't go through")
	assert_bool((shop._buy_buttons[SKU_COINS_SMALL] as Button).disabled).is_false()
	assert_array(analytics.calls).contains([[SKU_COINS_SMALL, false]])


func test_restore_reports_restored_count() -> void:
	# Arrange
	var iap = auto_free(FakeIap.new())
	iap.restored = 1
	var shop := _shop_with(iap, auto_free(FakeEntitlement.new()), FakeAnalytics.new())

	# Act
	shop._on_restore_pressed()

	# Assert (AC-4)
	assert_str(shop._toast_label.text).is_equal("Restored 1 purchase(s)")


func test_restore_with_nothing_reports_none() -> void:
	# Arrange
	var iap = auto_free(FakeIap.new())
	iap.restored = 0
	var shop := _shop_with(iap, auto_free(FakeEntitlement.new()), FakeAnalytics.new())

	# Act
	shop._on_restore_pressed()

	# Assert (AC-4)
	assert_str(shop._toast_label.text).is_equal("Nothing to restore")


func test_opens_with_remove_ads_already_owned() -> void:
	# Arrange: entitlement already held before the shop opens.
	var ent = auto_free(FakeEntitlement.new())
	ent.owned = true
	var shop := _shop_with(auto_free(FakeIap.new()), ent, FakeAnalytics.new())

	# Assert: the Remove-Ads card opens in the Owned state (AC-3).
	var btn: Button = shop._buy_buttons[SKU_REMOVE_ADS]
	assert_str(btn.text).is_equal("Owned ✓")
	assert_bool(btn.disabled).is_true()
