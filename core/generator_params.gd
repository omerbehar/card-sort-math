class_name GeneratorParams
extends RefCounted
## The full input record for [method LevelGenerator.generate] (GDD Core Rule 2).
##
## The generator consumes only these params — it never sees the level index N.
## The difficulty schedule (S2-003b) maps [code]N -> GeneratorParams[/code].
## [member seed] is the only source of randomness; [member world_id] and
## [member level_index] are carried through onto the generated [LevelConfig] as
## provenance (ADR-0007) for reproducible / shareable levels.

var layout_id: int = 0
var distinct_results: int = 4
var result_min: int = 2
var result_max: int = 12
var max_operand: int = 6
var allow_queue_repeats: bool = true
# Spread equal targets apart in the queue (no two-of-a-kind back-to-back, distinct
# starting decks). Default true; set false for the legacy plain-shuffle ordering.
var space_targets: bool = true
var seed: int = 0
var world_id: int = 0
var level_index: int = 0

# Which operations the generator may print (see [enum Operation.Type]). A
# single-operation world holds one entry; a mixed world holds several. Each
# card's operation is chosen from those valid for its result. Defaults to
# addition-only so callers that never set it are unaffected. Used only when
# term_count == 2 (binary cards).
var allowed_operations: Array[int] = [Operation.Type.ADD]

# Number of terms per card: 2 = binary a ∘ b (the default; uses allowed_operations
# and the legacy path byte-for-byte), 3 = three-term a ∘ b ∘ c (the teaching
# worlds; uses expression_specs).
var term_count: int = 2

# Allowed three-term expression specs, each a Vector3i (op1, op2, grouping) — see
# [enum Operation.Type] and [enum TernaryExpression.Grouping]. Only used when
# term_count == 3. Each card's spec+operands are drawn from those that produce its
# result. Empty leaves the generator on the binary path.
var expression_specs: Array[Vector3i] = []

# Minimum distinct displayed operand pairs a result must offer (for at least one
# allowed operation) to be a candidate — so equal-result cards aren't all the same
# exercise (e.g. a prime like 7 is excluded from a multiply world). Default 1 keeps
# legacy callers/tests unchanged; LevelData sets the gameplay floor.
var min_operand_options: int = 1

# Recoverability (Core Rule 10 / AC-32). 0 disables the check (the default, so
# S2-003a callers are unaffected); the difficulty schedule sets it to 1.
var min_recovery_margin: int = 0
var recovery_attempt_cap: int = 8


## Convenience factory. Field names mirror the GDD's `D` / `R_min` / `R_max`.
static func create(
		layout_id: int,
		distinct_results: int,
		result_min: int,
		result_max: int,
		max_operand: int,
		seed: int = 0,
		allow_queue_repeats: bool = true,
		world_id: int = 0,
		level_index: int = 0,
		allowed_operations: Array[int] = [Operation.Type.ADD],
		space_targets: bool = true) -> GeneratorParams:
	var p := GeneratorParams.new()
	p.layout_id = layout_id
	p.distinct_results = distinct_results
	p.result_min = result_min
	p.result_max = result_max
	p.max_operand = max_operand
	p.seed = seed
	p.allow_queue_repeats = allow_queue_repeats
	p.world_id = world_id
	p.level_index = level_index
	p.allowed_operations = allowed_operations.duplicate()
	p.space_targets = space_targets
	return p
