extends GdUnitTestSuite
## Integration tests for the Remove-Ads gate through [EntitlementService] (S4-003, ADR-0014 §3).
##
## Most tests drive real [EntitlementService] and [SaveService] instances via the
## [method EntitlementService.configure] DI seam; one test boots the real
## [code]scenes/main/main.tscn[/code] + autoloads via gdUnit4's scene_runner to prove the
## autoload registration and _ready() dependency resolution (CLAUDE.md mandatory
## validation). File I/O is confined to tests that exercise the save path, cleaned up
## unconditionally in [method after_test].
##
## Covers:
## - When owned: [method EntitlementService.should_suppress_interstitials] is true; rewarded
##   remains available.
## - When not owned: interstitials are not suppressed.
## - Save-write failure edge: in-memory owned survives the session (QA EC4/EC15).
## - End-to-end: grant via configure → persist → reload → gate active.
## - Real scene-tree boot: EntitlementService autoload resolves SaveService and reads the
##   live save field.

const ENTITLEMENT_SCRIPT := preload("res://autoloads/entitlement_service.gd")
const SAVE_SCRIPT := preload("res://autoloads/save_service.gd")
const BACKEND_SCRIPT := preload("res://autoloads/entitlement_backend.gd")
const MAIN := "res://scenes/main/main.tscn"

# Temp save paths created by file-I/O tests; cleaned unconditionally in after_test().
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


## Builds an in-memory [EntitlementService] wired to a fresh [SaveService] with the given
## owned state and a configurable mock backend. The save is pointed at a unique temp path so
## grant/restore persistence never leaks into the real user://save.json (test hygiene).
func _make_svc(owned: bool, receipt_present: bool = false):
	var path: String = "user://test_entitlement_gate_%d.json" % _temp_save_paths.size()
	_temp_save_paths.append(path)
	var save = auto_free(SAVE_SCRIPT.new())
	save.configure(path)
	save.data.remove_ads_owned = owned
	var backend = BACKEND_SCRIPT.MockEntitlementBackend.new()
	backend.receipt_present = receipt_present
	var svc = auto_free(ENTITLEMENT_SCRIPT.new())
	svc.configure(save, backend)
	return svc


# ---------------------------------------------------------------------------
# Core gate: owned → interstitials suppressed, rewarded still available
# ---------------------------------------------------------------------------

func test_owned_suppresses_interstitials_and_keeps_rewarded_available() -> void:
	# Arrange: Remove-Ads owned
	var svc = _make_svc(true)

	# Assert: interstitials suppressed (GAME_PLAN §8 / ADR-0014 §3)
	assert_bool(svc.should_suppress_interstitials()).is_true()

	# Assert: rewarded ads remain available (GAME_PLAN §8: "Remove-Ads keeps optional rewarded")
	assert_bool(svc.is_rewarded_available()).is_true()


# ---------------------------------------------------------------------------
# Core gate: not owned → interstitials not suppressed, rewarded still available
# ---------------------------------------------------------------------------

func test_not_owned_interstitials_not_suppressed_rewarded_available() -> void:
	# Arrange: Remove-Ads NOT owned
	var svc = _make_svc(false)

	# Assert: interstitials are NOT suppressed when entitlement is not held
	assert_bool(svc.should_suppress_interstitials()).is_false()

	# Assert: rewarded ads are still available (entitlement has no effect on rewarded)
	assert_bool(svc.is_rewarded_available()).is_true()


# ---------------------------------------------------------------------------
# Restore-across-reinstall: mock backend with receipt grants and then suppresses
# ---------------------------------------------------------------------------

func test_restore_with_receipt_grants_and_suppresses_interstitials() -> void:
	# Arrange: fresh save (no entitlement), mock backend has a receipt
	var svc = _make_svc(false, true)

	# Act: restore finds the receipt
	var did_restore: bool = svc.restore()

	# Assert: restore succeeded and the gate is now active
	assert_bool(did_restore).is_true()
	assert_bool(svc.is_remove_ads_owned()).is_true()
	assert_bool(svc.should_suppress_interstitials()).is_true()
	assert_bool(svc.is_rewarded_available()).is_true()


