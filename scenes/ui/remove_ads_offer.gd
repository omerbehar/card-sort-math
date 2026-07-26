class_name RemoveAdsOffer
extends PopupBase
## One-per-session Remove-Ads offer (S5-006) — a gentle, dismissible bottom sheet that
## anchors the Remove-Ads SKU and deep-links the Shop.
##
## Surfaced by main.gd at most once per session (after the first interstitial) and only
## when Remove-Ads is NOT already owned — the session cap + the owned check live in the
## controller; this view just presents the offer and emits intent. A thin view (ADR-0001):
## it reads the catalog price + the entitlement chokepoint and emits
## [signal shop_requested] / closes; it owns no state.
##
## Source: design/ux/monetization-ui.md §3.4 (Remove-Ads offer) · §7 (per-session cap).

## Emitted when the player taps the Remove-Ads CTA — the controller opens the Shop.
signal shop_requested

const _VIEWPORT_W: float = 390.0
const _VIEWPORT_H: float = 844.0
const _CATALOG_PATH := "res://assets/data/iap_catalog.tres"

const _SHEET_BG := Color(0.97, 0.96, 0.99)
const _HEADER_INK := Color(0.14, 0.16, 0.24)
const _SUBINK := Color(0.40, 0.43, 0.52)
const _GREEN := Color(0.30, 0.78, 0.34)
const _GREEN_DEEP := Color(0.20, 0.58, 0.24)
const _GREY := Color(0.72, 0.75, 0.80)
const _GREY_DEEP := Color(0.54, 0.57, 0.63)

var _entitlement = null
var _catalog: IAPCatalog = null
var _cta_button: Button = null   # the Remove-Ads CTA (null until built; stays null if owned)


## Injects the entitlement seam + catalog. Call before [method setup]; nulls resolve to the
## autoload / authored resource in [method setup].
func configure(entitlement: Object, catalog: IAPCatalog) -> void:
	_entitlement = entitlement
	_catalog = catalog


func setup() -> void:
	_resolve_defaults()
	# Defensive: never present the offer if Remove-Ads is already owned (the controller
	# also checks, but this keeps the component honest if reused elsewhere).
	if _entitlement != null and _entitlement.has_method("should_suppress_interstitials") \
			and _entitlement.should_suppress_interstitials():
		close()
		return
	_build_ui()
	backdrop_pressed.connect(close)   # tap-outside dismisses (main sets dismiss_on_backdrop)
	play_open()


func _resolve_defaults() -> void:
	if _entitlement == null:
		_entitlement = get_node_or_null(^"/root/EntitlementService")
	if _catalog == null:
		var res: Resource = load(_CATALOG_PATH)
		if res is IAPCatalog:
			_catalog = res


# The Remove-Ads SKU's localized price, or "" if the catalog has no entitlement entry.
func _remove_ads_price() -> String:
	if _catalog == null:
		return ""
	for e in _catalog.entries:
		if e != null and e.kind == IAPCatalogEntryResource.Kind.NON_CONSUMABLE_ENTITLEMENT:
			return e.price_display()
	return ""


func _build_ui() -> void:
	var sh: float = 196.0
	var sy: float = _VIEWPORT_H - sh

	var sheet := _panel(_SHEET_BG, 26, 26, 0, 0)
	sheet.position = Vector2(0.0, sy)
	sheet.size = Vector2(_VIEWPORT_W, sh + 20.0)   # +20 so the bottom radius runs off-screen
	body().add_child(sheet)

	UiFactory.label(body(), _tr("offer_title"), Vector2(24.0, sy + 22.0), Vector2(300.0, 32.0), 24, _HEADER_INK) \
		.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiFactory.label(body(), _tr("offer_body"), Vector2(24.0, sy + 60.0), Vector2(342.0, 26.0), 15, _SUBINK) \
		.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Primary CTA: Remove Ads + price → open the Shop.
	var price: String = _remove_ads_price()
	var cta_text: String = _tr("offer_cta") if price.is_empty() else "%s · %s" % [_tr("offer_cta"), price]
	var cta := _button(cta_text, _GREEN, _GREEN_DEEP, func() -> void:
		shop_requested.emit()
		close())
	cta.size = Vector2(_VIEWPORT_W - 48.0, 54.0)
	cta.position = Vector2(24.0, sy + 104.0)
	_cta_button = cta

	# Dismiss (secondary, quiet) — "Not now".
	var dismiss := _button(_tr("offer_dismiss"), _GREY, _GREY_DEEP, close)
	dismiss.size = Vector2(_VIEWPORT_W - 48.0, 30.0)
	dismiss.position = Vector2(24.0, sy + 162.0)
	dismiss.add_theme_font_size_override("font_size", 15)


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

func _button(text: String, bg: Color, deep: Color, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
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
	sb.shadow_size = 12
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
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
		"offer_title": return "Tired of ads?"
		"offer_body": return "Remove interstitials — keep your rewarded ads."
		"offer_cta": return "Remove Ads"
		"offer_dismiss": return "Not now"
		_:
			push_warning("RemoveAdsOffer: unknown localization key '%s'" % key)
			return key
