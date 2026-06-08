extends Node
## Autoload: persistent, game-wide meta state only.
##
## Deliberately holds NO references to board scene nodes (stacks, cards, etc.) —
## per-level gameplay lives in [BoardModel] and is driven by the [code]Main[/code]
## controller. This singleton tracks progression and broadcasts coarse signals
## other systems (menus, audio) can listen to.

signal level_started(level: int)
signal level_completed(level: int)
signal game_over(level: int)

var current_level: int = 1
var score: int = 0


## Marks a level as started, resetting per-level meta.
func start_level(level: int) -> void:
	current_level = level
	level_started.emit(level)


## Records a win on the current level and advances [member current_level] if a
## further authored level exists.
func complete_level() -> void:
	level_completed.emit(current_level)
	if current_level < LevelData.level_count():
		current_level += 1


## Records a loss on the current level.
func fail_level() -> void:
	game_over.emit(current_level)
