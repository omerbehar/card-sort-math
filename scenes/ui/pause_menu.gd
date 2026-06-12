class_name PauseMenu
extends PopupBase
## Modal pause menu, bound to [SettingsService]. Styled after the project's
## reference mock: a header strip with a red close button, a row of round audio
## toggles (sound / music / haptics), pill-switch rows for the accessibility
## settings (colorblind / reduced-motion), and Home / Continue actions.
##
## The menu owns no state — it reads current values from the service, requests
## changes via [method SettingsService.toggle], and refreshes from the service's
## [signal SettingsService.changed] signal. Built in code to match the rest of
## the UI layer (see [Hud] / [UiFactory]); the pill switch and buttons are
## code-drawn from neutral Kenney art (no bespoke switch/home assets). The service
## is injectable (see [method configure]) so the binding is interaction-testable.
##
## While open it pauses the [SceneTree] (the controller sets that up); the node
## runs with [constant Node.PROCESS_MODE_ALWAYS] so its buttons stay live.
## Implements Sprint 1 story S1-011 (+ the colorblind accessibility mode).

## Emitted when the player resumes (close button, Continue, or backdrop tap).
signal resumed()
## Emitted when the player taps Home (controller decides what "home" means).
signal home_pressed()
## Emitted when the player taps "Reset Tutorial" (controller clears the flag).
signal reset_tutorial_pressed()

# Round audio toggles, left-to-right. Keys must exist in [constant Settings.KEYS].
const _AUDIO_TOGGLES: Array[Dictionary] = [
	{key = "sound", glyph = "SFX"},
	{key = "music", glyph = "BGM"},
	{key = "haptics", glyph = "VIB"},
]

# Pill-switch rows, top-to-bottom.
const _SWITCHES: Array[Dictionary] = [
	{key = "colorblind", label = "Colorblind Mode"},
	{key = "reduced_motion", label = "Reduced Motion"},
]

const _PANEL_POS: Vector2 = Vector2(33, 210)
const _PANEL_SIZE: Vector2 = Vector2(324, 416)
const _HEADER_H: float = 62.0
const _KNOB_SIZE: float = 26.0

const _HEADER_TINT: Color = Color(0.16, 0.45, 0.78)   # darker blue strip
const _RED: Color = Color(0.86, 0.30, 0.31)
const _GREEN: Color = Color(0.40, 0.78, 0.34)
const _ON_TINT: Color = Color(0.36, 0.78, 0.45)
const _OFF_TINT: Color = Color(0.52, 0.55, 0.62)

# SettingsService; resolves to the autoload at runtime, injectable in tests.
var _settings = null
# key -> { type, ... } refresh handles, so a flip can re-skin just that control.
var _round_bg: Dictionary = {}      # key -> NinePatchRect (round button skin)
var _round_label: Dictionary = {}   # key -> Label
var _switch_track: Dictionary = {}  # key -> NinePatchRect
var _switch_knob: Dictionary = {}   # key -> Sprite2D
# key -> Button, exposed so tests can drive the real pressed path.
var _buttons: Dictionary = {}


func _ready() -> void:
	if _settings == null:
		_settings = SettingsService
	# Pop-up chassis (ADR-0006): tap-outside resumes; main.gd owns the tree-pause.
	dismiss_on_backdrop = true
	backdrop_color = Color(0.0, 0.0, 0.0, 0.55)
	super()
	backdrop_pressed.connect(_resume)
	_build()
	_settings.changed.connect(_on_setting_changed)


## Injects the settings service. Must run before the node enters the tree (before
## [method _ready]). Intended for tests.
func configure(settings: Object) -> void:
	_settings = settings


# --- Construction -----------------------------------------------------------

func _build() -> void:
	# Panel card + header strip (backdrop is provided by PopupBase).
	UiFactory.nine_patch(body(), "kenney/rect_blue.png", _PANEL_POS, _PANEL_SIZE, 24)
	UiFactory.nine_patch(body(), "kenney/rect_blue.png", _PANEL_POS, Vector2(_PANEL_SIZE.x, _HEADER_H), 22, _HEADER_TINT)
	UiFactory.label(body(), "PAUSE", _PANEL_POS, Vector2(_PANEL_SIZE.x, _HEADER_H), 26, Color.WHITE)

	# Red close button straddling the header's top-right.
	var close := _bare_button(_PANEL_POS + Vector2(_PANEL_SIZE.x - 50, 8), Vector2(44, 44))
	UiFactory.nine_patch(close, "kenney/round_grey.png", Vector2.ZERO, Vector2(44, 44), 20, _RED)
	UiFactory.label(close, "X", Vector2.ZERO, Vector2(44, 44), 20, Color.WHITE)
	close.pressed.connect(_resume)

	_build_audio_toggles()
	_build_switches()
	_build_reset_tutorial()
	_build_actions()


# A slim "Reset Tutorial" row between the switches and the Home/Continue actions.
func _build_reset_tutorial() -> void:
	var size := Vector2(_PANEL_SIZE.x - 44.0, 40.0)
	var pos := Vector2(_PANEL_POS.x + 22, _PANEL_POS.y + _PANEL_SIZE.y - 122.0)
	var btn := _bare_button(pos, size)
	UiFactory.nine_patch(btn, "kenney/rect_blue.png", Vector2.ZERO, size, 16, Color(0.12, 0.32, 0.58))
	UiFactory.label(btn, "Reset Tutorial", Vector2.ZERO, size, 18, Color.WHITE)
	btn.pressed.connect(func() -> void:
		reset_tutorial_pressed.emit()
		_resume())
	_buttons["reset_tutorial"] = btn


