extends GdUnitTestSuite
## Integration tests — S5-006 one-per-session Remove-Ads offer.
##
##  - Component: the RemoveAdsOffer renders a CTA that requests the Shop, and suppresses
##    itself entirely when Remove-Ads is already owned.
##  - Real scene (scenes/main/main.tscn + autoloads): the offer is surfaced at most once per
##    session (after an interstitial) and never when Remove-Ads is owned.

const MAIN := "res://scenes/main/main.tscn"
const CATALOG_PATH := "res://assets/data/iap_catalog.tres"


class FakeEntitlement extends Node:
	signal remove_ads_changed(owned: bool)
	var owned: bool = false
	func should_suppress_interstitials() -> bool:
		return owned


var _motion_was: bool = false


func before() -> void:
	# Force reduced-motion so PopupBase.close() resolves synchronously (deterministic
	# ref-clear timing for the session-cap assertions).
	_motion_was = SettingsService.get_value("reduced_motion")
	SettingsService.set_value("reduced_motion", true)


func after() -> void:
	SettingsService.set_value("reduced_motion", _motion_was)


func after_test() -> void:
	# The owned-path test flips the shared save's Remove-Ads flag; reset it so it never
	# leaks into other suites that assume a not-owned wallet.
	var save = get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.remove_ads_owned = false


func _catalog() -> IAPCatalog:
	return load(CATALOG_PATH) as IAPCatalog


func _offer_with(entitlement: Object) -> RemoveAdsOffer:
	var offer: RemoveAdsOffer = auto_free(RemoveAdsOffer.new())
	add_child(offer)
	offer.configure(entitlement, _catalog())
	offer.setup()
	return offer


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

func test_offer_renders_cta_that_requests_shop() -> void:
	# Arrange: Remove-Ads not owned.
	var offer := _offer_with(auto_free(FakeEntitlement.new()))

	# Assert: the CTA is built and shows the catalog price.
	assert_object(offer._cta_button).is_not_null()
	assert_str(offer._cta_button.text).contains("$")

	# Act: tap the CTA (emits shop_requested synchronously, before close()).
	var requested: Array = [false]
	offer.shop_requested.connect(func() -> void: requested[0] = true)
	offer._cta_button.pressed.emit()

	# Assert: it requests the Shop (deep-link intent).
	assert_bool(requested[0]).is_true()


func test_offer_suppressed_when_remove_ads_owned() -> void:
	# Arrange: Remove-Ads already owned → the sheet must not build.
	var ent = auto_free(FakeEntitlement.new())
	ent.owned = true
	var offer := _offer_with(ent)

	# Assert: no CTA was built (setup closed early).
	assert_object(offer._cta_button).is_null()


# ---------------------------------------------------------------------------
# Real scene — session cap + owned suppression
# ---------------------------------------------------------------------------

func test_offer_shown_once_per_session() -> void:
	# Arrange
	var runner = await _boot()
	var main = runner.scene()

	# Act: first offer opportunity → shown.
	main._maybe_offer_remove_ads()
	await runner.simulate_frames(2)
	assert_object(main._remove_ads_offer).is_not_null()

	# Dismiss it, then a second opportunity must NOT re-show (one per session).
	main._remove_ads_offer.close()
	await runner.simulate_frames(6)
	assert_object(main._remove_ads_offer).is_null()
	main._maybe_offer_remove_ads()
	await runner.simulate_frames(2)
	assert_object(main._remove_ads_offer).is_null()


func test_offer_not_shown_when_remove_ads_owned() -> void:
	# Arrange: own Remove-Ads on the real save.
	var runner = await _boot()
	var main = runner.scene()
	get_tree().root.get_node("SaveService").data.remove_ads_owned = true

	# Act
	main._maybe_offer_remove_ads()
	await runner.simulate_frames(2)

	# Assert: suppressed entirely when owned.
	assert_object(main._remove_ads_offer).is_null()
