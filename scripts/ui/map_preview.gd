class_name MapPreview
extends Control
## A small picture of a scenario's map for the Scenarios table (PRD M): the
## regions in their owners' colours on the sea, thin borders, and a gold dot
## on each capital, the player's larger.

const SEA := Color("#2c5560")
const NEUTRAL := Color("#d9c9a0")
const INK := Color(0.16, 0.1, 0.05, 0.55)

var _map: MapData
var _land := Node2D.new()
var _lines := Node2D.new()
var _capitals := []
var _player_capital := ""


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_land)
	add_child(_lines)
	_lines.draw.connect(_draw_lines)
	resized.connect(_fit)


func show_scenario(scenario: Dictionary) -> void:
	_map = MapData.load_map(scenario.map)
	for child in _land.get_children():
		child.queue_free()
	var colors := {}
	for faction in scenario.factions:
		colors[faction.id] = Color(faction.color)
	for region in _map.province_order:
		var shape := Polygon2D.new()
		shape.polygon = _map.provinces[region].polygon
		shape.color = colors.get(scenario.owners.get(region, "neutral"), NEUTRAL)
		_land.add_child(shape)
	_capitals = scenario.get("capitals", {}).values()
	var player: String = scenario.get("mission", {}).get("player", "")
	_player_capital = scenario.get("capitals", {}).get(player, "")
	_fit()


func _fit() -> void:
	if _map == null:
		return
	var scale := minf(size.x / _map.size.x, size.y / _map.size.y)
	var offset := (size - _map.size * scale) / 2.0
	for node in [_land, _lines]:
		node.position = offset
		node.scale = Vector2(scale, scale)
	_lines.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA)


func _draw_lines() -> void:
	if _map == null:
		return
	var scale := _lines.scale.x
	for region in _map.province_order:
		var outline: PackedVector2Array = _map.provinces[region].polygon.duplicate()
		outline.append(outline[0])
		_lines.draw_polyline(outline, INK, 1.0 / scale)
	for capital in _capitals:
		var at: Vector2 = _map.provinces[capital].centroid
		var r := (7.0 if capital == _player_capital else 4.5) / scale
		_lines.draw_circle(at, r * 1.3, Color(0, 0, 0, 0.5))
		_lines.draw_circle(at, r, Color("#f0c64a"))
