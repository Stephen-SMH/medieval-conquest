extends SceneTree
## Builds the UI textures and theme into assets/ui/: dark wood with a riveted
## stone frame, parchment, the wooden shield buttons for the screen corners,
## the gold plaque, slider parts, and the Theme resource using them with the
## Cinzel and IM FELL English fonts. Run it twice: once for the images, then
## (after an import) for the theme.
##   godot --headless -s tools/make_theme.gd -- images
##   godot --headless --import
##   godot --headless -s tools/make_theme.gd -- theme

const OUT := "res://assets/ui"
const INK := Color("#2f2012")
const GOLD := Color("#d9b25a")
const PARCHMENT := Color("#e9dcba")
const LIGHT_TEXT := Color("#f1e3bd")
const STONE := Color("#8d8a82")
const WOOD_DARK := Color("#2a1a0e")
const WOOD_LIGHT := Color("#6b4426")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if "theme" in OS.get_cmdline_user_args():
		_build_theme()
	elif "frame" in OS.get_cmdline_user_args():
		_save_frame_parts()
	else:
		_save_frame_parts()
		_save(_parchment(256, 256), "parchment.png")
		_save(_paper(256), "paper.png")
		_save(_wood(256, 256), "wood.png")
		_save(_frame(512, true), "wood_frame.png")
		_save(_frame(96, false), "parchment_card.png")
		_save(_plaque(128, 48), "plaque.png")
		for style in ["normal", "hover", "pressed", "disabled"]:
			_save(_button(64, 40, style), "button_%s.png" % style)
		for style in ["normal", "hover", "pressed"]:
			_save(_shield(128, 150, style), "shield_%s.png" % style)
		_save(_knob(32), "slider_knob.png")
		_save(_groove(32, 12), "slider_groove.png")
	quit()


func _save(image: Image, file: String) -> void:
	image.save_png(OUT.path_join(file))
	print("wrote ", file)


func _noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 4
	return noise


func _n(noise: FastNoiseLite, x: float, y: float) -> float:
	return noise.get_noise_2d(x, y) * 0.5 + 0.5


