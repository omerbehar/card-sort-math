extends SceneTree
## Dev harness: captures the S5-006 one-per-session Remove-Ads offer sheet:
##   remove-ads-offer.png — the dismissible bottom sheet over the board
##
## Run with a real display (headless renders nothing):
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_remove_ads_offer.gd

const PATH := "user://remove-ads-offer.png"


func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(8)

	# Ensure a clean not-owned state so the offer surfaces.
	root.get_node("SaveService").data.remove_ads_owned = false

	main._maybe_offer_remove_ads()
	await _wait_frames(12)
	_capture(PATH)

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
