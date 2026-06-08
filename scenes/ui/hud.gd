class_name Hud
extends Control
## Cosmetic chrome around the board, matching the reference layout: a top bar
## (settings gear, level badge, completion badge) and a bottom action bar (three
## tool buttons). Built from Kenney UI buttons + Kenney game icons; only the
## colourful tool illustrations reuse the Layer Lab pack (Kenney has no equivalent).
##
## This layer is presentational. The gear and tools emit signals so wiring can
## be added later, but they drive no gameplay today; the percentage reflects
## [GameManager] level state only as flavour.

signal settings_pressed()
signal tool_pressed(tool_id: int)

# Tool bar: drill / hammer / potion, with placeholder charge counts.
const _TOOLS: Array[Dictionary] = [
	{icon = "icons/tool_drill.png", count = 1},
	{icon = "icons/tool_hammer.png", count = 4},
	{icon = "icons/tool_potion.png", count = 1},
]

var _percent_label: Label
var _level_label: Label


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header()
	_build_toolbar()


# --- Header -----------------------------------------------------------------

func _build_header() -> void:
	# Settings gear (Kenney round button + Kenney gear icon).
	var gear := _bare_button(Vector2(12, 12), Vector2(60, 60))
	gear.pressed.connect(func() -> void: settings_pressed.emit())
	UiFactory.nine_patch(gear, "kenney/round_grey.png", Vector2.ZERO, Vector2(60, 60), 28)
	UiFactory.sprite(gear, "kenney/gear.png", Vector2(15, 14), Vector2(30, 30), Color(0.30, 0.34, 0.46))

	# Level badge (centre of the header).
	UiFactory.nine_patch(self, "kenney/rect_green.png", Vector2(155, 16), Vector2(80, 42), 18)
	_level_label = UiFactory.label(self, "", Vector2(155, 14), Vector2(80, 42), 18, Color.WHITE)

	# Completion badge (top-right).
	UiFactory.nine_patch(self, "kenney/round_blue.png", Vector2(322, 10), Vector2(58, 58), 26)
	_percent_label = UiFactory.label(self, "", Vector2(322, 8), Vector2(58, 58), 17, Color.WHITE)

	refresh()


# --- Bottom tool bar --------------------------------------------------------

func _build_toolbar() -> void:
	var btn_w: float = 106.0
	var btn_h: float = 78.0
	var gap: float = 12.0
	var total: float = _TOOLS.size() * btn_w + (_TOOLS.size() - 1) * gap
	var start_x: float = (390.0 - total) * 0.5
	var y: float = 724.0

	for i in _TOOLS.size():
		var data: Dictionary = _TOOLS[i]
		var pos := Vector2(start_x + i * (btn_w + gap), y)
		var btn := _bare_button(pos, Vector2(btn_w, btn_h))
		UiFactory.nine_patch(btn, "kenney/rect_blue.png", Vector2.ZERO, Vector2(btn_w, btn_h), 18)
		var tool_id: int = i
		btn.pressed.connect(func() -> void: tool_pressed.emit(tool_id))
		UiFactory.sprite(btn, data.icon, Vector2((btn_w - 54) * 0.5, 10), Vector2(54, 54))
		_count_badge(btn, Vector2(btn_w - 30, btn_h - 30), int(data.count))


# --- Widgets ----------------------------------------------------------------

func _bare_button(pos: Vector2, size: Vector2) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.position = pos
	btn.size = size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(btn)
	return btn


func _count_badge(parent: Node, pos: Vector2, count: int) -> void:
	UiFactory.sprite(parent, "kenney/round_blue.png", pos, Vector2(28, 28), Color(1.0, 0.45, 0.55))
	UiFactory.label(parent, str(count), pos, Vector2(28, 28), 15, Color.WHITE)


## Refreshes flavour text from [GameManager].
func refresh() -> void:
	var level: int = GameManager.current_level
	if _level_label != null:
		_level_label.text = "LV%d" % level
	if _percent_label != null:
		var pct: int = int(round(100.0 * float(level - 1) / float(maxi(LevelData.level_count(), 1))))
		_percent_label.text = "%d%%" % pct
