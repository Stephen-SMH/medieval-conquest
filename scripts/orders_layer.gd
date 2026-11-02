class_name OrdersLayer
extends Node2D
## Draws planned orders as big spear-shaped arrows from one region to another
## (PRD 8.3, B, C): red to attack, blue to move, darker red to support another
## attack (so several arrows converge on one target): a wooden shaft and a steel head
## over a tapered wedge of the order's colour, edged in gold. Only the
## orders of the faction whose turn it is show: yours while you plan, an
## enemy's (where you can see) while its turn plays out. A fainter arrow
## previews the order under the mouse, or follows the pointer while you drag
## from your army (PRD I). A unit split across several orders has one arrow per
## detachment, each with a small shield showing how many soldiers go.
## Clicking an arrow cancels that one order. When the hourglass is pressed
## the arrows stay on the map while the turn plays out, as in S&T (`playing`):
## the arrows aimed at a battle burn while it's fought, and each arrow goes
## once its order has been carried out.

const ATTACK := Color("#c8402c")
const MOVE := Color("#3a6ed0")
const BESIEGE := Color("#8a5a2a")
const SUPPORT := Color("#9a2a4a")
const OUTLINE := Color("#e7b74e")
const WOOD := Color("#8a5a2e")
const STEEL := Color("#c9ccd2")

var state: GameState
## Arrows run between the units' feet when set, else between region centres.
var tokens: TokenLayer
## {"from": region, "to": region, "kind": "move"/"attack"} (or map points
## instead of regions) or {} for no preview.
var preview := {}

var _shapes := []  # [Unit, order index, PackedVector2Array], for clicking.
var _font: Font
## The arrows of a turn being played out: [{from, to (the last target),
## points, colors, count}], from snapshot(). Empty while planning.
var playing := []
var _burning := {}  # target region -> true while its battle is fought
var _clock := 0.0


func _ready() -> void:
	z_index = 5
	_font = load("res://assets/fonts/IMFellEnglish-Italic.ttf")


## The arrows the current faction's orders show now: [{unit, index, from,
## to, points, colors, count}] (count 0 when the arrow sends the whole army).
func arrows() -> Array:
	var result := []
	var seen := state.visible_provinces(state.viewer())
	for unit: Unit in state.orders:
		if unit.owner != state.current_faction() or not state.units.has(unit):
			continue
		if unit.owner != state.viewer() and not seen.has(unit.province):
			continue
		var list: Array = state.orders[unit]
		for index in list.size():
			var steps: Array = list[index].steps
			var colors := []
			for step in steps:
				var color := MOVE if step.type == "move" else (ATTACK if step.type == "attack" else BESIEGE)
				colors.append(SUPPORT if step.type == "attack" and list[index].get("support", false) else color)
			var count := int(list[index].size) if list.size() > 1 or int(list[index].size) < unit.soldiers() else 0
			result.append({"unit": unit, "index": index, "from": unit.province, "to": steps.back().target,
				"points": route(unit, index), "colors": colors, "count": count})
	return result


## Keeps this turn's arrows on the map while it plays out.
func snapshot() -> void:
	playing = arrows()
	_burning.clear()
	queue_redraw()


## The arrows aimed at `region` burn while its battle is fought.
func burn(region: String, on := true) -> void:
	if on:
		_burning[region] = true
	else:
		_burning.erase(region)
	queue_redraw()


## Removes the arrows to `region` (only those from `from`, if given): their
## orders have been carried out.
func drop(region: String, from := "") -> void:
	playing = playing.filter(func(a): return a.to != region or (from != "" and a.from != from))
	queue_redraw()


func stop_playing() -> void:
	playing.clear()
	_burning.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if not _burning.is_empty():
		_clock += delta
		queue_redraw()


func _draw() -> void:
	_shapes.clear()
	var counts := []  # Drawn last, above every arrow and the preview.
	for arrow in (playing if not playing.is_empty() else arrows()):
		var points: Array = arrow.points
		for i in points.size() - 1:
			var shape := draw_spear(self, points[i], points[i + 1], arrow.colors[i], 1.0)
			if arrow.has("unit"):
				_shapes.append([arrow.unit, arrow.index, shape])
			if _burning.has(arrow.to) and i == points.size() - 2:
				_draw_fire(points[i], points[i + 1])
		if arrow.count > 0:
			counts.append([points[0].lerp(points[1], 0.42), arrow.count])
	if not preview.is_empty():
		var ends: Array = route_through([preview.from, preview.to]) if preview.from is String else [preview.from, preview.to]
		draw_spear(self, ends[0], ends[1], MOVE if preview.kind == "move" else ATTACK, 0.45)
	for count in counts:
		_draw_count(count[0], count[1])


## Where arrows start and end in a region: at the feet of the unit standing there.
func anchor(region: String) -> Vector2:
	if tokens != null:
		return TokenLayer.layout(state.map.provinces[region].centroid, tokens.token_size()).foot
	return state.map.provinces[region].centroid


## The points an order's arrows run through: from the unit's feet, through
## each waypoint, to the last target, each moved off the region's name (see joint()).
func route(unit: Unit, index := 0) -> Array:
	var regions := [unit.province]
	var list: Array = state.orders.get(unit, [])
	if index < list.size():
		for step in list[index].steps:
			regions.append(step.target)
	return route_through(regions)


