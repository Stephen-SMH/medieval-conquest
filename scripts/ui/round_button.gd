class_name RoundButton
extends Button
## A round wooden button with a gold rim and a gold glyph, as on the reference
## game's briefing, victory and pause screens (PRD H, K): "back", "next",
## "restart", "start" and "objectives" (crossed swords), "forge" (the anvil),
## "map", "check", "resume", "surrender" (a white flag), "info" and "exit";
## and for the main menu's square buttons (SquareButton, PRD M) "tutorial",
## "campaigns", "scenarios", "skirmish", "continue", "records", "settings"
## and "credits".
## with_caption() puts a small caption under it, for touch screens with no
## tooltips.

const GOLD := Color("#e2bd5a")
const WOOD := Color("#3a2410")
const TEXTURES := {
	"start": "res://assets/icons/ui_swords.svg",
	"objectives": "res://assets/icons/ui_swords.svg",
	"forge": "res://assets/icons/ui_anvil.svg",
	"check": "res://assets/icons/ui_check.svg",
	"tutorial": "res://assets/icons/knight.svg",
	"campaigns": "res://assets/icons/map_crown.svg",
	"skirmish": "res://assets/icons/ui_swords.svg",
}

var kind := ""
## S&T's look on its scrolls: a plain dark disc, no gold rim.
var disc := false
var _texture: Texture2D


func _init(button_kind := "", size := 76.0) -> void:
	kind = button_kind
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(size, size)
	if TEXTURES.has(kind):
		_texture = load(TEXTURES[kind])
	Hud.react(self)


static func with_caption(button_kind: String, caption: String, on_pressed: Callable, size := 76.0) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	var button := RoundButton.new(button_kind, size)
	button.tooltip_text = caption
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(on_pressed)
	column.add_child(button)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", load("res://assets/fonts/Cinzel.ttf"))
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", GOLD)
	column.add_child(label)
	return column


func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	var c := size / 2.0
	var mode := get_draw_mode()
	var glow := 1.15 if mode in [DRAW_HOVER, DRAW_HOVER_PRESSED] else 1.0
	var gold := GOLD * glow if not disabled else Color(0.55, 0.5, 0.42)
	if disc:
		for k in 6:
			draw_circle(c, r + 5.0 - k, Color(0, 0, 0, 0.07))
		draw_circle(c, r, Color("#2a1b0e").lightened(0.08 if mode in [DRAW_HOVER, DRAW_HOVER_PRESSED] else 0.0))
		draw_glyph(self, kind, _texture, c, r * 1.25, gold, disabled)
		return
	draw_circle(c + Vector2(0, r * 0.06), r, Color(0, 0, 0, 0.45))
	draw_circle(c, r, Color("#7a5a24"))
	draw_circle(c, r * 0.9, gold.darkened(0.25))
	draw_circle(c, r * 0.82, WOOD.lightened(0.08 if mode in [DRAW_PRESSED, DRAW_HOVER_PRESSED] else 0.0))
	draw_arc(c, r * 0.82, PI * 1.1, PI * 1.9, 24, Color(1, 1, 1, 0.12), r * 0.08, true)
	draw_glyph(self, kind, _texture, c, r, gold, disabled)


