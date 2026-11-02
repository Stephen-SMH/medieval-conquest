class_name DotSlider
extends HSlider
## The order windows' slider, as in S&T: a dark groove, a row of small dots
## under it and a gold ring knob with a red jewel. Godot's own groove and
## grabber are hidden (a clear grabber of the knob's size keeps dragging
## lined up); this draws them instead.

const KNOB := 21.0
const DOTS := 11
const GROOVE_Y := 16.0
const DOTS_Y := 31.0

static var _clear: Texture2D


func _init() -> void:
	var groove := StyleBoxEmpty.new()
	groove.content_margin_top = 4.0
	groove.content_margin_bottom = 4.0
	add_theme_stylebox_override("slider", groove)
	add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	if _clear == null:
		_clear = ImageTexture.create_from_image(Image.create(int(KNOB), int(KNOB), false, Image.FORMAT_RGBA8))
	for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
		add_theme_icon_override(icon, _clear)
	tick_count = 0
	step = 1
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(156, 40)
	value_changed.connect(func(_v): queue_redraw())
	changed.connect(queue_redraw)


func _draw() -> void:
	var left := KNOB / 2.0
	var right := size.x - KNOB / 2.0
	draw_line(Vector2(left, GROOVE_Y), Vector2(right, GROOVE_Y), Color("#24130a"), 7.0)
	draw_line(Vector2(left, GROOVE_Y + 4.0), Vector2(right, GROOVE_Y + 4.0), Color(1, 0.9, 0.75, 0.08), 1.0)
	for k in DOTS:
		draw_circle(Vector2(lerpf(left, right, float(k) / (DOTS - 1)), DOTS_Y), 1.2, Color(1, 0.95, 0.85, 0.7))
	var ratio := 0.0 if max_value <= min_value else (value - min_value) / (max_value - min_value)
	var c := Vector2(left + ratio * (right - left), GROOVE_Y)
	var r := KNOB / 2.0
	draw_circle(c + Vector2(0, 1.5), r, Color(0, 0, 0, 0.4))
	draw_circle(c, r, Color("#8c6424"))
	draw_circle(c, r - 1.3, Color("#efd396"))
	draw_circle(c - Vector2(r * 0.25, r * 0.3), r * 0.5, Color(1, 1, 0.92, 0.35))
	draw_circle(c, r * 0.46, Color("#6e1009"))
	draw_circle(c, r * 0.38, Color("#c4291b"))
	draw_circle(c - Vector2(r * 0.12, r * 0.14), r * 0.13, Color(1, 0.75, 0.65, 0.7))
