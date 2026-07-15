extends SceneTree
## Dev harness: captures the S5-004 rewarded-ad flow as PNGs:
##   1. rewarded-offer.png — the win result screen with the opt-in "Watch for +N coins" offer
##   2. rewarded-prompt.png — the RewardedPrompt open over it
##
## Run with a real display (headless renders nothing):
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility -s res://tools/screenshot_rewarded.gd

const OFFER_PATH := "user://rewarded-offer.png"
const PROMPT_PATH := "user://rewarded-prompt.png"


func _initialize() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait_frames(8)

	# Adult under the daily cap → a rewarded ad can earn, so the offer is revealed.
	root.get_node("SaveService").data.age_band = SaveData.AgeBand.ADULT

	# --- Win result screen with the bonus offer. ---
	main._show_result(ResultScreen.Mode.WIN)
	await _wait_frames(10)
	_capture(OFFER_PATH)

	# --- Open the rewarded prompt over it. ---
	var offer: Button = main._result_screen.find_child("RewardedOffer", true, false)
	if offer != null:
		offer.pressed.emit()
	await _wait_frames(10)
	_capture(PROMPT_PATH)

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
