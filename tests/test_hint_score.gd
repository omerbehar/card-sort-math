extends GdUnitTestSuite
## Tests for [HintScore] (Formula 5) and [BoardModel.newly_exposed_count].
##
## All boards are constructed with [BoardModel.new(results, covered_by, target_queue)]
## so every test is pure and node-free. Weights 200/10/5 are the EconomyConfig
## defaults (ROUTES_WEIGHT / OPENS_WEIGHT / RELIEF_WEIGHT).


const R_WEIGHT: int = 200
const O_WEIGHT: int = 10
const L_WEIGHT: int = 5  # relief


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Builds a fully-exposed board (no coverage) from results + target queue.
func _open(results: Array[int], queue: Array[int]) -> BoardModel:
	var covered_by: Dictionary = {}
	for i in results.size():
		covered_by[i] = [] as Array[int]
	return BoardModel.new(results, covered_by, queue)


## Builds a board with a hand-crafted coverage dictionary and given queue.
func _board(results: Array[int], covered_by: Dictionary, queue: Array[int]) -> BoardModel:
	return BoardModel.new(results, covered_by, queue)


# ---------------------------------------------------------------------------
# BoardModel.newly_exposed_count
# ---------------------------------------------------------------------------

func test_newly_exposed_count_returns_zero_for_removed_card() -> void:
	## A card that has already been removed contributes 0.
	# Arrange: card 1 covers card 0; remove card 1 first.
	var covered_by: Dictionary = {
		0: [1] as Array[int],
		1: [] as Array[int],
		2: [] as Array[int],
	}
	var model := _board([7, 9, 5], covered_by, [7, 9, 11, 13])
	# Remove card 1 (so card 0 becomes exposed)
	model.tap_card(1)
	# Act / Assert: card 1 is already removed — newly_exposed_count must be 0.
	assert_int(model.newly_exposed_count(1)).is_equal(0)


func test_newly_exposed_count_returns_zero_for_card_covering_nothing() -> void:
	## A fully-exposed card that is the sole coverer of nobody returns 0.
	# All cards fully exposed; removing any of them cannot expose others.
	var model := _open([7, 9, 5], [7, 9, 11, 13])
	assert_int(model.newly_exposed_count(0)).is_equal(0)
	assert_int(model.newly_exposed_count(1)).is_equal(0)
	assert_int(model.newly_exposed_count(2)).is_equal(0)


func test_newly_exposed_count_single_coverer_exposes_one() -> void:
	## Card 1 is the sole coverer of card 0. Removing card 1 exposes exactly 1.
	# Arrange:
	#   card 0: covered by [1]
	#   card 1: exposed (no coverers)
	#   card 2: exposed (no coverers, not covered by 1)
	var covered_by: Dictionary = {
		0: [1] as Array[int],
		1: [] as Array[int],
		2: [] as Array[int],
	}
	var model := _board([7, 9, 5], covered_by, [7, 9, 11, 13])
	# Act / Assert
	assert_int(model.newly_exposed_count(1)).is_equal(1)  # removing 1 exposes card 0
	assert_int(model.newly_exposed_count(2)).is_equal(0)  # removing 2 exposes nothing


func test_newly_exposed_count_shared_coverer_does_not_expose_if_other_coverer_present() -> void:
	## Card 0 is covered by BOTH card 1 and card 2. Removing card 1 alone does NOT
	## expose card 0 because card 2 still covers it.
	var covered_by: Dictionary = {
		0: [1, 2] as Array[int],
		1: [] as Array[int],
		2: [] as Array[int],
	}
	var model := _board([7, 9, 5], covered_by, [7, 9, 11, 13])
	# Neither card 1 nor card 2 alone exposes card 0.
	assert_int(model.newly_exposed_count(1)).is_equal(0)
	assert_int(model.newly_exposed_count(2)).is_equal(0)


func test_newly_exposed_count_exposes_multiple_cards() -> void:
	## Card 0 covers both card 1 and card 2 (each exclusively). Removing card 0
	## exposes exactly 2 cards.
	# Arrange:
	#   card 0: exposed
	#   card 1: covered by [0] only
	#   card 2: covered by [0] only
	#   card 3: covered by [0] only
	var covered_by: Dictionary = {
		0: [] as Array[int],
		1: [0] as Array[int],
		2: [0] as Array[int],
		3: [0] as Array[int],
	}
	var model := _board([7, 9, 5, 11], covered_by, [7, 9, 11, 13])
	assert_int(model.newly_exposed_count(0)).is_equal(3)


