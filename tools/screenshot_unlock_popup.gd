extends SceneTree
## Dev-only harness: boots the real Main board and triggers the locked-deck
## UnlockPopup, saving a screenshot of the live scene.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 390x844 \
##     -s res://tools/screenshot_unlock_popup.gd -- <shot.png> [funded|broke]
## "funded" funds the wallet so the PAY button is enabled; "broke" leaves it
## disabled (greyed). Not shipped; pure tooling (tools/ scope).

var _main: Node = null
var _frames: int = 0
var _phase: int = 0
var _shot: String = "/tmp/unlock_popup.png"
var _fund: bool = true


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_shot = args[0]
	if args.size() >= 2:
		_fund = args[1] != "broke"
	var save := root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)


func _first_locked_stack() -> int:
	var model = _main._model
	for s in range(model.STACK_COUNT):
		if model.is_stack_locked(s):
			return s
	return -1


func _process(_delta: float) -> bool:
	_frames += 1
	match _phase:
		0:  # settle, optionally fund the wallet, then open the prompt
			if _frames >= 20:
				var wallet := root.get_node_or_null("WalletService")
				if wallet != null and _fund:
					wallet.earn(EconomyEnums.Currency.COINS, 1000, EconomyEnums.EarnSource.LEVEL_WIN)
				elif wallet != null:
					# Empty the wallet so the PAY button renders disabled (broke case).
					wallet.spend(EconomyEnums.Currency.COINS, wallet.balance(EconomyEnums.Currency.COINS))
				_main._on_unlock_requested(_first_locked_stack())
				_phase = 1
		1:  # wait for the open animation to settle, capture
			if _frames >= 45:
				var img: Image = root.get_texture().get_image()
				img.save_png(_shot)
				print("SHOT_SAVED ", _shot)
				quit()
	return false
