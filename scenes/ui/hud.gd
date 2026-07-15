class_name Hud
extends Control
## Cosmetic chrome around the board: a top bar (settings gear, level badge,
## completion badge) and a bottom **booster tray** (Picker / Reshuffle / Extra
## Discard Slot). The tray uses the booster icon set (`assets/ui/icons/booster_*`)
## on Kenney `slot_grey` tiles, per `design/ux/booster-icons.md`.
##
## The tray is a thin view: it shows each booster's coin cost and an
## affordable/unaffordable state (driven by [WalletService]) and emits
## [signal booster_pressed]; the [code]Main[/code] controller owns activation.
## State machine is a first cut — affordable vs unaffordable. The fuller spec
## (precondition slash, picker-armed dashed border, ≥250 spend-confirm modal) is
## tracked in `design/ux/booster-icons.md` §3 for a follow-up.

signal settings_pressed()
signal booster_pressed(booster_type: int)
## Emitted when a currency pill is tapped — deep-links the Shop to that currency
## (wired by the Shop screen, S5-003). Until the Shop lands this is a no-op hook.
signal currency_tapped(currency: int)

const COINS := EconomyEnums.Currency.COINS
const GEMS := EconomyEnums.Currency.GEMS

# Booster tray: icon + the BoosterType it activates (cost is read from WalletService).
const _BOOSTERS: Array[Dictionary] = [
	{icon = "icons/booster_picker.svg", type = EconomyEnums.BoosterType.PICKER},
	{icon = "icons/booster_reshuffle.svg", type = EconomyEnums.BoosterType.RESHUFFLE},
	{icon = "icons/booster_extra_discard.svg", type = EconomyEnums.BoosterType.EXTRA_DISCARD},
]

const _TILE_AFFORD: Color = Color(1.0, 0.96, 0.90)   # warm-neutral (not yellow/green)
const _TILE_BLOCKED: Color = Color(0.74, 0.77, 0.83) # cool desaturated grey
const _GLYPH_AFFORD: Color = Color(0.20, 0.24, 0.34) # dark glyph on the light tile
const _GLYPH_BLOCKED: Color = Color(0.20, 0.24, 0.34, 0.40)

# Wallet pills (S5-002): warm gold for coins, cool violet-blue for gems —
# luminance-distinct (colorblind-safe), not hue-only.
const _COINS_PILL: Color = Color(1.0, 0.90, 0.60)
const _GEMS_PILL: Color = Color(0.74, 0.82, 1.0)
const _COUNTUP_SECS: float = 0.3   # brief count-up on earn/spend (reduced-motion → snap)

var _percent_label: Label
var _level_label: Label

# Wallet display (S5-002): live-bound coins + gems pills. `_shown` values track the
# last-rendered balance so an earn/spend can count up from it (and spawn a +N/−N float).
var _coins_pill_label: Label
var _gems_pill_label: Label
var _coins_shown: int = 0
var _gems_shown: int = 0
var _coins_tween: Tween
var _gems_tween: Tween

# Per-booster widgets, kept so _refresh_boosters can restyle them on stock changes.
var _tiles: Array[NinePatchRect] = []
var _glyphs: Array[Sprite2D] = []
var _count_labels: Array[Label] = []


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header()
	_build_booster_tray()
	# Restyle the tray whenever a balance changes (earn/spend) or a booster's owned
	# count changes (consume/grant/seed).
	var wallet := get_node_or_null("/root/WalletService")
	if wallet != null and wallet.has_signal("economy_event"):
		wallet.economy_event.connect(_on_economy_event)
	if wallet != null and wallet.has_signal("booster_stock_changed"):
		wallet.booster_stock_changed.connect(func(_t: int, _n: int) -> void: _refresh_boosters())
	_refresh_boosters()


# --- Header -----------------------------------------------------------------

