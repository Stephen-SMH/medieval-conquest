class_name TokenLayer
extends Node2D
## Draws every visible unit as a token above its region (PRD UT-2, UT-3): the
## unit-type icon, a health bar, the soldier count, rank stars and a general's
## badge, up to 4 side by side. Regions with walls show a castle behind the
## tokens. Also plays the short battle effects (BR-4): shaking tokens and
## floating numbers.

const TOKEN := Vector2(40, 40)
const SPACING := 44.0
const ROW_OFFSET := Vector2(0, -48)  # From the region centre to the top of the token row.
const BAR_HEIGHT := 5.0
const SELECTED_COLOR := Color(1.0, 0.85, 0.3)
const OUTLINE_COLOR := Color(0.08, 0.06, 0.05)
const ICON_COLOR := Color(0.97, 0.95, 0.9)
const SHAKE_TIME := 0.6
const FLOAT_TIME := 1.6

var state: GameState
var selected: Array[Unit] = []
## Regions whose units the viewer can see; null shows everything.
var visible_provinces = null

var _rects := {}  # Unit -> Rect2, from the last draw, for clicking.
var _shakes := {}  # region -> seconds left
var _floats := []  # {position, text, color, time}


func _ready() -> void:
	z_index = 5


func _process(delta: float) -> void:
	if _shakes.is_empty() and _floats.is_empty():
		return
	for region in _shakes.keys():
		_shakes[region] -= delta
		if _shakes[region] <= 0.0:
			_shakes.erase(region)
	for effect in _floats:
		effect.time -= delta
	_floats = _floats.filter(func(e): return e.time > 0.0)
	queue_redraw()


func shake(region: String) -> void:
	_shakes[region] = SHAKE_TIME
	queue_redraw()


## Shows text rising from a point on the map, e.g. "−6" over a hurt unit.
func float_text(at: Vector2, text: String, color: Color) -> void:
	_floats.append({"position": at, "text": text, "color": color, "time": FLOAT_TIME})
	queue_redraw()


func is_animating() -> bool:
	return not _shakes.is_empty() or not _floats.is_empty()


func visible_units() -> Array[Unit]:
	var shown: Array[Unit] = []
	for unit in state.units:
		if visible_provinces == null or unit.owner == state.viewer() or visible_provinces.has(unit.province):
			shown.append(unit)
	return shown


## The rectangle a unit's token takes on the map.
func token_rect(unit: Unit) -> Rect2:
	var here := visible_units().filter(func(u: Unit): return u.province == unit.province)
	var index := here.find(unit)
	var centre: Vector2 = state.map.provinces[unit.province].centroid + ROW_OFFSET
	var x := centre.x + (index - (here.size() - 1) / 2.0) * SPACING - TOKEN.x / 2.0
	return Rect2(Vector2(x, centre.y), TOKEN)


## The unit whose token is under `point` (map coordinates), or null.
func unit_at(point: Vector2) -> Unit:
	for unit in _rects:
		if _rects[unit].grow(2.0).has_point(point):
			return unit
	return null


func _draw() -> void:
	_rects.clear()
	var font := ThemeDB.fallback_font
	for region in state.map.province_order:
		if Sieges.walls(state, region) > 0:
			_draw_castle(state.map.provinces[region].centroid + ROW_OFFSET + Vector2(0, 20), Sieges.walls(state, region))
	for unit in visible_units():
		var rect := token_rect(unit)
		if _shakes.has(unit.province):
			rect.position.x += sin(_shakes[unit.province] * 60.0) * 3.0
		_rects[unit] = rect
		_draw_token(unit, rect, font)
	for effect in _floats:
		var rise: float = (1.0 - effect.time / FLOAT_TIME) * 30.0
		var color: Color = effect.color
		color.a = clampf(effect.time / FLOAT_TIME * 2.0, 0.0, 1.0)
		var at: Vector2 = effect.position - Vector2(40, rise)
		draw_string_outline(font, at, effect.text, HORIZONTAL_ALIGNMENT_CENTER, 80, 16, 4, Color(0, 0, 0, color.a))
		draw_string(font, at, effect.text, HORIZONTAL_ALIGNMENT_CENTER, 80, 16, color)


