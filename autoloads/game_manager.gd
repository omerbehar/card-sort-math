extends Node
## Autoload: persistent, game-wide meta state only.
##
## Deliberately holds NO references to board scene nodes (stacks, cards, etc.) —
## per-level gameplay lives in [BoardModel] and is driven by the [code]Main[/code]
## controller. This singleton tracks progression (the level to resume on) and
## broadcasts coarse signals other systems (menus, audio) can listen to.
##
## Progression is persisted via [SaveService] (Sprint 1 story S1-002). The save
## service is injectable (see [method configure]) so the logic is unit-testable.

signal level_started(level: int)
signal level_completed(level: int)
signal game_over(level: int)

var current_level: int = 1
var score: int = 0

# SaveService dependency. Resolves to the autoload at runtime; tests inject a
# temp-path service via [method configure]. Untyped because the autoload has no
# class_name.
var _save = null


func _ready() -> void:
	if _save == null:
		_save = SaveService
	_load_progress()


## Injects the save service and reloads progression from it. Intended for tests:
## [code]game_manager.configure(save_service)[/code]. Normal play uses the
## [code]SaveService[/code] autoload automatically.
func configure(save: Object) -> void:
	_save = save
	_load_progress()


## Marks a level as started, resetting per-level meta. Does not persist — the
## resume point only advances on a win (see [method complete_level]).
func start_level(level: int) -> void:
	current_level = level
	level_started.emit(level)


## Records a win on the current level, advances [member current_level] to the next
## authored level (if any), and persists the new resume point.
func complete_level() -> void:
	level_completed.emit(current_level)
	if current_level < LevelData.level_count():
		current_level += 1
	_persist_progress()


## Records a loss on the current level. Progress is unchanged.
func fail_level() -> void:
	game_over.emit(current_level)


# Pulls the saved resume level into [member current_level] when a save service is
# available; otherwise leaves the default.
func _load_progress() -> void:
	if _save != null:
		current_level = _save.data.current_level


# Writes the current resume level to disk via the save service.
func _persist_progress() -> void:
	if _save != null:
		_save.set_current_level(current_level)
