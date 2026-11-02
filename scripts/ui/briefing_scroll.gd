class_name BriefingScroll
extends MarginContainer
## The mission briefing as an unrolled scroll (PRD H): parchment between two
## dark wooden rods with gold knobs, the text in ink.

const WIDTH := 780.0
const ROD := 20.0
const INK := Color("#2f2012")

var _text: RichTextLabel


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("margin_top", int(ROD))
	add_theme_constant_override("margin_bottom", int(ROD))
	add_theme_constant_override("margin_left", int(ROD * 0.8))
	add_theme_constant_override("margin_right", int(ROD * 0.8))
	var paper := PanelContainer.new()
	paper.theme_type_variation = "Parchment"
	add_child(paper)
	var inner := MarginContainer.new()
	for side in ["left", "right"]:
		inner.add_theme_constant_override("margin_" + side, 30)
	for side in ["top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 14)
	paper.add_child(inner)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.add_theme_color_override("default_color", INK)
	_text.add_theme_font_size_override("normal_font_size", 18)
	_text.add_theme_font_size_override("bold_font_size", 18)
	_text.add_theme_font_size_override("italics_font_size", 19)
	inner.add_child(_text)


func set_text(bbcode: String) -> void:
	_text.text = bbcode


func _draw() -> void:
	for y in [0.0, size.y - ROD]:
		_rod(Rect2(Vector2(0, y), Vector2(size.x, ROD)))


## A turned wooden rod with a gold knob at each end.
func _rod(box: Rect2) -> void:
	var r := box.size.y / 2.0
	var bar := Rect2(box.position + Vector2(r, 0), Vector2(box.size.x - 2 * r, box.size.y))
	draw_rect(Rect2(bar.position + Vector2(0, 3), bar.size), Color(0, 0, 0, 0.35))
	draw_rect(bar, Color("#4a2c14"))
	draw_rect(Rect2(bar.position + Vector2(0, box.size.y * 0.18), Vector2(bar.size.x, box.size.y * 0.22)), Color("#7a4e26"))
	draw_rect(Rect2(bar.position + Vector2(0, box.size.y * 0.75), Vector2(bar.size.x, box.size.y * 0.25)), Color("#2c180a"))
	for x in [box.position.x + r, box.end.x - r]:
		var c := Vector2(x, box.position.y + r)
		draw_circle(c + Vector2(0, 2), r * 1.15, Color(0, 0, 0, 0.35))
		draw_circle(c, r * 1.15, Color("#9c7a2c"))
		draw_circle(c, r * 0.95, Color("#e2bd5a"))
		draw_circle(c - Vector2(r * 0.3, r * 0.3), r * 0.35, Color(1, 0.96, 0.8, 0.6))
