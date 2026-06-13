extends SceneTree
## Dev-only harness: boots the real Main board, expands the discard buffer once
## (Extra Discard Slot booster, S3-006), and saves a screenshot of the live scene.
## Run headless-with-display:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 390x844 \
##     -s res://tools/screenshot_discard.gd -- <expansions> <out.png>
## Not shipped; pure tooling (tools/ scope).

var _main: Node = null
var _frames: int = 0
var _expanded: bool = false
var _expansions: int = 1
var _out: String = "/tmp/game_discard.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_expansions = int(args[0])
	if args.size() >= 2:
		_out = args[1]
	# Suppress the first-time tutorial coach so it never covers the board.
	var save := root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	# Let the board build + settle, then expand the discard buffer.
	if _frames == 20 and not _expanded:
		for i in _expansions:
			if _main.has_method("expand_discard"):
				_main.expand_discard()
		_expanded = true
	if _frames >= 55:
		var img: Image = root.get_texture().get_image()
		img.save_png(_out)
		print("SHOT_SAVED ", _out, " ", img.get_size())
		quit()
	return false
