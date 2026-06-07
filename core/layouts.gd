class_name Layouts
extends RefCounted
## Hand-authored floor layout presets.
##
## A layout is an ordered list of placements; the index into that list is a
## card's [code]slot[/code] (and its stable [code]card_id[/code] within a
## level). Each placement is [code]{pos: Vector2, layer: int}[/code] where a
## higher [code]layer[/code] sits on top and visually overlaps the cards below
## it. Exposure (which cards are tappable) is derived purely from these
## positions + layers by [Exposure]; authoring a layout is therefore just
## choosing positions and stacking depth.

const CARD_W: float = 72.0
const CARD_H: float = 96.0

## Number of placements in each preset, by layout id. Kept here so [LevelData]
## can assert a level's [member LevelConfig.card_pool] matches its layout.
const SLOT_COUNTS: Array[int] = [12, 18, 15]


## Returns the placements for [param layout_id] as an ordered array of
## [code]{pos: Vector2, layer: int}[/code] dictionaries.
static func get_layout(layout_id: int) -> Array[Dictionary]:
	match layout_id:
		0:
			return _layout_0()
		1:
			return _layout_1()
		2:
			return _layout_2()
		_:
			push_error("Unknown layout_id %d" % layout_id)
			return []


## Builds a grid block of placements, all on the same [param layer].
static func _grid(cols: int, rows: int, layer: int, x0: float, y0: float, dx: float, dy: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in rows:
		for c in cols:
			out.append({pos = Vector2(x0 + c * dx, y0 + r * dy), layer = layer})
	return out


# Layout 0 — 12 cards: 6 base, 4 mid (offset), 2 top. Pyramid-ish pile.
static func _layout_0() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_grid(3, 2, 0, 60, 60, 90, 120))
	out.append_array(_grid(2, 2, 1, 105, 120, 90, 120))
	out.append_array(_grid(2, 1, 2, 150, 180, 90, 0))
	return out


# Layout 1 — 18 cards: 8 base, 6 mid (offset), 4 top.
static func _layout_1() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_grid(4, 2, 0, 35, 50, 80, 120))
	out.append_array(_grid(3, 2, 1, 75, 110, 80, 120))
	out.append_array(_grid(2, 2, 2, 115, 170, 80, 90))
	return out


# Layout 2 — 15 cards: 6 base, 6 mid (offset), 3 top.
static func _layout_2() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_grid(3, 2, 0, 60, 60, 90, 130))
	out.append_array(_grid(3, 2, 1, 105, 125, 90, 130))
	out.append_array(_grid(3, 1, 2, 105, 190, 90, 0))
	return out
