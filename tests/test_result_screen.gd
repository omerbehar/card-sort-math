extends GdUnitTestSuite
## Interaction tests for the win/lose ResultScreen (S1-020).
##
## The screen is instantiated directly, added to the tree (so _ready builds the
## dim), then setup() builds the mode content above it — the same order main.gd
## uses. Buttons are located by text and their `pressed` signal is emitted to
## assert the screen forwards the correct intent signal.

const RESULT_SCRIPT := preload("res://scenes/ui/result_screen.gd")


func _make(mode_value: int) -> ResultScreen:
	var rs := ResultScreen.new()
	add_child(rs)        # _ready adds the dim
	auto_free(rs)
	rs.setup(mode_value) # content built above the dim
	return rs


func _find_button(root: Node, text: String) -> Button:
	for b: Node in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b as Button
	return null


# --- WIN ---------------------------------------------------------------------

func test_win_mode_is_set() -> void:
	var rs := _make(ResultScreen.Mode.WIN)
	assert_int(rs.mode).is_equal(ResultScreen.Mode.WIN)


func test_win_claim_emits_next() -> void:
	var rs := _make(ResultScreen.Mode.WIN)
	var fired: Array[bool] = [false]
	rs.next_pressed.connect(func() -> void: fired[0] = true)
	var claim := _find_button(rs, "TAP TO CLAIM")
	assert_object(claim).is_not_null()
	claim.pressed.emit()
	assert_bool(fired[0]).is_true()


func test_win_reserves_hidden_star_and_reward_placeholders() -> void:
	var rs := _make(ResultScreen.Mode.WIN)
	for slot_name: String in ["StarRatingPlaceholder", "RewardChipsPlaceholder", "TournamentPlaceholder"]:
		var node := rs.find_child(slot_name, true, false)
		assert_object(node).override_failure_message(
			"missing reserved placeholder '%s'" % slot_name).is_not_null()
		assert_bool((node as Control).visible).is_false()


# --- LOSE --------------------------------------------------------------------

func test_lose_mode_is_set() -> void:
	var rs := _make(ResultScreen.Mode.LOSE)
	assert_int(rs.mode).is_equal(ResultScreen.Mode.LOSE)


func test_lose_retry_emits_retry() -> void:
	var rs := _make(ResultScreen.Mode.LOSE)
	var fired: Array[bool] = [false]
	rs.retry_pressed.connect(func() -> void: fired[0] = true)
	var retry := _find_button(rs, "RETRY")
	assert_object(retry).is_not_null()
	retry.pressed.emit()
	assert_bool(fired[0]).is_true()


func test_lose_close_emits_home() -> void:
	var rs := _make(ResultScreen.Mode.LOSE)
	var fired: Array[bool] = [false]
	rs.home_pressed.connect(func() -> void: fired[0] = true)
	var close := _find_button(rs, "✕")
	assert_object(close).is_not_null()
	close.pressed.emit()
	assert_bool(fired[0]).is_true()


func test_lose_reserves_hidden_monetisation_placeholders() -> void:
	var rs := _make(ResultScreen.Mode.LOSE)
	for slot_name: String in ["RevivePlaceholder", "PlayOnPlaceholder", "SpecialOfferPlaceholder"]:
		var node := rs.find_child(slot_name, true, false)
		assert_object(node).override_failure_message(
			"missing reserved placeholder '%s'" % slot_name).is_not_null()
		assert_bool((node as Control).visible).is_false()
