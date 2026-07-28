class_name ConsentSheet
extends PopupBase
## Consent capture sheet (S6-002, ADR-0013) — shown after the age gate for a declared 13+
## player, and re-openable from Settings (S6-003).
##
## Three explicit, DEFAULT-OFF toggles (personalized ads / analytics / IAP) — protected
## fields are never pre-granted. A thin view (ADR-0001): it collects choices and calls
## [method SaveService.capture_consent]; [ComplianceService] remains the sole reader whose
## verdicts flip live on the next query. Injectable save for tests; defaults to the autoload.
##
## Source: design/ux/compliance-ui.md §3.2 · ADR-0013.

## Emitted after choices are written (Save or decline-all), with the captured values.
signal consent_saved(personalized_ads: bool, analytics: bool, iap: bool)

const _VIEWPORT_W: float = 390.0
const _CARD_BG := Color(0.97, 0.96, 0.99)
const _ROW_BG := Color(0.99, 0.99, 1.0)
const _HEADER_BLUE := Color(0.27, 0.52, 0.95)
const _GREEN := Color(0.30, 0.78, 0.34)
const _GREEN_DEEP := Color(0.20, 0.58, 0.24)
const _GREY := Color(0.70, 0.74, 0.80)
const _GREY_DEEP := Color(0.52, 0.56, 0.62)
const _INK := Color(0.14, 0.16, 0.24)
const _SUBINK := Color(0.42, 0.45, 0.54)

# key → SaveData/capture_consent argument order. Rendered top-to-bottom.
const _FIELDS: Array = [
	{key = "personalized_ads", title = "Personalized ads", sub = "Ads matched to your interests"},
	{key = "analytics", title = "Analytics", sub = "Anonymous usage data"},
	{key = "iap", title = "Store purchases", sub = "Enable in-app purchases"},
]

var _save = null
var _consent: Dictionary = {"personalized_ads": false, "analytics": false, "iap": false}
var _toggles: Dictionary = {}   # key -> Button
var _save_button: Button = null
var _decline_button: Button = null


## Injects the save service (tests); defaults to the SaveService autoload in [method setup].
func configure(save: Object) -> void:
	_save = save


## Pre-populates the toggles (for Settings "Manage" — S6-003). Call before [method setup].
func set_initial(personalized_ads: bool, analytics: bool, iap: bool) -> void:
	_consent["personalized_ads"] = personalized_ads
	_consent["analytics"] = analytics
	_consent["iap"] = iap


func setup() -> void:
	if _save == null:
		_save = get_node_or_null(^"/root/SaveService")
	_build_ui()
	play_open()


func _build_ui() -> void:
	var px: float = 25.0
	var py: float = 150.0
	var pw: float = 340.0
	var ph: float = 540.0

	var card := _panel(_CARD_BG, 24, 24, 24, 24)
	card.position = Vector2(px, py)
	card.size = Vector2(pw, ph)
	body().add_child(card)

	var header := _panel(_HEADER_BLUE, 24, 24, 0, 0)
	header.position = Vector2(px, py)
	header.size = Vector2(pw, 58.0)
	body().add_child(header)
	UiFactory.label(body(), _tr("consent_title"), Vector2(px, py), Vector2(pw, 58.0), 23, Color.WHITE)

	# Two explicit centered lines (autowrap on a programmatically-sized Label is unreliable).
	UiFactory.label(body(), _tr("consent_intro"), Vector2(px, py + 66.0), Vector2(pw, 46.0), 14, _SUBINK)

	# Three default-off toggle rows.
	var row_y: float = py + 128.0
	for field in _FIELDS:
		_build_row(px, row_y, pw, field)
		row_y += 96.0

	# Save choices → capture the current toggle state.
	_save_button = _button(_tr("consent_save"), _GREEN, _GREEN_DEEP, Color.WHITE,
		func() -> void: _commit(_consent["personalized_ads"], _consent["analytics"], _consent["iap"]))
	_save_button.size = Vector2(pw - 48.0, 52.0)
	_save_button.position = Vector2(px + 24.0, py + ph - 116.0)

	# Not now → decline all (still captured).
	_decline_button = _button(_tr("consent_decline"), _GREY, _GREY_DEEP, Color.WHITE,
		func() -> void: _commit(false, false, false))
	_decline_button.size = Vector2(pw - 48.0, 40.0)
	_decline_button.position = Vector2(px + 24.0, py + ph - 54.0)
	_decline_button.add_theme_font_size_override("font_size", 15)


func _build_row(px: float, y: float, pw: float, field: Dictionary) -> void:
	var row := _panel(_ROW_BG, 14, 14, 14, 14)
	row.position = Vector2(px + 16.0, y)
	row.size = Vector2(pw - 32.0, 82.0)
	body().add_child(row)

	UiFactory.label(row, field.title, Vector2(16.0, 12.0), Vector2(pw - 140.0, 26.0), 18, _INK) \
		.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiFactory.label(row, field.sub, Vector2(16.0, 44.0), Vector2(pw - 140.0, 24.0), 13, _SUBINK) \
		.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var toggle := _make_toggle(field.key)
	toggle.size = Vector2(74.0, 44.0)
	toggle.position = Vector2(pw - 32.0 - 90.0, 19.0)
	row.add_child(toggle)


func _make_toggle(key: String) -> Button:
	var btn := Button.new()
	_toggles[key] = btn
	btn.pressed.connect(func() -> void:
		_consent[key] = not _consent[key]
		_style_toggle(key))
	_style_toggle(key)
	return btn


func _style_toggle(key: String) -> void:
	var btn: Button = _toggles[key]
	var on: bool = _consent[key]
	btn.text = _tr("toggle_on") if on else _tr("toggle_off")
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	var bg: Color = _GREEN if on else _GREY
	var deep: Color = _GREEN_DEEP if on else _GREY_DEEP
	var sb := _round_box(bg, 20)
	sb.border_width_bottom = 3
	sb.border_color = deep
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", _round_box(deep, 20))


func _commit(personalized_ads: bool, analytics: bool, iap: bool) -> void:
	if _save != null and _save.has_method("capture_consent"):
		_save.capture_consent(personalized_ads, analytics, iap)
	consent_saved.emit(personalized_ads, analytics, iap)
	close()


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

func _button(text: String, bg: Color, deep: Color, fg: Color, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	var sb := _round_box(bg, 14)
	sb.border_width_bottom = 4
	sb.border_color = deep
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("hover", sb)
	button.add_theme_stylebox_override("pressed", _round_box(deep, 14))
	button.pressed.connect(on_press)
	body().add_child(button)
	return button


func _panel(bg: Color, tl: int, tr: int, bl: int, br: int) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = tl
	sb.corner_radius_top_right = tr
	sb.corner_radius_bottom_left = bl
	sb.corner_radius_bottom_right = br
	sb.shadow_size = 6
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _round_box(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(6)
	return sb


func _tr(key: String) -> String:
	match key:
		"consent_title": return "Your privacy choices"
		"consent_intro": return "You're in control. Choose what to allow\n— change it anytime in Settings."
		"consent_save": return "Save choices"
		"consent_decline": return "Not now"
		"toggle_on": return "ON"
		"toggle_off": return "OFF"
		_:
			push_warning("ConsentSheet: unknown localization key '%s'" % key)
			return key
