extends SceneTree
## Temporary tool: drives the real Main controller through a greedy win on the
## current level (emitting taps on the actual Card nodes so the full animation /
## event-playback path runs), then screenshots the win overlay and quits.

var _mirror: BoardModel


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	_play(main)


func _play(main: Node) -> void:
	for _i in range(10):
		await process_frame
	var floor_area: FloorArea = main.get_node("FloorArea")
	var level_data: Node = root.get_node("/root/LevelData")
	var game_manager: Node = root.get_node("/root/GameManager")
	_mirror = BoardModel.from_config(level_data.get_level(game_manager.current_level))

	var guard: int = 0
	while not _mirror.is_game_over() and guard < 500:
		guard += 1
		var pick: int = _greedy_pick()
		if pick == -1:
			break
		# Wait for the board to be idle before tapping, so the controller never
		# drops the tap — keeps mirror and controller in lockstep.
		while main.is_input_locked():
			await process_frame
		var card := floor_area.get_card(pick)
		if card != null:
			card.tapped.emit(pick)
		_mirror.tap_card(pick)
		await process_frame
		await process_frame
		while main.is_input_locked():
			await process_frame

	for _i in range(20):
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("res://tools/play_capture.png")
	print("PLAY_DONE won=", _mirror.is_won())
	quit()


func _greedy_pick() -> int:
	var discard_pick: int = -1
	for card_id: int in _mirror.exposed_cards():
		var result: int = _mirror.result_of(card_id)
		for i in BoardModel.STACK_COUNT:
			if _mirror.stack_target(i) == result and _mirror.stack_count(i) < BoardModel.STACK_CAPACITY:
				return card_id
		if discard_pick == -1:
			discard_pick = card_id
	return discard_pick
