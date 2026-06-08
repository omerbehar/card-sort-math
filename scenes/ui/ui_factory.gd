class_name UiFactory
extends RefCounted
## Helpers for composing the Layer Lab textured UI in code.
##
## The Layer Lab sprites are authored at varying native sizes (a frame border is
## 130px, its fill 70px, etc.). These helpers place a texture at an explicit
## top-left rect and scale it to fit, so callers can lay out against the fixed
## 390x844 portrait screen without juggling per-asset native sizes.

const UI_DIR: String = "res://assets/ui/"


## A [Sprite2D] showing [param rel_path] (relative to [constant UI_DIR]), with
## its top-left at [param pos] and scaled to [param size]. Optional [param tint]
## recolors white/neutral source art toward a pastel hue.
static func sprite(parent: Node, rel_path: String, pos: Vector2, size: Vector2, tint: Color = Color.WHITE) -> Sprite2D:
	var tex: Texture2D = load(UI_DIR + rel_path)
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.modulate = tint
	if tex != null and tex.get_width() > 0 and tex.get_height() > 0:
		s.scale = Vector2(size.x / tex.get_width(), size.y / tex.get_height())
	s.position = pos
	parent.add_child(s)
	return s


## A [NinePatchRect] showing [param rel_path] at [param pos]/[param size] with a
## uniform [param margin] (in source px) kept un-stretched at the corners — so
## rounded button/frame art stays crisp at any size. [param tint] recolors it.
static func nine_patch(parent: Node, rel_path: String, pos: Vector2, size: Vector2, margin: int = 16, tint: Color = Color.WHITE) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.texture = load(UI_DIR + rel_path)
	np.position = pos
	np.size = size
	np.patch_margin_left = margin
	np.patch_margin_top = margin
	np.patch_margin_right = margin
	np.patch_margin_bottom = margin
	np.self_modulate = tint
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(np)
	return np


## A centered [Label] filling [param size] at [param pos].
static func label(parent: Node, text: String, pos: Vector2, size: Vector2, font_size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.2, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
