class_name SquareButton
extends Button
## A square wooden button for the main menu's bottom row (PRD M): a dark
## plank in a gold-edged frame, a gold glyph (see RoundButton.draw_glyph) and
## a caption under it.

const SIZE := Vector2(118, 112)

var kind := ""
var caption := ""
var _texture: Texture2D
var _font: Font


func _init(button_kind := "", button_caption := "") -> void:
	kind = button_kind
	caption = button_caption
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = SIZE
	tooltip_text = caption
	if RoundButton.TEXTURES.has(kind):
		_texture = load(RoundButton.TEXTURES[kind])
	_font = load("res://assets/fonts/Cinzel.ttf")
	Hud.react(self)


func _draw() -> void:
	var mode := get_draw_mode()
	var lit := mode in [DRAW_HOVER, DRAW_HOVER_PRESSED]
	var gold := RoundButton.GOLD * (1.15 if lit else 1.0) if not disabled else Color(0.55, 0.5, 0.42)
	var box := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	draw_rect(Rect2(box.position + Vector2(0, 4), box.size), Color(0, 0, 0, 0.45))
	draw_rect(box, Color("#7a5a24"))
	draw_rect(box.grow(-3), gold.darkened(0.3))
	var plank := box.grow(-7)
	draw_rect(plank, RoundButton.WOOD.lightened(0.1 if mode in [DRAW_PRESSED, DRAW_HOVER_PRESSED] else 0.03))
	for i in range(1, 4):  # Wood grain.
		var y := plank.position.y + plank.size.y * i / 4.0
		draw_line(Vector2(plank.position.x + 6, y), Vector2(plank.end.x - 6, y + 2), Color(0, 0, 0, 0.18), 1.0)
	for corner in [plank.position + Vector2(6, 6), Vector2(plank.end.x - 6, plank.position.y + 6),
			Vector2(plank.position.x + 6, plank.end.y - 6), plank.end - Vector2(6, 6)]:
		draw_circle(corner, 2.5, gold.darkened(0.2))
	var r := minf(plank.size.x, plank.size.y) * 0.42
	RoundButton.draw_glyph(self, kind, _texture, Vector2(size.x / 2.0, plank.position.y + r + 6), r, gold, disabled)
	var font_size := 14
	draw_string(_font, Vector2(0, plank.end.y - 9), caption.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, gold)