func _build_header() -> void:
	var gear := _bare_button(Vector2(12, 12), Vector2(60, 60))
	gear.pressed.connect(func() -> void: settings_pressed.emit())
	UiFactory.nine_patch(gear, "kenney/round_grey.png", Vector2.ZERO, Vector2(60, 60), 28)
	UiFactory.sprite(gear, "kenney/gear.png", Vector2(15, 14), Vector2(30, 30), Color(0.30, 0.34, 0.46))

	# Progression chrome grouped on the left (after the gear); the wallet pills own
	# the right half of the bar. Previously the coins readout (a stopgap Label built
	# in main.gd) overlapped the percent badge — S5-002 reflows both into one row.
	UiFactory.nine_patch(self, "kenney/rect_green.png", Vector2(80, 16), Vector2(70, 40), 18)
	_level_label = UiFactory.label(self, "", Vector2(80, 14), Vector2(70, 40), 17, Color.WHITE)

	UiFactory.nine_patch(self, "kenney/round_blue.png", Vector2(156, 11), Vector2(52, 52), 24)
	_percent_label = UiFactory.label(self, "", Vector2(156, 9), Vector2(52, 52), 15, Color.WHITE)

	_build_wallet()
	refresh()


# --- Wallet display (S5-002) ------------------------------------------------

## Builds the coins + gems pills on the right of the top bar. Each pill is a
## tappable [Button] (deep-links the Shop via [signal currency_tapped]) backed by
## a tinted nine-patch and a live balance label seeded from [WalletService].
func _build_wallet() -> void:
	var wallet := get_node_or_null("/root/WalletService")
	_coins_shown = wallet.balance(COINS) if wallet != null else 0
	_gems_shown = wallet.balance(GEMS) if wallet != null else 0

	_coins_pill_label = _build_pill(Vector2(214, 15), _COINS_PILL, COINS)
	_gems_pill_label = _build_pill(Vector2(300, 15), _GEMS_PILL, GEMS)
	_coins_pill_label.text = "🪙 %d" % _coins_shown
	_gems_pill_label.text = "💎 %d" % _gems_shown


# One currency pill at [param pos]; returns its balance Label.
func _build_pill(pos: Vector2, tint: Color, currency: int) -> Label:
	var size := Vector2(84, 38)
	var btn := _bare_button(pos, size)
	UiFactory.nine_patch(btn, "kenney/round_grey.png", Vector2.ZERO, size, 18, tint)
	var lbl := UiFactory.label(btn, "", Vector2.ZERO, size, 17, Color.WHITE)
	btn.pressed.connect(func() -> void: currency_tapped.emit(currency))
	return lbl


# A wallet transaction landed: restyle the booster tray (affordability may have
# changed) and count the pills up/down to the new balances.
func _on_economy_event(_e: Variant) -> void:
	_refresh_boosters()
	_refresh_wallet(true)


## Snaps both pills to the current [WalletService] balances (no count-up). For
## callers that mutate the wallet without an [signal WalletService.economy_event]
## (e.g. the debug inventory reset).
func refresh_wallet() -> void:
	_refresh_wallet(false)


## Re-reads both balances from [WalletService] and updates the pills. When
## [param animate] and motion is allowed, each changed pill counts up/down over
## [constant _COUNTUP_SECS] and floats a +N/−N cue; otherwise it snaps.
func _refresh_wallet(animate: bool) -> void:
	var wallet := get_node_or_null("/root/WalletService")
	if wallet == null:
		return
	var coins: int = wallet.balance(COINS)
	var gems: int = wallet.balance(GEMS)
	_coins_tween = _animate_pill(_coins_pill_label, _coins_tween, "🪙", _coins_shown, coins, animate, Vector2(214, 15))
	_gems_tween = _animate_pill(_gems_pill_label, _gems_tween, "💎", _gems_shown, gems, animate, Vector2(300, 15))
	_coins_shown = coins
	_gems_shown = gems


# Drives one pill from [param from] to [param to]. Snaps instantly under
# reduced-motion / no-change; otherwise tweens the integer and spawns a delta
# float. Returns the live tween (or null) so the caller can retain/cancel it.
func _animate_pill(label: Label, prev: Tween, prefix: String, from: int, to: int, animate: bool, anchor: Vector2) -> Tween:
	if label == null:
		return null
	if prev != null and prev.is_valid():
		prev.kill()
	if not animate or from == to or _is_reduced_motion():
		label.text = "%s %d" % [prefix, to]
		return null
	_spawn_delta_float(anchor, to - from)
	var tw := create_tween()
	tw.tween_method(
			func(v: float) -> void: label.text = "%s %d" % [prefix, int(round(v))],
			float(from), float(to), _COUNTUP_SECS)
	return tw


