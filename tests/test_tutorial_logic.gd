extends GdUnitTestSuite
## Unit tests for [TutorialLogic] — covers AC1–AC5b from
## [code]design/gdd/first-time-tutorial.md[/code] §8.


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Build a single GameEvent of the given Kind.
func _event(kind: GameEvent.Kind) -> GameEvent:
	match kind:
		GameEvent.Kind.ROUTE:
			return GameEvent.route(0, 0)
		GameEvent.Kind.DISCARD:
			return GameEvent.discard(0, 0)
		GameEvent.Kind.WIN:
			return GameEvent.win()
		GameEvent.Kind.LOSE:
			return GameEvent.lose()
		GameEvent.Kind.STACK_CLEARED:
			return GameEvent.stack_cleared(0, -1)
		GameEvent.Kind.PULL:
			return GameEvent.pull(0, 0, 0)
		_:
			return GameEvent.new()


# ---------------------------------------------------------------------------
# AC1 — should_show truth table
# ---------------------------------------------------------------------------

func test_should_show_fresh_save_level_1_returns_true() -> void:
	# AC1: should_show(false, 1) == true
	assert_bool(TutorialLogic.should_show(false, 1)).is_true()


func test_should_show_already_seen_returns_false() -> void:
	# AC1: should_show(true, 1) == false
	assert_bool(TutorialLogic.should_show(true, 1)).is_false()


func test_should_show_level_0_returns_false() -> void:
	# AC1: should_show(false, 0) == false  (level 0 is not TUTORIAL_LEVEL)
	assert_bool(TutorialLogic.should_show(false, 0)).is_false()


func test_should_show_level_2_returns_false() -> void:
	# AC1: should_show(false, 2) == false  (level 2 is not TUTORIAL_LEVEL)
	assert_bool(TutorialLogic.should_show(false, 2)).is_false()


# ---------------------------------------------------------------------------
# AC2 — pick_target: productive path
# ---------------------------------------------------------------------------

func test_pick_target_productive_returns_lowest_productive_id() -> void:
	# AC2: pick_target([0,2,5], {0:7,2:4,5:7}, [7,9]) == 0
	# productive = {0,5} (results 7 and 7 are in open_targets [7,9])
	# min(productive) = 0; returned id is in exposed
	var exposed: Array[int] = [0, 2, 5]
	var results: Dictionary = {0: 7, 2: 4, 5: 7}
	var open_targets: Array[int] = [7, 9]

	var result: int = TutorialLogic.pick_target(exposed, results, open_targets)

	assert_int(result).is_equal(0)
	assert_bool(exposed.has(result)).is_true()


# ---------------------------------------------------------------------------
# AC3 — pick_target: fallback and empty cases
# ---------------------------------------------------------------------------

func test_pick_target_no_productive_returns_lowest_exposed() -> void:
	# AC3: pick_target([2,5], {2:4,5:8}, [7,9]) == 2
	# no card's result is in [7,9] → fallback to min(exposed) = 2
	var exposed: Array[int] = [2, 5]
	var results: Dictionary = {2: 4, 5: 8}
	var open_targets: Array[int] = [7, 9]

	var result: int = TutorialLogic.pick_target(exposed, results, open_targets)

	assert_int(result).is_equal(2)
	assert_bool(exposed.has(result)).is_true()


func test_pick_target_empty_exposed_returns_minus_one() -> void:
	# AC3: pick_target([], {}, [7]) == -1  (E=∅ — do not show coach)
	var exposed: Array[int] = []
	var results: Dictionary = {}
	var open_targets: Array[int] = [7]

	assert_int(TutorialLogic.pick_target(exposed, results, open_targets)).is_equal(-1)


# ---------------------------------------------------------------------------
# AC4 — is_route variants
# ---------------------------------------------------------------------------

func test_is_route_empty_list_returns_false() -> void:
	# AC4: is_route([]) == false
	var events: Array[GameEvent] = []
	assert_bool(TutorialLogic.is_route(events)).is_false()


func test_is_route_discard_only_returns_false() -> void:
	# AC4: is_route([discard]) == false
	var events: Array[GameEvent] = [_event(GameEvent.Kind.DISCARD)]
	assert_bool(TutorialLogic.is_route(events)).is_false()


func test_is_route_route_event_returns_true() -> void:
	# AC4: is_route([route]) == true
	var events: Array[GameEvent] = [_event(GameEvent.Kind.ROUTE)]
	assert_bool(TutorialLogic.is_route(events)).is_true()


func test_is_route_discard_then_route_returns_true() -> void:
	# AC4: is_route([discard,route]) == true
	var events: Array[GameEvent] = [
		_event(GameEvent.Kind.DISCARD),
		_event(GameEvent.Kind.ROUTE),
	]
	assert_bool(TutorialLogic.is_route(events)).is_true()


func test_is_route_route_and_win_returns_true() -> void:
	# AC4: is_route([route,win]) == true
	var events: Array[GameEvent] = [
		_event(GameEvent.Kind.ROUTE),
		_event(GameEvent.Kind.WIN),
	]
	assert_bool(TutorialLogic.is_route(events)).is_true()


