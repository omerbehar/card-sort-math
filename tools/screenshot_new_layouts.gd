extends SceneTree
## Dev harness: boots the real board on the first levels that use each new floor
## preset (layout 3 → LV57, layout 4 → LV65, layout 5 → LV73 under the late-game
## layout cycle) and captures one screenshot each, proving the presets render in
## the real scene with no same-layer overlap. Also logs the two starting deck
## targets so the "distinct starting decks / no two in a row" change is visible.
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_new_layouts.gd

const SHOTS := {
	57: "res://production/qa/evidence/layout3-lv57.png",
	65: "res://production/qa/evidence/layout4-lv65.png",
	73: "res://production/qa/evidence/layout5-lv73.png",
}


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

	var level_data: Node = root.get_node("LevelData")
	for level: int in SHOTS:
		main.start_level(level)
		await _wait_frames(14)
		var config: LevelConfig = level_data.get_level(level)
		var queue: Array = config.target_queue
		print("LV%d  layout=%d  queue=%s  starting decks=[%d, %d]"
			% [level, config.layout_id, str(queue), queue[0], queue[1]])
		var img := root.get_viewport().get_texture().get_image()
		var err := img.save_png(ProjectSettings.globalize_path(SHOTS[level]))
		if err == OK:
			print("  saved ", ProjectSettings.globalize_path(SHOTS[level]))
		else:
			printerr("  capture failed (", err, ")")

	quit()


func _wait_frames(n: int) -> void:
	for _i in n:
		await process_frame
