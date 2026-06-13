extends SceneTree
## Dev-only harness: boots the real Main board and captures (a) the booster tray
## showing owned counts, then (b) the out-of-stock buff top-up popup after draining
## one buff to zero and tapping it.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 390x844 \
##     -s res://tools/screenshot_buff_popup.gd -- <tray.png> <popup.png>
## Not shipped; pure tooling (tools/ scope).

var _main: Node = null
var _frames: int = 0
var _phase: int = 0
var _tray: String = "/tmp/buff_tray.png"
var _popup: String = "/tmp/buff_popup.png"
const _RESHUFFLE := 1   # EconomyEnums.BoosterType.RESHUFFLE


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_tray = args[0]
	if args.size() >= 2:
		_popup = args[1]
	var save := root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)


func _shot(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("SHOT_SAVED ", path)


func _process(_delta: float) -> bool:
	_frames += 1
	match _phase:
		0:  # settle, fund coins so the PAY option is enabled, capture the tray (with counts)
			if _frames >= 20:
				var wallet := root.get_node_or_null("WalletService")
				if wallet != null:
					wallet.earn(EconomyEnums.Currency.COINS, 1000, EconomyEnums.EarnSource.LEVEL_WIN)
				_shot(_tray)
				_phase = 1
		1:  # drain Reshuffle to zero, then tap it → out-of-stock popup
			var wallet := root.get_node_or_null("WalletService")
			if wallet != null:
				while wallet.booster_count(_RESHUFFLE) > 0:
					wallet.consume_booster(_RESHUFFLE)
			_main._on_booster_pressed(_RESHUFFLE)
			_phase = 2
			_frames = 0
		2:  # let the open animation settle, capture the popup
			if _frames >= 45:
				_shot(_popup)
				quit()
	return false
