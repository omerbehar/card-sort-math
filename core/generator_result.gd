class_name GeneratorResult
extends RefCounted
## The output of [method LevelGenerator.generate] (GDD §Open Questions / ADR-0007).
##
## Wrapping the config lets the generator surface non-fatal [member warnings]
## (clamped params, promoted flags) as testable data instead of global
## [code]push_warning[/code] side effects. On a hard error (incoherent params)
## [member config] is [code]null[/code] and a diagnostic is appended to
## [member warnings]; callers MUST check [member config] before using it.

var config: LevelConfig = null
var warnings: Array[String] = []


## Records a non-fatal diagnostic.
func warn(message: String) -> void:
	warnings.append(message)


## Whether generation failed (no usable config).
func is_error() -> bool:
	return config == null
