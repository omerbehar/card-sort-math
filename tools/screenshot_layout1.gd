extends SceneTree
## Dev harness: boots the board on LV2 (layout 1) and captures it, to verify the
## top-layer cards no longer overlap each other. Run with a real display:
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_layout1.gd

const OUT_PATH := "res://production/qa/evidence/layout1-no-self-overlap.png"


func _initialize() -> void:
	var save := root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true

	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(10)
	if is_instance_valid(main._coach):
		main._coach.queue_free()
		main._coach = null
	main.start_level(2)               # LV2 → layout 1 (the reported case)
	await _wait_frames(12)

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
