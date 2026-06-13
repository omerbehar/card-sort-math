class_name UnlockPopup
extends PopupBase
## Locked-deck unlock prompt (prototype: locked-decks). Tapping a locked stack
## opens this modal, which offers two ways to add the deck: watch a (stubbed)
## rewarded ad, or pay with game coins. Mirrors the two-button "CONTINUE?"
## reference layout (REVIVE = ad, PLAY ON = currency).
##
## A [PopupBase] subclass (ADR-0006): the base owns the modal chassis (backdrop,
## input capture, open/close animation, lifecycle); this class only builds the
## content into [method body] and emits intent signals. View only (ADR-0001) — it
## owns no game state and performs no transaction; [code]main.gd[/code] decides
## whether the unlock can be afforded and runs it through [WalletService].
##
## The ad path is a prototype stub (free unlock, no SDK — ads are deferred to M4);
## the coin path spends real coins via [WalletService]. Compliance gating of the ad
## offer (ADR-0005) is intentionally deferred — both options always show for now.

## Player chose the rewarded-ad unlock (prototype stub — free for now).
signal watch_ad_pressed
## Player chose to pay coins. [code]main.gd[/code] runs the [WalletService] spend.
signal pay_coins_pressed

const _VIEWPORT_W: float = 390.0

# Palette (matches ResultScreen so the pop-up family reads as one skin).
const _CARD_BG := Color(0.97, 0.94, 0.87)
const _HEADER_BLUE := Color(0.27, 0.52, 0.95)
const _GREEN := Color(0.30, 0.78, 0.34)
const _GREEN_DEEP := Color(0.20, 0.58, 0.24)
const _GOLD := Color(1.0, 0.80, 0.12)
const _GOLD_DEEP := Color(0.85, 0.58, 0.05)
const _RED := Color(0.90, 0.27, 0.27)
const _RED_DEEP := Color(0.72, 0.18, 0.18)
const _GREY := Color(0.62, 0.64, 0.70)        # disabled (unaffordable) pay button
const _GREY_DEEP := Color(0.45, 0.47, 0.52)
const _INK := Color(0.12, 0.14, 0.22)


## Builds the prompt for an unlock costing [param cost] coins and plays the open
## animation. [param can_afford] greys/disables the pay button when the player
## cannot cover the cost (the ad option stays available). [param title] and
## [param subtitle] override the default locked-deck copy so the same modal can
## front the buff-restock flow; empty strings keep the deck defaults. Call once
## after instancing and after adding to the tree.
func setup(cost: int, can_afford: bool, title: String = "", subtitle: String = "") -> void:
	var title_text: String = title if title != "" else _tr("unlock_title")
	var subtitle_text: String = subtitle if subtitle != "" else _tr("unlock_subtitle")
	var pw: float = 336.0
	var ph: float = 300.0
	var px: float = (_VIEWPORT_W - pw) * 0.5
	var py: float = 260.0

	# Card body (rounded, light, drop shadow) + coloured header strip.
	var card := _panel(_CARD_BG, 22, 22, 22, 22, true)
	card.name = "Panel"
	card.position = Vector2(px, py)
	card.size = Vector2(pw, ph)
	body().add_child(card)

	var header := _panel(_HEADER_BLUE, 22, 22, 0, 0, false)
	header.position = Vector2(px, py)
	header.size = Vector2(pw, 64.0)
	body().add_child(header)
	UiFactory.label(body(), title_text, Vector2(px, py),
		Vector2(pw, 64.0), 28, Color.WHITE)

	# Close (X) at the panel's top-right corner → dismiss (no unlock).
	var close := _action_button("✕", _RED, _RED_DEEP, func() -> void: close())
	close.size = Vector2(46.0, 46.0)
	close.position = Vector2(px + pw - 30.0, py - 18.0)

	# Big "+" deck glyph + one-line subtext (mirrors the reference "Add 1 box").
	UiFactory.label(body(), "➕", Vector2(px, py + 74.0), Vector2(pw, 84.0), 52, _GREEN)
	UiFactory.label(body(), subtitle_text, Vector2(px, py + 158.0),
		Vector2(pw, 26.0), 17, Color(0.32, 0.30, 0.36))

	# Two side-by-side options (REVIVE / PLAY ON layout): WATCH AD | PAY <cost>.
	var bw: float = (pw - 48.0 - 16.0) * 0.5   # two buttons, 24px side margins, 16px gap
	var bh: float = 64.0
	var by: float = py + ph - bh - 22.0

	var ad := _action_button(_tr("unlock_watch_ad"), _GOLD, _GOLD_DEEP,
		func() -> void: watch_ad_pressed.emit())
	ad.size = Vector2(bw, bh)
	ad.position = Vector2(px + 24.0, by)
	_add_ad_badge(ad)

	var pay := _action_button(_pay_label(cost),
		_GREEN if can_afford else _GREY,
		_GREEN_DEEP if can_afford else _GREY_DEEP,
		func() -> void: pay_coins_pressed.emit())
	pay.size = Vector2(bw, bh)
	pay.position = Vector2(px + 24.0 + bw + 16.0, by)
	if not can_afford:
		pay.disabled = true

	play_open()


# ---------------------------------------------------------------------------
# Builders (content goes into body(); the base owns the backdrop). Mirrors the
# small builder set ResultScreen keeps locally — the base is skin-agnostic.
# ---------------------------------------------------------------------------

func _pay_label(cost: int) -> String:
	return "%s %d" % [_tr("unlock_pay"), cost]


# A small red "▶" badge in the ad button's top-right corner, echoing the rewarded
# -ad marker on the reference REVIVE button.
func _add_ad_badge(button: Button) -> void:
	var badge := Label.new()
	badge.text = "▶"
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.size = Vector2(22.0, 22.0)
	badge.position = Vector2(button.size.x - 16.0, -8.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _RED
	sb.set_corner_radius_all(11)
	badge.add_theme_stylebox_override("normal", sb)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(badge)


func _action_button(text: String, bg: Color, deep: Color, on_press: Callable) -> Button:
	var button := _make_button(text, bg, deep, Color.WHITE)
	button.pressed.connect(on_press)
	body().add_child(button)
	return button


func _make_button(text: String, bg: Color, deep: Color, fg: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	var sb := _round_box(bg, 16)
	sb.border_width_bottom = 5             # chunky "3D" bottom edge
	sb.border_color = deep
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("hover", sb)
	button.add_theme_stylebox_override("disabled", sb)
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


# Localization stub (mirrors ResultScreen._tr / CoachOverlay._tr). Replace these
# call sites when a real l10n system lands; keeps user-facing strings out of
# inline literals (ui-code rule).
func _tr(key: String) -> String:
	match key:
		"unlock_title": return "ADD A DECK?"
		"unlock_subtitle": return "Unlock this stack to keep sorting."
		"unlock_watch_ad": return "WATCH AD"
		"unlock_pay": return "PAY"
		_:
			push_warning("UnlockPopup: unknown localization key '%s'" % key)
			return key
