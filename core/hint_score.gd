class_name HintScore
extends RefCounted
## Pure, static scoring functions for the Hint booster (Formula 5).
##
## Scores each exposed card by three weighted components and returns the
## card_id of the best candidate. Weights are supplied by the caller (from
## [EconomyConfig]) so this class holds no tuning values.
##
## [b]No-arithmetic-solving pillar (Core Rule 12):[/b] this class NEVER
## surfaces a card's arithmetic result to the player. It returns a routing
## target (card_id) only. The result value is used internally to check
## whether a stack target matches — the same information a player can infer
## by looking at the stack row — but it is never forwarded or emitted.
##
## Source: design/gdd/deck-economy.md §Formula 5, §Core Rule 8, §AC-H01..H05.


## Computes the hint score for a single [param card_id] on [param board].
## [param routes_weight], [param opens_weight], [param relief_weight] come
## from [EconomyConfig] (never hardcoded here).
##
## Formula 5:
##   hint_score = routes_directly(r) * routes_weight
##              + opens_new_cards(card_id) * opens_weight
##              + discard_relief(r) * relief_weight
## where r = board.result_of(card_id).
static func score(
		board: BoardModel,
		card_id: int,
		routes_weight: int,
		opens_weight: int,
		relief_weight: int,
) -> int:
	var r: int = board.result_of(card_id)
	var routes: int = 1 if _routes_directly(board, r) else 0
	var opens: int = board.newly_exposed_count(card_id)
	var relief: int = _discard_relief(board, r)
	return routes * routes_weight + opens * opens_weight + relief * relief_weight


## Returns the [param board]-exposed card with the highest [method score].
## Tie-break: lowest card_id (deterministic — AC-H02). Returns [code]-1[/code]
## if no card is currently exposed (AC-H03 precondition handled upstream, but
## -1 is the defined sentinel for callers that check here).
##
## [b]No arithmetic reveal:[/b] returns a card_id routing target only.
static func best_card(
		board: BoardModel,
		routes_weight: int,
		opens_weight: int,
		relief_weight: int,
) -> int:
	var exposed: Array[int] = board.exposed_cards()
	if exposed.is_empty():
		return -1
	var best_id: int = -1
	var best_score: int = -1
	for card_id: int in exposed:
		var s: int = score(board, card_id, routes_weight, opens_weight, relief_weight)
		# Tie-break: lower card_id wins (exposed_cards() returns ascending order,
		# but we make the comparison explicit for robustness — AC-H02).
		if s > best_score or (s == best_score and (best_id == -1 or card_id < best_id)):
			best_score = s
			best_id = card_id
	return best_id


# Returns true if at least one stack currently has target == r AND
# count < STACK_CAPACITY (i.e. the card can route directly right now).
static func _routes_directly(board: BoardModel, r: int) -> bool:
	for i: int in BoardModel.STACK_COUNT:
		if board.stack_target(i) == r and board.stack_count(i) < BoardModel.STACK_CAPACITY:
			return true
	return false


# Returns the count of cards sitting in a discard slot whose result == r.
# These would be pulled free once this result's stack is cleared — discard
# relief reflects future board flexibility, not immediate routing.
static func _discard_relief(board: BoardModel, r: int) -> int:
	var count: int = 0
	for slot: int in BoardModel.DISCARD_SLOTS:
		var cid: int = board.discard_card(slot)
		if cid != -1 and board.result_of(cid) == r:
			count += 1
	return count
