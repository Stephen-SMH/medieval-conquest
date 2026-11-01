class_name MapDecor
extends Node2D
## Everything painted on the map above the region colours: the sea around the
## land, double borders where two factions meet, rivers, ships on the coast with
## dotted sea lanes for coastal raids, region names in a serif map font, each
## region's gold income, and small icons for capitals, castles, towns and camps.

const INK := Color("#2a1a0e")
const RIVER := Color("#3d6f86")
const SEA := Color("#1e4a55")
const SHALLOWS := Color("#3f7480")
const SEA_MARGIN := 900.0
const SEA_SHADER := preload("res://shaders/sea.gdshader")

var state: GameState
var _font: Font
var _italic: Font
var _icons := {}
var _sea: Polygon2D


func _ready() -> void:
	z_index = 2
	_font = load("res://assets/fonts/IMFellEnglish-Regular.ttf")
	_italic = load("res://assets/fonts/IMFellEnglish-Italic.ttf")
	for name in ["map_crown", "map_tower", "map_camp", "map_town", "map_ship", "ui_coins"]:
		_icons[name] = load("res://assets/icons/%s.svg" % name)
	# The sea sits behind the regions, under everything else.
	_sea = Polygon2D.new()
	var size := state.map.size
	_sea.polygon = PackedVector2Array([Vector2(-SEA_MARGIN, -SEA_MARGIN), Vector2(size.x + SEA_MARGIN, -SEA_MARGIN),
		Vector2(size.x + SEA_MARGIN, size.y + SEA_MARGIN), Vector2(-SEA_MARGIN, size.y + SEA_MARGIN)])
	var material := ShaderMaterial.new()
	material.shader = SEA_SHADER
	material.set_shader_parameter("paper", load("res://assets/ui/paper.png"))
	material.set_shader_parameter("sea_color", SEA)
	_sea.material = material
	_sea.z_index = -10
	_sea.z_as_relative = false
	add_child(_sea)


func _draw() -> void:
	var map := state.map
	# Shallow water along the coast, then the edge of the land.
	draw_polyline(PackedVector2Array([Vector2.ZERO, Vector2(map.size.x, 0), map.size, Vector2(0, map.size.y), Vector2.ZERO]),
		Color(SHALLOWS, 0.6), 22.0, true)
	draw_polyline(PackedVector2Array([Vector2.ZERO, Vector2(map.size.x, 0), map.size, Vector2(0, map.size.y), Vector2.ZERO]),
		Color(INK, 0.8), 2.5, true)

	# Double borders where two factions meet: each side gets a line in its own colour.
	for region in map.province_order:
		for other in map.neighbours(region):
			if region < other and state.owners[region] != state.owners[other]:
				for edge in map.shared_edges(region, other):
					var points := map.edge_points(edge[0], edge[1])
					for side in [region, other]:
						draw_polyline(_inset(points, side, 4.5), Color(ProvinceView.paint(state.faction_color(state.owners[side])).darkened(0.25), 0.95), 2.6, true)
					draw_polyline(points, INK, 2.2, true)

	for key in map.borders:
		if map.borders[key] == "river":
			var pair: PackedStringArray = key.split("|")
			for edge in map.shared_edges(pair[0], pair[1]):
				var points := map.edge_points(edge[0], edge[1])
				draw_polyline(points, RIVER.darkened(0.3), 6.0, true)
				draw_polyline(points, RIVER.lightened(0.15), 3.5, true)

	_draw_ships()

	for region in map.province_order:
		_draw_label(region)


## The border line moved a few pixels into `region`.
func _inset(points: PackedVector2Array, region: String, distance: float) -> PackedVector2Array:
	var polygon: PackedVector2Array = state.map.provinces[region].polygon
	var result := PackedVector2Array()
	for i in points.size():
		var a := points[maxi(i - 1, 0)]
		var b := points[mini(i + 1, points.size() - 1)]
		var normal := (b - a).orthogonal().normalized()
		var p := points[i] + normal * distance
		if not Geometry2D.is_point_in_polygon(p, polygon):
			p = points[i] - normal * distance
		result.append(p)
	return result


## Ships off coastal regions, and dotted lanes between ships two coastal regions apart.
func _draw_ships() -> void:
	var map := state.map
	var ships := {}
	for region in map.province_order:
		if not map.is_coastal(region) or map.outer_edges(region).is_empty():
			continue
		var edge: Array = map.outer_edges(region)[0]
		var points := map.edge_points(edge[0], edge[1])
		var middle := (points[0] + points[points.size() - 1]) / 2.0
		var outward := (middle - map.size / 2.0)
		outward = Vector2(signf(outward.x) if absf(middle.x) < 1.0 or absf(middle.x - map.size.x) < 1.0 else 0.0,
			signf(outward.y) if absf(middle.y) < 1.0 or absf(middle.y - map.size.y) < 1.0 else 0.0)
		ships[region] = middle + outward * 34.0
	var drawn := {}
	for a in ships:
		for b in map.neighbours(a):
			for c in map.neighbours(b):
				if c != a and ships.has(c) and ships.has(b) and not map.are_neighbours(a, c) and not drawn.has(MapData.border_key(a, c)) \
						and ships[a].distance_to(ships[c]) < 420.0 and (is_equal_approx(ships[a].x, ships[c].x) or is_equal_approx(ships[a].y, ships[c].y)):
					drawn[MapData.border_key(a, c)] = true
					draw_dashed_line(ships[a], ships[c], Color("#9fc4d0", 0.7), 2.0, 7.0)
	for region in ships:
		var ship: Texture2D = _icons.map_ship
		draw_texture_rect(ship, Rect2(ships[region] - Vector2(15, 17), Vector2(30, 30)), false, Color("#1a1008", 0.85))


func _draw_label(region: String) -> void:
	var map := state.map
	var centre: Vector2 = map.provinces[region].centroid
	var name: String = map.region_name(region)
	var at := centre + Vector2(0, 30)
	draw_string_outline(_font, at - Vector2(100, 0), name, HORIZONTAL_ALIGNMENT_CENTER, 200, 19, 4, Color(1, 0.96, 0.85, 0.35))
	draw_string(_font, at - Vector2(100, 0), name, HORIZONTAL_ALIGNMENT_CENTER, 200, 19, INK)

	# Gold income: a coin stack and the number, in italic.
	var income := roundi(Economy.region_income(state, region))
	if state.factions.has(state.owners[region]):
		var coin_at := centre + Vector2(-18, 37)
		draw_texture_rect(_icons.ui_coins, Rect2(coin_at, Vector2(15, 15)), false, Color("#3a2410", 0.9))
		draw_string(_italic, coin_at + Vector2(17, 13), str(income), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#3a2410"))

	# Little icons beside the name: crown for a capital, tower for walls, tent or houses for mercenaries.
	var icons := []
	if state.is_capital(region):
		icons.append("map_crown")
	if Sieges.walls(state, region) > 0:
		icons.append("map_tower")
	match Economy.site(state, region):
		"camp":
			icons.append("map_camp")
		"town":
			icons.append("map_town")
	for i in icons.size():
		var spot := centre + Vector2(-62 - i * 24, 18)
		draw_texture_rect(_icons[icons[i]], Rect2(spot, Vector2(22, 22)), false, Color("#3a2410", 0.85))
