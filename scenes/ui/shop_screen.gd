class_name ShopScreen
extends PopupBase
## The in-game store (S5-003) — renders the [IAPCatalog] as purchasable offer cards
## and drives [IAPService].purchase / restore.
##
## A thin view (ADR-0001): it reads catalog + entitlement state and emits purchase
## intent to the injected services; the services own every economy/entitlement/consent
## decision. Remove-Ads "Owned" is read through
## [method EntitlementService.should_suppress_interstitials] — never the
## [member SaveData.remove_ads_owned] field (single-reader chokepoint, ADR-0014 §3).
##
## Dependencies are injected via [method configure] (mirroring the M4 services) so the
## screen is integration-testable with fakes; in normal play [code]main.gd[/code] wires
## the autoloads + the authored [code]assets/data/iap_catalog.tres[/code].
##
## Source: design/ux/monetization-ui.md §3.2 · AC-2/3/4/7.

const _VIEWPORT_W: float = 390.0
const _CATALOG_PATH := "res://assets/data/iap_catalog.tres"
# Preloaded so the State enum resolves without depending on the autoload's identity.
const _IAP := preload("res://autoloads/iap_service.gd")

# Palette (aligned with result_screen.gd's language).
const _SHEET_BG := Color(0.93, 0.95, 0.99)
const _CARD_BG := Color(0.98, 0.96, 0.90)
const _ANCHOR_BG := Color(0.99, 0.90, 0.55)   # Remove-Ads anchor card (warm)
const _HEADER_BLUE := Color(0.27, 0.52, 0.95)
const _GREEN := Color(0.30, 0.78, 0.34)
const _GREEN_DEEP := Color(0.20, 0.58, 0.24)
const _GREY := Color(0.62, 0.66, 0.72)
const _GREY_DEEP := Color(0.46, 0.50, 0.56)
const _RED := Color(0.90, 0.27, 0.27)
const _RED_DEEP := Color(0.72, 0.18, 0.18)
const _INK := Color(0.12, 0.14, 0.22)
const _SUBINK := Color(0.36, 0.38, 0.46)

# Injected services (resolve to autoloads in _resolve_defaults()).
var _iap = null
var _entitlement = null
var _analytics = null
var _compliance = null   # ComplianceService: child-safe / consent gating (S6-004)
var _catalog: IAPCatalog = null

# Per-SKU buy Button + entry so completion handlers can restyle the right card.
var _buy_buttons: Dictionary = {}   # sku_id -> Button
var _entries: Dictionary = {}       # sku_id -> IAPCatalogEntryResource
var _toast_label: Label = null


## Injects the service seams + catalog. Call before [method setup]. Any argument left
## null is resolved from the matching autoload / authored resource in [method setup].
func configure(iap: Object, entitlement: Object, analytics: Object, catalog: IAPCatalog, compliance: Object = null) -> void:
	_iap = iap
	_entitlement = entitlement
	_analytics = analytics
	_catalog = catalog
	_compliance = compliance


## Builds the store content into the pop-up body, wires the services, and plays the
## open animation. Call once after instancing and adding to the tree.
func setup() -> void:
	_resolve_defaults()
	_build_ui()
	_connect_services()
	_refresh_owned()
	backdrop_pressed.connect(close)   # tap-outside closes (main sets dismiss_on_backdrop)
	play_open()


