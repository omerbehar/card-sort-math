extends SceneTree
## Dev-only harness: boots the real Main board, optionally expands the discard
## buffer (Extra Discard Slot booster, S3-006) and taps a few cards into discard,
## then saves a screenshot of the live scene.
## Run headless-with-display:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 390x844 \
##     -s res://tools/screenshot_discard.gd -- <expansions> <out.png> [taps]
## Not shipped; pure tooling (tools/ scope).

var _main: Node = null
var _frames: int = 0
var _phase: int = 0
var _expansions: int = 1
var _taps: int = 0
var _taps_done: int = 0
var _tap_list: Array = []
var _capture_at: int = 0
var _out: String = "/tmp/game_discard.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_expansions = int(args[0])
	if args.size() >= 2:
		_out = args[1]
	if args.size() >= 3:
		_taps = int(args[2])
	var save := root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)


func _build_tap_list() -> void:
	var model = _main._model
	var open_target: int = -1
	for i in BoardModel.STACK_COUNT:
		if not model.is_stack_locked(i):
			open_target = model.stack_target(i)
			break
	# Cards whose result does NOT match the open stack target → they discard.
	for cid in model.exposed_cards():
		if model.result_of(cid) != open_target:
			_tap_list.append(cid)


func _process(_delta: float) -> bool:
	_frames += 1
	match _phase:
		0:  # settle, then expand the buffer and prepare the tap list
			if _frames >= 20:
				for i in _expansions:
					if _main.has_method("expand_discard"):
						_main.expand_discard()
				_build_tap_list()
				_phase = 1
		1:  # tap discardable cards one at a time (wait for each animation to finish)
			if _taps_done >= _taps or _tap_list.is_empty():
				_capture_at = _frames + 12
				_phase = 2
			elif not _main.is_input_locked():
				_main._on_card_tapped(_tap_list.pop_front())
				_taps_done += 1
		2:  # wait for the last fly+scale to finish (input unlocks), then settle + capture
			if not _main.is_input_locked() and _frames >= _capture_at:
				var img: Image = root.get_texture().get_image()
				img.save_png(_out)
				print("SHOT_SAVED ", _out, " ", img.get_size(), " taps=", _taps_done)
				quit()
	return false
