class_name TutorialState
extends RefCounted
## Mutable session state for the First-Time Tutorial (S1-010).
##
## This is a pure data container — no [Node], no I/O. It holds the single
## counter that [TutorialLogic] (stateless) needs across taps. Lives in
## [code]core/[/code] because it is pure data with no scene-tree dependency
## (ADR-0001). [code]main.gd[/code] owns its lifetime: created when arming the
## coach and reset on each [code]start_level(1)[/code] call (Edge Case 10).
##
## See [code]design/gdd/first-time-tutorial.md[/code] §6 Dependencies.

## Running count of committed non-routing taps while the coach is active.
## Starts at 0 each time the coach arms. Incremented by the caller (main.gd /
## CoachOverlay) after [method TutorialLogic.should_complete] returns
## [code]{complete: false}[/code]. Passed by value to [method TutorialLogic.should_complete].
var n_nonroute: int = 0


## Resets the counter to 0. Call when the coach re-arms on a fresh start_level.
func reset() -> void:
	n_nonroute = 0