# ---------------------------------------------------------------------------
# AC5b — is_lose variants
# ---------------------------------------------------------------------------

func test_is_lose_empty_list_returns_false() -> void:
	# AC5b: is_lose([]) == false
	var events: Array[GameEvent] = []
	assert_bool(TutorialLogic.is_lose(events)).is_false()


func test_is_lose_route_only_returns_false() -> void:
	# AC5b: is_lose([route]) == false
	var events: Array[GameEvent] = [_event(GameEvent.Kind.ROUTE)]
	assert_bool(TutorialLogic.is_lose(events)).is_false()


func test_is_lose_lose_event_returns_true() -> void:
	# AC5b: is_lose([lose]) == true
	var events: Array[GameEvent] = [_event(GameEvent.Kind.LOSE)]
	assert_bool(TutorialLogic.is_lose(events)).is_true()


func test_is_lose_route_and_lose_returns_true() -> void:
	# AC5b: is_lose([route,lose]) == true
	# The ROUTE+LOSE case (routing the last card that also triggers lose) must
	# be detectable — though should_complete resolves it as routed:true because
	# is_route is checked first.
	var events: Array[GameEvent] = [
		_event(GameEvent.Kind.ROUTE),
		_event(GameEvent.Kind.LOSE),
	]
	assert_bool(TutorialLogic.is_lose(events)).is_true()


# ---------------------------------------------------------------------------
# AC5 — should_complete: return type, keys, and all outcome branches
# ---------------------------------------------------------------------------

func test_should_complete_returns_dictionary_with_required_keys() -> void:
	# AC5: result must be a Dictionary with keys "complete" and "routed" (both bool)
	var events: Array[GameEvent] = [_event(GameEvent.Kind.ROUTE)]
	var result: Dictionary = TutorialLogic.should_complete(events, 0, 3)

	assert_bool(result.has("complete")).is_true()
	assert_bool(result.has("routed")).is_true()
	assert_bool(result["complete"] is bool).is_true()
	assert_bool(result["routed"] is bool).is_true()


func test_should_complete_route_event_completes_with_routed_true() -> void:
	# AC5: should_complete([route], 0, 3) → {complete:true, routed:true}
	var events: Array[GameEvent] = [_event(GameEvent.Kind.ROUTE)]
	var result: Dictionary = TutorialLogic.should_complete(events, 0, 3)

	assert_bool(result["complete"]).is_true()
	assert_bool(result["routed"]).is_true()


func test_should_complete_discard_below_valve_keeps_coaching() -> void:
	# AC5: should_complete([discard], 0, 3) → {complete:false, routed:false}
	# n_nonroute=0, (0+1)=1 < 3 → safety valve not yet reached
	var events: Array[GameEvent] = [_event(GameEvent.Kind.DISCARD)]
	var result: Dictionary = TutorialLogic.should_complete(events, 0, 3)

	assert_bool(result["complete"]).is_false()
	assert_bool(result["routed"]).is_false()


func test_should_complete_discard_at_valve_threshold_completes() -> void:
	# AC5: should_complete([discard], 2, 3) → {complete:true, routed:false}
	# n_nonroute passed as pre-tap value 2; (2+1)=3 >= 3 → safety valve fires
	var events: Array[GameEvent] = [_event(GameEvent.Kind.DISCARD)]
	var result: Dictionary = TutorialLogic.should_complete(events, 2, 3)

	assert_bool(result["complete"]).is_true()
	assert_bool(result["routed"]).is_false()


func test_should_complete_lose_event_completes_without_route() -> void:
	# AC5: should_complete([lose], 0, 3) → {complete:true, routed:false}
	var events: Array[GameEvent] = [_event(GameEvent.Kind.LOSE)]
	var result: Dictionary = TutorialLogic.should_complete(events, 0, 3)

	assert_bool(result["complete"]).is_true()
	assert_bool(result["routed"]).is_false()


func test_should_complete_route_and_win_completes_with_routed_true() -> void:
	# AC5: should_complete([route,win], 0, 3) → {complete:true, routed:true}
	# Priority: is_route checked before is_lose — ROUTE+WIN resolves as success.
	var events: Array[GameEvent] = [
		_event(GameEvent.Kind.ROUTE),
		_event(GameEvent.Kind.WIN),
	]
	var result: Dictionary = TutorialLogic.should_complete(events, 0, 3)

	assert_bool(result["complete"]).is_true()
	assert_bool(result["routed"]).is_true()


func test_should_complete_route_and_lose_resolves_as_routed_true() -> void:
	# §4 priority note: [ROUTE, LOSE] → {complete:true, routed:true}
	# A successful route is the tutorial's positive outcome even if the board
	# also loses — is_route is checked before is_lose.
	var events: Array[GameEvent] = [
		_event(GameEvent.Kind.ROUTE),
		_event(GameEvent.Kind.LOSE),
	]
	var result: Dictionary = TutorialLogic.should_complete(events, 0, 3)

	assert_bool(result["complete"]).is_true()
	assert_bool(result["routed"]).is_true()
