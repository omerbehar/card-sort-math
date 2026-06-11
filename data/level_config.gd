class_name LevelConfig
extends Resource
## A fully authored level: a floor layout, the queue of stack targets, and the
## pool of cards dealt onto the floor.
##
## The four stacks start showing [code]target_queue[0..3][/code]; each time a
## stack clears it draws the next unused entry from the queue. A level is
## solvable when every card's result appears in [member target_queue] and the
## number of cards with a given result equals 3 x (its occurrences in the
## queue) — see [method LevelData.is_solvable].
##
## [member level_id] distinguishes provenance: a positive id is a hand-authored
## level (1-based); [constant GENERATED_ID] (0) marks a procedurally generated
## one (see [method is_generated]); the default [code]-1[/code] means "unset"
## so a bare [code]LevelConfig.new()[/code] never reads as generated.

## Marker [member level_id] value for a procedurally generated level (ADR-0007).
const GENERATED_ID: int = 0

@export var level_id: int = -1
@export var layout_id: int = 0
@export var target_queue: Array[int] = []
@export var card_pool: Array[CardData] = []

# Provenance for generated levels (ADR-0007). Runtime-only — deliberately NOT
# [code]@export[/code], so they are never baked into an authored [code].tres[/code]
# where their zero defaults would make an authored level look generated.
var seed: int = 0
var world_id: int = 0
var level_index: int = 0


## Whether this level was produced by the generator rather than hand-authored.
func is_generated() -> bool:
	return level_id == GENERATED_ID
