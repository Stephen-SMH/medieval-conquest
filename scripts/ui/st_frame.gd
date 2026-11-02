class_name StFrame
extends RefCounted
## The wood-and-iron window of S&T's order windows, drawn rather than
## stretched from an image: planks of straight vertical grain inside a light
## grey iron frame cut at the corners, with dark rivets along the bars, and
## the framed boxes in the bottom corners that hold the check and the X.
## The textures come from tools/make_theme.gd (planks.png, iron.png); the
## canvas item drawing them must repeat its textures.

const BAR := 11.0  # Frame thickness.
const CUT := 15.0  # How much each outer corner is cut off.
const EDGE := Color("#34322d")
const RIVET_SPACING := 46.0

static var _planks: Texture2D
static var _iron: Texture2D


static func planks() -> Texture2D:
	if _planks == null:
		_planks = load("res://assets/ui/planks.png")
	return _planks


static func iron() -> Texture2D:
	if _iron == null:
		_iron = load("res://assets/ui/iron.png")
	return _iron


## A rectangle with its corners cut off, clockwise from the top left.
static func cut_rect(rect: Rect2, cut: float) -> PackedVector2Array:
	var a := rect.position
	var b := rect.end
	return PackedVector2Array([Vector2(a.x + cut, a.y), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut), Vector2(b.x, b.y - cut),
		Vector2(b.x - cut, b.y), Vector2(a.x + cut, b.y), Vector2(a.x, b.y - cut), Vector2(a.x, a.y + cut)])


static func _fill(canvas: CanvasItem, points: PackedVector2Array, texture: Texture2D) -> void:
	var uvs := PackedVector2Array()
	for point in points:
		uvs.append(point / texture.get_size())
	canvas.draw_colored_polygon(points, Color.WHITE, uvs, texture)


static func _outline(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	canvas.draw_polyline(closed, color, width, true)


static func _rivet(canvas: CanvasItem, at: Vector2) -> void:
	canvas.draw_circle(at + Vector2(0.4, 0.8), 2.1, Color(1, 1, 1, 0.25))
	canvas.draw_circle(at, 2.0, Color("#2e2c28"))
	canvas.draw_circle(at - Vector2(0.6, 0.6), 0.7, Color(1, 1, 1, 0.35))


## Rivets along a bar from `from` to `to`, one at each end.
static func _rivets(canvas: CanvasItem, from: Vector2, to: Vector2) -> void:
	var count := maxi(roundi(from.distance_to(to) / RIVET_SPACING), 1)
	for k in count + 1:
		_rivet(canvas, from.lerp(to, float(k) / count))


## The window: iron frame, wood inside with a soft shadow under the frame.
static func draw_panel(canvas: CanvasItem, rect: Rect2) -> void:
	var outer := cut_rect(rect, CUT)
	var inner := cut_rect(rect.grow(-BAR), CUT * 0.55)
	_fill(canvas, outer, iron())
	_fill(canvas, inner, planks())
	for k in 5:
		_outline(canvas, cut_rect(rect.grow(-BAR - 1.0 - k * 2.0), CUT * 0.55), Color(0, 0, 0, 0.3 - k * 0.06), 2.0)
	_outline(canvas, cut_rect(rect.grow(-1.5), CUT - 0.6), Color(1, 1, 1, 0.22), 1.0)
	_outline(canvas, outer, EDGE, 2.0)
	_outline(canvas, inner, EDGE, 1.5)
	var middle := cut_rect(rect.grow(-BAR / 2.0), CUT * 0.8)
	for i in range(0, 8, 2):
		_rivets(canvas, middle[i], middle[i + 1])


## The framed box in a bottom corner of `panel`: an iron bar along its top
## and its inner side, cut where they meet. `box` is the box's own area,
## inside the window's frame; `left` for the bottom-left corner.
static func draw_corner_box(canvas: CanvasItem, panel: Rect2, box: Rect2, left: bool) -> void:
	var top := box.position.y
	var bottom := panel.end.y
	var cut := CUT * 0.8
	var points: PackedVector2Array
	if left:
		var side := box.end.x  # The bar's outer edge, toward the window's middle.
		points = PackedVector2Array([Vector2(panel.position.x + BAR, top), Vector2(side - cut, top), Vector2(side, top + cut), Vector2(side, bottom - BAR),
			Vector2(side - BAR, bottom - BAR), Vector2(side - BAR, top + BAR + cut * 0.4), Vector2(side - BAR - cut * 0.4, top + BAR),
			Vector2(panel.position.x + BAR, top + BAR)])
	else:
		var side := box.position.x
		points = PackedVector2Array([Vector2(panel.end.x - BAR, top), Vector2(side + cut, top), Vector2(side, top + cut), Vector2(side, bottom - BAR),
			Vector2(side + BAR, bottom - BAR), Vector2(side + BAR, top + BAR + cut * 0.4), Vector2(side + BAR + cut * 0.4, top + BAR),
			Vector2(panel.end.x - BAR, top + BAR)])
	# A shadow under the bars, then the bars.
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(0, 3))
	canvas.draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
	_fill(canvas, points, iron())
	_outline(canvas, points, EDGE, 1.5)
	var corner := Vector2(points[1].x, top + BAR / 2.0) if left else Vector2(points[1].x, top + BAR / 2.0)
	_rivets(canvas, Vector2(points[0].x + 6.0 * (1 if left else -1), top + BAR / 2.0), corner)
	var down_x := (box.end.x - BAR / 2.0) if left else (box.position.x + BAR / 2.0)
	_rivets(canvas, Vector2(down_x, top + cut + 4.0), Vector2(down_x, bottom - BAR - 5.0))
