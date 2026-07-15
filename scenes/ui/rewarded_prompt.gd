class_name RewardedPrompt
extends PopupBase
## Opt-in "watch a rewarded ad" prompt (S5-004) — the reusable component behind the
## result-screen bonus-coins offer (and, later, booster/near-loss attach points).
##
## A thin view (ADR-0001): it presents the offer and, on confirm, asks
## [method AdService.show_rewarded]; the service owns the ad presentation, the daily/
## compliance gate, and the [WalletService] credit. The reward amount is read from the
## service ([method AdService.rewarded_reward_amount]), never hardcoded. Rewarded is
## always opt-in and never auto-shown — the attach point only reveals the offer when
## [method AdService.is_rewarded_available] (S5-004 AC-5).
##
## Dependencies are injected via [method configure] (mirroring the M4 services) so the
## prompt is integration-testable with fakes; in normal play it resolves the autoloads.
##
## Source: design/ux/monetization-ui.md §3.3 · AC-5.

## Emitted when a rewarded view credited coins (the attach point may animate reward chips).
signal reward_earned(coins: int)

const _VIEWPORT_W: float = 390.0
const _CARD_BG := Color(0.97, 0.94, 0.87)
const _HEADER_BLUE := Color(0.27, 0.52, 0.95)
const _GREEN := Color(0.30, 0.78, 0.34)
const _GREEN_DEEP := Color(0.20, 0.58, 0.24)
const _GREY := Color(0.62, 0.66, 0.72)
const _GREY_DEEP := Color(0.46, 0.50, 0.56)
const _GOLD := Color(0.98, 0.74, 0.10)
const _INK := Color(0.12, 0.14, 0.22)
const _RESULT_HOLD: float = 0.9   # how long the outcome shows before auto-close

# Injected seams (resolve to autoloads in _resolve_defaults()).
var _ad = null
var _analytics = null

# Optional caller-supplied offer text (defaults to "+N coins" from the service).
var _offer_text: String = ""

var _reward_label: Label = null
var _watch_btn: Button = null
var _decline_btn: Button = null
var _resolved: bool = false


## Injects the AdService + AnalyticsService seams and an optional offer label. Call before
## [method setup]. Any null is resolved from the matching autoload in [method setup].
func configure(ad: Object, analytics: Object, offer_text: String = "") -> void:
	_ad = ad
	_analytics = analytics
	_offer_text = offer_text


## Builds the prompt into the pop-up body and plays the open animation. Call once after
## instancing and adding to the tree.
func setup() -> void:
	_resolve_defaults()
	_build_ui()
	backdrop_pressed.connect(close)   # tap-outside declines (main sets dismiss_on_backdrop)
	play_open()


func _resolve_defaults() -> void:
	if _ad == null:
		_ad = get_node_or_null(^"/root/AdService")
	if _analytics == null:
		_analytics = get_node_or_null(^"/root/AnalyticsService")


func _reward_amount() -> int:
	if _ad != null and _ad.has_method("rewarded_reward_amount"):
		return _ad.rewarded_reward_amount()
	return 0


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var px: float = 45.0
	var py: float = 274.0
	var pw: float = 300.0
	var ph: float = 300.0

	var card := _panel(_CARD_BG, 22, 22, 22, 22, true)
	card.position = Vector2(px, py)
	card.size = Vector2(pw, ph)
	body().add_child(card)

	var header := _panel(_HEADER_BLUE, 22, 22, 0, 0, false)
	header.position = Vector2(px, py)
	header.size = Vector2(pw, 56.0)
	body().add_child(header)
	UiFactory.label(body(), _tr("reward_title"), Vector2(px, py), Vector2(pw, 56.0), 26, Color.WHITE)

	UiFactory.label(body(), _tr("reward_prompt"), Vector2(px, py + 74.0), Vector2(pw, 26.0), 17, _INK)

	# The offer amount — read from the service, or the caller's custom text.
	var offer: String = _offer_text if not _offer_text.is_empty() else "+%d coins" % _reward_amount()
	_reward_label = UiFactory.label(body(), offer, Vector2(px, py + 104.0), Vector2(pw, 56.0), 40, _GOLD)

	_watch_btn = _action_button(_tr("reward_watch"), _GREEN, _GREEN_DEEP, _on_watch)
	_watch_btn.size = Vector2(240.0, 54.0)
	_watch_btn.position = Vector2(px + (pw - 240.0) * 0.5, py + 176.0)

	_decline_btn = _action_button(_tr("reward_decline"), _GREY, _GREY_DEEP, close)
	_decline_btn.size = Vector2(200.0, 42.0)
	_decline_btn.position = Vector2(px + (pw - 200.0) * 0.5, py + 240.0)


# ---------------------------------------------------------------------------
# Flow
# ---------------------------------------------------------------------------

func _on_watch() -> void:
	if _resolved or _ad == null:
		return
	_resolved = true
	_watch_btn.disabled = true
	_decline_btn.disabled = true

	# The service owns presentation + the credit; it returns the coins actually credited
	# (0 when unavailable / abandoned / capped — no view is spent for nothing).
	var credited: int = _ad.show_rewarded() if _ad.has_method("show_rewarded") else 0
	if credited > 0:
		if _analytics != null and _analytics.has_method("track_ad_reward"):
			_analytics.track_ad_reward(credited)
		reward_earned.emit(credited)
		_finish("+%d coins!" % credited, _GOLD)
	else:
		_finish(_tr("reward_none"), _INK)


# Shows the outcome briefly, then auto-closes. Hides the action buttons so the result
# reads cleanly.
func _finish(text: String, color: Color) -> void:
	if _reward_label != null:
		_reward_label.text = text
		_reward_label.add_theme_color_override("font_color", color)
	_watch_btn.visible = false
	_decline_btn.visible = false
	var t := create_tween()
	t.tween_interval(_RESULT_HOLD)
	t.tween_callback(close)


# ---------------------------------------------------------------------------
# Builders (mirrors result_screen.gd)
# ---------------------------------------------------------------------------

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
	var sb := _round_box(bg, 14)
	sb.border_width_bottom = 5
	sb.border_color = deep
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("hover", sb)
	button.add_theme_stylebox_override("pressed", _round_box(deep, 14))
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
	sb.set_content_margin_all(8)
	return sb


func _tr(key: String) -> String:
	match key:
		"reward_title": return "FREE COINS"
		"reward_prompt": return "Watch a short ad for"
		"reward_watch": return "▶  Watch"
		"reward_decline": return "No thanks"
		"reward_none": return "No reward this time"
		_:
			push_warning("RewardedPrompt: unknown localization key '%s'" % key)
			return key
