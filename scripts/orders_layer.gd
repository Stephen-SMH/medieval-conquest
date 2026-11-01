class_name OrdersLayer
extends Node2D
## Draws planned orders as big spear-shaped arrows from one region to another
## (PRD 8.3): red to attack, blue to move: a wooden shaft and a steel head
## over a tapered wedge of the order's colour, edged in gold. Only the
## viewer's own orders show while planning; a fainter arrow previews the order
## under the mouse. Clicking an arrow cancels its order.

const ATTACK := Color("#c8402c")
const MOVE := Color("#3a6ed0")
const BESIEGE := Color("#8a5a2a")
const OUTLINE := Color("#e7b74e")
const WOOD := Color("#8a5a2e")
const STEEL := Color("#c9ccd2")

var state: GameState
## Arrows run between the units' feet when set, else between region centres.
var tokens: TokenLayer
## {"from": Vector2, "to": Vector2, "kind": "move"/"attack"} or {} for no preview.
var preview := {}

var _shapes := {}  # Unit -> Array of PackedVector2Array, for clicking.


func _ready() -> void:
	z_index = 5


func _draw() -> void:
	_shapes.clear()
	for unit: Unit in state.orders:
		if unit.owner != state.viewer() or not state.units.has(unit):
			continue
		var from := unit.province
		var shapes := []
		for step in state.orders[unit].steps:
			var color := MOVE if step.type == "move" else (ATTACK if step.type == "attack" else BESIEGE)
			var shape := draw_spear(self, anchor(from), anchor(step.target), color, 1.0)
			shapes.append(shape)
			from = step.target
		_shapes[unit] = shapes
	if not preview.is_empty():
		draw_spear(self, preview.from, preview.to, MOVE if preview.kind == "move" else ATTACK, 0.45)


## Where arrows start and end in a region: at the feet of the unit standing there.
func anchor(region: String) -> Vector2:
	if tokens != null:
		return TokenLayer.layout(state.map.provinces[region].centroid, tokens.token_size()).foot
	return state.map.provinces[region].centroid


## The unit whose arrow is under `point`, or null.
func unit_at(point: Vector2) -> Unit:
	for unit in _shapes:
		for shape: PackedVector2Array in _shapes[unit]:
			if Geometry2D.is_point_in_polygon(point, shape):
				return unit
	return null


## Draws a spear arrow on `canvas` and returns its outline polygon (for
## clicking): a faint wedge of the order's colour behind a long wooden shaft,
## a coloured binding below an iron socket, and a leaf-shaped steel head
## tinted with the order's colour, all edged in gold.
static func draw_spear(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, strength: float) -> PackedVector2Array:
	var g := spear_geometry(from, to)
	if g.is_empty():
		return PackedVector2Array()
	var direction: Vector2 = g.direction
	var normal: Vector2 = g.normal
	var start: Vector2 = g.start
	var end: Vector2 = g.end
	var socket: Vector2 = g.socket
	var tail: float = g.tail
	var head_length: float = g.head_length
	var head_width: float = g.head_width
	var a := strength

	# The wake: a translucent wedge of the order's colour, wide at the tail.
	var wake := PackedVector2Array([start + normal * tail, socket + normal * 5.0, socket - normal * 5.0, start - normal * tail])
	canvas.draw_polygon(wake, PackedColorArray([Color(color, 0.42 * a), Color(color, 0.78 * a), Color(color, 0.78 * a), Color(color, 0.42 * a)]))
	var wake_line := wake.duplicate()
	wake_line.append(wake[0])
	canvas.draw_polyline(wake_line, Color(OUTLINE, 0.9 * a), 2.0, true)

	# The shaft: dark edge, wood, and a light grain line along it.
	var butt := start - direction * 6.0
	canvas.draw_line(butt, socket + direction * 2.0, Color(0.12, 0.07, 0.03, 0.9 * a), 7.2, true)
	canvas.draw_line(butt, socket + direction * 2.0, Color(WOOD, a), 4.6, true)
	canvas.draw_line(butt + normal * 1.0, socket + normal * 1.0, Color(WOOD.lightened(0.35), 0.9 * a), 1.3, true)
	canvas.draw_line(butt - direction * 3.0, butt + direction * 3.0, Color(0.25, 0.25, 0.27, a), 6.0, true)  # Iron butt cap.

	# A coloured binding just below the socket, then the socket ring.
	for i in 3:
		var at := socket - direction * (6.0 + i * 4.5)
		canvas.draw_line(at + normal * 4.2, at - normal * 4.2, Color(0.1, 0.05, 0.02, 0.85 * a), 3.6, true)
		canvas.draw_line(at + normal * 3.6, at - normal * 3.6, Color(color.lightened(0.1), a), 2.4, true)
	canvas.draw_line(socket - direction * 2.0 + normal * 4.0, socket - direction * 2.0 - normal * 4.0, Color(0.12, 0.12, 0.13, a), 5.0, true)
	canvas.draw_line(socket - direction * 2.0 + normal * 3.2, socket - direction * 2.0 - normal * 3.2, Color(STEEL, a), 3.0, true)

	# The head: leaf-shaped, lit on one side of the ridge and shaded on the other.
	var widest := socket + direction * head_length * 0.38
	var left := PackedVector2Array([socket + normal * 2.6, widest + normal * head_width, socket + direction * head_length * 0.75 + normal * head_width * 0.45, end])
	var right := PackedVector2Array([socket - normal * 2.6, widest - normal * head_width, socket + direction * head_length * 0.75 - normal * head_width * 0.45, end])
	var steel := STEEL.lerp(color, 0.62)
	var outline := PackedVector2Array([socket, left[0], left[1], left[2], end, right[2], right[1], right[0]])
	var ring := outline.duplicate()
	ring.append(outline[0])
	canvas.draw_polyline(ring, Color(0.08, 0.05, 0.03, 0.9 * a), 3.4, true)
	canvas.draw_colored_polygon(PackedVector2Array([socket, left[0], left[1], left[2], end]), Color(steel.lightened(0.3), a))
	canvas.draw_colored_polygon(PackedVector2Array([socket, end, right[2], right[1], right[0]]), Color(steel.darkened(0.2), a))
	canvas.draw_line(socket, end, Color(steel.lightened(0.55), 0.9 * a), 1.2, true)  # The ridge.
	canvas.draw_polyline(ring, Color(OUTLINE, 0.95 * a), 1.4, true)

	return g.shape


## The measurements of a spear arrow between two points, and the outline a
## click hits (the wake and the head); empty when the points are too close.
static func spear_geometry(from: Vector2, to: Vector2) -> Dictionary:
	var direction := (to - from).normalized()
	var normal := direction.orthogonal()
	var start := from + direction * 22.0
	var end := to - direction * 14.0
	var length := start.distance_to(end)
	if length < 20.0:
		return {}
	var head_length := clampf(length * 0.17, 26.0, 42.0)
	var head_width := clampf(head_length * 0.32, 9.0, 13.5)
	var socket := end - direction * head_length
	var tail := clampf(length * 0.13, 12.0, 28.0)
	var widest := socket + direction * head_length * 0.38
	var shape := PackedVector2Array([start + normal * tail, socket + normal * 6.0, widest + normal * head_width, end,
		widest - normal * head_width, socket - normal * 6.0, start - normal * tail])
	return {"direction": direction, "normal": normal, "start": start, "end": end, "socket": socket, "tail": tail,
		"head_length": head_length, "head_width": head_width, "shape": shape}
