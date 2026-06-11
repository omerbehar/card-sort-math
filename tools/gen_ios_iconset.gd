@tool
extends SceneTree
## Headless tool: downscales ios/icon_1024.png into the full iOS icon set that
## Godot's iOS exporter expects (opaque, no alpha). Run:
##   godot --headless -s res://tools/gen_ios_iconset.gd
## Placeholder art — regenerate after replacing ios/icon_1024.png.

const SIZES: Array[int] = [120, 180, 40, 80, 58, 87, 60, 152, 167, 76, 20, 29]


func _init() -> void:
	var src := Image.load_from_file("res://ios/icon_1024.png")
	if src == null:
		push_error("gen_ios_iconset: ios/icon_1024.png not found — run gen_ios_icon.gd first.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://ios/icons")
	for size in SIZES:
		var img := src.duplicate() as Image
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)  # opaque, iOS icons must not have alpha
		var out := "res://ios/icons/icon_%dx%d.png" % [size, size]
		if img.save_png(out) == OK:
			print("saved %s" % out)
		else:
			push_error("failed to save %s" % out)
	quit()
