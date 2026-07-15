extends SceneTree
## Dev harness: captures the S5-005 mock interstitial as a PNG:
##   interstitial-mock.png — the full-screen mock "ad" with the close affordance revealed
##
## Run with a real display (headless renders nothing):
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_interstitial.gd

const PATH := "user://interstitial-mock.png"


func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(8)

	# Present the mock via the real presentation path (AdService supplies the ad type).
	main._present_interstitial(root.get_node("AdService"))
	await _wait_frames(8)
	# Reveal the close affordance (skip the beat) for the capture.
	if is_instance_valid(main._interstitial):
		main._interstitial._reveal_close()
	await _wait_frames(4)
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
