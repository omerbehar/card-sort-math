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

const COINS := EconomyEnums.Currency.COINS

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

var _percent_label: Label
var _level_label: Label

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
		wallet.economy_event.connect(func(_e: Variant) -> void: _refresh_boosters())
	if wallet != null and wallet.has_signal("booster_stock_changed"):
		wallet.booster_stock_changed.connect(func(_t: int, _n: int) -> void: _refresh_boosters())
	_refresh_boosters()


# --- Header -----------------------------------------------------------------

func _build_header() -> void:
	var gear := _bare_button(Vector2(12, 12), Vector2(60, 60))
	gear.pressed.connect(func() -> void: settings_pressed.emit())
	UiFactory.nine_patch(gear, "kenney/round_grey.png", Vector2.ZERO, Vector2(60, 60), 28)
	UiFactory.sprite(gear, "kenney/gear.png", Vector2(15, 14), Vector2(30, 30), Color(0.30, 0.34, 0.46))

	UiFactory.nine_patch(self, "kenney/rect_green.png", Vector2(155, 16), Vector2(80, 42), 18)
	_level_label = UiFactory.label(self, "", Vector2(155, 14), Vector2(80, 42), 18, Color.WHITE)

	UiFactory.nine_patch(self, "kenney/round_blue.png", Vector2(322, 10), Vector2(58, 58), 26)
	_percent_label = UiFactory.label(self, "", Vector2(322, 8), Vector2(58, 58), 17, Color.WHITE)

	refresh()


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
