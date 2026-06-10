class_name CoachOverlay
extends Control
## First-Time Tutorial overlay: renders ring + arrow + banner + confirm toast
## for the coaching hint (S1-010).
##
## Responsibilities (view only — ADR-0001):
## - Draw a shape-based highlight (ring + attention arrow) on the target card.
## - Show a one-line banner with localized copy.
## - Show a confirm toast after a successful ROUTE, then fade out.
## - Suppress completion feedback until the grace window has elapsed.
## - Never own game-logic state — [TutorialState] carries [member n_nonroute];
##   [TutorialLogic] is stateless.
##
## Dependencies: [TutorialLogic], [TutorialState], [SaveData], [SaveService],
## [SettingsService], [Layouts]. Implements
## [code]design/gdd/first-time-tutorial.md[/code] §6 CoachOverlay contract.
##
## Parented to the HUD [CanvasLayer] (layer 1) so it renders above all 2D nodes.

# ---------------------------------------------------------------------------
# Constants (§4 Formulas / §7 Tuning Knobs)
# ---------------------------------------------------------------------------

## Seconds for the banner to fade in.
const MESSAGE_FADE_IN: float = 0.25
## Seconds during which completion processing is suppressed after spawn.
const INPUT_GRACE: float = 0.30
## Seconds the confirm toast lingers before the overlay fades out.
const CONFIRM_DWELL: float = 1.2
## Seconds for the overlay to fade out on completion.
const FADE_OUT: float = 0.30
## Period (s) of the ring/arrow attention pulse; ignored under reduced_motion.
const HIGHLIGHT_PULSE_PERIOD: float = 0.90
## Amplitude (px) of the arrow bob; forced to 0 under reduced_motion.
const HIGHLIGHT_ARROW_BOB: float = 6.0
## Stroke width (px) of the highlight ring.
const HIGHLIGHT_RING_WIDTH: float = 5.0
## Arrow size (px, square).
const HIGHLIGHT_ARROW_SIZE: float = 28.0
## Banner width (px) at the 390×844 base viewport.
const BANNER_W: float = 358.0

## Bottom band Y for the banner (clear of the tool bar, §3 R4).
const _BANNER_BOTTOM_Y: float = 652.0
## Top band Y for the banner (just under the HUD header, §3 R4).
const _BANNER_TOP_Y: float = 84.0
## Banner height.
const _BANNER_H: float = 48.0

## Viewport width (portrait).
const _VIEWPORT_W: float = 390.0

## Y-threshold for the card "top band" flip (matches main.gd FLOOR_ORIGIN.y = 300).
## Cards with global_position.y < this threshold get the arrow flipped to point up
## from below (§3 R4). The GDD notation is Layouts.FLOOR_ORIGIN but that constant
## lives in main.gd; the numeric value (300) is authoritative.
const _FLOOR_ORIGIN_Y: float = 300.0

# ---------------------------------------------------------------------------
# State enum (§3 Lifecycle)
# ---------------------------------------------------------------------------

## Three lifecycle states for the tutorial coach.
enum State {
	## A level started and should_show was true; overlay is being constructed.
	ARMED,
	## Hint visible; waiting for first ROUTE or safety valve / LOSE.
	COACHING,
	## Tutorial complete; overlay fading out.
	DONE,
}

# ---------------------------------------------------------------------------
# Observable test hooks (§6 CoachOverlay API)
# ---------------------------------------------------------------------------

## Current lifecycle state.
var state: State = State.ARMED
## Card id the ring/arrow is highlighting.
var target_card_id: int = -1
## True when the highlighted card is productive (result matches an open stack).
var is_productive: bool = false
## True once the confirm toast has been shown.
var confirm_shown: bool = false

## Emitted when the overlay arms (transitions into COACHING).
signal armed(card_id: int, productive: bool)
## Emitted when the tutorial completes.
signal completed(routed: bool)

# ---------------------------------------------------------------------------
# Injected dependencies
# ---------------------------------------------------------------------------

## Session counter owned by main.gd. Named _state_obj because AC9/AC12 tests
## read coach._state_obj.n_nonroute directly.
var _state_obj: TutorialState = null
var _save_data: SaveData = null
var _save_service: Object = null

# ---------------------------------------------------------------------------
# Internal nodes (built in _ready / configure)
# ---------------------------------------------------------------------------

