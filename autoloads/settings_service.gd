extends Node
## Autoload: app-facing settings access, backed by [SaveData] via [SaveService].
##
## The UI binds to this: it reads current values, flips them with [method
## set_value], and listens to [signal changed] to refresh. Every change is
## persisted immediately through the save service. The save service is injectable
## (see [method configure]) so this is unit-testable in isolation.
##
## Implements Sprint 1 story S1-003 (`production/sprints/sprint-01.md`).

## Emitted after a setting changes, with its key and new value.
signal changed(key: String, value: bool)

# SaveService dependency; resolves to the autoload at runtime, injectable in tests.
var _save = null


func _ready() -> void:
	if _save == null:
		_save = SaveService


## Injects the save service. Intended for tests.
func configure(save: Object) -> void:
	_save = save


## Returns the current settings model (read-only convenience).
func settings() -> Settings:
	return _save.data.settings


## Reads a single setting by key (see [constant Settings.KEYS]).
func get_value(key: String) -> bool:
	return settings().get_value(key)


## Sets a single setting by key, persists, and emits [signal changed]. Unknown
## keys are ignored. Re-setting the same value still persists and notifies.
func set_value(key: String, value: bool) -> void:
	if not settings().set_value(key, value):
		return
	_save.save_game()
	changed.emit(key, value)


## Convenience toggler — flips a boolean setting and persists.
func toggle(key: String) -> void:
	set_value(key, not get_value(key))
