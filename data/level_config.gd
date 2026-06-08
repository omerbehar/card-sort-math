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

@export var level_id: int = 0
@export var layout_id: int = 0
@export var target_queue: Array[int] = []
@export var card_pool: Array[CardData] = []
