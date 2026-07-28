extends SceneTree
## Dev harness: captures the S6-001 first-run neutral age gate:
##   age-gate.png — the birth-year gate shown over the board on first launch
##
## Run with a real display (headless renders nothing):
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_age_gate.gd

const PATH := "user://age-gate.png"


func _initialize() -> void:
	# Let the SaveService autoload finish _ready()/load_game() first, THEN force a first-run
	# state in memory (else the persisted band overwrites it), before main is built.
	await _wait_frames(2)
	root.get_node("SaveService").data.age_band = SaveData.AgeBand.UNKNOWN

	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)   # main._ready → sees UNKNOWN → presents the gate
	await _wait_frames(14)
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
