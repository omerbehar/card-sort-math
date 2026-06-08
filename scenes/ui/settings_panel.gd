class_name SettingsPanel
extends Control
## Modal settings overlay: one toggle row per [Settings] key, bound to
## [SettingsService]. The panel owns no state — it reads current values from the
## service, requests changes via [method SettingsService.toggle], and refreshes
## from the service's [signal SettingsService.changed] signal, so it stays in
## sync even if a setting is flipped elsewhere.
##
## Built in code to match the rest of the UI layer (see [Hud] / [UiFactory]); no
## `.tscn`. The service is injectable (see [method configure]) so the row/toggle
## wiring is interaction-testable in isolation. Implements Sprint 1 story S1-011.

## Emitted when the player dismisses the panel (close button or backdrop tap).
signal closed()

# Rows, top-to-bottom. Keys must match [constant Settings.KEYS].
const _ROWS: Array[Dictionary] = [
	{key = "sound", label = "Sound"},
	{key = "music", label = "Music"},
	{key = "haptics", label = "Haptics"},
	{key = "reduced_motion", label = "Reduced Motion"},
]

const _PANEL_POS: Vector2 = Vector2(35, 250)
const _PANEL_SIZE: Vector2 = Vector2(320, 344)
const _ROW_H: float = 56.0
const _ROW_GAP: float = 8.0
const _ROW_TOP: float = 80.0
const _ON_TINT: Color = Color(0.36, 0.78, 0.45)   # filled dot — enabled
const _OFF_TINT: Color = Color(0.55, 0.58, 0.66)   # empty dot — disabled

# SettingsService; resolves to the autoload at runtime, injectable in tests.
var _settings = null
# Per-key toggle indicator sprite, so a flip can re-skin just that row.
var _dots: Dictionary = {}
# Per-key row button, so a tap drives the bound toggle (exposed for tests).
var _row_buttons: Dictionary = {}


func _ready() -> void:
	if _settings == null:
		_settings = SettingsService
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build()
	_settings.changed.connect(_on_setting_changed)


## Injects the settings service. Must be called before the node enters the tree
## (i.e. before [method _ready]) to take effect. Intended for tests.
func configure(settings: Object) -> void:
	_settings = settings


# --- Construction -----------------------------------------------------------

func _build() -> void:
	# Dimmed, input-blocking backdrop; tapping it dismisses the panel.
	var backdrop := Button.new()
	backdrop.flat = true
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.modulate = Color(0, 0, 0, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(bg)
	backdrop.pressed.connect(_dismiss)
	add_child(backdrop)

	# Panel card.
	UiFactory.nine_patch(self, "kenney/rect_blue.png", _PANEL_POS, _PANEL_SIZE, 24)
	UiFactory.label(self, "Settings", _PANEL_POS + Vector2(0, 18), Vector2(_PANEL_SIZE.x, 40), 24, Color.WHITE)

	# Close button (round, top-right of the panel).
	var close := Button.new()
	close.flat = true
	close.position = _PANEL_POS + Vector2(_PANEL_SIZE.x - 56, 12)
	close.size = Vector2(44, 44)
	close.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(close)
	UiFactory.nine_patch(close, "kenney/round_grey.png", Vector2.ZERO, Vector2(44, 44), 20)
	UiFactory.label(close, "X", Vector2.ZERO, Vector2(44, 44), 20, Color(0.30, 0.34, 0.46))
	close.pressed.connect(_dismiss)

	for i in _ROWS.size():
		_build_row(i, _ROWS[i])


func _build_row(index: int, row: Dictionary) -> void:
	var key: String = row.key
	var y: float = _PANEL_POS.y + _ROW_TOP + index * (_ROW_H + _ROW_GAP)
	var row_pos := Vector2(_PANEL_POS.x + 16, y)
	var row_size := Vector2(_PANEL_SIZE.x - 32, _ROW_H)

	# Whole row is a button so the entire strip is a comfortable touch target.
	var btn := Button.new()
	btn.flat = true
	btn.position = row_pos
	btn.size = row_size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(btn)
	btn.pressed.connect(_on_row_pressed.bind(key))
	_row_buttons[key] = btn

	UiFactory.nine_patch(btn, "kenney/rect_green.png", Vector2.ZERO, row_size, 16, Color(1, 1, 1, 0.18))
	UiFactory.label(btn, row.label, Vector2(18, 0), Vector2(row_size.x - 80, row_size.y), 19, Color.WHITE)

	var dot := UiFactory.sprite(btn, "kenney/dot_full.png", Vector2(row_size.x - 52, (row_size.y - 34) * 0.5), Vector2(34, 34))
	_dots[key] = dot
	_refresh_dot(key)


# --- Binding ----------------------------------------------------------------

func _on_row_pressed(key: String) -> void:
	_settings.toggle(key)


func _on_setting_changed(key: String, _value: bool) -> void:
	_refresh_dot(key)


# Re-skins a row's indicator from the service's current value: filled+green when
# on, empty+grey when off.
func _refresh_dot(key: String) -> void:
	var dot: Sprite2D = _dots.get(key)
	if dot == null:
		return
	var on: bool = _settings.get_value(key)
	dot.texture = load(UiFactory.UI_DIR + ("kenney/dot_full.png" if on else "kenney/dot_empty.png"))
	dot.modulate = _ON_TINT if on else _OFF_TINT


func _dismiss() -> void:
	closed.emit()
	queue_free()
