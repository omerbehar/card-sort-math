class_name AudioCues
extends RefCounted
## Pure, node-free mapping from [GameEvent] kinds (and named UI cues) to audio
## file paths. Keeping the mapping here — rather than inside [AudioService] —
## makes cue selection deterministic and unit-testable, and lets the bespoke
## audio pass re-point cues by editing data only.
##
## Cues are CC0 Kenney Interface Sounds (see assets/audio/README.md). Implements
## part of Sprint 1 story S1-004.

const SFX_DIR: String = "res://assets/audio/kenney_interface_sounds/"
const MUSIC_PATH: String = "res://assets/audio/music/calm_ambience.ogg"

## [GameEvent.Kind] -> sfx filename (within [constant SFX_DIR]).
const EVENT_CUES: Dictionary = {
	GameEvent.Kind.ROUTE: "confirmation_001.wav",
	GameEvent.Kind.DISCARD: "drop_003.wav",
	GameEvent.Kind.STACK_CLEARED: "maximize_006.wav",
	GameEvent.Kind.PULL: "pluck_002.wav",
	GameEvent.Kind.WIN: "confirmation_004.wav",
	GameEvent.Kind.LOSE: "error_004.wav",
}

## Named UI cue -> sfx filename.
const UI_CUES: Dictionary = {
	"tap": "select_001.wav",
	"click": "click_002.wav",
	"back": "back_001.wav",
}


## Full resource path for a [GameEvent] kind, or "" when the kind has no cue.
static func event_cue_path(kind: int) -> String:
	if EVENT_CUES.has(kind):
		return SFX_DIR + String(EVENT_CUES[kind])
	return ""


## Full resource path for a named UI cue, or "" when unknown.
static func ui_cue_path(name: String) -> String:
	if UI_CUES.has(name):
		return SFX_DIR + String(UI_CUES[name])
	return ""