# A brief "+N" / "−N" cue that rises and fades above a pill. Skipped under
# reduced-motion (callers only reach here when motion is allowed).
func _spawn_delta_float(anchor: Vector2, delta: int) -> void:
	if delta == 0:
		return
	var text: String = "+%d" % delta if delta > 0 else "%d" % delta
	var color: Color = Color(0.55, 0.85, 0.45) if delta > 0 else Color(0.92, 0.5, 0.45)
	var f := UiFactory.label(self, text, anchor + Vector2(0, -2), Vector2(84, 22), 15, color)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(f, "position:y", f.position.y - 22.0, 0.6)
	tw.tween_property(f, "modulate:a", 0.0, 0.6)
	tw.finished.connect(f.queue_free)


func _is_reduced_motion() -> bool:
	var s := get_node_or_null("/root/SettingsService")
	return s != null and s.get_value("reduced_motion")


# --- Booster tray -----------------------------------------------------------

func _build_booster_tray() -> void:
	var tile: float = 72.0
	var gap: float = 14.0
	var glyph: float = 42.0
	var total: float = _BOOSTERS.size() * tile + (_BOOSTERS.size() - 1) * gap
	var start_x: float = (390.0 - total) * 0.5
	var y: float = 738.0

	for i in _BOOSTERS.size():
		var data: Dictionary = _BOOSTERS[i]
		var pos := Vector2(start_x + i * (tile + gap), y)
		var btn := _bare_button(pos, Vector2(tile, tile))
		var frame := UiFactory.nine_patch(btn, "kenney/slot_grey.png", Vector2.ZERO, Vector2(tile, tile), 16, _TILE_AFFORD)
		var g := UiFactory.sprite(btn, data.icon, Vector2((tile - glyph) * 0.5, (tile - glyph) * 0.5 - 6), Vector2(glyph, glyph), _GLYPH_AFFORD)
		# Owned-count badge (bottom-right): the number you hold, or "+" when empty
		# (a tap then opens the watch-ad / pay-coins top-up popup).
		var count_label := UiFactory.label(btn, "", Vector2(tile - 30, tile - 26), Vector2(26, 22), 17, Color.WHITE)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_color_override("font_outline_color", Color(0.12, 0.16, 0.26, 0.95))
		count_label.add_theme_constant_override("outline_size", 5)
		var btype: int = data.type
		btn.pressed.connect(func() -> void: booster_pressed.emit(btype))
		_tiles.append(frame)
		_glyphs.append(g)
		_count_labels.append(count_label)


## Restyles each booster tile for its current owned count: a stocked buff reads
## normal with its count; an empty buff dims and shows a warm "+" refill cue
## (luminance + glyph change, not hue-only — colorblind-safe).
func _refresh_boosters() -> void:
	var wallet := get_node_or_null("/root/WalletService")
	if wallet == null:
		return
	for i in _BOOSTERS.size():
		var count: int = wallet.booster_count(_BOOSTERS[i].type)
		var has: bool = count > 0
		_tiles[i].self_modulate = _TILE_AFFORD if has else _TILE_BLOCKED
		_glyphs[i].modulate = _GLYPH_AFFORD if has else _GLYPH_BLOCKED
		_count_labels[i].text = str(count) if has else "+"
		_count_labels[i].add_theme_color_override(
				"font_color", Color.WHITE if has else Color(1.0, 0.86, 0.4))


# --- Widgets ----------------------------------------------------------------

func _bare_button(pos: Vector2, size: Vector2) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.position = pos
	btn.size = size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(btn)
	return btn


## Refreshes flavour text from [GameManager].
func refresh() -> void:
	var level: int = GameManager.current_level
	if _level_label != null:
		_level_label.text = "LV%d" % level
	if _percent_label != null:
		var pct: int = int(round(100.0 * float(level - 1) / float(maxi(LevelData.level_count(), 1))))
		_percent_label.text = "%d%%" % pct