# ---------------------------------------------------------------------------
# Save-write failure: in-memory owned survives the session (QA EC4/EC15)
# When the save directory is unwritable (simulated), the in-memory flag stays
# true so the player retains the entitlement for the session.
# ---------------------------------------------------------------------------

func test_grant_persists_in_memory_even_if_save_path_unwritable() -> void:
	# Arrange: wire a SaveService with a path that cannot be written
	# (non-existent subdirectory → the rename step will fail, save_game() logs an error).
	var save = auto_free(SAVE_SCRIPT.new())
	# Point at a path in a subdirectory that does not exist — write will fail silently.
	var bad_path: String = "user://nonexistent_subdir_ec15/test_entitlement_ec15.json"
	save.configure(bad_path)
	# Data is in memory (fresh defaults — no disk load).
	save.data.remove_ads_owned = false

	var backend = BACKEND_SCRIPT.MockEntitlementBackend.new()
	backend.receipt_present = false
	var svc = auto_free(ENTITLEMENT_SCRIPT.new())
	svc.configure(save, backend)

	# Act: grant — the save will fail (bad path), but grant_remove_ads must still
	# set the in-memory flag so the session retains the entitlement (EC4/EC15).
	svc.grant_remove_ads()

	# Assert the write ACTUALLY failed — otherwise this test would silently stop
	# exercising the EC15 path (e.g. if save_game() ever auto-created the subdir).
	assert_bool(FileAccess.file_exists(bad_path)).is_false()

	# Assert: in-memory flag is true despite the write failure.
	assert_bool(save.data.remove_ads_owned).is_true()
	assert_bool(svc.is_remove_ads_owned()).is_true()
	assert_bool(svc.should_suppress_interstitials()).is_true()


# ---------------------------------------------------------------------------
# Full end-to-end: grant via configure → persist to file → reload → gate active
# ---------------------------------------------------------------------------

func test_grant_persists_across_save_reload_cycle() -> void:
	# Arrange: write a save, grant entitlement, load into a new service.
	var path: String = "user://test_entitlement_persist.json"
	_temp_save_paths.append(path)

	# First session: grant Remove-Ads and save.
	var save1 = auto_free(SAVE_SCRIPT.new())
	save1.configure(path)
	var svc1 = auto_free(ENTITLEMENT_SCRIPT.new())
	svc1.configure(save1, BACKEND_SCRIPT.MockEntitlementBackend.new())
	svc1.grant_remove_ads()
	# Verify in-memory before reload.
	assert_bool(svc1.is_remove_ads_owned()).is_true()

	# Second session: load the save into a fresh service.
	var save2 = auto_free(SAVE_SCRIPT.new())
	save2.configure(path)
	save2.load_game()
	var svc2 = auto_free(ENTITLEMENT_SCRIPT.new())
	svc2.configure(save2, BACKEND_SCRIPT.MockEntitlementBackend.new())

	# Assert: the gate is active after reload.
	assert_bool(svc2.is_remove_ads_owned()).is_true()
	assert_bool(svc2.should_suppress_interstitials()).is_true()
	assert_bool(svc2.is_rewarded_available()).is_true()


# ---------------------------------------------------------------------------
# Real scene-tree boot: EntitlementService registers as an autoload, resolves
# SaveService in _ready(), and the gate reads the live save end-to-end
# (CLAUDE.md mandatory validation + ADR-0014 validation criteria).
# ---------------------------------------------------------------------------

func test_entitlement_service_boots_as_autoload_and_resolves_save() -> void:
	# Arrange: boot the real main scene + all autoloads.
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	var root := get_tree().root

	# Assert: the new autoload is registered, and so is its SaveService dependency.
	var ent := root.get_node_or_null("EntitlementService")
	var save := root.get_node_or_null("SaveService")
	assert_object(ent).is_not_null()
	assert_object(save).is_not_null()

	# Assert: _ready() resolved _save = SaveService — the gate reads the LIVE save field
	# (proves end-to-end wiring, not an isolated unit). Holds for either owned state.
	assert_bool(ent.should_suppress_interstitials()).is_equal(save.data.remove_ads_owned)
	assert_bool(ent.is_remove_ads_owned()).is_equal(save.data.remove_ads_owned)
	assert_bool(ent.is_rewarded_available()).is_true()
