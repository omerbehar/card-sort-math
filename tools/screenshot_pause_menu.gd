extends SceneTree
## Dev harness: boots the main board, opens the pause menu, and saves a
## screenshot to user://settings_screenshot.png. Run with a real display (e.g.
## xvfb-run) — headless uses a dummy renderer that produces no image.
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_settings.gd

const OUT_PATH := "user://settings_screenshot.png"


func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	# Let the board build and autoloads finish _ready.
	await _wait_frames(8)

	# Set explicit values so the capture is deterministic (it writes to the real
	# user:// save). Shows variety: music muted (dim round toggle), colorblind on
	# (recoloured stacks via the live signal + an ON pill switch), reduced-motion
	# off (an OFF pill switch).
	var settings: Node = root.get_node("SettingsService")
	settings.set_value("sound", true)
	settings.set_value("music", false)
	settings.set_value("haptics", true)
	settings.set_value("colorblind", true)
	settings.set_value("reduced_motion", false)
	await _wait_frames(2)

	main._open_pause()
	await _wait_frames(8)

	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(ProjectSettings.globalize_path(OUT_PATH))
	if err == OK:
		print("Saved screenshot to ", ProjectSettings.globalize_path(OUT_PATH))
	else:
		printerr("Screenshot failed: ", err)
	quit()


func _wait_frames(n: int) -> void:
	for _i in n:
		await process_frame
