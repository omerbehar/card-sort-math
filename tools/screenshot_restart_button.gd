extends SceneTree
## Dev harness: boots the main board, opens the pause menu, and captures it to a
## PNG so the new debug "Restart from Lv 1" button can be verified visually. Run
## with a real display (headless has no renderer):
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_restart_button.gd

const OUT_PATH := "res://production/qa/evidence/restart-from-lv1-button.png"


func _initialize() -> void:
	var save := root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true

	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(10)

	main._open_pause()
	await _wait_frames(8)

	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(ProjectSettings.globalize_path(OUT_PATH))
	if err == OK:
		print("Saved ", ProjectSettings.globalize_path(OUT_PATH))
	else:
		printerr("Capture failed (", err, ")")
	quit()


func _wait_frames(n: int) -> void:
	for _i in n:
		await process_frame
