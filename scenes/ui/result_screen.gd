class_name ResultScreen
extends PopupBase
## Win / lose result screen shown when the board reaches WIN or LOSE (S1-020).
##
## A [PopupBase] subclass (ADR-0006): the base owns the modal chassis (backdrop,
## input capture, open/close animation, lifecycle); this class only builds the
## win/lose content into [method body] and emits intent signals. View only
## (ADR-0001) — it owns no game state; [code]main.gd[/code] advances/retries.
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

# Palette (approximates the reference mocks).
const _GOLD := Color(1.0, 0.80, 0.12)
const _GOLD_DEEP := Color(0.85, 0.58, 0.05)
const _GREEN := Color(0.30, 0.78, 0.34)
const _GREEN_DEEP := Color(0.20, 0.58, 0.24)
const _CARD_BG := Color(0.97, 0.94, 0.87)
const _HEADER_BLUE := Color(0.27, 0.52, 0.95)
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


## Builds the layout for [param result_mode] into the pop-up body and plays the
## open animation. Call once after instancing and after adding to the tree.
func setup(result_mode: Mode) -> void:
	mode = result_mode
	if mode == Mode.WIN:
		_build_win()
	else:
		_build_lose()
	play_open()


# ---------------------------------------------------------------------------
# WIN — "WELL DONE!" + glowing hero star + claim
# ---------------------------------------------------------------------------

func _build_win() -> void:
	if _motion_ok():
		_add_confetti()

	_title(_tr("result_win_title"), _GOLD, 150.0)

	# Hero star — celebration only (NOT a 1-3 rating; that is the M2 star_rating).
	# A large translucent star behind the crisp one fakes a soft glow.
	UiFactory.label(body(), "★", Vector2(0.0, 270.0), Vector2(_VIEWPORT_W, 300.0),
		220, Color(_GOLD.r, _GOLD.g, _GOLD.b, 0.22))
	UiFactory.label(body(), "★", Vector2(0.0, 310.0), Vector2(_VIEWPORT_W, 220.0),
		140, _GOLD)

	# [M2] Reserved: 1-3 star efficiency rating row (hidden until scoring ships).
	_star_rating = _reserve_row(Vector2(0.0, 530.0), "StarRatingPlaceholder")
	# [M4] Reserved: reward chips (coins / gems) row (hidden until economy ships).
	_reward_chips = _reserve_row(Vector2(0.0, 575.0), "RewardChipsPlaceholder")

	# Primary action: claim the win and advance. Bottom-anchored so it survives
	# aspect 'expand' on non-base devices instead of floating mid-screen.
	var claim := _action_button(_tr("result_claim"), _GREEN, _GREEN_DEEP,
		func() -> void: next_pressed.emit())
	_anchor_bottom(claim, 204.0, 66.0, 300.0)

	# [M3] Reserved: tournament / live-ops strip (hidden until live-ops ships).
	_tournament_strip = _reserve_bottom_row(90.0, "TournamentPlaceholder")


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
	body().add_child(card)

	# Coloured header strip (rounded top only).
	var header := _panel(_HEADER_BLUE, 22, 22, 0, 0, false)
	header.position = Vector2(px, py)
	header.size = Vector2(pw, 64.0)
	body().add_child(header)

	UiFactory.label(body(), _tr("result_lose_title"), Vector2(px, py),
		Vector2(pw, 64.0), 30, Color.WHITE)

	# Close (X) at the panel's top-right corner → home.
	var close := _action_button("✕", _RED, _RED_DEEP, func() -> void: home_pressed.emit())
	close.size = Vector2(46.0, 46.0)
	close.position = Vector2(px + pw - 30.0, py - 18.0)

	# Icon card + subtext.
	UiFactory.label(body(), "🃏", Vector2(px, py + 78.0), Vector2(pw, 96.0), 60, _INK)
	UiFactory.label(body(), _tr("result_lose_reason"), Vector2(px, py + 178.0),
		Vector2(pw, 28.0), 18, Color(0.32, 0.30, 0.36))

	# [M4] Reserved: REVIVE (rewarded ad) and PLAY ON (soft currency). Hidden until
	# ads/economy exist AND ComplianceService gating is wired (ADR-0005).
	_revive_button = _reserve_row(Vector2(px + 16.0, py + 220.0), "RevivePlaceholder")
	_play_on_button = _reserve_row(Vector2(px + 180.0, py + 220.0), "PlayOnPlaceholder")

	# Primary action available today: retry the level.
	var retry := _action_button(_tr("result_retry"), _GOLD, _GOLD_DEEP,
		func() -> void: retry_pressed.emit())
	retry.size = Vector2(pw - 48.0, 60.0)
	retry.position = Vector2(px + 24.0, py + 220.0)

	# [M4] Reserved: SPECIAL OFFER IAP banner (hidden until IAP ships; ADR-0005).
	_special_offer = _reserve_bottom_row(120.0, "SpecialOfferPlaceholder")


