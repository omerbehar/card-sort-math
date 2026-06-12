extends SceneTree
## Dev harness: boots the main board and captures it to a PNG so we can see the
## locked-decks prototype (1 deck open, 3 buyable "+" slots) + coin HUD. Run with
## a real display (headless has no renderer):
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_board.gd

const OUT_PATH := "res://production/qa/evidence/locked-decks.png"


func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(10)

	# Free the first-run tutorial coach so it does not cover the board.
	if is_instance_valid(main._coach):
		main._coach.queue_free()
		main._coach = null
	await _wait_frames(4)

	_capture(OUT_PATH)
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