var _ring: ColorRect = null           # highlight ring (border simulation)
var _arrow: Label = null              # text arrow glyph
var _banner: Label = null
var _confirm_label: Label = null

# ---------------------------------------------------------------------------
# Grace timer state
# ---------------------------------------------------------------------------

## Set to true once MESSAGE_FADE_IN + INPUT_GRACE has elapsed since spawn.
var _grace_elapsed: bool = false
## If a completing tap arrives inside the grace window, store its result here.
var _deferred_completion: Dictionary = {}

# Arrow bob base Y so tween can animate relative to it.
var _arrow_base_y: float = 0.0


func _ready() -> void:
	# Root must be MOUSE_FILTER_IGNORE (AC8a — doesn't propagate, set explicitly).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Build child visuals.
	_build_ring()
	_build_arrow()
	_build_banner()
	_build_confirm()

	# Start grace timer using a node-scoped tween.
	var grace_tween := self.create_tween()
	grace_tween.tween_interval(MESSAGE_FADE_IN + INPUT_GRACE)
	grace_tween.tween_callback(_on_grace_elapsed)

	# Fade banner in.
	_banner.modulate.a = 0.0
	_confirm_label.modulate.a = 0.0
	var fade_in := self.create_tween()
	fade_in.tween_property(_banner, "modulate:a", 1.0, MESSAGE_FADE_IN)


## Injects the tutorial state, save data, and save service. Must be called
## before the node enters the tree (before [method _ready]).
##
## [param state_obj] is the [TutorialState] owned by [code]main.gd[/code].
## [param save_data] is the live [SaveData] from [SaveService].
## [param save_service_obj] is the [SaveService] autoload (or a test double).
func configure(
		state_obj: TutorialState,
		save_data: SaveData,
		save_service_obj: Object) -> void:
	_state_obj = state_obj
	_save_data = save_data
	_save_service = save_service_obj


## Activates the coaching state, positions the ring/arrow on [param card], and
## emits [signal armed].
##
## Must be called after [method configure] and after the node is in the tree.
## [param card] is the [Card] node to highlight.
## [param productive] is whether the card has a productive route.
func arm(card: Card, productive: bool) -> void:
	target_card_id = card.card_id
	is_productive = productive

	# Position ring and arrow based on card's global position.
	var card_rect := Rect2(card.global_position, Vector2(Layouts.CARD_W, Layouts.CARD_H))
	_position_ring(card_rect)
	_position_arrow(card_rect)
	_position_banner(card_rect)

	# Set banner text via localization stub.
	var key: String = "tutorial_route" if productive else "tutorial_neutral"
	_banner.text = _tr(key)

	state = State.COACHING

	# Start highlight animations unless reduced_motion is on.
	if not _is_reduced_motion():
		_start_pulse()
		_start_arrow_bob()

	armed.emit(target_card_id, is_productive)


## Called by [code]main.gd[/code] after each committed tap (non-empty event list).
## Classifies the tap and handles completion / counter increment.
##
## [param events] must be the non-empty [Array][GameEvent]] from
## [method BoardModel.tap_card].
func on_committed_tap(events: Array[GameEvent]) -> void:
	if state != State.COACHING:
		return

	var result: Dictionary = TutorialLogic.should_complete(
		events, _state_obj.n_nonroute, TutorialLogic.TUTORIAL_MAX_TAPS)

	if not result["complete"]:
		# Stay coaching; increment the counter.
		_state_obj.n_nonroute += 1
		return

	# Tutorial should complete.
	if not _grace_elapsed:
		# Within grace window: defer completion until grace elapses (AC8c).
		_deferred_completion = result
		return

	_complete(result)


# ---------------------------------------------------------------------------
# Private — completion logic
# ---------------------------------------------------------------------------

