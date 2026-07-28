extends SceneTree
## Dev harness: captures the S6-002 consent capture sheet (shown after an adult clears the
## age gate):
##   consent-sheet.png
##
## Run with a real display (headless renders nothing):
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_consent_sheet.gd

const PATH := "user://consent-sheet.png"


func _initialize() -> void:
	await _wait_frames(2)
	var save := root.get_node("SaveService")
	save.data.age_band = SaveData.AgeBand.UNKNOWN
	save.data.consent_captured = false

	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(12)

	# Clear the age gate as an adult → the consent sheet is presented.
	if is_instance_valid(main._age_gate):
		main._age_gate._set_year(int(Time.get_date_dict_from_system().get("year", 2026)) - 30)
		main._age_gate._on_confirm()
	await _wait_frames(12)
	# Toggle one on so the screenshot shows both states.
	if is_instance_valid(main._consent_sheet):
		main._consent_sheet._toggles["analytics"].pressed.emit()
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