## How many soldiers a detachment takes, on a small round shield on its arrow.
func _draw_count(at: Vector2, count: int) -> void:
	var r := _size() * 0.2
	draw_circle(at, r + 2.0, Color(0.1, 0.06, 0.03, 0.9))
	draw_circle(at, r, Color("#f1e3bd"))
	draw_arc(at, r, 0.0, TAU, 24, OUTLINE, 2.0, true)
	var text := str(count)
	var font_size := int(r * 1.25)
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, at + Vector2(-width / 2.0, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#1d130a"))


## Flames licking along an arrow whose battle is being fought, as in S&T:
## flickering orange and yellow tongues that run toward the target.
func _draw_fire(from: Vector2, to: Vector2) -> void:
	var g := spear_geometry(from, to)
	if g.is_empty():
		return
	var direction: Vector2 = g.direction
	var normal: Vector2 = g.normal
	var length: float = (g.end - g.start).length()
	var count := maxi(int(length / 9.0), 4)
	for k in count:
		var t := fposmod(float(k) / count + _clock * 0.9, 1.0)
		var at: Vector2 = g.start + direction * length * t
		var width: float = lerpf(g.tail, 5.0, t) * 0.8
		var flicker := 0.6 + 0.4 * sin(_clock * 17.0 + k * 2.3)
		var side := normal * sin(k * 1.7 + _clock * 6.0) * width * 0.5
		var tip := at + side - normal * width * 0.1 + direction * 10.0 * flicker
		var flame := PackedVector2Array([at + side + normal * width * 0.45 * flicker, tip, at + side - normal * width * 0.45 * flicker,
			at + side - direction * 6.0])
		draw_colored_polygon(flame, Color(1.0, 0.42 + 0.3 * flicker, 0.08, 0.55 * flicker))
		draw_circle(at + side * 0.5, width * 0.18 * flicker, Color(1.0, 0.9, 0.45, 0.6 * flicker))


## The points an arrow through these regions runs through, clear of their names.
func route_through(regions: Array) -> Array:
	return route_points(regions.map(anchor), regions.map(func(r): return name_rect(state.map, r)), _size())


## Moves each point of an arrow's path (normally the feet of the unit's spot
## in that region) off its region's name: two passes, so each point sees
## where its neighbours ended up.
static func route_points(anchors: Array, labels: Array, size: float) -> Array:
	var points := anchors.duplicate()
	for pass_number in 2:
		for i in points.size():
			var before = points[i - 1] if i > 0 else null
			var after = points[i + 1] if i < points.size() - 1 else null
			points[i] = joint(before, anchors[i], after, labels[i], size)
	return points


func _size() -> float:
	return tokens.token_size() if tokens != null else 50.0


static var _label_font: Font


## The box a region's name and gold line fill on the map, measured to the text.
static func name_rect(map: MapData, region: String) -> Rect2:
	if _label_font == null:
		_label_font = load("res://assets/fonts/IMFellEnglish-Regular.ttf")
	var centroid: Vector2 = map.provinces[region].centroid
	var width := _label_font.get_string_size(map.region_name(region), HORIZONTAL_ALIGNMENT_LEFT, -1, MapDecor.LABEL_SIZE).x
	var top := MapDecor.label_rect(centroid).position.y
	return Rect2(Vector2(centroid.x - width / 2.0 - 6.0, top - 2.0), Vector2(width + 12.0, centroid.y + 54.0 - top))


## Where an arrow starts, ends or turns (at a two-step order's waypoint) in a
## region. Normally at the feet of the unit's spot there; when an arrow to or
## from that point would cross the region's name, the point moves up or to the
## side so the name stays readable. `from` or `to` is null at the ends.
static func joint(from, foot: Vector2, to, label: Rect2, size: float) -> Vector2:
	var aside := label.size.x * 0.5 + 18.0
	var candidates := []
	for dy in [0.0, -0.45, -0.9, -1.35]:
		for dx in [0.0, -1.0, 1.0, -1.5, 1.5, -2.1, 2.1]:
			candidates.append(foot + Vector2(dx * aside, dy * size))
	candidates.sort_custom(func(a, b): return a.distance_squared_to(foot) < b.distance_squared_to(foot))
	# The first point that keeps the name clear; when none can (a sharp V
	# around the name), the one that covers least of it.
	var best := foot
	var least := INF
	for candidate in candidates:
		var covered := (0.0 if from == null else spear_cover(from, candidate, label)) + (0.0 if to == null else spear_cover(candidate, to, label))
		if covered <= 0.0:
			return candidate
		if covered < least - 1.0:
			least = covered
			best = candidate
	return best


## Whether a spear arrow between two points covers any of `rect`.
static func spear_crosses(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	return spear_cover(from, to, rect) > 0.0


## How much of `rect` (in square pixels) a spear arrow between two points covers.
static func spear_cover(from: Vector2, to: Vector2, rect: Rect2) -> float:
	var g := spear_geometry(from, to)
	if g.is_empty():
		return 0.0
	var box := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var area := 0.0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(g.shape, box):
		area += absf(MapData.polygon_area(piece))
	return area


## The order whose arrow is under `point`: [unit, order index], or [].
func order_at(point: Vector2) -> Array:
	for i in range(_shapes.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(point, _shapes[i][2]):
			return [_shapes[i][0], _shapes[i][1]]
	return []


## The unit whose arrow is under `point`, or null.
func unit_at(point: Vector2) -> Unit:
	var hit := order_at(point)
	return hit[0] if not hit.is_empty() else null


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
