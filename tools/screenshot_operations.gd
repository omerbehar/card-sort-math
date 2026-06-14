extends SceneTree
## Dev harness: boots the main board and captures one level per operation world to
## PNGs, proving subtraction (−), multiplication (×) and division (÷) cards render
## alongside addition (+) and a mixed-operation level. Run with a real display
## (headless has no renderer):
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_operations.gd

const OUT_DIR := "res://production/qa/evidence/"

# (level index, output file) — one representative level per world.
const SHOTS := [
	[3, "operations-add.png"],        # authored addition (world 0)
	[8, "operations-subtract.png"],   # world 1 = subtraction
	[13, "operations-multiply.png"],  # world 2 = multiplication
	[18, "operations-divide.png"],    # world 3 = division
	[25, "operations-mixed.png"],     # mixed world
]


func _initialize() -> void:
	var save := root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true

	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(10)

	# Free the first-run tutorial coach so it does not cover the board.
	if is_instance_valid(main._coach):
		main._coach.queue_free()
		main._coach = null
	await _wait_frames(4)

	for shot in SHOTS:
		main.start_level(int(shot[0]))
		await _wait_frames(12)
		_capture(OUT_DIR + str(shot[1]))

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
