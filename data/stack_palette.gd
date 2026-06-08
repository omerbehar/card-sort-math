class_name StackPalette
extends RefCounted
## Pure, node-free mapping from a stack index to the art used for its frame.
##
## The default palette mirrors the reference skin — four distinctly *hued* Kenney
## slots (red / amber / green / blue). Red↔green are the classic
## colour-vision-deficiency confusion pair, so the **colorblind** palette swaps to
## a neutral grey slot tinted with the Okabe-Ito qualitative palette — eight
## colours chosen to stay distinguishable across the common CVD types
## (https://jfly.uni-koeln.de/color/). We use four of them, ordered for maximum
## separation. Keeping this as data (not baked into the view) makes the swap
## unit-testable and lets the board recolour live when the setting flips.
##
## Supports Sprint 1 story S1-011 (settings) + the colorblind accessibility mode.

const _NEUTRAL_SLOT: String = "kenney/slot_grey.png"

# Default skin: one pre-coloured Kenney slot per stack, shown at full white tint.
const _DEFAULT_SLOTS: Array[String] = [
	"kenney/slot_red.png",
	"kenney/slot_yellow.png",
	"kenney/slot_green.png",
	"kenney/slot_blue.png",
]

# Okabe-Ito colour-blind-safe tints applied over the neutral grey slot, ordered
# blue → orange → bluish-green → vermillion for high mutual separation.
const _COLORBLIND_TINTS: Array[Color] = [
	Color(0.0, 0.447, 0.698),    # blue        #0072B2
	Color(0.902, 0.624, 0.0),    # orange      #E69F00
	Color(0.0, 0.620, 0.451),    # bluish-green #009E73
	Color(0.835, 0.369, 0.0),    # vermillion  #D55E00
]


## The Kenney slot texture path for stack [param index] under the active palette.
## Indices wrap, so this is safe for any stack count.
static func slot_file(index: int, colorblind: bool) -> String:
	if colorblind:
		return _NEUTRAL_SLOT
	return _DEFAULT_SLOTS[index % _DEFAULT_SLOTS.size()]


## The [code]self_modulate[/code] tint for stack [param index]. Default art is
## already coloured, so it tints white (no change); the colorblind palette tints
## the neutral slot with an Okabe-Ito colour. Indices wrap.
static func tint(index: int, colorblind: bool) -> Color:
	if colorblind:
		return _COLORBLIND_TINTS[index % _COLORBLIND_TINTS.size()]
	return Color.WHITE
