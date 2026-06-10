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

# Palette (approximates the reference mocks).
const _DIM := Color(0.04, 0.05, 0.09, 0.88)
const _GOLD := Color(1.0, 0.80, 0.12)
const _GOLD_DEEP := Color(0.85, 0.58, 0.05)
const _GREEN := Color(0.30, 0.78, 0.34)
const _GREEN_DEEP := Color(0.20, 0.58, 0.24)
const _CARD_BG := Color(0.97, 0.94, 0.87)
const _HEADER_BLUE := Color(0.27, 0.52, 0.95)
const _HEADER_BLUE_DEEP := Color(0.18, 0.38, 0.78)
const _RED := Color(0.90, 0.27, 0.27)
const _RED_DEEP := Color(0.72, 0.18, 0.18)
const _INK := Color(0.12, 0.14, 0.22)

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
	dim.color = _DIM
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)


## Builds the layout for [param result_mode]. Call once after instancing and after
## adding to the tree (so the dim from [method _ready] sits underneath).
func setup(result_mode: Mode) -> void:
	mode = result_mode
	if mode == Mode.WIN:
		_build_win()
	else:
		_build_lose()


# ---------------------------------------------------------------------------
# WIN — "WELL DONE!" + glowing hero star + claim
# ---------------------------------------------------------------------------

func _build_win() -> void:
	if _motion_ok():
		_add_confetti()

	_add_title("WELL DONE!", _GOLD, 150.0)

	# Hero star — celebration only (NOT a 1-3 rating; that is the M2 star_rating).
	# A large translucent star behind the crisp one fakes a soft glow.
	var glow := _make_label("★", 220, Color(_GOLD.r, _GOLD.g, _GOLD.b, 0.22))
	glow.size = Vector2(_VIEWPORT_W, 300.0)
	glow.position = Vector2(0.0, 270.0)
	add_child(glow)

	var star := _make_label("★", 140, _GOLD)
	star.size = Vector2(_VIEWPORT_W, 220.0)
	star.position = Vector2(0.0, 310.0)
	add_child(star)
	if _motion_ok():
		_pop(star)

	# [M2] Reserved: 1-3 star efficiency rating row (hidden until scoring ships).
	_star_rating = _reserve_row(Vector2(0.0, 530.0), "StarRatingPlaceholder")
	# [M4] Reserved: reward chips (coins / gems) row (hidden until economy ships).
	_reward_chips = _reserve_row(Vector2(0.0, 575.0), "RewardChipsPlaceholder")

	# Primary action: claim the win and advance.
	var claim := _make_button("TAP TO CLAIM", _GREEN, _GREEN_DEEP, Color.WHITE)
	claim.size = Vector2(300.0, 66.0)
	claim.position = Vector2((_VIEWPORT_W - 300.0) * 0.5, 640.0)
	claim.pressed.connect(func() -> void: next_pressed.emit())
	add_child(claim)

	# [M3] Reserved: tournament / live-ops strip (hidden until live-ops ships).
	_tournament_strip = _reserve_row(Vector2(0.0, _VIEWPORT_H - 90.0), "TournamentPlaceholder")


# ---------------------------------------------------------------------------
# LOSE — rounded modal + retry (reference "CONTINUE?" layout)
# ---------------------------------------------------------------------------

