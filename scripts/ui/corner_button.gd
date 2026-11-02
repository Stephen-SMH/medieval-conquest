class_name CornerButton
extends Button
## The check or the X in a bottom corner box of a wood window (StFrame), as
## in S&T: a gold brushed mark that brightens under the pointer.

const GOLD := Color("#e4b84a")
const GOLD_LIGHT := Color("#ffe08a")
const SHADOW := Color(0.12, 0.07, 0.02, 0.75)

var kind := "check"  # "check" or "cross"


func _init(mark := "check") -> void:
	kind = mark
	flat = true
	focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var c := size / 2.0 + (Vector2(0, 1.5) if is_pressed() else Vector2.ZERO)
	var s := minf(size.x, size.y) * 0.3
	var color := GOLD_LIGHT if is_hovered() else GOLD
	var strokes := []
	if kind == "check":
		strokes = [[c + Vector2(-s * 0.95, -s * 0.05), c + Vector2(-s * 0.3, s * 0.75), s * 0.34, s * 0.42],
			[c + Vector2(-s * 0.3, s * 0.75), c + Vector2(s * 1.05, -s * 0.95), s * 0.4, s * 0.12]]
	else:
		strokes = [[c + Vector2(-s * 0.85, -s * 0.85), c + Vector2(s * 0.85, s * 0.85), s * 0.3, s * 0.3],
			[c + Vector2(s * 0.85, -s * 0.85), c + Vector2(-s * 0.85, s * 0.85), s * 0.3, s * 0.3]]
	for pass_shadow in [true, false]:
		for stroke in strokes:
			var offset := Vector2(1.5, 2.0) if pass_shadow else Vector2.ZERO
			_brush(stroke[0] + offset, stroke[1] + offset, stroke[2], stroke[3], SHADOW if pass_shadow else color)


## A stroke that tapers from width `from_width` to `to_width`, like a brush.
func _brush(a: Vector2, b: Vector2, from_width: float, to_width: float, color: Color) -> void:
	var normal := (b - a).normalized().orthogonal()
	draw_colored_polygon(PackedVector2Array([a + normal * from_width / 2.0, b + normal * to_width / 2.0,
		b - normal * to_width / 2.0, a - normal * from_width / 2.0]), color)
	draw_circle(a, from_width / 2.0, color)
	draw_circle(b, to_width / 2.0, color)