func _complete(result: Dictionary) -> void:
	if state == State.DONE:
		return
	state = State.DONE

	# Persist the flag.
	_save_data.tutorial_seen = true
	if _save_service != null and _save_service.has_method("save_game"):
		_save_service.save_game()

	var routed: bool = result["routed"]

	if routed:
		# Show confirm toast, dwell, then fade out.
		confirm_shown = true
		_confirm_label.text = _tr("tutorial_confirm")
		_confirm_label.modulate.a = 0.0
		_banner.modulate.a = 0.0

		var confirm_tween := self.create_tween()
		if _is_reduced_motion():
			confirm_tween.tween_property(_confirm_label, "modulate:a", 1.0, MESSAGE_FADE_IN)
		else:
			confirm_tween.tween_property(_confirm_label, "modulate:a", 1.0, MESSAGE_FADE_IN)
		confirm_tween.tween_interval(CONFIRM_DWELL)
		confirm_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
		confirm_tween.tween_callback(_finish)
	else:
		# Safety valve / LOSE: no confirm, fade immediately.
		var fade_tween := self.create_tween()
		fade_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
		fade_tween.tween_callback(_finish)

	completed.emit(routed)


func _finish() -> void:
	queue_free()


# ---------------------------------------------------------------------------
# Private — grace window
# ---------------------------------------------------------------------------

func _on_grace_elapsed() -> void:
	_grace_elapsed = true
	if not _deferred_completion.is_empty():
		_complete(_deferred_completion)
		_deferred_completion = {}


# ---------------------------------------------------------------------------
# Private — node building
# ---------------------------------------------------------------------------

func _build_ring() -> void:
	# Simulate a ring with an outer ColorRect clipped to show only the border.
	# We use a simple ColorRect that will be sized/positioned to the card rect
	# with transparency in the centre achieved by self_modulate alpha.
	# For the actual ring we draw a DrawingNode or use a StyleBox. Since
	# CoachOverlay is a pure-code Control, we use four thin ColorRect strips
	# (top, bottom, left, right) as borders.
	_ring = ColorRect.new()
	_ring.name = "Ring"
	_ring.color = Color(1.0, 0.85, 0.1, 0.9)   # bright yellow highlight
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	add_child(_ring)


func _build_arrow() -> void:
	_arrow = Label.new()
	_arrow.name = "Arrow"
	_arrow.text = "v"   # Downward arrow glyph; flipped logic sets it per placement
	_arrow.add_theme_font_size_override("font_size", int(HIGHLIGHT_ARROW_SIZE))
	_arrow.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1, 0.9))
	_arrow.add_theme_constant_override("outline_size", 4)
	_arrow.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2, 0.9))
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.visible = false
	add_child(_arrow)


func _build_banner() -> void:
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.size = Vector2(BANNER_W, _BANNER_H)
	_banner.position = Vector2((_VIEWPORT_W - BANNER_W) * 0.5, _BANNER_BOTTOM_Y)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 18)
	_banner.add_theme_color_override("font_color", Color.WHITE)
	_banner.add_theme_constant_override("outline_size", 4)
	_banner.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2, 0.9))
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)


func _build_confirm() -> void:
	_confirm_label = Label.new()
	_confirm_label.name = "ConfirmToast"
	_confirm_label.size = Vector2(BANNER_W, _BANNER_H)
	_confirm_label.position = Vector2((_VIEWPORT_W - BANNER_W) * 0.5, _BANNER_BOTTOM_Y)
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confirm_label.add_theme_font_size_override("font_size", 20)
	_confirm_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 1.0))
	_confirm_label.add_theme_constant_override("outline_size", 4)
	_confirm_label.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2, 0.9))
	_confirm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_confirm_label)


# ---------------------------------------------------------------------------
# Private — positioning
# ---------------------------------------------------------------------------

