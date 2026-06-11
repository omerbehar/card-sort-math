class_name Solvability
extends RefCounted
## Pure, node-free check of the solvability invariant (ADR-0003).
##
## A level is solvable when every card's result appears in the target queue and
## the number of cards with a given result equals [constant STACK_CAPACITY] x its
## occurrences in the queue. Kept in [code]core/[/code] so the generator can
## self-check without depending on the [LevelData] autoload; [LevelData.is_solvable]
## is the same rule and may delegate here in a later story (S2-004).

## Cards required to clear one stack — the multiplier in the invariant (ADR-0003).
const STACK_CAPACITY: int = 3


## Returns [code]true[/code] when [param config] satisfies the solvability
## invariant: identical result sets in queue and pool, and
## [code]#cards(R) == STACK_CAPACITY x queue_count(R)[/code] for every result R.
static func is_solvable(config: LevelConfig) -> bool:
	var queue_counts: Dictionary = {}
	for target: int in config.target_queue:
		queue_counts[target] = int(queue_counts.get(target, 0)) + 1

	var card_counts: Dictionary = {}
	for card: CardData in config.card_pool:
		card_counts[card.result] = int(card_counts.get(card.result, 0)) + 1

	if card_counts.size() != queue_counts.size():
		return false
	for result: int in card_counts:
		if not queue_counts.has(result):
			return false
		if int(card_counts[result]) != STACK_CAPACITY * int(queue_counts[result]):
			return false
	return true