func test_newly_exposed_count_after_coverer_removed_exposes_previously_blocked() -> void:
	## Card 0 is covered by both card 1 and card 2. After card 2 is removed,
	## card 1 becomes card 0's sole coverer → newly_exposed_count(1) == 1.
	var covered_by: Dictionary = {
		0: [1, 2] as Array[int],
		1: [] as Array[int],
		2: [] as Array[int],
		3: [] as Array[int],
	}
	# Use a queue long enough to keep stacks active.
	var model := _board([7, 9, 5, 11], covered_by, [9, 5, 11, 7, 99])
	# Remove card 2 (it goes to a stack or discard; its removal is what matters).
	model.tap_card(2)
	# Now card 1 is the only remaining coverer of card 0.
	assert_int(model.newly_exposed_count(1)).is_equal(1)


# ---------------------------------------------------------------------------
# HintScore.score — component contributions (AC-H05 and weight arithmetic)
# ---------------------------------------------------------------------------

func test_hint_score_routes_directly_contributes_exactly_routes_weight() -> void:
	## AC-H05: a card whose result matches an open stack target contributes
	## exactly ROUTES_WEIGHT (200) to the routes_directly component.
	# Board: stacks targeting [7, 9, 11, 13]; card 0 has result 7 (routes directly).
	# No coverage → card 0 is exposed. No discard matches.
	var model := _open([7], [7, 9, 11, 13])
	var s: int = HintScore.score(model, 0, R_WEIGHT, O_WEIGHT, L_WEIGHT)
	# routes=1*200 + opens=0*10 + relief=0*5 = 200
	assert_int(s).is_equal(200)


func test_hint_score_opens_new_cards_contributes_k_times_opens_weight() -> void:
	## A card that would expose k=3 others (sole coverer of each) contributes 3*OPENS_WEIGHT.
	# Card 0 covers cards 1, 2, 3 (solely). Card 0 does not route directly (result=99,
	# stacks target 7/9/11/13). No discard matches.
	var covered_by: Dictionary = {
		0: [] as Array[int],
		1: [0] as Array[int],
		2: [0] as Array[int],
		3: [0] as Array[int],
	}
	var model := _board([99, 7, 9, 11], covered_by, [7, 9, 11, 13])
	var s: int = HintScore.score(model, 0, R_WEIGHT, O_WEIGHT, L_WEIGHT)
	# routes=0 + opens=3*10 + relief=0 = 30
	assert_int(s).is_equal(30)


func test_hint_score_discard_relief_contributes_per_matching_discard_card() -> void:
	## Cards in discard whose result matches the scored card's result contribute
	## RELIEF_WEIGHT each.
	# Board: 4 stacks (7,9,11,13). Card 0 has result 5 (no routing). Cards 1,2 also
	# result 5 and will be discarded to set up the relief scenario.
	# We need enough cards to fill the stacks without routing result-5 cards.
	var results: Array[int] = [5, 5, 5, 7, 9, 11, 13]
	var model := _open(results, [7, 9, 11, 13])
	# Discard two result-5 cards so they sit in discard.
	model.tap_card(1)   # result 5 → discard slot 0
	model.tap_card(2)   # result 5 → discard slot 1
	# Now score card 0 (result 5, not discarded yet, exposed).
	var s: int = HintScore.score(model, 0, R_WEIGHT, O_WEIGHT, L_WEIGHT)
	# routes=0 + opens=0 + relief=2*5 = 10
	assert_int(s).is_equal(10)


# ---------------------------------------------------------------------------
# HintScore.best_card — selection and tie-break (AC-H01, AC-H02)
# ---------------------------------------------------------------------------

