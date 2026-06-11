class_name LevelGenerator
extends RefCounted
## Procedurally builds a solvable [LevelConfig] by construction (GDD
## level-generator, ADR-0007). Pure and node-free: a single seeded
## [RandomNumberGenerator] is the only randomness, consumed in a fixed step
## order, so the same [GeneratorParams] always yields a field-identical level.
##
## Solvability (ADR-0003) is structural, never sampled: the target queue is built
## first, then exactly [code]3 x queue_count(R)[/code] cards are dealt for each
## result R. Usage:
## [codeblock]
## var params := GeneratorParams.create(0, 4, 3, 12, 6, 42)
## var result := LevelGenerator.generate(params)
## if not result.is_error():
##     BoardModel.from_config(result.config)
## [/codeblock]
##
## Out of scope for this story (S2-003a): the difficulty schedule (S2-003b), the
## Rule 10 recoverability re-seed (S2-003b), and [LevelData] dispatch (S2-004).

## Cards per stack clear — the queue-to-pool multiplier (ADR-0003).
const STACK_CAPACITY: int = 3


## Generates a solvable [LevelConfig] from [param params]. On incoherent params
## (bad [code]layout_id[/code]/[code]max_operand[/code], or no legal result)
## the returned [GeneratorResult] has a [code]null[/code] config and a warning.
static func generate(params: GeneratorParams) -> GeneratorResult:
	var result := GeneratorResult.new()

	# INIT — validate params before any allocation (GDD Core Rule 4 guard, Edge Cases).
	if params.layout_id < 0 or params.layout_id >= Layouts.SLOT_COUNTS.size():
		push_error("LevelGenerator: layout_id %d out of range" % params.layout_id)
		result.warn("layout_id %d out of range {0,1,2}" % params.layout_id)
		return result
	if params.max_operand < 1:
		push_error("LevelGenerator: max_operand must be >= 1 (got %d)" % params.max_operand)
		result.warn("max_operand %d < 1" % params.max_operand)
		return result
	if params.distinct_results < 1:
		push_error("LevelGenerator: distinct_results must be >= 1")
		result.warn("distinct_results %d < 1" % params.distinct_results)
		return result

	var rng := RandomNumberGenerator.new()
	rng.seed = params.seed

	var slot_count: int = Layouts.SLOT_COUNTS[params.layout_id]
	var queue_length: int = slot_count / STACK_CAPACITY

	# PICK_RESULTS — candidates are results with at least one legal operand pair.
	var candidates: Array[int] = []
	for r in range(params.result_min, params.result_max + 1):
		if OperandPicker.has_valid_pair(r, params.max_operand):
			candidates.append(r)
	# Empty-pool guard MUST precede the clamp: clampi(D, 1, 0) returns 1, which
	# would otherwise draw from an empty set (GDD Edge Cases / Formula 5).
	if candidates.is_empty():
		push_error("LevelGenerator: no valid result in [%d, %d] under max_operand %d"
			% [params.result_min, params.result_max, params.max_operand])
		result.warn("empty candidate pool")
		return result

	var distinct: int = clampi(params.distinct_results, 1, mini(queue_length, candidates.size()))
	if distinct < params.distinct_results:
		result.warn("distinct_results clamped from %d to %d" % [params.distinct_results, distinct])

	_shuffle_int(candidates, rng)
	var chosen: Array[int] = candidates.slice(0, distinct)

	# BUILD_QUEUE — one of each chosen result, then seeded repeats fill to length L.
	var allow_repeats: bool = params.allow_queue_repeats
	if not allow_repeats and distinct < queue_length:
		allow_repeats = true
		result.warn("allow_queue_repeats promoted to true (distinct %d < queue length %d)"
			% [distinct, queue_length])

	var queue: Array[int] = chosen.duplicate()
	while queue.size() < queue_length:
		queue.append(chosen[rng.randi_range(0, chosen.size() - 1)])
	_shuffle_int(queue, rng)

	# BUILD_POOL — exactly 3*k cards per result (the solvability identity).
	var queue_counts: Dictionary = {}
	for target: int in queue:
		queue_counts[target] = int(queue_counts.get(target, 0)) + 1

	var placements := Layouts.get_layout(params.layout_id)
	# ASSIGN_SLOTS — a seeded slot permutation; card order is canonicalised below.
	var slot_order: Array[int] = []
	for s in range(slot_count):
		slot_order.append(s)
	_shuffle_int(slot_order, rng)

	var pool: Array[CardData] = []
	var next_slot_index: int = 0
	for result_value: int in queue_counts:
		var card_count: int = STACK_CAPACITY * int(queue_counts[result_value])
		for i in range(card_count):
			var slot: int = slot_order[next_slot_index]
			next_slot_index += 1
			var layer: int = placements[slot].layer
			var operands := OperandPicker.pick(result_value, i, params.max_operand)
			pool.append(CardData.create(operands.x, operands.y, layer, slot))

	# Canonical ordering (determinism-critical, AC-08): pool order is a pure
	# function of slot assignment, never of result draw order.
	pool.sort_custom(func(a: CardData, b: CardData) -> bool: return a.layout_slot < b.layout_slot)

	# ASSEMBLE — fresh arrays (no aliasing of working buffers).
	var config := LevelConfig.new()
	config.level_id = LevelConfig.GENERATED_ID
	config.layout_id = params.layout_id
	config.target_queue = queue.duplicate()
	config.card_pool = pool
	config.seed = params.seed
	config.world_id = params.world_id
	config.level_index = params.level_index

	# VALIDATE — debug self-check; by construction it cannot fail.
	# S2-003b: the Rule 10 recoverability check / re-seed slots in here.
	assert(Solvability.is_solvable(config), "LevelGenerator produced an unsolvable level (construction bug)")

	result.config = config
	return result


## In-place seeded Fisher-Yates over [param arr]. The ONLY shuffle the generator
## uses — [code]Array.shuffle()[/code] is banned in [code]core/[/code] because it
## draws from the global RNG and breaks determinism (see gameplay-code rules).
static func _shuffle_int(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
