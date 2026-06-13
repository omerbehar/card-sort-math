extends SceneTree
## Dev-only harness: boots the real Main board, funds the wallet, then triggers a
## booster (Picker or Reshuffle) and saves before/after screenshots of the live scene.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 390x844 \
##     -s res://tools/screenshot_boosters.gd -- <picker|reshuffle> <before.png> <after.png>
## Not shipped; pure tooling (tools/ scope).

var _main: Node = null
var _frames: int = 0
var _phase: int = 0
var _mode: String = "picker"
var _before: String = "/tmp/before.png"
var _after: String = "/tmp/after.png"
var _act_at: int = 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_mode = args[0]
	if args.size() >= 2:
		_before = args[1]
	if args.size() >= 3:
		_after = args[2]
	var save := root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)


func _save_shot(path: String) -> void:
	var img: Image = root.get_texture().get_image()
	img.save_png(path)
	print("SHOT_SAVED ", path)


# First covered (not-exposed, not-removed) card on the floor — the Picker target.
func _first_covered_card() -> int:
	var model = _main._model
	var count: int = _main._config.card_pool.size()
	for cid in count:
		if not model.is_card_removed(cid) and not model.is_exposed(cid):
			return cid
	return -1


func _process(_delta: float) -> bool:
	_frames += 1
	match _phase:
		0:  # settle, fund the wallet, capture "before"
			if _frames >= 20:
				var wallet := root.get_node_or_null("WalletService")
				if wallet != null:
					wallet.earn(EconomyEnums.Currency.COINS, 1000, EconomyEnums.EarnSource.LEVEL_WIN)
				_save_shot(_before)
				_phase = 1
		1:  # trigger the booster
			if _mode == "picker":
				var cid: int = _first_covered_card()
				_main.pick(cid)
			else:
				_main.reshuffle_now()
			_act_at = _frames + 45
			_phase = 2
		2:  # wait for the animation/tween to settle, capture "after"
			if not _main.is_input_locked() and _frames >= _act_at:
				_save_shot(_after)
				quit()
	return false
