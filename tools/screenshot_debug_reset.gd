extends SceneTree
## Dev harness: verifies the Settings "Reset Inventory" debug button end-to-end and
## captures the story as three PNGs under user://:
##   1. debug_reset_before.png   — HUD with a depleted inventory (buffs at "+", low coins)
##   2. debug_reset_settings.png — pause menu open, showing the "Reset Inventory" button
##   3. debug_reset_after.png    — HUD after pressing it (1000 coins, every buff badge = 3)
##
## Run with a real display (headless uses a dummy renderer that produces no image):
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_debug_reset.gd

const BEFORE_PATH := "user://debug_reset_before.png"
const SETTINGS_PATH := "user://debug_reset_settings.png"
const AFTER_PATH := "user://debug_reset_after.png"


func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	# Let the board build and autoloads finish _ready.
	await _wait_frames(8)

	var wallet: Node = root.get_node("WalletService")
	var coins := EconomyEnums.Currency.COINS

	# --- Arrange a depleted "before" state: drain every buff to 0 and coins to ~75. ---
	for type: int in [
			EconomyEnums.BoosterType.PICKER,
			EconomyEnums.BoosterType.RESHUFFLE,
			EconomyEnums.BoosterType.EXTRA_DISCARD]:
		while wallet.booster_count(type) > 0:
			wallet.consume_booster(type)
	var bal: int = wallet.balance(coins)
	if bal > 75:
		wallet.spend(coins, bal - 75)
	elif bal < 75:
		wallet.earn(coins, 75 - bal, EconomyEnums.EarnSource.LEVEL_WIN)
	main._update_coins_hud()
	await _wait_frames(3)
	_capture(BEFORE_PATH)

	# --- Open the pause menu and capture the debug button. ---
	main._open_pause()
	await _wait_frames(8)
	_capture(SETTINGS_PATH)

	# --- Press the real debug button → debug_reset_pressed → main._on_debug_reset. ---
	var btn: Button = main._pause_menu._buttons.get("debug_reset")
	if btn == null:
		printerr("Reset Inventory button not found (is this a debug build?)")
		quit()
		return
	btn.pressed.emit()
	await _wait_frames(3)

	# --- Dismiss the menu and capture the unobstructed, refreshed HUD. ---
	var menu: Node = main._pause_menu
	main._close_pause()
	if is_instance_valid(menu):
		menu.queue_free()
	await _wait_frames(5)
	_capture(AFTER_PATH)

	print("coins=%d picker=%d reshuffle=%d extra=%d" % [
		wallet.balance(coins),
		wallet.booster_count(EconomyEnums.BoosterType.PICKER),
		wallet.booster_count(EconomyEnums.BoosterType.RESHUFFLE),
		wallet.booster_count(EconomyEnums.BoosterType.EXTRA_DISCARD)])
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
