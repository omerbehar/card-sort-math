class_name TutorialLogic
extends RefCounted
## Pure, stateless tutorial decision logic for the First-Time Tutorial (S1-010).
##
## Implements all predicates from [code]design/gdd/first-time-tutorial.md[/code]
## §4 (Formulas). Every function is static and deterministic — inputs in, result
## out, no side effects. Session counter state lives in [TutorialState]; the view
## lives in [code]scenes/ui/coach_overlay.gd[/code] per ADR-0001.

## Level index (1-indexed) that triggers the tutorial coach.
## Only value `1` is valid in shipped builds; other values are QA-only.
const TUTORIAL_LEVEL: int = 1

## Maximum number of committed non-routing taps before the safety valve fires.
## Configurable in the safe range 2–6 (see §7 Tuning Knobs).
const TUTORIAL_MAX_TAPS: int = 3


## Returns [code]true[/code] when the tutorial coach should be shown this session.
##
## Formula (§4): [code]should_show = (not seen) AND (level == TUTORIAL_LEVEL)[/code]
##
## [param seen] is [code]SaveData.tutorial_seen[/code].
## [param level] is the 1-indexed level number being started.
static func should_show(seen: bool, level: int) -> bool:
	return (not seen) and (level == TUTORIAL_LEVEL)


## Selects the card id the coach should highlight.
##
## Formula (§4):
## [codeblock]
## productive = { c in exposed : results[c] in open_targets }
## pick_target = min(productive)    if productive != empty
##            = min(exposed)        else if exposed != empty  (fallback, neutral copy)
##            = -1                  else                      (E=empty, do not show coach)
## [/codeblock]
##
## [param exposed] is the ordered list of tappable card ids (from
## [method BoardModel.exposed_cards]).
## [param results] maps [code]card_id -> result value[/code] (from
## [code]BoardModel._result_of[/code] via public query — caller must populate
## an entry for every id in [param exposed]; subscript access is safe under that
## guarantee).
## [param open_targets] is the deduplicated list of targets belonging to stacks
## that are non-full ([code]stack_count(i) < STACK_CAPACITY[/code]).
##
## The returned id is always a member of [param exposed] (guaranteed tappable).
## Deterministic: ties broken by lowest card_id via [code]min()[/code].
static func pick_target(
		exposed: Array[int],
		results: Dictionary,
		open_targets: Array[int]) -> int:
	if exposed.is_empty():
		return -1

	# Productive = exposed cards whose result is in the open-target set.
	var productive: Array[int] = []
	for c: int in exposed:
		if open_targets.has(results.get(c, -1)):
			productive.append(c)

	if not productive.is_empty():
		return productive.min()

	# Fallback: no productive card — highlight lowest exposed id with neutral copy.
	return exposed.min()


## Returns [code]true[/code] if any event in [param events] is a ROUTE.
##
## Formula (§4): [code]is_route = exists e in events : e.kind == ROUTE[/code]
static func is_route(events: Array[GameEvent]) -> bool:
	for e: GameEvent in events:
		if e.kind == GameEvent.Kind.ROUTE:
			return true
	return false


## Returns [code]true[/code] if any event in [param events] is a LOSE.
##
## Formula (§4): [code]is_lose = exists e in events : e.kind == LOSE[/code]
static func is_lose(events: Array[GameEvent]) -> bool:
	for e: GameEvent in events:
		if e.kind == GameEvent.Kind.LOSE:
			return true
	return false


## Classifies a committed tap and returns whether the tutorial should complete.
##
## Returns [code]{"complete": bool, "routed": bool}[/code].
##
## Priority (§4 — must be checked in this exact order):
## [codeblock]
## if is_route(events):                → {complete:true,  routed:true}   # success
## elif is_lose(events):               → {complete:true,  routed:false}  # terminal
## elif (n_nonroute + 1) >= max_taps:  → {complete:true,  routed:false}  # safety valve
## else:                               → {complete:false, routed:false}  # keep coaching
## [/codeblock]
##
## [param events] must be a non-empty list (a committed tap). Empty lists (covered
## / removed card, no-op) are ignored by the caller and never passed here.
##
## [param n_nonroute] is the running count of non-routing taps **before** this
## tap (owned by [TutorialState]). The caller increments it after calling this
## function when [code]complete == false[/code].
##
## [param max_taps] is [constant TUTORIAL_MAX_TAPS] (passed explicitly so the
## function remains stateless and independently testable).
static func should_complete(
		events: Array[GameEvent],
		n_nonroute: int,
		max_taps: int) -> Dictionary:
	if is_route(events):
		return {"complete": true, "routed": true}
	elif is_lose(events):
		return {"complete": true, "routed": false}
	elif (n_nonroute + 1) >= max_taps:
		return {"complete": true, "routed": false}
	else:
		return {"complete": false, "routed": false}