func _build_lose() -> void:
	var pw: float = 336.0
	var ph: float = 330.0
	var px: float = (_VIEWPORT_W - pw) * 0.5
	var py: float = 250.0

	# Card body (rounded, light, drop shadow).
	var card := _panel(_CARD_BG, 22, 22, 22, 22, true)
	card.name = "Panel"
	card.position = Vector2(px, py)
	card.size = Vector2(pw, ph)
	add_child(card)

	# Coloured header strip (rounded top only).
	var header := _panel(_HEADER_BLUE, 22, 22, 0, 0, false)
	header.position = Vector2(px, py)
	header.size = Vector2(pw, 64.0)
	add_child(header)

	var title := _make_label("GAME OVER", 30, Color.WHITE)
	title.size = Vector2(pw, 64.0)
	title.position = Vector2(px, py)
	add_child(title)

	# Close (X) at the panel's top-right corner → home.
	var close := _make_button("✕", _RED, _RED_DEEP, Color.WHITE)
	close.size = Vector2(46.0, 46.0)
	close.position = Vector2(px + pw - 30.0, py - 18.0)
	close.pressed.connect(func() -> void: home_pressed.emit())
	add_child(close)

	# Icon card + subtext.
	var icon := _make_label("🃏", 60, _INK)
	icon.size = Vector2(pw, 96.0)
	icon.position = Vector2(px, py + 78.0)
	add_child(icon)

	var sub := _make_label("The discard row filled up.", 18, Color(0.32, 0.30, 0.36))
	sub.size = Vector2(pw, 28.0)
	sub.position = Vector2(px, py + 178.0)
	add_child(sub)

	# [M4] Reserved: REVIVE (rewarded ad) and PLAY ON (soft currency). Hidden until
	# ads/economy exist AND ComplianceService gating is wired (ADR-0005).
	_revive_button = _reserve_row(Vector2(px + 16.0, py + 220.0), "RevivePlaceholder")
	_play_on_button = _reserve_row(Vector2(px + 180.0, py + 220.0), "PlayOnPlaceholder")

	# Primary action available today: retry the level.
	var retry := _make_button("RETRY", _GOLD, _GOLD_DEEP, Color.WHITE)
	retry.size = Vector2(pw - 48.0, 60.0)
	retry.position = Vector2(px + 24.0, py + 220.0)
	retry.pressed.connect(func() -> void: retry_pressed.emit())
	add_child(retry)

	# [M4] Reserved: SPECIAL OFFER IAP banner (hidden until IAP ships; ADR-0005).
	_special_offer = _reserve_row(Vector2(0.0, _VIEWPORT_H - 120.0), "SpecialOfferPlaceholder")


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

func _add_title(text: String, color: Color, y: float) -> void:
	var title := _make_label(text, 52, color)
	title.size = Vector2(_VIEWPORT_W, 72.0)
	title.position = Vector2(0.0, y)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", _INK)
	add_child(title)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", _INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String, bg: Color, deep: Color, fg: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	var sb := _round_box(bg, 16)
	sb.border_width_bottom = 5             # chunky "3D" bottom edge
	sb.border_color = deep
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("hover", sb)
	var pressed := _round_box(deep, 16)    # flatten on press
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _panel(bg: Color, tl: int, tr: int, bl: int, br: int, shadow: bool) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = tl
	sb.corner_radius_top_right = tr
	sb.corner_radius_bottom_left = bl
	sb.corner_radius_bottom_right = br
	if shadow:
		sb.shadow_size = 10
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _round_box(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb


# A short scale "pop" so the hero star lands with a bit of life.
func _pop(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(0.5, 0.5)
	var t := create_tween()
	t.tween_property(node, "scale", Vector2(1.12, 1.12), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, 0.10)


# A one-shot multicolour confetti burst from the top of the screen.
func _add_confetti() -> void:
	var p := CPUParticles2D.new()
	p.name = "Confetti"
	p.position = Vector2(_VIEWPORT_W * 0.5, 20.0)
	p.amount = 48
	p.lifetime = 2.6
	p.one_shot = true
	p.explosiveness = 0.35
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(_VIEWPORT_W * 0.5, 6.0)
	p.direction = Vector2(0.0, 1.0)
	p.spread = 35.0
	p.gravity = Vector2(0.0, 240.0)
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.angular_velocity_min = -260.0
	p.angular_velocity_max = 260.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.32, 0.46))
	ramp.set_color(1, Color(0.30, 0.70, 1.0))
	ramp.add_point(0.33, Color(1.0, 0.85, 0.20))
	ramp.add_point(0.66, Color(0.40, 0.85, 0.45))
	p.color_initial_ramp = ramp
	add_child(p)


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


func _motion_ok() -> bool:
	# Respect the reduced-motion accessibility setting (ui-code rule). Resolve the
	# autoload via its tree path (not the global identifier) so dev harnesses that
	# load this script standalone still compile.
	var settings := get_node_or_null(^"/root/SettingsService")
	return not (settings != null and settings.get_value("reduced_motion"))
