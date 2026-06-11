@tool
extends SceneTree
## Headless tool: rasterizes res://icon.svg into the iOS App Store icon
## (1024x1024, opaque). Run: godot --headless -s res://tools/gen_ios_icon.gd
## Placeholder art — replace ios/icon_1024.png with final branded artwork.


func _init() -> void:
	var svg_text := FileAccess.get_file_as_string("res://icon.svg")
	var img := Image.new()
	var err := img.load_svg_from_string(svg_text, 8.0)  # 128 * 8 = 1024
	if err != OK or img.get_width() < 1024:
		# Fallback: upscale the imported texture.
		var tex: Texture2D = load("res://icon.svg")
		img = tex.get_image()
		img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)

	# App Store icons must be opaque — flatten onto the project's background colour.
	if img.get_width() != 1024 or img.get_height() != 1024:
		img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	var bg := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	bg.fill(Color("#363d52"))  # matches icon.svg background
	bg.blend_rect(img, Rect2i(0, 0, 1024, 1024), Vector2i(0, 0))
	bg.convert(Image.FORMAT_RGB8)  # drop alpha -> fully opaque

	var out := "res://ios/icon_1024.png"
	var save_err := bg.save_png(out)
	if save_err == OK:
		print("Saved %s (%dx%d, opaque)" % [out, bg.get_width(), bg.get_height()])
	else:
		push_error("Failed to save icon: %d" % save_err)
	quit()
