extends SceneTree
## Dev harness: boots the main board and captures one representative level per new
## progression band, proving the three-term teaching worlds render correctly and
## that two decks start unlocked. Run with a real display (headless has no
## renderer):
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_progression.gd

const OUT_DIR := "res://production/qa/evidence/"

# (level index, output file) — one representative level per new band. Level 21
# also evidences the two-decks-unlocked-by-default change (stacks 2 & 3 locked).
const SHOTS := [
	[21, "progression-three-term-addsub.png"],   # 21-25: a ± b ± c, left-to-right
	[28, "progression-parentheses.png"],         # 26-30: parentheses
	[33, "progression-order-of-operations.png"], # 31-40: ×/÷ with +/−
	[45, "progression-mixed.png"],               # 41+: all styles mixed
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
		var locked := _locked_summary(main)
		print("Level ", shot[0], " locked stacks: ", locked)
		_capture(OUT_DIR + str(shot[1]))

	quit()


# Lists which stack indices start locked, to evidence the 2-deck default.
func _locked_summary(main: Node) -> Array:
	var locked: Array = []
	for s in range(BoardModel.STACK_COUNT):
		if main._model.is_stack_locked(s):
			locked.append(s)
	return locked


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
