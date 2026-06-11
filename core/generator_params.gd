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
var seed: int = 0
var world_id: int = 0
var level_index: int = 0

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
		level_index: int = 0) -> GeneratorParams:
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
	return p