func _parchment(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var blotches := _noise(3, 0.012)
	var fibres := _noise(9, 0.2)
	for y in height:
		for x in width:
			var c := PARCHMENT.lerp(Color("#cdb98a"), clampf(_n(blotches, x, y) * 1.5 - 0.35, 0.0, 1.0))
			image.set_pixel(x, y, c.darkened((_n(fibres, x, y) - 0.5) * 0.08))
	return image


## Grey paper grain for the map; it multiplies the region colours gently.
func _paper(size: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var blotches := _noise(21, 0.02)
	var fibres := _noise(5, 0.35)
	for y in size:
		for x in size:
			# Mirror-blend so the tile repeats without a seam.
			var v := 0.0
			for corner in [Vector2(x, y), Vector2(size - x, y), Vector2(x, size - y), Vector2(size - x, size - y)]:
				v += 0.8 + 0.14 * _n(blotches, corner.x, corner.y) + 0.06 * _n(fibres, corner.x, corner.y)
			v /= 4.0
			image.set_pixel(x, y, Color(v, v, v))
	return image


func _wood(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var grain := _noise(13, 0.01)
	var fine := _noise(17, 0.25)
	for y in height:
		for x in width:
			var g := _n(grain, x * 0.15, y * 2.0)
			var stripes := 0.5 + 0.5 * sin((x + g * 60.0) * 0.45)
			var c := WOOD_DARK.lerp(WOOD_LIGHT, stripes * 0.45 + _n(fine, x, y) * 0.3)
			image.set_pixel(x, y, c)
	return image


## The order windows' wood and iron (as in S&T): straight vertical grain
## that tiles, and a light grey iron for the riveted frame bars. The windows
## draw them themselves (StFrame), cut at the corners.
func _save_frame_parts() -> void:
	_save(_planks(256, 256), "planks.png")
	_save(_iron(64), "iron.png")


## Fine straight vertical grain in mid brown. Every column's shade comes from
## sums of whole waves across the width, so the texture tiles both ways.
func _planks(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var waves := []  # [waves across the width, phase, weight]
	for k in 26:
		waves.append([rng.randi_range(6, 110), rng.randf() * TAU, rng.randf_range(0.3, 1.0)])
	var columns := PackedFloat32Array()
	for x in width:
		var v := 0.0
		var total := 0.0
		for wave in waves:
			v += wave[2] * sin(TAU * wave[0] * x / width + wave[1])
			total += wave[2]
		columns.append(v / total)
	var lines := PackedFloat32Array()  # A few darker grain lines.
	lines.resize(width)
	for k in 22:
		var at := rng.randi_range(0, width - 1)
		lines[at] = rng.randf_range(0.4, 1.0)
	var flecks := _noise(53, 0.6)
	for y in height:
		var row := TAU * y / height
		for x in width:
			var shade := 0.5 + columns[x] * 1.6 + 0.06 * sin(row * 2.0 + x * 0.7) + (_n(flecks, x, y * 0.15) - 0.5) * 0.12
			shade -= lines[x] * 0.35
			image.set_pixel(x, y, Color("#3f2716").lerp(Color("#7a5434"), clampf(shade, 0.0, 1.0)))
	return image


## Light grey iron with faint mottling, for the frame bars.
func _iron(size: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mottle := _noise(61, 0.08)
	var grit := _noise(67, 0.9)
	for y in size:
		for x in size:
			var a := TAU * x / size
			var b := TAU * y / size
			var m := _n(mottle, cos(a) * 40.0 + 100.0, sin(a) * 40.0 + cos(b) * 40.0)
			var shade := 0.55 + (m - 0.5) * 0.5 + (_n(grit, x, y) - 0.5) * 0.18
			image.set_pixel(x, y, Color("#6f6c64").lerp(Color("#bdb9ae"), clampf(shade, 0.0, 1.0)))
	return image


func _rivet(image: Image, cx: int, cy: int) -> void:
	for y in range(cy - 3, cy + 4):
		for x in range(cx - 3, cx + 4):
			var d := Vector2(x - cx, y - cy).length()
			if d <= 3.0 and x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, Color("#d8d4cb") if d < 1.5 else Color("#55524c"))


## A 9-slice frame: a riveted stone border around dark wood (or parchment).
func _frame(size: int, wood: bool) -> Image:
	var inner := _wood(size, size) if wood else _parchment(size, size)
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var stone := _noise(29, 0.3)
	var border := 14 if wood else 6
	for y in size:
		for x in size:
			var edge := mini(mini(x, y), mini(size - 1 - x, size - 1 - y))
			var c := inner.get_pixel(x, y)
			if edge < border:
				c = STONE.darkened(0.2 - _n(stone, x, y) * 0.35) if wood else Color("#7a5a32").darkened(_n(stone, x, y) * 0.2)
				if edge == 0 or edge == border - 1:
					c = c.darkened(0.45)
				elif edge == 1:
					c = c.lightened(0.2)
			elif edge < border + 4:
				c = c.darkened(0.35 * (1.0 - (edge - border) / 4.0))  # A shadow inside the frame.
			image.set_pixel(x, y, c)
	if wood:
		for i in range(10, size - 6, 18):
			_rivet(image, i, 6)
			_rivet(image, i, size - 7)
			_rivet(image, 6, i)
			_rivet(image, size - 7, i)
	return image


func _plaque(width: int, height: int) -> Image:
	var wood := _wood(width, height)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var edge := mini(mini(x, y), mini(width - 1 - x, height - 1 - y))
			var c := wood.get_pixel(x, y).darkened(0.15)
			if edge < 7:
				c = STONE.darkened(0.25 if edge in [0, 6] else 0.0)
			image.set_pixel(x, y, c)
	for i in range(8, width - 4, 16):
		_rivet(image, i, 3)
		_rivet(image, i, height - 4)
	return image


## A 9-slice wooden button with a dark iron border.
func _button(width: int, height: int, style: String) -> Image:
	var wood := _wood(width, height)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var lift: float = {"normal": 0.0, "hover": 0.18, "pressed": -0.2, "disabled": -0.35}[style]
	for y in height:
		for x in width:
			var edge := mini(mini(x, y), mini(width - 1 - x, height - 1 - y))
			var c := wood.get_pixel(x, y)
			c = c.lightened(lift) if lift > 0 else c.darkened(-lift)
			if style == "disabled":
				c = c.lerp(Color(0.3, 0.28, 0.25), 0.5)
			if edge < 3:
				c = Color("#5e5850") if edge == 1 else Color("#24201c")
			elif edge == 3 and style != "pressed":
				c = c.lightened(0.25)
			var corner := 4.0
			if Vector2(x, y).distance_to(Vector2(clampf(x, corner, width - 1 - corner), clampf(y, corner, height - 1 - corner))) > corner:
				c = Color(0, 0, 0, 0)
			image.set_pixel(x, y, c)
	return image


## A heater shield of wood in a stone rim, for the corner buttons.
func _shield(width: int, height: int, style: String) -> Image:
	var wood := _wood(width, height)
	var stone := _noise(41, 0.25)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var lift: float = {"normal": 0.0, "hover": 0.15, "pressed": -0.15}[style]
	for y in height:
		for x in width:
			var inside := _shield_distance(x, y, width, height)
			var c := Color(0, 0, 0, 0)
			if inside > 11.0:
				c = wood.get_pixel(x, y)
				c = c.lightened(lift) if lift > 0 else c.darkened(-lift)
				c = c.darkened(clampf(1.0 - (inside - 11.0) / 8.0, 0.0, 1.0) * 0.4)
			elif inside > 0.0:
				c = STONE.darkened(0.15 - _n(stone, x, y) * 0.3)
				if inside < 1.5 or (inside > 9.5):
					c = c.darkened(0.5)
				elif inside < 3.0:
					c = c.lightened(0.2)
			image.set_pixel(x, y, c)
	for p in [Vector2(0.18, 0.12), Vector2(0.82, 0.12), Vector2(0.08, 0.45), Vector2(0.92, 0.45), Vector2(0.3, 0.82), Vector2(0.7, 0.82)]:
		_rivet(image, int(p.x * width), int(p.y * height))
	return image


## Distance inside the shield outline, in pixels (negative outside).
func _shield_distance(x: float, y: float, width: float, height: float) -> float:
	var top := 4.0
	var half := width / 2.0 - 4.0
	var cx := width / 2.0
	if y < top:
		return y - top
	var shoulder := height * 0.45
	var side := half
	if y > shoulder:
		var t := (y - shoulder) / (height - 4.0 - shoulder)
		side = half * sqrt(maxf(1.0 - t * t, 0.0))
	return minf(minf(y - top, side - absf(x - cx)), height - 4.0 - y + 1.0)


func _knob(size: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
			var color := Color(0, 0, 0, 0)
			if d < c - 1:
				color = GOLD.lightened(0.2) if d > c - 6 else Color("#c23a2c").lightened(0.25 * (1.0 - d / c))
				if d > c - 2.5:
					color = Color("#3a2410")
			image.set_pixel(x, y, color)
	return image


func _groove(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var edge := mini(y, height - 1 - y)
			image.set_pixel(x, y, Color("#1a100a") if edge > 1 else Color("#5a3a20"))
	return image


func _box(file: String, margin: int, content: Vector4) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(OUT.path_join(file))
	box.texture_margin_left = margin
	box.texture_margin_top = margin
	box.texture_margin_right = margin
	box.texture_margin_bottom = margin
	box.content_margin_left = content.x
	box.content_margin_top = content.y
	box.content_margin_right = content.z
	box.content_margin_bottom = content.w
	return box


func _build_theme() -> void:
	var theme := Theme.new()
	var body: FontFile = load("res://assets/fonts/IMFellEnglish-Regular.ttf")
	var italic: FontFile = load("res://assets/fonts/IMFellEnglish-Italic.ttf")
	var cinzel: FontFile = load("res://assets/fonts/Cinzel.ttf")
	var heading := FontVariation.new()
	heading.base_font = cinzel
	heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	theme.default_font = body
	theme.default_font_size = 19

	# Windows are dark wood in a riveted stone frame, with light text.
	theme.set_stylebox("panel", "PanelContainer", _box("wood_frame.png", 24, Vector4(28, 24, 28, 24)))
	theme.set_stylebox("panel", "Panel", _box("wood_frame.png", 24, Vector4(28, 24, 28, 24)))
	theme.set_type_variation("Parchment", "PanelContainer")
	theme.set_stylebox("panel", "Parchment", _box("parchment_card.png", 10, Vector4(16, 12, 16, 12)))
	theme.set_type_variation("Plaque", "PanelContainer")
	theme.set_stylebox("panel", "Plaque", _box("plaque.png", 12, Vector4(28, 10, 28, 10)))

	for type in ["Button", "OptionButton", "MenuButton"]:
		for style in ["normal", "hover", "pressed", "disabled"]:
			theme.set_stylebox(style, type, _box("button_%s.png" % style, 8, Vector4(14, 7, 14, 7)))
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
		theme.set_font("font", type, heading)
		theme.set_font_size("font_size", type, 15)
		theme.set_color("font_color", type, GOLD)
		theme.set_color("font_hover_color", type, GOLD.lightened(0.35))
		theme.set_color("font_pressed_color", type, GOLD.darkened(0.15))
		theme.set_color("font_focus_color", type, GOLD)
		theme.set_color("font_hover_pressed_color", type, GOLD.lightened(0.2))
		theme.set_color("font_disabled_color", type, Color("#8a7f6a"))
		theme.set_color("icon_normal_color", type, GOLD)
		theme.set_color("icon_hover_color", type, GOLD.lightened(0.35))
		theme.set_color("icon_pressed_color", type, GOLD.darkened(0.15))
		theme.set_color("icon_disabled_color", type, Color("#8a7f6a"))
	theme.set_type_variation("ShieldButton", "Button")
	for style in ["normal", "hover", "pressed"]:
		var shield := StyleBoxTexture.new()
		shield.texture = load(OUT.path_join("shield_%s.png" % style))
		theme.set_stylebox(style, "ShieldButton", shield)
	theme.set_stylebox("disabled", "ShieldButton", theme.get_stylebox("normal", "ShieldButton"))

	for type in ["CheckBox", "CheckButton"]:
		for style in ["normal", "hover", "pressed", "focus"]:
			theme.set_stylebox(style, type, StyleBoxEmpty.new())
		theme.set_color("font_color", type, LIGHT_TEXT)
		theme.set_color("font_hover_color", type, GOLD)
		theme.set_color("font_pressed_color", type, LIGHT_TEXT)

	theme.set_color("font_color", "Label", LIGHT_TEXT)
	theme.set_type_variation("HeadingLabel", "Label")
	theme.set_font("font", "HeadingLabel", heading)
	theme.set_font_size("font_size", "HeadingLabel", 26)
	theme.set_color("font_color", "HeadingLabel", GOLD)
	theme.set_color("font_shadow_color", "HeadingLabel", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_x", "HeadingLabel", 2)
	theme.set_constant("shadow_offset_y", "HeadingLabel", 2)
	theme.set_type_variation("InkLabel", "Label")
	theme.set_color("font_color", "InkLabel", INK)
	theme.set_type_variation("ScriptLabel", "Label")
	theme.set_font("font", "ScriptLabel", italic)
	theme.set_color("font_color", "ScriptLabel", INK)
	theme.set_font_size("font_size", "ScriptLabel", 20)

	theme.set_color("default_color", "RichTextLabel", LIGHT_TEXT)
	theme.set_font("normal_font", "RichTextLabel", body)
	theme.set_font("italics_font", "RichTextLabel", italic)
	theme.set_font("bold_font", "RichTextLabel", heading)
	theme.set_font("bold_italics_font", "RichTextLabel", heading)
	theme.set_font_size("normal_font_size", "RichTextLabel", 18)
	theme.set_font_size("italics_font_size", "RichTextLabel", 18)
	theme.set_font_size("bold_font_size", "RichTextLabel", 15)
	theme.set_font_size("bold_italics_font_size", "RichTextLabel", 15)

	theme.set_stylebox("panel", "PopupMenu", _box("wood_frame.png", 24, Vector4(14, 12, 14, 12)))
	theme.set_stylebox("hover", "PopupMenu", _box("button_hover.png", 8, Vector4(8, 4, 8, 4)))
	theme.set_color("font_color", "PopupMenu", LIGHT_TEXT)
	theme.set_color("font_hover_color", "PopupMenu", GOLD)
	theme.set_color("font_disabled_color", "PopupMenu", Color("#8a7f6a"))
	theme.set_stylebox("panel", "TooltipPanel", _box("parchment_card.png", 10, Vector4(12, 8, 12, 8)))
	theme.set_color("font_color", "TooltipLabel", INK)
	theme.set_font_size("font_size", "TooltipLabel", 17)

	var line := StyleBoxLine.new()
	line.color = Color(GOLD, 0.5)
	line.thickness = 2
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_constant("separation", "HSeparator", 10)

	theme.set_icon("grabber", "HSlider", load(OUT.path_join("slider_knob.png")))
	theme.set_icon("grabber_highlight", "HSlider", load(OUT.path_join("slider_knob.png")))
	var groove := _box("slider_groove.png", 3, Vector4(0, 5, 0, 5))
	theme.set_stylebox("slider", "HSlider", groove)
	var filled := StyleBoxFlat.new()
	filled.bg_color = Color("#7a4a22")
	filled.content_margin_top = 5
	filled.content_margin_bottom = 5
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)

	for bar in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.25)
		track.set_corner_radius_all(4)
		var grabber := StyleBoxFlat.new()
		grabber.bg_color = GOLD.darkened(0.3)
		grabber.set_corner_radius_all(4)
		theme.set_stylebox("scroll", bar, track)
		theme.set_stylebox("grabber", bar, grabber)
		theme.set_stylebox("grabber_highlight", bar, grabber)
		theme.set_stylebox("grabber_pressed", bar, grabber)

	var error := ResourceSaver.save(theme, OUT.path_join("medieval_theme.tres"))
	print("wrote medieval_theme.tres: ", error_string(error))
