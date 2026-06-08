extends SceneTree
## Dev harness: boots the main board, opens the settings panel, and saves a
## screenshot to user://settings_screenshot.png. Run with a real display (e.g.
## xvfb-run) — headless uses a dummy renderer that produces no image.
##
##   xvfb-run -a godot --path . -s res://tools/screenshot_settings.gd

const OUT_PATH := "user://settings_screenshot.png"


func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	# Let the board build, then open settings and let it lay out.
	await _wait_frames(8)
	main._open_settings()
	# Flip a couple of toggles so the screenshot shows both on and off dots.
	var settings: Node = root.get_node("SettingsService")
	settings.set_value("music", false)
	settings.set_value("reduced_motion", true)
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