func _build_audio_toggles() -> void:
	var btn_size := Vector2(66, 66)
	var gap: float = 26.0
	var total: float = _AUDIO_TOGGLES.size() * btn_size.x + (_AUDIO_TOGGLES.size() - 1) * gap
	var start_x: float = _PANEL_POS.x + (_PANEL_SIZE.x - total) * 0.5
	var y: float = _PANEL_POS.y + _HEADER_H + 22.0

	for i in _AUDIO_TOGGLES.size():
		var item: Dictionary = _AUDIO_TOGGLES[i]
		var key: String = item.key
		var pos := Vector2(start_x + i * (btn_size.x + gap), y)
		var btn := _bare_button(pos, btn_size)
		var bg := UiFactory.nine_patch(btn, "kenney/round_grey.png", Vector2.ZERO, btn_size, 30)
		var lbl := UiFactory.label(btn, item.glyph, Vector2.ZERO, btn_size, 18, Color.WHITE)
		btn.pressed.connect(_on_toggle_pressed.bind(key))
		_round_bg[key] = bg
		_round_label[key] = lbl
		_buttons[key] = btn
		_refresh_round(key)


func _build_switches() -> void:
	var row_w: float = _PANEL_SIZE.x - 44.0
	var row_h: float = 52.0
	var gap: float = 12.0
	var y0: float = _PANEL_POS.y + _HEADER_H + 110.0

	for i in _SWITCHES.size():
		var item: Dictionary = _SWITCHES[i]
		var key: String = item.key
		var pos := Vector2(_PANEL_POS.x + 22, y0 + i * (row_h + gap))
		var size := Vector2(row_w, row_h)

		var btn := _bare_button(pos, size)
		UiFactory.nine_patch(btn, "kenney/rect_blue.png", Vector2.ZERO, size, 16, Color(0.12, 0.32, 0.58))
		UiFactory.label(btn, item.label, Vector2(18, 0), Vector2(size.x - 96, size.y), 17, Color.WHITE) \
			.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_toggle_pressed.bind(key))
		_buttons[key] = btn

		# Code-drawn pill switch: rounded track + sliding knob.
		var track_size := Vector2(58, 30)
		var track_pos := Vector2(size.x - track_size.x - 14, (size.y - track_size.y) * 0.5)
		var track := UiFactory.nine_patch(btn, "kenney/slot_grey.png", track_pos, track_size, 14)
		var knob := UiFactory.sprite(btn, "kenney/round_grey.png", Vector2.ZERO, Vector2(_KNOB_SIZE, _KNOB_SIZE))
		_switch_track[key] = track
		_switch_knob[key] = knob
		_position_knob(key)
		_refresh_switch(key)


func _build_actions() -> void:
	var y: float = _PANEL_POS.y + _PANEL_SIZE.y - 70.0
	var home_w: float = 86.0
	var gap: float = 14.0

	var home := _bare_button(Vector2(_PANEL_POS.x + 22, y), Vector2(home_w, 56))
	UiFactory.nine_patch(home, "kenney/rect_blue.png", Vector2.ZERO, Vector2(home_w, 56), 18, _RED)
	UiFactory.label(home, "⌂", Vector2.ZERO, Vector2(home_w, 56), 30, Color.WHITE)  # house glyph
	home.pressed.connect(_go_home)

	var cont_x: float = _PANEL_POS.x + 22 + home_w + gap
	var cont_w: float = _PANEL_SIZE.x - 44 - home_w - gap
	var cont := _bare_button(Vector2(cont_x, y), Vector2(cont_w, 56))
	UiFactory.nine_patch(cont, "kenney/rect_green.png", Vector2.ZERO, Vector2(cont_w, 56), 18, _GREEN)
	UiFactory.label(cont, "CONTINUE", Vector2.ZERO, Vector2(cont_w, 56), 22, Color.WHITE)
	cont.pressed.connect(_resume)


func _bare_button(pos: Vector2, size: Vector2) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.position = pos
	btn.size = size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	body().add_child(btn)
	return btn


# --- Binding ----------------------------------------------------------------

func _on_toggle_pressed(key: String) -> void:
	_settings.toggle(key)


func _on_setting_changed(key: String, _value: bool) -> void:
	if _round_bg.has(key):
		_refresh_round(key)
	if _switch_track.has(key):
		_position_knob(key)
		_refresh_switch(key)


# A lit round toggle is green with a bright label; muted is grey and dimmed.
func _refresh_round(key: String) -> void:
	var on: bool = _settings.get_value(key)
	var bg: NinePatchRect = _round_bg[key]
	var lbl: Label = _round_label[key]
	bg.self_modulate = _ON_TINT if on else _OFF_TINT
	lbl.modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)


func _refresh_switch(key: String) -> void:
	var on: bool = _settings.get_value(key)
	var track: NinePatchRect = _switch_track[key]
	track.self_modulate = _ON_TINT if on else _OFF_TINT


# Slides the knob to the track's right (on) or left (off) edge. Uses the knob's
# display size ([constant _KNOB_SIZE]); [method Sprite2D.get_rect] would report
# the unscaled texture size.
func _position_knob(key: String) -> void:
	var on: bool = _settings.get_value(key)
	var track: NinePatchRect = _switch_track[key]
	var knob: Sprite2D = _switch_knob[key]
	var inset: float = 2.0
	var x: float = track.position.x + (track.size.x - _KNOB_SIZE - inset if on else inset)
	knob.position = Vector2(x, track.position.y + (track.size.y - _KNOB_SIZE) * 0.5)


func _resume() -> void:
	resumed.emit()
	close()


func _go_home() -> void:
	home_pressed.emit()
	close()