func _draw_token(unit: Unit, rect: Rect2, font: Font) -> void:
	var unit_type := unit.type()
	var spent := unit.owner == state.current_faction() and (unit.attacked or unit.move_points_left == 0)
	var base := state.faction_color(unit.owner).darkened(0.15)
	if spent:
		base = base.darkened(0.35)
	draw_rect(rect, base)
	var is_selected := selected.has(unit)
	draw_rect(rect, SELECTED_COLOR if is_selected else OUTLINE_COLOR, false, 3.0 if is_selected else 1.5)
	_draw_icon(unit_type, Rect2(rect.position + Vector2(4, 4), Vector2(24, 24)), ICON_COLOR if not spent else ICON_COLOR.darkened(0.3))
	if unit_type.civilization != "":
		# A small diamond marks a civilization's special unit.
		var corner := rect.position + Vector2(rect.size.x - 7, 7)
		draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -4.5), corner + Vector2(4.5, 0),
			corner + Vector2(0, 4.5), corner + Vector2(-4.5, 0)]), SELECTED_COLOR)

	# Soldier count, bottom right.
	var count := str(unit.soldiers())
	var count_at := rect.position + Vector2(rect.size.x - 23, rect.size.y - 2)
	draw_string_outline(font, count_at, count, HORIZONTAL_ALIGNMENT_RIGHT, 22, 15, 5, Color.BLACK)
	draw_string(font, count_at, count, HORIZONTAL_ALIGNMENT_RIGHT, 22, 15, Color.WHITE)

	# Health bar under the token: green, then yellow, then red (UT-2).
	var bar := Rect2(rect.position + Vector2(0, rect.size.y + 1), Vector2(rect.size.x, BAR_HEIGHT))
	draw_rect(bar, Color(0.1, 0.1, 0.1))
	var health := clampf(unit.strength(), 0.0, 1.0)
	var bar_color := Color("#d04030").lerp(Color("#e8c840"), clampf(health * 2.0, 0.0, 1.0)) if health < 0.5 \
		else Color("#e8c840").lerp(Color("#50c050"), (health - 0.5) * 2.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)), bar_color)

	# Rank stars above the token (UT-6) and a general's badge.
	for i in unit.rank():
		_draw_star(rect.position + Vector2(6 + i * 8, rect.size.y - 6), 4.0, SELECTED_COLOR)
	if unit.general != null:
		var badge := rect.position + Vector2(rect.size.x - 2, -4)
		draw_circle(badge, 8.0, OUTLINE_COLOR)
		draw_circle(badge, 6.5, Color("#f2d16b"))
		draw_string(font, badge + Vector2(-6, 5), "G", HORIZONTAL_ALIGNMENT_CENTER, 12, 12, OUTLINE_COLOR)


## A simple white icon for the unit's class: shield and spear, bow, horse head or catapult.
func _draw_icon(unit_type: UnitType, box: Rect2, color: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return box.position + Vector2(x * box.size.x, y * box.size.y)
	match unit_type.unit_class:
		"infantry":
			draw_line(p.call(0.75, 0.95), p.call(0.75, 0.12), color, 2.0)
			draw_colored_polygon(PackedVector2Array([p.call(0.75, 0.0), p.call(0.88, 0.2), p.call(0.62, 0.2)]), color)
			draw_colored_polygon(PackedVector2Array([p.call(0.1, 0.25), p.call(0.55, 0.25), p.call(0.55, 0.6),
				p.call(0.32, 0.95), p.call(0.1, 0.6)]), color)
			if unit_type.heavy:
				draw_line(p.call(0.32, 0.3), p.call(0.32, 0.8), Color(0, 0, 0, 0.5), 2.0)
		"ranged":
			var centre: Vector2 = p.call(0.3, 0.5)
			var radius := box.size.y * 0.48
			draw_arc(centre, radius, -PI / 2.6, PI / 2.6, 12, color, 2.0)
			var top := centre + Vector2.from_angle(-PI / 2.6) * radius
			var bottom := centre + Vector2.from_angle(PI / 2.6) * radius
			draw_line(top, bottom, color, 1.0)
			draw_line(p.call(0.05, 0.5), p.call(0.92, 0.5), color, 1.5)
			draw_colored_polygon(PackedVector2Array([p.call(1.0, 0.5), p.call(0.82, 0.38), p.call(0.82, 0.62)]), color)
			if unit_type.is_cavalry():
				draw_circle(p.call(0.85, 0.12), 2.5, color)  # Horse archers: a rider's mark.
		"cavalry":
			draw_colored_polygon(PackedVector2Array([
				p.call(0.25, 1.0), p.call(0.3, 0.55), p.call(0.15, 0.4), p.call(0.05, 0.42), p.call(0.0, 0.3),
				p.call(0.35, 0.05), p.call(0.45, 0.0), p.call(0.5, 0.08), p.call(0.7, 0.15), p.call(0.9, 0.45),
				p.call(1.0, 1.0)]), color)
			draw_circle(p.call(0.32, 0.22), 1.5, Color(0, 0, 0, 0.7))
			if unit_type.heavy:
				draw_line(p.call(0.55, 0.3), p.call(0.85, 0.85), Color(0, 0, 0, 0.5), 2.0)
		"siege":
			draw_line(p.call(0.05, 0.75), p.call(0.95, 0.75), color, 2.0)
			draw_circle(p.call(0.25, 0.85), 2.5, color)
			draw_circle(p.call(0.75, 0.85), 2.5, color)
			draw_line(p.call(0.5, 0.75), p.call(0.35, 0.45), color, 2.0)
			draw_line(p.call(0.3, 0.7), p.call(0.9, 0.12), color, 2.0)
			draw_circle(p.call(0.88, 0.12), 3.5, color)


func _draw_star(at: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(at + Vector2.from_angle(-PI / 2 + i * PI / 5) * r)
	draw_colored_polygon(points, color)


## A castle behind a region's tokens: more towers for stronger walls.
func _draw_castle(at: Vector2, level: int) -> void:
	var width := 70.0 + level * 30.0
	var wall := Rect2(at - Vector2(width / 2.0, 14), Vector2(width, 34))
	var stone := Color(0.55, 0.52, 0.47)
	draw_rect(wall, stone)
	for i in level + 1:
		var x := wall.position.x + i * (width - 12) / level
		draw_rect(Rect2(Vector2(x, wall.position.y - 16), Vector2(12, 20)), stone)
		draw_rect(Rect2(Vector2(x, wall.position.y - 16), Vector2(12, 20)), OUTLINE_COLOR, false, 1.0)
	draw_rect(wall, OUTLINE_COLOR, false, 1.0)
