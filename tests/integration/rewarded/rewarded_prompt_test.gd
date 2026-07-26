extends GdUnitTestSuite
## Integration tests — S5-004 rewarded-ad prompt (design/ux/monetization-ui.md §3.3, AC-5).
##
## Two integration layers:
##  - REAL scene (scenes/main/main.tscn + autoloads): a win reveals the opt-in bonus
##    offer only when AdService.is_rewarded_available(); tapping it opens the prompt.
##  - Injected fakes: the RewardedPrompt view driven against a controllable fake AdService
##    / Analytics, proving confirm credits exactly once, abandon credits nothing, and the
##    analytics event fires — deterministically.

const MAIN := "res://scenes/main/main.tscn"


# --- Controllable fakes -----------------------------------------------------

class FakeAd extends Node:
	signal rewarded_earned(coins: int)
	var available: bool = true
	var credit: int = 60
	var watch_calls: int = 0
	func is_rewarded_available() -> bool:
		return available
	func rewarded_reward_amount() -> int:
		return 60
	func show_rewarded() -> int:
		watch_calls += 1
		if credit > 0:
			rewarded_earned.emit(credit)
		return credit


class FakeAnalytics extends RefCounted:
	var rewards: Array = []
	func track_ad_reward(coins: int) -> bool:
		rewards.append(coins)
		return true


func _prompt_with(ad: Object, analytics: Object) -> RewardedPrompt:
	var prompt: RewardedPrompt = auto_free(RewardedPrompt.new())
	add_child(prompt)
	prompt.configure(ad, analytics, "")
	prompt.setup()
	return prompt


# ---------------------------------------------------------------------------
# Layer 1 — real scene tree (offer reveal gating + open)
# ---------------------------------------------------------------------------

func _boot() -> Variant:
	var save := get_tree().root.get_node_or_null("SaveService")
	if save != null and save.data != null:
		save.data.tutorial_seen = true
	var runner := scene_runner(MAIN)
	await runner.simulate_frames(5)
	return runner


func test_win_reveals_rewarded_offer_when_available_and_opens_prompt() -> void:
	# Arrange: an adult under the daily cap → rewarded is available.
	var runner = await _boot()
	var main = runner.scene()
	get_tree().root.get_node("SaveService").data.age_band = SaveData.AgeBand.ADULT

	# Act: show the win result screen.
	main._show_result(ResultScreen.Mode.WIN)
	await runner.simulate_frames(3)

	# Assert: the offer button is revealed, and tapping it opens the prompt.
	var offer: Button = main._result_screen.find_child("RewardedOffer", true, false)
	assert_object(offer).is_not_null()
	offer.pressed.emit()
	await runner.simulate_frames(2)
	assert_object(main._rewarded_prompt).is_not_null()


func test_win_hides_offer_when_rewarded_unavailable() -> void:
	# Arrange: a CHILD age band → ComplianceService restricts → rewarded unavailable.
	var runner = await _boot()
	var main = runner.scene()
	get_tree().root.get_node("SaveService").data.age_band = SaveData.AgeBand.CHILD

	# Act
	main._show_result(ResultScreen.Mode.WIN)
	await runner.simulate_frames(3)

	# Assert: no offer button, so no dead rewarded button (AC-5).
	assert_object(main._result_screen.find_child("RewardedOffer", true, false)).is_null()


# ---------------------------------------------------------------------------
# Layer 2 — injected fakes (confirm credits once / abandon credits nothing)
# ---------------------------------------------------------------------------

func test_watch_credits_once_and_tracks_reward() -> void:
	# Arrange
	var ad = auto_free(FakeAd.new())
	ad.credit = 60
	var analytics := FakeAnalytics.new()
	var prompt := _prompt_with(ad, analytics)
	monitor_signals(prompt)

	# Act: confirm the watch.
	prompt._watch_btn.pressed.emit()

	# Assert: exactly one ad shown, reward credited + tracked once (AC-5).
	assert_int(ad.watch_calls).is_equal(1)
	assert_array(analytics.rewards).is_equal([60])
	await assert_signal(prompt).is_emitted("reward_earned", [60])


func test_double_confirm_only_watches_once() -> void:
	# Arrange
	var ad = auto_free(FakeAd.new())
	ad.credit = 60
	var prompt := _prompt_with(ad, FakeAnalytics.new())

	# Act: a fast double-tap must not spend two views.
	prompt._watch_btn.pressed.emit()
	prompt._watch_btn.pressed.emit()

	# Assert (AC-5: credit exactly once)
	assert_int(ad.watch_calls).is_equal(1)


func test_abandoned_view_credits_nothing() -> void:
	# Arrange: the ad was watched but no reward (dismissed / no-fill / capped → 0).
	var ad = auto_free(FakeAd.new())
	ad.credit = 0
	var analytics := FakeAnalytics.new()
	var prompt := _prompt_with(ad, analytics)

	# Act
	prompt._watch_btn.pressed.emit()

	# Assert: no reward tracked, no reward_earned, soft no-reward message (AC-5).
	assert_array(analytics.rewards).is_empty()
	assert_str(prompt._reward_label.text).is_equal("No reward this time")


func test_declining_never_shows_an_ad() -> void:
	# Arrange
	var ad = auto_free(FakeAd.new())
	var prompt := _prompt_with(ad, FakeAnalytics.new())

	# Act: decline the offer.
	prompt._decline_btn.pressed.emit()

	# Assert: opt-in only — declining never presents an ad (AC-5).
	assert_int(ad.watch_calls).is_equal(0)