func test_best_card_formula5_worked_example() -> void:
	## Reproduces the Formula 5 worked example from the GDD:
	##   Card 2 (result 7): routes_directly=1(200) opens=2(20) relief=0   → score 220  ← winner
	##   Card 5 (result 9): routes_directly=0      opens=3(30) relief=1(5) → score 35
	##   Card 8 (result 7): routes_directly=1(200) opens=0     relief=0    → score 200
	##
	## Layout (queue [7, 11, 13, 17] seeds stacks 7/11/13/17 — deliberately NO "9"
	## stack so the result-9 card 7 goes to discard and supplies card 5's relief=1):
	##
	## card_id | result | covered_by | role
	##   0     |  99    |  [2]       | hidden, solely by card 2
	##   1     |  99    |  [2]       | hidden, solely by card 2   → card 2 opens=2
	##   2     |   7    |  []        | exposed; routes to stack 7 → score 220 (winner)
	##   3     |  99    |  [5]       | hidden, solely by card 5
	##   4     |  99    |  [5]       | hidden, solely by card 5
	##   6     |  99    |  [5]       | hidden, solely by card 5   → card 5 opens=3
	##   5     |   9    |  []        | exposed; no "9" stack (routes=0); relief=1 → score 35
	##   7     |   9    |  []        | discarded below → relief card for result 9
	##   8     |   7    |  []        | exposed; routes to stack 7 → score 200
	var covered_by: Dictionary = {
		0: [2] as Array[int],
		1: [2] as Array[int],
		2: [] as Array[int],
		3: [5] as Array[int],
		4: [5] as Array[int],
		5: [] as Array[int],
		6: [5] as Array[int],
		7: [] as Array[int],
		8: [] as Array[int],
	}
	var results: Array[int] = [99, 99, 7, 99, 99, 9, 99, 9, 7]
	var model := _board(results, covered_by, [7, 11, 13, 17])
	model.tap_card(7)   # result 9, no stack targets 9 → lands in discard slot 0.
	assert_int(model.discard_card(0)).is_equal(7)  # precondition: card 7 supplies relief

	# Verify individual scores.
	assert_int(HintScore.score(model, 2, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(220)
	assert_int(HintScore.score(model, 5, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(35)
	assert_int(HintScore.score(model, 8, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(200)

	# best_card must select card 2 (score 220).
	assert_int(HintScore.best_card(model, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(2)


func test_best_card_tie_break_returns_lowest_card_id() -> void:
	## AC-H02: when two exposed cards have identical hint_scores, the lower card_id wins.
	# Both card 0 and card 1 have result 7 and route directly (score = 200 each).
	# No coverage, no discard cards. card_id 0 < 1 → card 0 wins.
	var model := _open([7, 7], [7, 9, 11, 13])
	assert_int(HintScore.best_card(model, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(0)


func test_best_card_tie_break_lower_id_wins_reversed_order() -> void:
	## AC-H02 robustness: same as above but card 3 and card 1 tie — card 1 wins.
	# Cards 0,2: result 5 (no routing). Cards 1,3: result 7 (routes). Scores equal.
	var model := _open([5, 7, 5, 7], [7, 9, 11, 13])
	assert_int(HintScore.best_card(model, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(1)


func test_best_card_returns_minus_one_when_no_exposed_cards() -> void:
	## Returns -1 when there are zero exposed cards.
	# Card 0 covers card 1; card 1 covers card 0 — neither is exposed.
	# (A mutual cover is artificial but sufficient to produce 0 exposed cards for this test.)
	var covered_by: Dictionary = {
		0: [1] as Array[int],
		1: [0] as Array[int],
	}
	var model := _board([7, 9], covered_by, [7, 9, 11, 13])
	assert_int(HintScore.best_card(model, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(-1)


func test_best_card_selects_highest_score_among_candidates() -> void:
	## Among three candidates with distinct scores, best_card selects the maximum.
	# Three exposed cards (queue seeds stack targets 7/9/11/13):
	#   card 0: result 7, routes directly, opens 1 → 200 + 10 = 210
	#   card 1: result 5, NOT a stack target → no routing, opens 0, 0 relief → 0
	#   card 2: result 7, routes directly, opens 0 → 200
	# card 3 is covered by card 0 solely (opens=1 for card 0).
	var covered_by: Dictionary = {
		0: [] as Array[int],
		1: [] as Array[int],
		2: [] as Array[int],
		3: [0] as Array[int],
	}
	var results: Array[int] = [7, 5, 7, 99]
	var model := _board(results, covered_by, [7, 9, 11, 13])
	assert_int(HintScore.score(model, 0, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(210)
	assert_int(HintScore.score(model, 1, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(0)
	assert_int(HintScore.score(model, 2, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(200)
	assert_int(HintScore.best_card(model, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(0)


func test_best_card_single_exposed_card_returns_it() -> void:
	## When only one card is exposed, it is always selected regardless of score.
	# Card 0 covered by card 1; card 1 is exposed (result 99, no routing, 0 opens).
	var covered_by: Dictionary = {
		0: [1] as Array[int],
		1: [] as Array[int],
	}
	var model := _board([7, 99], covered_by, [7, 9, 11, 13])
	assert_int(HintScore.best_card(model, R_WEIGHT, O_WEIGHT, L_WEIGHT)).is_equal(1)
