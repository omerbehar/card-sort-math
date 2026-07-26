extends SceneTree
## Dev harness: captures the S5-002 HUD wallet display (coins + gems pills) as PNGs,
## proving both currencies render in the top bar (no overlap with the level/percent
## chrome) and that the pills live-update on WalletService.economy_event:
##   1. wallet-display-before.png — coins + gems seeded from the wallet
##   2. wallet-display-after.png  — after an earn/grant, both pills counted up
##
## Run with a real display (headless uses a dummy renderer that produces no image):
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_wallet_display.gd

const BEFORE_PATH := "user://wallet-display-before.png"
const AFTER_PATH := "user://wallet-display-after.png"


func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(8)

	var wallet: Node = root.get_node("WalletService")
	var settings: Node = root.get_node("SettingsService")
	settings.set_value("reduced_motion", false)   # exercise the real count-up path
	var coins := EconomyEnums.Currency.COINS
	var gems := EconomyEnums.Currency.GEMS

	# --- "before": a readable, distinct starting balance for each currency. ---
	wallet.debug_set_inventory(1250, 3)            # coins = 1250 (no economy_event)
	main._hud.refresh_wallet()                      # so snap the pills to it
	wallet.grant_iap_currency(gems, 8)              # gems = 8 (emits economy_event)
	await _wait_frames(30)                           # let any count-up settle
	_capture(BEFORE_PATH)

	# --- "after": earn coins + grant gems → both pills live-update via economy_event. ---
	wallet.earn(coins, 250, EconomyEnums.EarnSource.LEVEL_WIN)   # coins → 1500
	wallet.grant_iap_currency(gems, 40)                          # gems → 48
	await _wait_frames(30)                                        # settle the count-up
	_capture(AFTER_PATH)

	print("coins=%d gems=%d" % [wallet.balance(coins), wallet.balance(gems)])
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