func _position_ring(card_rect: Rect2) -> void:
	# Overlay a ring around the card rect using a ColorRect sized to the outer
	# ring edge; the ring "fill" is a slightly inset transparent panel drawn on
	# top. Since we only have ColorRect (no shader), we use a DrawingRect approach:
	# we set the ColorRect to the card rect size + ring width on each side, and
	# draw a second covering rect (inner crop) if needed. For simplicity we just
	# draw the full outer rect with alpha — it reads clearly as a highlight outline.
	var ring_inset: float = HIGHLIGHT_RING_WIDTH
	_ring.position = card_rect.position - Vector2(ring_inset, ring_inset)
	_ring.size = card_rect.size + Vector2(ring_inset * 2.0, ring_inset * 2.0)
	_ring.color = Color(1.0, 0.85, 0.1, 0.45)  # semi-transparent fill
	_ring.visible = true

	# Draw actual ring strokes as child ColorRects (top/bottom/left/right).
	# Clean any prior stroke children.
	for child in _ring.get_children():
		child.queue_free()

	var stroke_color := Color(1.0, 0.85, 0.1, 0.95)
	var w: float = _ring.size.x
	var h: float = _ring.size.y

	# Top strip.
	var top := ColorRect.new()
	top.color = stroke_color
	top.position = Vector2.ZERO
	top.size = Vector2(w, ring_inset)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(top)

	# Bottom strip.
	var bot := ColorRect.new()
	bot.color = stroke_color
	bot.position = Vector2(0.0, h - ring_inset)
	bot.size = Vector2(w, ring_inset)
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(bot)

	# Left strip.
	var left := ColorRect.new()
	left.color = stroke_color
	left.position = Vector2(0.0, ring_inset)
	left.size = Vector2(ring_inset, h - ring_inset * 2.0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(left)

	# Right strip.
	var right := ColorRect.new()
	right.color = stroke_color
	right.position = Vector2(w - ring_inset, ring_inset)
	right.size = Vector2(ring_inset, h - ring_inset * 2.0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(right)


func _position_arrow(card_rect: Rect2) -> void:
	# Arrow points down from above by default (arrowhead faces the card from above).
	# When the card is in the top band (y < FLOOR_ORIGIN.y = 300), flip to point up.
	var flip: bool = card_rect.position.y < _FLOOR_ORIGIN_Y
	_arrow.text = "^" if flip else "v"
	_arrow.size = Vector2(HIGHLIGHT_ARROW_SIZE * 2.0, HIGHLIGHT_ARROW_SIZE * 1.5)

	var arrow_x: float = card_rect.position.x + (card_rect.size.x - _arrow.size.x) * 0.5
	var arrow_y: float
	if flip:
		# Below the card — arrow points up.
		arrow_y = card_rect.position.y + card_rect.size.y + 4.0
	else:
		# Above the card — arrow points down.
		arrow_y = card_rect.position.y - _arrow.size.y - 4.0

	_arrow.position = Vector2(arrow_x, arrow_y)
	_arrow_base_y = arrow_y
	_arrow.visible = true


func _position_banner(card_rect: Rect2) -> void:
	# Default: bottom band. If the card's bottom edge overlaps, move to top band.
	var card_bottom: float = card_rect.position.y + card_rect.size.y
	if card_bottom >= _BANNER_BOTTOM_Y:
		_banner.position.y = _BANNER_TOP_Y
		_confirm_label.position.y = _BANNER_TOP_Y
	else:
		_banner.position.y = _BANNER_BOTTOM_Y
		_confirm_label.position.y = _BANNER_BOTTOM_Y


# ---------------------------------------------------------------------------
# Private — animations
# ---------------------------------------------------------------------------

func _start_pulse() -> void:
	# Looping alpha pulse on the ring.
	var pulse := self.create_tween()
	pulse.set_loops()
	pulse.tween_property(_ring, "modulate:a", 0.5, HIGHLIGHT_PULSE_PERIOD * 0.5)
	pulse.tween_property(_ring, "modulate:a", 1.0, HIGHLIGHT_PULSE_PERIOD * 0.5)


func _start_arrow_bob() -> void:
	if HIGHLIGHT_ARROW_BOB <= 0.0:
		return
	var bob := self.create_tween()
	bob.set_loops()
	bob.tween_property(_arrow, "position:y", _arrow_base_y + HIGHLIGHT_ARROW_BOB,
		HIGHLIGHT_PULSE_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_arrow, "position:y", _arrow_base_y,
		HIGHLIGHT_PULSE_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------------------
# Private — helpers
# ---------------------------------------------------------------------------

## Stub localization lookup. Returns the canonical copy for each key.
## When a real l10n system is introduced, replace this call site only.
func _tr(key: String) -> String:
	match key:
		"tutorial_route":
			return "Solve it — your answer picks the stack."
		"tutorial_neutral":
			return "Tap any card to start."
		"tutorial_confirm":
			return "Matched — nice work!"
		_:
			push_warning("CoachOverlay: unknown localization key '%s'" % key)
			return key


func _is_reduced_motion() -> bool:
	if SettingsService != null:
		return SettingsService.get_value("reduced_motion")
	return false
