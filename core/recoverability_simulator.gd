class_name RecoverabilitySimulator
extends RefCounted
## Pure "fair to play" backstop for the generator (GDD Core Rule 10 / AC-32).
##
## Replays a level with a greedy player that makes exactly one forced mistake,
## reusing [BoardModel] (no scene tree, events consumed as data). A board the
## greedy+1-mistake player still WINS — keeping at least [code]min_margin[/code]
## free discard slots throughout — is "recoverable". This is a *necessary, not
## sufficient* fairness check; the real gate is human playtest (AC-27).


## Runs the simulation on [param config]. The single mistake happens on turn
## [param mistake_turn] (default: half the queue length): the player discards an
## exposed card instead of stacking it. Returns
## [code]{ won: bool, headroom: int }[/code] where [code]headroom[/code] is the
## minimum number of free discard slots observed (5 = never used discard).
static func run(config: LevelConfig, mistake_turn: int = -1) -> Dictionary:
	var board := BoardModel.from_config(config)
	var turn_of_mistake: int = mistake_turn
	if turn_of_mistake < 0:
		turn_of_mistake = config.target_queue.size() / 2

	var min_headroom: int = BoardModel.DISCARD_SLOTS
	var mistake_done: bool = false
	var turn: int = 0
	var safety_cap: int = config.card_pool.size() * 3 + 8

	while not board.is_game_over() and turn < safety_cap:
		var exposed := board.exposed_cards()
		if exposed.is_empty():
			break

		var card_id: int = -1
		# The one mistake: at/after the target turn, the first time a discardable
		# card is available, take it. Deferring (rather than firing blindly at the
		# target turn) ensures the mistake actually happens — otherwise a turn
		# where every exposed card routes would silently consume it (no-op),
		# weakening the check.
		if not mistake_done and turn >= turn_of_mistake:
			card_id = _lowest_discarding_card(board, exposed)
			if card_id != -1:
				mistake_done = true
		if card_id == -1:
			card_id = _greedy_card(board, exposed)

		board.tap_card(card_id)
		min_headroom = mini(min_headroom, BoardModel.DISCARD_SLOTS - _discard_occupancy(board))
		turn += 1

	return {won = board.is_won(), headroom = min_headroom}


## Whether [param config] is recoverable with at least [param min_margin] free
## discard slots under the default one-mistake simulation.
static func is_recoverable(config: LevelConfig, min_margin: int) -> bool:
	var outcome := run(config)
	return bool(outcome.won) and int(outcome.headroom) >= min_margin


# Lowest-result exposed card that would route to an open stack (greedy: stack
# when you can); falls back to the lowest-result exposed card (a forced discard).
static func _greedy_card(board: BoardModel, exposed: Array[int]) -> int:
	var best_route: int = -1
	var best_route_result: int = 0
	var best_any: int = -1
	var best_any_result: int = 0
	for card_id: int in exposed:
		var result: int = board.result_of(card_id)
		if best_any == -1 or result < best_any_result:
			best_any = card_id
			best_any_result = result
		if _has_open_stack(board, result):
			if best_route == -1 or result < best_route_result:
				best_route = card_id
				best_route_result = result
	return best_route if best_route != -1 else best_any


# The forced mistake: lowest-result exposed card that has NO open stack (so it
# is sent to discard). Returns -1 if every exposed card would route.
static func _lowest_discarding_card(board: BoardModel, exposed: Array[int]) -> int:
	var best: int = -1
	var best_result: int = 0
	for card_id: int in exposed:
		var result: int = board.result_of(card_id)
		if _has_open_stack(board, result):
			continue
		if best == -1 or result < best_result:
			best = card_id
			best_result = result
	return best


static func _has_open_stack(board: BoardModel, result: int) -> bool:
	for i in BoardModel.STACK_COUNT:
		if board.stack_target(i) == result and board.stack_count(i) < BoardModel.STACK_CAPACITY:
			return true
	return false


static func _discard_occupancy(board: BoardModel) -> int:
	var used: int = 0
	for slot in BoardModel.DISCARD_SLOTS:
		if board.discard_card(slot) != -1:
			used += 1
	return used
