extends SceneTree
## Dev harness: opens the S5-003 Shop over the board and captures it, plus a
## Remove-Ads "Owned" variant, as PNGs:
##   1. shop-default.png    — full catalog (Remove-Ads anchor + coin/gem packs + bundle)
##   2. shop-remove-ads-owned.png — after granting Remove-Ads: card reads "Owned ✓"
##
## Run with a real display (headless renders nothing):
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_shop.gd

const DEFAULT_PATH := "user://shop-default.png"
const OWNED_PATH := "user://shop-remove-ads-owned.png"


func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(8)

	# Grant IAP consent so a real purchase could resolve (mock consent granted).
	var save: Node = root.get_node("SaveService")
	save.data.age_band = SaveData.AgeBand.ADULT
	save.data.consent_iap = true
	# Ensure a clean, purchasable "before" state (the save persists remove_ads across runs).
	save.data.remove_ads_owned = false

	# --- Open the shop via the wallet-pill deep-link and capture the full catalog. ---
	main._hud.currency_tapped.emit(EconomyEnums.Currency.COINS)
	await _wait_frames(12)
	_capture(DEFAULT_PATH)

	# --- Grant Remove-Ads, reopen, and capture the "Owned ✓" state. ---
	if is_instance_valid(main._shop_screen):
		main._shop_screen.close()
	await _wait_frames(6)
	root.get_node("EntitlementService").grant_remove_ads()
	main._hud.currency_tapped.emit(EconomyEnums.Currency.COINS)
	await _wait_frames(12)
	_capture(OWNED_PATH)

	quit()


func _capture(path: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err == OK:
		print("Saved screenshot to ", ProjectSettings.globalize_path(path))
	else:
		printerr("Screenshot failed (", err, ") for ", path)


func _wait_frames(n: int) -> void:
	for _i in n:
		await process_frame
