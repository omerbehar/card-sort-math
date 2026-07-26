class_name AgeGate
extends PopupBase
## First-run neutral age gate (S6-001, ADR-0005).
##
## A non-leading birth-year entry shown once on first launch (when
## [member SaveData.age_band] is UNKNOWN), before any personal-data collection. It is
## deliberately NOT a leading "are you 13+?" prompt — it collects a birth year and the
## controller maps it to an [enum SaveData.AgeBand] via
## [method ComplianceService.age_band_for_birth_year], which drives the whole ad/analytics/
## IAP posture (13+ → ADULT full experience; under-13 → CHILD child-safe).
##
## View only (ADR-0001): it collects the year and emits [signal age_submitted]; the
## controller owns the policy mapping + persistence ([SaveService.set_age_band]). Not
## dismissable — the player must answer before playing (no backdrop dismiss, no close X).
##
## Source: design/ux/compliance-ui.md (S6-000) · ADR-0005 · ADR-0013.

## Emitted when the player confirms their birth year. The controller maps it to a band and
## persists it, then closes the gate and proceeds.
signal age_submitted(birth_year: int)

const _VIEWPORT_W: float = 390.0
const _MIN_YEAR: int = 1900
const _DEFAULT_OFFSET: int = 20   # neutral starting year (current − 20); the player adjusts

const _CARD_BG := Color(0.97, 0.96, 0.99)
const _HEADER_BLUE := Color(0.27, 0.52, 0.95)
const _GREEN := Color(0.30, 0.78, 0.34)
const _GREEN_DEEP := Color(0.20, 0.58, 0.24)
const _STEP := Color(0.80, 0.84, 0.92)
const _STEP_DEEP := Color(0.60, 0.64, 0.72)
const _INK := Color(0.14, 0.16, 0.24)
const _SUBINK := Color(0.42, 0.45, 0.54)

var _current_year: int = 2026
var _year: int = 2006
var _year_label: Label = null


func _init() -> void:
	# A first-run gate: opaque, undismissable (no backdrop dismiss).
	backdrop_color = Color(0.10, 0.12, 0.20, 0.97)


## Builds the gate for [param current_year] (injected so it's deterministic in tests) and
## plays the open animation. Call once after instancing and adding to the tree.
func setup(current_year: int) -> void:
	_current_year = current_year
	_year = clampi(current_year - _DEFAULT_OFFSET, _MIN_YEAR, current_year)
	_build_ui()
	play_open()


func _build_ui() -> void:
	var px: float = 35.0
	var py: float = 232.0
	var pw: float = 320.0
	var ph: float = 372.0

	var card := _panel(_CARD_BG, 24, 24, 24, 24)
	card.position = Vector2(px, py)
	card.size = Vector2(pw, ph)
	body().add_child(card)

	var header := _panel(_HEADER_BLUE, 24, 24, 0, 0)
	header.position = Vector2(px, py)
	header.size = Vector2(pw, 58.0)
	body().add_child(header)
	UiFactory.label(body(), _tr("gate_title"), Vector2(px, py), Vector2(pw, 58.0), 24, Color.WHITE)

	# Neutral, non-leading prompt.
	UiFactory.label(body(), _tr("gate_prompt"), Vector2(px, py + 78.0), Vector2(pw, 30.0), 20, _INK)

	# Birth-year stepper:  [ − ]   YYYY   [ + ]
	var minus := _make_button("−", _STEP, _STEP_DEEP, _INK)
	minus.size = Vector2(58.0, 58.0)
	minus.position = Vector2(px + 26.0, py + 128.0)
	minus.pressed.connect(func() -> void: _set_year(_year - 1))
	body().add_child(minus)

	_year_label = UiFactory.label(body(), "", Vector2(px + 92.0, py + 128.0), Vector2(pw - 184.0, 58.0), 40, _INK)

	var plus := _make_button("+", _STEP, _STEP_DEEP, _INK)
	plus.size = Vector2(58.0, 58.0)
	plus.position = Vector2(px + pw - 84.0, py + 128.0)
	plus.pressed.connect(func() -> void: _set_year(_year + 1))
	body().add_child(plus)

	# Two explicit centered lines (autowrap on a programmatically-sized Label is unreliable).
	UiFactory.label(body(), _tr("gate_note"), Vector2(px, py + 202.0), Vector2(pw, 48.0), 14, _SUBINK)

	var confirm := _make_button(_tr("gate_confirm"), _GREEN, _GREEN_DEEP, Color.WHITE)
	confirm.size = Vector2(pw - 48.0, 54.0)
	confirm.position = Vector2(px + 24.0, py + 292.0)
	confirm.pressed.connect(_on_confirm)
	body().add_child(confirm)

	_set_year(_year)


func _set_year(y: int) -> void:
	_year = clampi(y, _MIN_YEAR, _current_year)
	if _year_label != null:
		_year_label.text = str(_year)


func _on_confirm() -> void:
	age_submitted.emit(_year)
	close()


# ---------------------------------------------------------------------------
# Builders (mirrors the other PopupBase surfaces)
# ---------------------------------------------------------------------------

func _make_button(text: String, bg: Color, deep: Color, fg: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	var sb := _round_box(bg, 14)
	sb.border_width_bottom = 4
	sb.border_color = deep
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("hover", sb)
	button.add_theme_stylebox_override("pressed", _round_box(deep, 14))
	return button


func _panel(bg: Color, tl: int, tr: int, bl: int, br: int) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = tl
	sb.corner_radius_top_right = tr
	sb.corner_radius_bottom_left = bl
	sb.corner_radius_bottom_right = br
	sb.shadow_size = 10
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
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
		"gate_title": return "Before you play"
		"gate_prompt": return "When were you born?"
		"gate_note": return "We ask once, to keep the\nexperience age-appropriate."
		"gate_confirm": return "Continue"
		_:
			push_warning("AgeGate: unknown localization key '%s'" % key)
			return key
