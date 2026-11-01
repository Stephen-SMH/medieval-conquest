class_name OrdersLayer
extends Node2D
## Draws planned orders as big spear-shaped arrows from one region to another
## (PRD 8.3): red to attack, blue to move, with a gold outline and a tapered
## tail. Only the viewer's own orders show while planning; a fainter arrow
## previews the order under the mouse. Clicking an arrow cancels its order.

const ATTACK := Color("#c8402c")
const MOVE := Color("#3a6ed0")
const BESIEGE := Color("#8a5a2a")
const OUTLINE := Color("#e7b74e")

var state: GameState
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
			var shape := draw_spear(self, _centre(from), _centre(step.target), color, 1.0)
			shapes.append(shape)
			from = step.target
		_shapes[unit] = shapes
	if not preview.is_empty():
		draw_spear(self, preview.from, preview.to, MOVE if preview.kind == "move" else ATTACK, 0.45)


func _centre(region: String) -> Vector2:
	return state.map.provinces[region].centroid


## The unit whose arrow is under `point`, or null.
func unit_at(point: Vector2) -> Unit:
	for unit in _shapes:
		for shape: PackedVector2Array in _shapes[unit]:
			if Geometry2D.is_point_in_polygon(point, shape):
				return unit
	return null


## Draws a spear arrow on `canvas` and returns its outline polygon.
static func draw_spear(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, strength: float) -> PackedVector2Array:
	var direction := (to - from).normalized()
	var normal := direction.orthogonal()
	var start := from + direction * 22.0
	var end := to - direction * 14.0
	var length := start.distance_to(end)
	if length < 20.0:
		return PackedVector2Array()
	var tail := clampf(length * 0.2, 14.0, 30.0)
	# [position along the arrow (0 to 1), half width]: a tapered tail, the shaft, a socket ring and a leaf-shaped head.
	var head := clampf(length * 0.075, 11.0, 17.0)
	var profile := [[0.0, tail], [0.6, 4.0], [0.63, 7.5], [0.66, 4.0], [0.7, 6.0], [0.84, head], [1.0, 0.0]]
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var colors_left := PackedColorArray()
	var colors_right := PackedColorArray()
	for point in profile:
		var at: Vector2 = start + direction * length * point[0]
		left.append(at + normal * point[1])
		right.append(at - normal * point[1])
		var alpha: float = lerpf(0.35, 0.92, clampf(point[0] * 1.3, 0.0, 1.0)) * strength
		colors_left.append(Color(color, alpha))
		colors_right.append(Color(color, alpha))
	right.reverse()
	colors_right.reverse()
	var shape := left + right
	var colors := colors_left + colors_right
	canvas.draw_polygon(shape, colors)
	var outline := shape.duplicate()
	outline.append(shape[0])
	canvas.draw_polyline(outline, Color(OUTLINE, 0.95 * strength), 2.0, true)
	return shape
