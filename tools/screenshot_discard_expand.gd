extends SceneTree
## Dev harness: proves the discard-row fixes (2026-06-14) visually — fills a few
## discard slots, then grows the row twice (Extra Discard) and captures it, so the
## cards already in the row should sit centred on their slots (not between slots).
## Run with a real display (headless has no renderer):
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_discard_expand.gd

const OUT_PATH := "res://production/qa/evidence/discard-expand-reposition.png"


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

	# All-discard board so taps fill the discard row deterministically.
	var cfg := LevelConfig.new()
	cfg.level_id = 1
	cfg.layout_id = 0
	cfg.target_queue = [1, 2, 3, 4] as Array[int]
	var placements := Layouts.get_layout(0)
	var pool: Array[CardData] = []
	for slot in 12:
		pool.append(CardData.create(90, 9, int(placements[slot].layer), slot))  # 90+9 = 99
	cfg.card_pool = pool
	main.load_level_config(cfg, BoardModel.STACK_COUNT)
	await _wait_frames(5)

	# Discard four cards, then grow the row to 7 slots (two Extra Discard expansions).
	for _i in 4:
		var exposed: Array = main._model.exposed_cards()
		if exposed.is_empty():
			break
		main._on_card_tapped(exposed[0])
		await _wait_frames(18)
	main.expand_discard()
	await _wait_frames(18)
	main.expand_discard()
	await _wait_frames(24)

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
