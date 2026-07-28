extends SceneTree
## Dev harness: captures the S6-004 child-safe shop (parental-gate banner):
##   child-shop.png
##
## Run with a real display (headless renders nothing):
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_child_shop.gd

const PATH := "user://child-shop.png"


func _initialize() -> void:
	await _wait_frames(2)
	var save := root.get_node("SaveService")
	save.data.age_band = SaveData.AgeBand.CHILD   # declared under-13

	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(12)

	main._hud.currency_tapped.emit(EconomyEnums.Currency.COINS)
	await _wait_frames(12)
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