## A glyph in gold around `c`, `r` the button's radius: a texture when the
## kind has one, else drawn with lines and polygons.
static func draw_glyph(canvas: CanvasItem, glyph: String, texture: Texture2D, c: Vector2, r: float, gold: Color, off := false) -> void:
	if texture != null:
		var s := r * 1.0
		canvas.draw_texture_rect(texture, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, gold)
		return
	var w := maxf(r * 0.13, 2.0)
	match glyph:
		"castle":
			# S&T's "back": a castle tower with an arrow leaving it.
			var base := c + Vector2(r * 0.05, r * 0.36)
			canvas.draw_rect(Rect2(base + Vector2(-r * 0.05, -r * 0.62), Vector2(r * 0.42, r * 0.62)), gold)
			for k in 3:
				canvas.draw_rect(Rect2(base + Vector2(-r * 0.05 + k * r * 0.16, -r * 0.74), Vector2(r * 0.1, r * 0.14)), gold)
			canvas.draw_rect(Rect2(base + Vector2(r * 0.1, -r * 0.2), Vector2(r * 0.12, r * 0.2)), Color(0.16, 0.1, 0.05))
			canvas.draw_line(c + Vector2(r * 0.2, r * 0.18), c + Vector2(-r * 0.4, r * 0.18), gold, w, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.5, r * 0.18), c + Vector2(-r * 0.3, r * 0.04),
				c + Vector2(-r * 0.3, r * 0.32)]), gold)
		"arrow":
			# S&T's "next" and "start": a long fletched arrow.
			canvas.draw_line(c + Vector2(-r * 0.45, 0), c + Vector2(r * 0.3, 0), gold, w * 0.8, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.5, 0), c + Vector2(r * 0.22, -r * 0.16), c + Vector2(r * 0.28, 0),
				c + Vector2(r * 0.22, r * 0.16)]), gold)
			for k in 2:
				var x := -r * 0.45 + k * r * 0.12
				canvas.draw_line(c + Vector2(x, 0), c + Vector2(x - r * 0.1, -r * 0.13), gold, w * 0.6, true)
				canvas.draw_line(c + Vector2(x, 0), c + Vector2(x - r * 0.1, r * 0.13), gold, w * 0.6, true)
		"replay":
			canvas.draw_arc(c, r * 0.36, -PI * 0.2, PI * 1.55, 28, gold, w, true)
			var tip := c + Vector2.from_angle(-PI * 0.2) * r * 0.36
			canvas.draw_colored_polygon(PackedVector2Array([tip + Vector2(r * 0.12, r * 0.2), tip + Vector2(-r * 0.2, -r * 0.02),
				tip + Vector2(r * 0.16, -r * 0.14)]), gold)
			var tail := c + Vector2.from_angle(PI * 1.55) * r * 0.36
			for k in 2:
				canvas.draw_line(tail + Vector2(-r * 0.12 * (k + 1), 0), tail + Vector2(-r * 0.12 * k - r * 0.04, -r * 0.1), gold, w * 0.6, true)
				canvas.draw_line(tail + Vector2(-r * 0.12 * (k + 1), 0), tail + Vector2(-r * 0.12 * k - r * 0.04, r * 0.1), gold, w * 0.6, true)
		"back", "next":
			var d := -1.0 if glyph == "back" else 1.0
			canvas.draw_line(c - Vector2(d * r * 0.38, 0), c + Vector2(d * r * 0.18, 0), gold, w, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(d * r * 0.45, 0), c + Vector2(d * r * 0.08, -r * 0.3),
				c + Vector2(d * r * 0.08, r * 0.3)]), gold)
		"restart":
			canvas.draw_arc(c, r * 0.38, -PI * 0.35, PI * 1.45, 28, gold, w, true)
			var tip := c + Vector2.from_angle(-PI * 0.35) * r * 0.38
			canvas.draw_colored_polygon(PackedVector2Array([tip + Vector2(r * 0.2, 0), tip + Vector2(-r * 0.12, -r * 0.18),
				tip + Vector2(-r * 0.08, r * 0.2)]), gold)
		"resume", "continue":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.22, -r * 0.38), c + Vector2(r * 0.42, 0), c + Vector2(-r * 0.22, r * 0.38)]), gold)
		"info":
			canvas.draw_circle(c + Vector2(0, -r * 0.36), r * 0.1, gold)
			canvas.draw_line(c + Vector2(0, -r * 0.14), c + Vector2(0, r * 0.4), gold, w * 1.3, true)
			canvas.draw_line(c + Vector2(-r * 0.14, r * 0.4), c + Vector2(r * 0.14, r * 0.4), gold, w * 0.8, true)
		"surrender":
			canvas.draw_line(c + Vector2(-r * 0.3, -r * 0.45), c + Vector2(-r * 0.3, r * 0.45), gold, w * 0.8, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.26, -r * 0.42), c + Vector2(r * 0.42, -r * 0.34),
				c + Vector2(r * 0.3, -r * 0.12), c + Vector2(r * 0.44, r * 0.08), c + Vector2(-r * 0.26, r * 0.04)]), Color("#f4ecd8") if not off else gold)
		"exit":
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.4, -r * 0.42), Vector2(r * 0.5, r * 0.84)), gold, false, w * 0.8)
			canvas.draw_circle(c + Vector2(r * 0.0, r * 0.02), r * 0.05, gold)
			canvas.draw_line(c + Vector2(-r * 0.05, 0), c + Vector2(r * 0.32, 0), gold, w, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.48, 0), c + Vector2(r * 0.26, -r * 0.18), c + Vector2(r * 0.26, r * 0.18)]), gold)
		"map":
			var points := PackedVector2Array([c + Vector2(-r * 0.45, -r * 0.3), c + Vector2(-r * 0.15, -r * 0.4), c + Vector2(r * 0.15, -r * 0.3),
				c + Vector2(r * 0.45, -r * 0.4), c + Vector2(r * 0.45, r * 0.3), c + Vector2(r * 0.15, r * 0.4), c + Vector2(-r * 0.15, r * 0.3),
				c + Vector2(-r * 0.45, r * 0.4)])
			canvas.draw_colored_polygon(points, gold)
			canvas.draw_line(c + Vector2(-r * 0.15, -r * 0.4), c + Vector2(-r * 0.15, r * 0.3), WOOD, w * 0.5, true)
			canvas.draw_line(c + Vector2(r * 0.15, -r * 0.3), c + Vector2(r * 0.15, r * 0.4), WOOD, w * 0.5, true)
		"scroll", "scenarios":
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.32, -r * 0.36), Vector2(r * 0.64, r * 0.72)), gold)
			for y in [-r * 0.4, r * 0.4]:
				canvas.draw_line(c + Vector2(-r * 0.44, y), c + Vector2(r * 0.44, y), gold, w * 1.4, true)
			for y in [-r * 0.15, 0.0, r * 0.15]:
				canvas.draw_line(c + Vector2(-r * 0.2, y), c + Vector2(r * 0.2, y), WOOD, w * 0.4, true)
		"records":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, -r * 0.5), c + Vector2(-r * 0.05, -r * 0.5), c + Vector2(0, -r * 0.05),
				c + Vector2(-r * 0.2, 0)]), gold.darkened(0.25))
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.3, -r * 0.5), c + Vector2(r * 0.05, -r * 0.5), c + Vector2(0, -r * 0.05),
				c + Vector2(r * 0.2, 0)]), gold.darkened(0.25))
			canvas.draw_circle(c + Vector2(0, r * 0.18), r * 0.3, gold)
			TypeIcons.draw_star(canvas, c + Vector2(0, r * 0.18), r * 0.18)
		"settings":
			for k in 8:
				var a := k * PI / 4.0
				canvas.draw_line(c + Vector2.from_angle(a) * r * 0.25, c + Vector2.from_angle(a) * r * 0.46, gold, w * 1.3, true)
			canvas.draw_circle(c, r * 0.32, gold)
			canvas.draw_circle(c, r * 0.13, WOOD)
		"credits":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.4, -r * 0.45), c + Vector2(r * 0.1, -r * 0.05), c + Vector2(-r * 0.3, r * 0.4),
				c + Vector2(-r * 0.12, -r * 0.02), c + Vector2(r * 0.15, -r * 0.3)]), gold)
			canvas.draw_line(c + Vector2(-r * 0.3, r * 0.4), c + Vector2(-r * 0.42, r * 0.5), gold, w * 0.6, true)
