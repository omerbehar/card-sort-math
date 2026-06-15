extends GdUnitTestSuite
## Unit tests for [EntitlementService] and the [SaveData] remove_ads_owned field (S4-003).
##
## Covers:
## - The v5→v6 migration step adds remove_ads_owned = false in the SAME block as the
##   consent fields (assert only ONE `if version == 5:` step, no second migration block).
## - [method from_dict] / [method to_dict] round-trip preserves remove_ads_owned.
## - Missing key → not-owned conservative default (ADR-0014 §3, save-service.md Core Rule 6 / EC9).
## - Null or non-bool values → not-owned (mirrors EC7 _parse_age_band pattern).
## - [method EntitlementService.grant_remove_ads] is idempotent.
## - [method EntitlementService.restore] with a mock backend that has a receipt grants ownership.
## - Grant-then-restore is idempotent (owned stays owned, signal not emitted twice).
## - Fresh install (no field in save dict) → not owned.

const ENTITLEMENT_SCRIPT := preload("res://autoloads/entitlement_service.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const BACKEND_SCRIPT := preload("res://autoloads/entitlement_backend.gd")


# ---------------------------------------------------------------------------
# Shared v6 migration: remove_ads_owned appears in the same `if version == 5:` step
# as the consent fields — NO second migration block (ADR-0014 §3, M4-R4).
# ---------------------------------------------------------------------------

func test_migrate_v5_to_v6_seeds_remove_ads_owned_false() -> void:
	# A v5 save dict must gain remove_ads_owned = false after migration.
	var v5_dict: Dictionary = {
		"schema_version": 5,
		"current_level": 2,
		"wallet_coins": 100,
		"boosters_seeded": true,
	}
	var data := SaveData.from_dict(v5_dict)
	assert_bool(data.remove_ads_owned).is_false()


func test_migrate_v5_to_v6_single_step_adds_both_consent_and_entitlement() -> void:
	# Assert the migration adds consent fields AND remove_ads_owned in ONE call to _migrate
	# from version 5 (not two). We verify the output dict has all keys after one pass.
	var v5_dict: Dictionary = {
		"schema_version": 5,
		"current_level": 1,
	}
	# Call _migrate directly (the static function); version 5 → 6 is one block.
	var migrated: Dictionary = SaveData._migrate(v5_dict, 5)
	# All consent keys must be present from the same step.
	assert_bool(migrated.has("consent_personalized_ads")).is_true()
	assert_bool(migrated.has("consent_analytics")).is_true()
	assert_bool(migrated.has("consent_iap")).is_true()
	assert_bool(migrated.has("consent_captured")).is_true()
	assert_bool(migrated.has("consent_version")).is_true()
	# remove_ads_owned must also be present — same step, no second block.
	assert_bool(migrated.has("remove_ads_owned")).is_true()
	assert_bool(migrated.get("remove_ads_owned", true)).is_false()


func test_migrate_v5_to_v6_preserves_existing_wallet_and_level() -> void:
	# Migration must not clobber pre-existing fields while adding the entitlement key.
	var v5_dict: Dictionary = {
		"schema_version": 5,
		"current_level": 9,
		"wallet_coins": 500,
		"wallet_gems": 10,
		"boosters_seeded": true,
	}
	var data := SaveData.from_dict(v5_dict)
	assert_int(data.current_level).is_equal(9)
	assert_int(data.wallet_coins).is_equal(500)
	assert_int(data.wallet_gems).is_equal(10)
	assert_bool(data.boosters_seeded).is_true()
	# Entitlement must default to not-owned.
	assert_bool(data.remove_ads_owned).is_false()


func test_migrate_v1_flows_all_steps_and_sets_remove_ads_not_owned() -> void:
	# A v1 save flows v1→v2→v3→v4→v5→v6; remove_ads_owned must be false at the end.
	var v1_dict: Dictionary = {
		"schema_version": 1,
		"current_level": 5,
		"age_band": int(SaveData.AgeBand.ADULT),
	}
	var data := SaveData.from_dict(v1_dict)
	assert_int(data.schema_version).is_equal(6)
	assert_bool(data.remove_ads_owned).is_false()


# ---------------------------------------------------------------------------
# from_dict conservative defaults: missing key → not-owned (Core Rule 6 / EC9)
# ---------------------------------------------------------------------------

func test_fresh_install_empty_dict_remove_ads_not_owned() -> void:
	# EC9 / fresh install: from_dict({}) must default remove_ads_owned to false.
	var data := SaveData.from_dict({})
	assert_bool(data.remove_ads_owned).is_false()


func test_from_dict_v6_missing_remove_ads_key_defaults_not_owned() -> void:
	# Downgrade-drop protection: a v6 dict without the key must load as not-owned.
	var dict_missing: Dictionary = {
		"schema_version": 6,
		"current_level": 3,
		"consent_personalized_ads": false,
		"consent_analytics": false,
		"consent_iap": false,
		"consent_captured": false,
		"consent_version": 0,
		# remove_ads_owned deliberately absent
	}
	var data := SaveData.from_dict(dict_missing)
	assert_bool(data.remove_ads_owned).is_false()


# ---------------------------------------------------------------------------
# Null / non-bool values → not-owned (mirrors EC7 _parse_age_band)
# ---------------------------------------------------------------------------

func test_from_dict_null_remove_ads_owned_treated_as_not_owned() -> void:
	var data := SaveData.from_dict({"schema_version": 6, "remove_ads_owned": null})
	assert_bool(data.remove_ads_owned).is_false()


func test_from_dict_int_nonone_remove_ads_owned_treated_as_not_owned() -> void:
	# An int that is not 1 must not be treated as owned.
	var data := SaveData.from_dict({"schema_version": 6, "remove_ads_owned": 99})
	assert_bool(data.remove_ads_owned).is_false()


func test_from_dict_string_remove_ads_owned_treated_as_not_owned() -> void:
	# A string "true" is not a valid bool — must default to not-owned.
	var data := SaveData.from_dict({"schema_version": 6, "remove_ads_owned": "true"})
	assert_bool(data.remove_ads_owned).is_false()


# ---------------------------------------------------------------------------
# to_dict / from_dict round-trip
# ---------------------------------------------------------------------------

func test_round_trip_remove_ads_owned_false_preserved() -> void:
	var original := SaveData.new()
	original.remove_ads_owned = false
	var restored := SaveData.from_dict(original.to_dict())
	assert_bool(restored.remove_ads_owned).is_false()


func test_round_trip_remove_ads_owned_true_preserved() -> void:
	var original := SaveData.new()
	original.remove_ads_owned = true
	var restored := SaveData.from_dict(original.to_dict())
	assert_bool(restored.remove_ads_owned).is_true()


func test_to_dict_contains_remove_ads_owned_key() -> void:
	# to_dict() must include remove_ads_owned so it is always serialized (protected field).
	var keys: Array = SaveData.new().to_dict().keys()
	assert_bool(keys.has("remove_ads_owned")).is_true()


func test_json_string_round_trip_remove_ads_owned_true() -> void:
	# Full JSON serialization path (booleans may round-trip as int 1/0).
	var original := SaveData.new()
	original.remove_ads_owned = true
	var text := JSON.stringify(original.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	var restored := SaveData.from_dict(parsed as Dictionary)
	assert_bool(restored.remove_ads_owned).is_true()


# ---------------------------------------------------------------------------
# EntitlementService.grant_remove_ads() — idempotent
# ---------------------------------------------------------------------------

# Temp save paths for the persisting (grant/restore) tests; cleaned in after_test so
# entitlement persistence never leaks into the real user://save.json (test hygiene).
var _temp_save_paths: Array[String] = []


func after_test() -> void:
	for path: String in _temp_save_paths:
		if FileAccess.file_exists(path):
			DirAccess.open("user://").remove(path.get_file())
		var tmp: String = path + ".tmp"
		if FileAccess.file_exists(tmp):
			DirAccess.open("user://").remove(tmp.get_file())
	_temp_save_paths.clear()


# A SaveService pointed at a unique temp path so save_game() never touches the real save.
func _temp_save():
	var path: String = "user://test_entitlement_unit_%d.json" % _temp_save_paths.size()
	_temp_save_paths.append(path)
	var save = auto_free(SAVE_SCRIPT.new())
	save.configure(path)
	return save


func test_grant_remove_ads_sets_owned_true() -> void:
	var save = _temp_save()
	save.data.remove_ads_owned = false
	var svc = auto_free(ENTITLEMENT_SCRIPT.new())
	var backend = BACKEND_SCRIPT.MockEntitlementBackend.new()
	svc.configure(save, backend)

	svc.grant_remove_ads()

	assert_bool(svc.is_remove_ads_owned()).is_true()


func test_grant_remove_ads_idempotent_second_call_stays_owned() -> void:
	# Calling grant_remove_ads() when already owned must not error or emit again.
	var save = _temp_save()
	var svc = auto_free(ENTITLEMENT_SCRIPT.new())
	var backend = BACKEND_SCRIPT.MockEntitlementBackend.new()
	svc.configure(save, backend)

	svc.grant_remove_ads()
	svc.grant_remove_ads()  # Second call must be a no-op

	assert_bool(svc.is_remove_ads_owned()).is_true()


var _emitted_signal_args: Array = []

func _capture_remove_ads_changed(owned: bool) -> void:
	_emitted_signal_args.append(owned)


func test_grant_remove_ads_emits_signal_exactly_once() -> void:
	# The remove_ads_changed signal must fire on the first grant and NOT again on a
	# redundant (idempotent) second call.
	var save = _temp_save()
	var svc = auto_free(ENTITLEMENT_SCRIPT.new())
	var backend = BACKEND_SCRIPT.MockEntitlementBackend.new()
	svc.configure(save, backend)

	_emitted_signal_args.clear()
	svc.remove_ads_changed.connect(_capture_remove_ads_changed)

	svc.grant_remove_ads()  # Should emit once
	svc.grant_remove_ads()  # Idempotent — must NOT emit again

	assert_int(_emitted_signal_args.size()).is_equal(1)
	assert_bool(_emitted_signal_args[0]).is_true()

	svc.remove_ads_changed.disconnect(_capture_remove_ads_changed)


# ---------------------------------------------------------------------------
# EntitlementService.restore() — mock backend grants when receipt present
# ---------------------------------------------------------------------------

func test_restore_with_receipt_present_grants_entitlement() -> void:
	var save = _temp_save()
	var svc = auto_free(ENTITLEMENT_SCRIPT.new())
	var backend = BACKEND_SCRIPT.MockEntitlementBackend.new()
	backend.receipt_present = true
	svc.configure(save, backend)

	var did_restore: bool = svc.restore()

	assert_bool(did_restore).is_true()
	assert_bool(svc.is_remove_ads_owned()).is_true()


func test_restore_without_receipt_does_not_grant() -> void:
	var save = _temp_save()
	var svc = auto_free(ENTITLEMENT_SCRIPT.new())
	var backend = BACKEND_SCRIPT.MockEntitlementBackend.new()
	backend.receipt_present = false
	svc.configure(save, backend)

	var did_restore: bool = svc.restore()

	assert_bool(did_restore).is_false()
	assert_bool(svc.is_remove_ads_owned()).is_false()


func test_restore_after_grant_is_idempotent_returns_true() -> void:
	# Grant first, then restore — owned stays owned; restore returns true because
	# after the call the entitlement is (still) owned.
	var save = _temp_save()
	var svc = auto_free(ENTITLEMENT_SCRIPT.new())
	var backend = BACKEND_SCRIPT.MockEntitlementBackend.new()
	backend.receipt_present = true
	svc.configure(save, backend)

	svc.grant_remove_ads()
	var did_restore: bool = svc.restore()

	# restore() calls grant_remove_ads() which is idempotent; result is still owned.
	assert_bool(did_restore).is_true()
	assert_bool(svc.is_remove_ads_owned()).is_true()


# ---------------------------------------------------------------------------
# Gating API: should_suppress_interstitials / is_rewarded_available
# ---------------------------------------------------------------------------

func test_not_owned_interstitials_not_suppressed() -> void:
	var save = _temp_save()
	save.data.remove_ads_owned = false
	var svc = auto_free(ENTITLEMENT_SCRIPT.new())
	svc.configure(save, BACKEND_SCRIPT.MockEntitlementBackend.new())
	assert_bool(svc.should_suppress_interstitials()).is_false()


func test_owned_interstitials_suppressed() -> void:
	var save = _temp_save()
	save.data.remove_ads_owned = true
	var svc = auto_free(ENTITLEMENT_SCRIPT.new())
	svc.configure(save, BACKEND_SCRIPT.MockEntitlementBackend.new())
	assert_bool(svc.should_suppress_interstitials()).is_true()


func test_rewarded_always_available_regardless_of_entitlement() -> void:
	# GAME_PLAN §8: rewarded ads remain available even when Remove-Ads is owned.
	var save_not_owned = auto_free(SAVE_SCRIPT.new())
	save_not_owned.data.remove_ads_owned = false
	var svc_not_owned = auto_free(ENTITLEMENT_SCRIPT.new())
	svc_not_owned.configure(save_not_owned, BACKEND_SCRIPT.MockEntitlementBackend.new())

	var save_owned = auto_free(SAVE_SCRIPT.new())
	save_owned.data.remove_ads_owned = true
	var svc_owned = auto_free(ENTITLEMENT_SCRIPT.new())
	svc_owned.configure(save_owned, BACKEND_SCRIPT.MockEntitlementBackend.new())

	assert_bool(svc_not_owned.is_rewarded_available()).is_true()
	assert_bool(svc_owned.is_rewarded_available()).is_true()


# ---------------------------------------------------------------------------
# Single-reader chokepoint: remove_ads_owned is referenced ONLY by the serializer
# (SaveData), the persistence autoload (SaveService), and EntitlementService — the
# entitlement-gating analogue of the consent single-reader rule (ADR-0014 §3). Mirrors
# test_consent_fields_read_only_by_permitted_files in the consent suite.
# ---------------------------------------------------------------------------

func test_remove_ads_owned_read_only_by_permitted_files() -> void:
	var permitted: Array[String] = [
		"res://core/save_data.gd",
		"res://autoloads/save_service.gd",
		"res://autoloads/entitlement_service.gd",
	]
	var scan_dirs: Array[String] = ["res://autoloads", "res://core"]
	var violations: Array[String] = []

	for dir_path: String in scan_dirs:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".gd"):
				var full_path: String = dir_path + "/" + fname
				var is_permitted: bool = false
				for p: String in permitted:
					if full_path == p:
						is_permitted = true
						break
				if not is_permitted:
					var file := FileAccess.open(full_path, FileAccess.READ)
					if file != null:
						var content: String = file.get_as_text()
						file.close()
						if content.contains("remove_ads_owned"):
							violations.append(full_path + " references remove_ads_owned")
			fname = dir.get_next()
		dir.list_dir_end()

	assert_int(violations.size()).is_equal(0)