func _resolve_defaults() -> void:
	if _iap == null:
		_iap = get_node_or_null(^"/root/IAPService")
	if _entitlement == null:
		_entitlement = get_node_or_null(^"/root/EntitlementService")
	if _analytics == null:
		_analytics = get_node_or_null(^"/root/AnalyticsService")
	if _compliance == null:
		_compliance = get_node_or_null(^"/root/ComplianceService")
	if _catalog == null:
		var res: Resource = load(_CATALOG_PATH)
		if res is IAPCatalog:
			_catalog = res


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var sx: float = 15.0
	var sy: float = 64.0
	var sw: float = 360.0
	var sh: float = 724.0

	# Sheet + rounded header strip.
	var sheet := _panel(_SHEET_BG, 24, 24, 24, 24, true)
	sheet.position = Vector2(sx, sy)
	sheet.size = Vector2(sw, sh)
	body().add_child(sheet)

	var header := _panel(_HEADER_BLUE, 24, 24, 0, 0, false)
	header.position = Vector2(sx, sy)
	header.size = Vector2(sw, 58.0)
	body().add_child(header)
	UiFactory.label(body(), _tr("shop_title"), Vector2(sx, sy), Vector2(sw, 58.0), 28, Color.WHITE)

	# Close (X) → close.
	var close_btn := _action_button("✕", _RED, _RED_DEEP, close)
	close_btn.size = Vector2(44.0, 44.0)
	close_btn.position = Vector2(sx + sw - 52.0, sy + 8.0)

	# Scrollable list of offer cards.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(sx + 12.0, sy + 74.0)
	scroll.size = Vector2(sw - 24.0, 556.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body().add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	# S6-004: a child sees a calm parental-gate notice above the offers.
	if _is_child_restricted():
		list.add_child(_child_banner())

	for entry in _catalog_entries():
		list.add_child(_build_card(entry))

	# Toast (transient result message) + Restore button.
	_toast_label = UiFactory.label(body(), "", Vector2(sx, sy + 636.0), Vector2(sw, 34.0), 18, _INK)
	_toast_label.visible = false

	var restore := _action_button(_tr("shop_restore"), _GREY, _GREY_DEEP, _on_restore_pressed)
	restore.size = Vector2(280.0, 48.0)
	restore.position = Vector2((_VIEWPORT_W - 280.0) * 0.5, sy + 674.0)


# Catalog entries in render order: the Remove-Ads anchor first, then everything else in
# authored order (currency packs + bundle). Non-entitlement order is preserved.
func _catalog_entries() -> Array:
	var anchors: Array = []
	var rest: Array = []
	if _catalog == null:
		return rest
	for e in _catalog.entries:
		if e == null:
			continue
		if e.kind == IAPCatalogEntryResource.Kind.NON_CONSUMABLE_ENTITLEMENT:
			anchors.append(e)
		else:
			rest.append(e)
	return anchors + rest


func _build_card(entry) -> Control:
	var is_entitlement: bool = entry.kind == IAPCatalogEntryResource.Kind.NON_CONSUMABLE_ENTITLEMENT
	var card := _panel(_ANCHOR_BG if is_entitlement else _CARD_BG, 16, 16, 16, 16, true)
	card.custom_minimum_size = Vector2(0.0, 88.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_card_text(card, entry.display_name, Vector2(16.0, 12.0), 20, _INK)
	_card_text(card, entry.grant_summary, Vector2(16.0, 48.0), 15, _SUBINK)

	# Buy button (price), right-aligned inside the card.
	var buy := _make_button(entry.price_display(), _GREEN, _GREEN_DEEP, Color.WHITE)
	buy.size = Vector2(96.0, 46.0)
	buy.position = Vector2(220.0, 21.0)
	buy.pressed.connect(func() -> void: _on_buy_pressed(entry.sku_id))
	card.add_child(buy)

	_buy_buttons[entry.sku_id] = buy
	_entries[entry.sku_id] = entry
	return card


# A left-aligned card text row that stops before the buy button, ellipsizing a long
# grant summary (measured against the real font) so it never renders under the price.
const _CARD_TEXT_W: float = 196.0

func _card_text(card: Control, text: String, pos: Vector2, font_size: int, color: Color) -> void:
	var lbl := UiFactory.label(card, "", pos, Vector2(_CARD_TEXT_W, 30.0), font_size, color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.clip_text = true
	lbl.text = _ellipsize(lbl, text, font_size)


# Trims [param text] to fit _CARD_TEXT_W at [param font_size], appending "…" on overflow.
func _ellipsize(lbl: Label, text: String, font_size: int) -> String:
	var font: Font = lbl.get_theme_font(&"font")
	if font == null:
		return text
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= _CARD_TEXT_W:
		return text
	var t: String = text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > _CARD_TEXT_W:
		t = t.substr(0, t.length() - 1)
	return t.strip_edges() + "…"


# ---------------------------------------------------------------------------
# Purchase / restore flow
# ---------------------------------------------------------------------------

func _connect_services() -> void:
	if _iap != null:
		if _iap.has_signal("purchase_completed"):
			_iap.purchase_completed.connect(_on_purchase_completed)
		if _iap.has_signal("restore_completed"):
			_iap.restore_completed.connect(_on_restore_completed)
	if _entitlement != null and _entitlement.has_signal("remove_ads_changed"):
		_entitlement.remove_ads_changed.connect(func(_owned: bool) -> void: _refresh_owned())


func _on_buy_pressed(sku: int) -> void:
	if _iap == null or not _entries.has(sku):
		return
	# S6-004 child-safe: an under-13 (restricted) player's purchases sit behind a parental
	# gate. Surface a calm "ask a grown-up" cue instead of driving IAPService (which would
	# fail-closed on the compliance gate anyway) — the wallet is never touched.
	if _is_child_restricted():
		_show_toast(_tr("shop_parental_gate"))
		return
	# An adult who declined IAP consent can re-enable it in Settings → Privacy (S6-003), rather
	# than driving a purchase that fail-closes on the compliance gate with a generic error.
	if _iap_consent_denied():
		_show_toast(_tr("shop_consent_off"))
		return
	_set_pending(sku, true)
	# The mock backend resolves synchronously → purchase_completed fires within this
	# call and _on_purchase_completed restyles the card. An async backend leaves the
	# card disabled until the signal lands.
	_iap.purchase(sku)


func _on_purchase_completed(sku: int, outcome: int) -> void:
	if not is_inside_tree() or not _buy_buttons.has(sku):
		return
	var success: bool = outcome == _IAP.State.SUCCESS
	if _analytics != null and _analytics.has_method("track_iap_purchase"):
		_analytics.track_iap_purchase(sku, success)
	_set_pending(sku, false)
	if success:
		_show_toast(_tr("shop_purchase_ok"))
		if _entry_is_entitlement(sku):
			_mark_owned(sku)
	else:
		_show_toast(_tr("shop_purchase_fail"))


func _on_restore_pressed() -> void:
	if _iap != null and _iap.has_method("restore"):
		_iap.restore()


func _on_restore_completed(restored_count: int) -> void:
	if not is_inside_tree():
		return
	_refresh_owned()
	if restored_count > 0:
		_show_toast(_tr("shop_restore_done") % restored_count)
	else:
		_show_toast(_tr("shop_restore_none"))


# ---------------------------------------------------------------------------
# Card state
# ---------------------------------------------------------------------------

# Disables/re-enables a card's buy button while a purchase is in flight.
func _set_pending(sku: int, pending: bool) -> void:
	var btn: Button = _buy_buttons.get(sku)
	if btn == null or btn.text == _tr("shop_owned"):
		return
	btn.disabled = pending


# Flips a Remove-Ads card to the terminal "Owned ✓" state.
func _mark_owned(sku: int) -> void:
	var btn: Button = _buy_buttons.get(sku)
	if btn == null:
		return
	btn.text = _tr("shop_owned")
	btn.disabled = true
	var sb := _round_box(_GREY, 14)
	sb.border_width_bottom = 4
	sb.border_color = _GREY_DEEP
	btn.add_theme_stylebox_override("disabled", sb)


# Reads the entitlement chokepoint and marks every entitlement card owned if held.
func _refresh_owned() -> void:
	if _entitlement == null or not _entitlement.has_method("should_suppress_interstitials"):
		return
	if not _entitlement.should_suppress_interstitials():
		return
	for sku in _entries:
		if _entry_is_entitlement(sku):
			_mark_owned(sku)


func _entry_is_entitlement(sku: int) -> bool:
	var e = _entries.get(sku)
	return e != null and e.kind == IAPCatalogEntryResource.Kind.NON_CONSUMABLE_ENTITLEMENT


# True when the player is age-restricted (under-13 / undeclared) — purchases sit behind a
# parental gate (ADR-0005 child-safe; S6-004).
func _is_child_restricted() -> bool:
	return _compliance != null and _compliance.has_method("is_restricted") and _compliance.is_restricted()


# True for a NON-restricted (adult) player who declined IAP consent — purchases are turned
# off, but re-enablable in Settings → Privacy (distinct from the child parental gate).
func _iap_consent_denied() -> bool:
	if _compliance == null or not _compliance.has_method("can_process_iap"):
		return false
	return not _compliance.is_restricted() and not _compliance.can_process_iap()


# A warm, calm notice card shown atop the offer list for a restricted (child) player.
func _child_banner() -> Control:
	var b := _panel(Color(1.0, 0.92, 0.74), 14, 14, 14, 14, true)
	b.custom_minimum_size = Vector2(0.0, 50.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiFactory.label(b, _tr("shop_child_banner"), Vector2(10.0, 0.0), Vector2(316.0, 50.0), 15, _INK)
	return b


func _show_toast(text: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.visible = true
	_toast_label.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.4)
	# Reduced-motion: hold, then hide instantly instead of fading (S5-008 a11y pass).
	if _is_reduced_motion():
		t.tween_callback(func() -> void: _toast_label.visible = false)
	else:
		t.tween_property(_toast_label, "modulate:a", 0.0, 0.4)


func _is_reduced_motion() -> bool:
	var s := get_node_or_null(^"/root/SettingsService")
	return s != null and s.get_value("reduced_motion")


# ---------------------------------------------------------------------------
# Builders (mirrors result_screen.gd's flat-styled buttons/panels)
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
	button.add_theme_color_override("font_disabled_color", Color.WHITE)
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
		sb.shadow_size = 8
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


# Localization stub (mirrors result_screen._tr). Replace when a string table lands.
func _tr(key: String) -> String:
	match key:
		"shop_title": return "SHOP"
		"shop_restore": return "Restore Purchases"
		"shop_owned": return "Owned ✓"
		"shop_purchase_ok": return "Purchase complete!"
		"shop_purchase_fail": return "Purchase didn't go through"
		"shop_restore_done": return "Restored %d purchase(s)"
		"shop_restore_none": return "Nothing to restore"
		"shop_parental_gate": return "Ask a grown-up to buy this"
		"shop_child_banner": return "🔒  A grown-up can make purchases"
		"shop_consent_off": return "Purchases are off — turn them on in Settings › Privacy"
		_:
			push_warning("ShopScreen: unknown localization key '%s'" % key)
			return key
