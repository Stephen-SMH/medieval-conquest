class_name RoundButton
extends Button
## A round wooden button with a gold rim and a gold glyph, as on the reference
## game's briefing and victory screens (PRD H): "back", "next", "restart",
## "start" (crossed swords), "forge" (the anvil), "map" and "check".
## with_caption() puts a small caption under it, for touch screens with no
## tooltips.

const GOLD := Color("#e2bd5a")
const WOOD := Color("#3a2410")
const TEXTURES := {
	"start": "res://assets/icons/ui_swords.svg",
	"forge": "res://assets/icons/ui_anvil.svg",
	"check": "res://assets/icons/ui_check.svg",
}

var kind := ""
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
	draw_circle(c + Vector2(0, r * 0.06), r, Color(0, 0, 0, 0.45))
	draw_circle(c, r, Color("#7a5a24"))
	draw_circle(c, r * 0.9, gold.darkened(0.25))
	draw_circle(c, r * 0.82, WOOD.lightened(0.08 if mode in [DRAW_PRESSED, DRAW_HOVER_PRESSED] else 0.0))
	draw_arc(c, r * 0.82, PI * 1.1, PI * 1.9, 24, Color(1, 1, 1, 0.12), r * 0.08, true)
	if _texture != null:
		var s := r * 1.0
		draw_texture_rect(_texture, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, gold)
		return
	var w := maxf(r * 0.13, 2.0)
	match kind:
		"back", "next":
			var d := -1.0 if kind == "back" else 1.0
			draw_line(c - Vector2(d * r * 0.38, 0), c + Vector2(d * r * 0.18, 0), gold, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(d * r * 0.45, 0), c + Vector2(d * r * 0.08, -r * 0.3),
				c + Vector2(d * r * 0.08, r * 0.3)]), gold)
		"restart":
			draw_arc(c, r * 0.38, -PI * 0.35, PI * 1.45, 28, gold, w, true)
			var tip := c + Vector2.from_angle(-PI * 0.35) * r * 0.38
			draw_colored_polygon(PackedVector2Array([tip + Vector2(r * 0.2, 0), tip + Vector2(-r * 0.12, -r * 0.18),
				tip + Vector2(-r * 0.08, r * 0.2)]), gold)
		"map":
			var points := PackedVector2Array([c + Vector2(-r * 0.45, -r * 0.3), c + Vector2(-r * 0.15, -r * 0.4), c + Vector2(r * 0.15, -r * 0.3),
				c + Vector2(r * 0.45, -r * 0.4), c + Vector2(r * 0.45, r * 0.3), c + Vector2(r * 0.15, r * 0.4), c + Vector2(-r * 0.15, r * 0.3),
				c + Vector2(-r * 0.45, r * 0.4)])
			draw_colored_polygon(points, gold)
			draw_line(c + Vector2(-r * 0.15, -r * 0.4), c + Vector2(-r * 0.15, r * 0.3), WOOD, w * 0.5, true)
			draw_line(c + Vector2(r * 0.15, -r * 0.3), c + Vector2(r * 0.15, r * 0.4), WOOD, w * 0.5, true)
