class_name GameEvent
extends RefCounted
## A single resolved step produced by [method BoardModel.tap_card].
##
## The model is a pure state machine: it mutates its own state instantly and
## returns an ordered list of these events describing exactly what happened.
## The view (see [code]scenes/main/main.gd[/code]) replays them as animations,
## one after another, so a cascade reads as a satisfying combo.

enum Kind {
	ROUTE,          ## card flew from the floor into a matching stack
	DISCARD,        ## card had no matching stack and went to a discard slot
	STACK_CLEARED,  ## a stack reached capacity, cleared, and took a new target
	PULL,           ## a card was pulled out of discard into a (re)targeted stack
	WIN,            ## the floor is empty
	LOSE,           ## a card had to be discarded but the discard row was full
}

var kind: Kind
var card_id: int = -1           ## card involved (ROUTE / DISCARD / PULL)
var stack_index: int = -1       ## stack involved (ROUTE / STACK_CLEARED / PULL)
var discard_slot: int = -1      ## discard slot used/freed (DISCARD / PULL)
var new_target: int = -1        ## target a cleared stack adopted (STACK_CLEARED; -1 = none)


static func route(card_id: int, stack_index: int) -> GameEvent:
	var e := GameEvent.new()
	e.kind = Kind.ROUTE
	e.card_id = card_id
	e.stack_index = stack_index
	return e


static func discard(card_id: int, discard_slot: int) -> GameEvent:
	var e := GameEvent.new()
	e.kind = Kind.DISCARD
	e.card_id = card_id
	e.discard_slot = discard_slot
	return e


static func stack_cleared(stack_index: int, new_target: int) -> GameEvent:
	var e := GameEvent.new()
	e.kind = Kind.STACK_CLEARED
	e.stack_index = stack_index
	e.new_target = new_target
	return e


static func pull(card_id: int, stack_index: int, discard_slot: int) -> GameEvent:
	var e := GameEvent.new()
	e.kind = Kind.PULL
	e.card_id = card_id
	e.stack_index = stack_index
	e.discard_slot = discard_slot
	return e


static func win() -> GameEvent:
	var e := GameEvent.new()
	e.kind = Kind.WIN
	return e


static func lose() -> GameEvent:
	var e := GameEvent.new()
	e.kind = Kind.LOSE
	return e


func _to_string() -> String:
	return "GameEvent(%s card=%d stack=%d slot=%d target=%d)" % [
		Kind.keys()[kind], card_id, stack_index, discard_slot, new_target,
	]