# ---------------------------------------------------------------------------
# Builders (content goes into body(); the base owns the backdrop)
# ---------------------------------------------------------------------------

func _title(text: String, color: Color, y: float) -> void:
	# Reuses the shared UiFactory label, then thickens the outline for the big
	# celebratory headline.
	var title := UiFactory.label(body(), text, Vector2(0.0, y),
		Vector2(_VIEWPORT_W, 72.0), 52, color)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", _INK)


## Creates a primary action [Button], wires its press, and adds it to the body.
## Callers position/size the returned node. Centralises button creation + wiring.
func _action_button(text: String, bg: Color, deep: Color, on_press: Callable) -> Button:
	var button := _make_button(text, bg, deep, Color.WHITE)
	button.pressed.connect(on_press)
	body().add_child(button)
	return button


func _make_button(text: String, bg: Color, deep: Color, fg: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	# StyleBoxFlat (rather than UiFactory's nine-patch art) gives the bright, flat,
	# rounded button look the reference mocks use.
	var sb := _round_box(bg, 16)
	sb.border_width_bottom = 5             # chunky "3D" bottom edge
	sb.border_color = deep
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("hover", sb)
	button.add_theme_stylebox_override("pressed", _round_box(deep, 16))
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
	body().add_child(p)


# Anchors a control to the bottom-centre so it tracks the screen edge under the
# 'expand' aspect on non-base devices instead of floating at a fixed pixel Y.
func _anchor_bottom(c: Control, from_bottom: float, height: float, width: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = -width * 0.5
	c.offset_right = width * 0.5
	c.offset_top = -from_bottom
	c.offset_bottom = -from_bottom + height


## A hidden, zero-content placeholder anchor for a future (milestone-gated) row.
## Kept in the tree by name so the owning milestone can find and populate it.
func _reserve_row(pos: Vector2, node_name: String) -> Control:
	var slot := Control.new()
	slot.name = node_name
	slot.position = pos
	slot.visible = false
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body().add_child(slot)
	return slot


# As _reserve_row, but bottom-anchored (the strip-style placeholders live against
# the screen's bottom edge).
func _reserve_bottom_row(from_bottom: float, node_name: String) -> Control:
	var slot := _reserve_row(Vector2.ZERO, node_name)
	_anchor_bottom(slot, from_bottom, from_bottom, _VIEWPORT_W)
	return slot


# Localization stub (mirrors CoachOverlay._tr). Replace this call site when a real
# l10n system lands; keeps user-facing strings out of inline literals.
func _tr(key: String) -> String:
	match key:
		"result_win_title": return "WELL DONE!"
		"result_claim": return "TAP TO CLAIM"
		"result_lose_title": return "GAME OVER"
		"result_lose_reason": return "The discard row filled up."
		"result_retry": return "RETRY"
		_:
			push_warning("ResultScreen: unknown localization key '%s'" % key)
			return key
