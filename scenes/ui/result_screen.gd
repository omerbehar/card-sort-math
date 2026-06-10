class_name ResultScreen
extends Control
## Win / lose result screen shown when the board reaches WIN or LOSE (S1-020).
##
## View only (ADR-0001): it renders the outcome and emits intent signals; it owns
## no game state and never advances the level itself — [code]main.gd[/code] listens
## and calls [code]start_level[/code]. Built programmatically (no .tscn instancing)
## for the same reliability reasons as [CoachOverlay].
##
## Visual direction follows the win ("WELL DONE!" + hero star + claim) and lose
## ("CONTINUE?"-style modal + retry) reference mocks. The monetised elements in
## those mocks — REVIVE (rewarded ad), PLAY ON (soft currency), the SPECIAL OFFER
## IAP banner, the reward chips, the 1-3 star rating, and the tournament strip — do
## NOT exist yet. They are reserved here as hidden, clearly-marked placeholders to
## be wired up by their owning milestones:
##   - star rating .......... M2 (scoring/stars, deferred S1-021)
##   - reward chips ......... M4 (economy)
##   - REVIVE / PLAY ON ..... M4 (ads / IAP) — must gate through ComplianceService
##   - SPECIAL OFFER banner . M4 (IAP) — ADR-0005 compliance (13+, no kids ads)
##   - tournament strip ..... M3 (live-ops)

## The two outcomes this screen renders.
enum Mode { WIN, LOSE }

## Player chose to retry the failed level.
signal retry_pressed
## Player claimed the win / advanced to the next level.
signal next_pressed
## Player chose to leave to "home" (restarts the current level until a menu lands).
signal home_pressed

const _VIEWPORT_W: float = 390.0
const _VIEWPORT_H: float = 844.0

## Current outcome (set by [method setup]).
var mode: Mode = Mode.WIN

# Reserved-placeholder handles (hidden; see header for the owning milestone).
var _reward_chips: Control = null      # M4 economy
var _star_rating: Control = null       # M2 scoring/stars
var _revive_button: Control = null     # M4 ads
var _play_on_button: Control = null    # M4 IAP/currency
var _special_offer: Control = null     # M4 IAP
var _tournament_strip: Control = null  # M3 live-ops


func _ready() -> void:
	# Full-rect and opaque to input: block taps from reaching the board beneath.
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.04, 0.05, 0.09, 0.86)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)


## Builds the layout for [param result_mode]. Call once after instancing, before
## (or right after) adding to the tree.
func setup(result_mode: Mode) -> void:
	mode = result_mode
	if mode == Mode.WIN:
		_build_win()
	else:
		_build_lose()


# ---------------------------------------------------------------------------
# WIN — "WELL DONE!" + hero star + claim
# ---------------------------------------------------------------------------

func _build_win() -> void:
	_add_title("WELL DONE!", Color(1.0, 0.85, 0.1), 240.0)

	# Hero star — celebration only (NOT a 1-3 rating; that is the M2 star_rating).
	var star := _make_label("★", 132, Color(1.0, 0.82, 0.05))
	star.size = Vector2(_VIEWPORT_W, 200.0)
	star.position = Vector2(0.0, 300.0)
	add_child(star)

	# [M2] Reserved: 1-3 star efficiency rating row (hidden until scoring ships).
	_star_rating = _reserve_row(Vector2(0.0, 470.0), "StarRatingPlaceholder")

	# [M4] Reserved: reward chips (coins / gems) row (hidden until economy ships).
	_reward_chips = _reserve_row(Vector2(0.0, 520.0), "RewardChipsPlaceholder")

	# Primary action: claim the win and advance.
	var claim := _make_button("TAP TO CLAIM", Color(0.30, 0.78, 0.30))
	claim.size = Vector2(300.0, 64.0)
	claim.position = Vector2((_VIEWPORT_W - 300.0) * 0.5, 600.0)
	claim.pressed.connect(func() -> void: next_pressed.emit())
	add_child(claim)

	# [M3] Reserved: tournament / live-ops strip (hidden until live-ops ships).
	_tournament_strip = _reserve_row(Vector2(0.0, _VIEWPORT_H - 90.0), "TournamentPlaceholder")


# ---------------------------------------------------------------------------
# LOSE — modal + retry (reference "CONTINUE?" layout)
# ---------------------------------------------------------------------------

func _build_lose() -> void:
	# Modal panel.
	var panel := Panel.new()
	panel.name = "Panel"
	panel.size = Vector2(330.0, 300.0)
	panel.position = Vector2((_VIEWPORT_W - 330.0) * 0.5, 250.0)
	add_child(panel)

	_add_title("OUT OF MOVES", Color(0.95, 0.97, 1.0), 270.0)

	# Close (X) → home. No main menu yet, so main.gd restarts the current level.
	var close := _make_button("✕", Color(0.85, 0.25, 0.25))
	close.size = Vector2(44.0, 44.0)
	close.position = Vector2(_VIEWPORT_W - 44.0 - 36.0, 262.0)
	close.pressed.connect(func() -> void: home_pressed.emit())
	add_child(close)

	# Centered icon + subtext.
	var icon := _make_label("🃏", 72, Color(0.9, 0.9, 1.0))
	icon.size = Vector2(_VIEWPORT_W, 96.0)
	icon.position = Vector2(0.0, 330.0)
	add_child(icon)

	var sub := _make_label("The discard row filled up.", 18, Color(0.75, 0.78, 0.88))
	sub.size = Vector2(_VIEWPORT_W, 32.0)
	sub.position = Vector2(0.0, 430.0)
	add_child(sub)

	# [M4] Reserved: REVIVE (rewarded ad) and PLAY ON (soft currency). Hidden until
	# ads/economy exist AND ComplianceService gating is wired (ADR-0005).
	_revive_button = _reserve_row(Vector2(40.0, 478.0), "RevivePlaceholder")
	_play_on_button = _reserve_row(Vector2(200.0, 478.0), "PlayOnPlaceholder")

	# Primary action available today: retry the level.
	var retry := _make_button("RETRY", Color(0.95, 0.72, 0.15))
	retry.size = Vector2(300.0, 64.0)
	retry.position = Vector2((_VIEWPORT_W - 300.0) * 0.5, 478.0)
	retry.pressed.connect(func() -> void: retry_pressed.emit())
	add_child(retry)

	# [M4] Reserved: SPECIAL OFFER IAP banner (hidden until IAP ships; ADR-0005).
	_special_offer = _reserve_row(Vector2(0.0, _VIEWPORT_H - 120.0), "SpecialOfferPlaceholder")


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

func _add_title(text: String, color: Color, y: float) -> void:
	var title := _make_label(text, 44, color)
	title.size = Vector2(_VIEWPORT_W, 64.0)
	title.position = Vector2(0.0, y)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2))
	add_child(title)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 24)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(8)
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("hover", sb)
	button.add_theme_stylebox_override("pressed", sb)
	button.add_theme_color_override("font_color", Color.WHITE)
	return button


## A hidden, zero-content placeholder anchor for a future (milestone-gated) row.
## Kept in the tree by name so the owning milestone can find and populate it.
func _reserve_row(pos: Vector2, node_name: String) -> Control:
	var slot := Control.new()
	slot.name = node_name
	slot.position = pos
	slot.visible = false
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot)
	return slot
