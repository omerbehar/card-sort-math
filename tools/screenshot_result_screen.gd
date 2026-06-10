extends SceneTree
## Dev harness: boots the main board and captures the win and lose ResultScreen
## (S1-020) to PNGs. Run with a real display (headless has no renderer):
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_result_screen.gd

const WIN_PATH := "res://production/qa/evidence/s1-020-result-win.png"
const LOSE_PATH := "res://production/qa/evidence/s1-020-result-lose.png"


func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(8)

	# Free the first-run tutorial coach so it does not bleed into the capture (it
	# would never be present at a real win/lose).
	if is_instance_valid(main._coach):
		main._coach.queue_free()
		main._coach = null
	await _wait_frames(2)

	# WIN
	main._show_result(ResultScreen.Mode.WIN)
	await _wait_frames(8)
	_capture(WIN_PATH)

	# Dismiss and show LOSE (dismiss rebuilds the board; re-show in lose mode).
	if is_instance_valid(main._result_screen):
		main._result_screen.queue_free()
		main._result_screen = null
	await _wait_frames(4)
	main._show_result(ResultScreen.Mode.LOSE)
	await _wait_frames(8)
	_capture(LOSE_PATH)

	quit()


func _capture(path: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err == OK:
		print("Saved ", ProjectSettings.globalize_path(path))
	else:
		printerr("Capture failed (", err, ") for ", path)


func _wait_frames(n: int) -> void:
	for _i in n:
		await process_frame
