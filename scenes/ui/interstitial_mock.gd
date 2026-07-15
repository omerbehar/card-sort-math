class_name InterstitialMock
extends PopupBase
## Mock full-screen interstitial (S5-005).
##
## Presented by [code]main.gd[/code] ONLY when [method AdService.maybe_show_interstitial]
## returns [code]SHOWN[/code] — never mid-puzzle, and respecting the frequency cap +
## Remove-Ads suppression (AdService owns those gates; this view shows nothing on any
## SUPPRESSED_* / NO_FILL outcome). A placeholder stand-in until a real ad SDK lands
## (device sprint): a full-screen "ad" with a close affordance that appears after a short
## beat; closing resumes the between-levels flow.
##
## View only (ADR-0001): it owns no ad/economy state and emits only [signal PopupBase.closed].
##
## Source: design/ux/monetization-ui.md §3.4 · AC-6.

const _VIEWPORT_W: float = 390.0
const _CLOSE_DELAY: float = 1.2   # the "ad" beat before the close affordance appears
const _PANEL := Color(0.16, 0.19, 0.30)
const _ACCENT := Color(0.38, 0.64, 1.0)
const _INK := Color(0.92, 0.94, 1.0)
const _SUBINK := Color(0.62, 0.67, 0.80)

var _close_btn: Button = null


func _init() -> void:
	# Opaque backdrop — a full-screen ad, not a translucent modal. Taps do nothing until
	# the close affordance appears (dismiss_on_backdrop stays false).
	backdrop_color = Color(0.06, 0.07, 0.12, 1.0)


## Builds the mock ad, plays the open animation, and schedules the close affordance.
func setup() -> void:
	_build_ui()
	play_open()
	_schedule_close_affordance()


func _build_ui() -> void:
	# Small "Advertisement" tag (top), like a real interstitial's disclosure.
	UiFactory.label(body(), _tr("ad_tag"), Vector2(0.0, 40.0), Vector2(_VIEWPORT_W, 24.0), 15, _SUBINK)

	# Centre "creative" placeholder card.
	var cx: float = 45.0
	var cy: float = 250.0
	var cw: float = 300.0
	var ch: float = 320.0
	var card := _panel(_PANEL, 24)
	card.position = Vector2(cx, cy)
	card.size = Vector2(cw, ch)
	body().add_child(card)

	UiFactory.label(body(), "▶", Vector2(cx, cy + 44.0), Vector2(cw, 120.0), 96, _ACCENT)
	UiFactory.label(body(), _tr("ad_title"), Vector2(cx, cy + 176.0), Vector2(cw, 40.0), 30, _INK)
	UiFactory.label(body(), _tr("ad_body"), Vector2(cx, cy + 224.0), Vector2(cw, 28.0), 16, _SUBINK)

	# Close (X), hidden until the beat elapses.
	_close_btn = _make_button("✕", Color(0.90, 0.27, 0.27), Color(0.72, 0.18, 0.18))
	_close_btn.size = Vector2(46.0, 46.0)
	_close_btn.position = Vector2(_VIEWPORT_W - 60.0, 44.0)
	_close_btn.pressed.connect(close)
	_close_btn.visible = false
	body().add_child(_close_btn)


# Reveals the close affordance after the ad beat (kept even under reduced motion — the
# beat models the un-skippable window of a real interstitial).
func _schedule_close_affordance() -> void:
	var t := create_tween()
	t.tween_interval(_CLOSE_DELAY)
	t.tween_callback(_reveal_close)


func _reveal_close() -> void:
	if _close_btn != null:
		_close_btn.visible = true


func _panel(bg: Color, radius: int) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _make_button(text: String, bg: Color, deep: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(8)
	sb.border_width_bottom = 5
	sb.border_color = deep
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("hover", sb)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = deep
	pressed.set_corner_radius_all(14)
	pressed.set_content_margin_all(8)
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _tr(key: String) -> String:
	match key:
		"ad_tag": return "Advertisement"
		"ad_title": return "Mock Interstitial"
		"ad_body": return "Your ad could be here"
		_:
			push_warning("InterstitialMock: unknown localization key '%s'" % key)
			return key
