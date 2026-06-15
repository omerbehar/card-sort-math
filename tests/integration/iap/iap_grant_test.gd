extends GdUnitTestSuite
## Integration tests for [IAPService] (S4-002, ADR-0014 §2).
##
## One test boots the real [code]scenes/main/main.tscn[/code] + autoloads via gdUnit4's
## scene_runner to prove autoload registration and _ready() dependency resolution
## (CLAUDE.md mandatory validation). The others drive the REAL IAPService +
## ComplianceService + EntitlementService together over a fresh in-memory SaveService
## (consent x age gate end-to-end through real services), so no autoload-singleton state
## is mutated. File I/O is confined to the grant path and cleaned up in [method after_test].

const MAIN := "res://scenes/main/main.tscn"
const IAP_SCRIPT := preload("res://autoloads/iap_service.gd")
const IAP_BACKEND := preload("res://autoloads/iap_backend.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const COMPLIANCE_SCRIPT := preload("res://autoloads/compliance_service.gd")
const ENTITLEMENT_SCRIPT := preload("res://autoloads/entitlement_service.gd")
const ENT_BACKEND := preload("res://autoloads/entitlement_backend.gd")

var _temp_save_paths: Array[String] = []


func after_test() -> void:
	# Unconditional teardown so a failing assert never leaks user:// files.
	for path: String in _temp_save_paths:
		if FileAccess.file_exists(path):
			DirAccess.open("user://").remove(path.get_file())
		var tmp: String = path + ".tmp"
		if FileAccess.file_exists(tmp):
			DirAccess.open("user://").remove(tmp.get_file())
	_temp_save_paths.clear()


# Remove-Ads-only catalog (the non-consumable path needs no wallet).
func _catalog() -> Dictionary:
	var cat: Dictionary = {}
	cat[IAP_SCRIPT.SKU_REMOVE_ADS] = IAP_SCRIPT.IAPCatalogEntry.make_entitlement()
	return cat


# ---------------------------------------------------------------------------
# Real scene-tree boot: IAPService registers as an autoload and resolves deps.
# ---------------------------------------------------------------------------

func test_iap_service_boots_as_autoload_and_resolves_deps() -> void:
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	var root := get_tree().root

	var iap := root.get_node_or_null("IAPService")
	assert_object(iap).is_not_null()
	assert_object(root.get_node_or_null("WalletService")).is_not_null()
	assert_object(root.get_node_or_null("ComplianceService")).is_not_null()
	assert_object(root.get_node_or_null("EntitlementService")).is_not_null()

	# _ready() resolved the placeholder catalog and started in a clean IDLE state.
	assert_bool(iap.is_valid_sku(IAP_SCRIPT.SKU_REMOVE_ADS)).is_true()
	assert_int(iap.current_state()).is_equal(IAP_SCRIPT.State.IDLE)


# ---------------------------------------------------------------------------
# End-to-end through real services: adult + IAP consent → Remove-Ads purchase
# flips the real EntitlementService gate.
# ---------------------------------------------------------------------------

func test_remove_ads_purchase_grants_entitlement_through_real_services() -> void:
	var path: String = "user://test_iap_grant_remove_ads.json"
	_temp_save_paths.append(path)

	var save = auto_free(SAVE_SCRIPT.new())
	save.configure(path)
	save.data.age_band = SaveData.AgeBand.ADULT
	save.data.consent_iap = true

	var compliance = auto_free(COMPLIANCE_SCRIPT.new())
	compliance.configure(save)
	var entitlement = auto_free(ENTITLEMENT_SCRIPT.new())
	entitlement.configure(save, ENT_BACKEND.MockEntitlementBackend.new())

	var backend = IAP_BACKEND.MockIAPBackend.new()
	backend.next_result = IAP_BACKEND.PurchaseResult.SUCCESS
	var iap = auto_free(IAP_SCRIPT.new())
	iap.configure(null, compliance, entitlement, backend, _catalog())

	# Act: purchase Remove-Ads through the real service chain.
	var ok: bool = iap.purchase(IAP_SCRIPT.SKU_REMOVE_ADS)

	# Assert: the real EntitlementService gate is now active.
	assert_bool(ok).is_true()
	assert_bool(entitlement.is_remove_ads_owned()).is_true()
	assert_bool(entitlement.should_suppress_interstitials()).is_true()


# ---------------------------------------------------------------------------
# End-to-end gate: a CHILD age_band → ComplianceService.can_process_iap() false →
# purchase blocked, no entitlement granted (no save write happens).
# ---------------------------------------------------------------------------

func test_compliance_restricted_blocks_purchase_through_real_services() -> void:
	var save = auto_free(SAVE_SCRIPT.new())
	save.data.age_band = SaveData.AgeBand.CHILD
	save.data.consent_iap = true  # consent present, but age gate still restricts

	var compliance = auto_free(COMPLIANCE_SCRIPT.new())
	compliance.configure(save)
	var entitlement = auto_free(ENTITLEMENT_SCRIPT.new())
	entitlement.configure(save, ENT_BACKEND.MockEntitlementBackend.new())

	var backend = IAP_BACKEND.MockIAPBackend.new()
	backend.next_result = IAP_BACKEND.PurchaseResult.SUCCESS
	var iap = auto_free(IAP_SCRIPT.new())
	iap.configure(null, compliance, entitlement, backend, _catalog())

	var ok: bool = iap.purchase(IAP_SCRIPT.SKU_REMOVE_ADS)

	assert_bool(ok).is_false()
	assert_bool(entitlement.is_remove_ads_owned()).is_false()
