extends SceneTree
## Builds the Android launcher icons. Called by tools/make_android_icons.sh,
## which passes a 432 px black-on-white render of icon.svg's glyph.

const OUT_DIR := "res://assets/android"
const SIZE := 432


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var glyph := _glyph_mask(Image.load_from_file(args[0]))
	var svg := FileAccess.get_file_as_string("res://icon.svg")

	# Box only (ThorVG ignores the <text>), then the glyph on top.
	var full := Image.new()
	full.load_svg_from_string(svg, float(SIZE) / 128.0)
	full.blend_rect(glyph, Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
	full.resize(192, 192, Image.INTERPOLATE_LANCZOS)
	_save(full, "icon_192.png")

	_save(glyph, "icon_foreground_432.png")
	_save(glyph, "icon_monochrome_432.png")

	var bg := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	bg.fill(_box_colour(svg))
	_save(bg, "icon_background_432.png")
	quit()


## White glyph whose alpha is the darkness of the black-on-white render.
func _glyph_mask(src: Image) -> Image:
	src.convert(Image.FORMAT_RGBA8)
	src.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			out.set_pixel(x, y, Color(1, 1, 1, 1.0 - src.get_pixel(x, y).get_luminance()))
	return out


func _box_colour(svg: String) -> Color:
	var m := RegEx.create_from_string("<rect[^>]* fill=\"(#[0-9a-fA-F]+)\"").search(svg)
	return Color(m.get_string(1))


func _save(img: Image, file: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png(OUT_DIR.path_join(file))
	print("wrote %s (%dx%d)" % [file, img.get_width(), img.get_height()])
