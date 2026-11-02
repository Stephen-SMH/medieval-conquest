class_name MapDecor
extends Node2D
## Everything painted on the map above the region colours: the sea around the
## land, double borders where two factions meet, rivers, ships on the coast with
## dotted sea lanes for coastal raids, region names in a serif map font, each
## region's gold income, and small icons for capitals, castles, towns and camps.
## Real-geography maps (data/maps with "scenery", "sea_links" or "sea_labels")
## also get their coastline with shallows, land outside the play area, boats in
## the ports, dashed sea links between ports, and the names of the seas.

const INK := Color("#2a1a0e")
const RIVER := Color("#3d6f86")
const SEA := Color("#1e4a55")
const SHALLOWS := Color("#3f7480")
const SEA_MARGIN := 900.0
const SEA_SHADER := preload("res://shaders/sea.gdshader")
const PARCHMENT_SHADER := preload("res://shaders/parchment_overlay.gdshader")
## The region name sits this far below the region's centroid (baseline), in this font size.
const LABEL_BASELINE := 30.0
const LABEL_SIZE := 19
const SCENERY := Color("#b9ab8a")
const SEA_LINK := Color("#16305e")
const SEA_NAME := Color("#c9dde0", 0.75)

var state: GameState
var _font: Font
var _italic: Font
var _icons := {}
var _sea: Polygon2D
## From the map file: sea links, sea names and scenery. Empty for the made-up maps.
var _extras := {}
var _coast_lines: Array[PackedVector2Array] = []


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
	# Old paper over land and sea: stains, mottling and grain, under the borders and names.
	var paper := Polygon2D.new()
	paper.polygon = _sea.polygon
	var paper_material := ShaderMaterial.new()
	paper_material.shader = PARCHMENT_SHADER
	paper_material.set_shader_parameter("paper", load("res://assets/ui/paper.png"))
	paper.material = paper_material
	paper.z_index = 1
	paper.z_as_relative = false
	add_child(paper)
	_extras = map_extras(state.map)
	if is_real_map():
		_add_real_geography()


## Extra drawing data from a real-geography map file: "sea_links", "sea_labels", "scenery".
static func map_extras(map: MapData) -> Dictionary:
	var path := MapData.MAP_DIR.path_join(map.id + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		return {}
	var extras := {}
	for key in ["sea_links", "sea_labels", "scenery"]:
		if data.has(key):
			extras[key] = data[key]
	return extras


func is_real_map() -> bool:
	return not _extras.is_empty()


## Land outside the play area, and shallow water along every coast, under the regions.
func _add_real_geography() -> void:
	var map := state.map
	for area in _extras.get("scenery", []):
		var land := Polygon2D.new()
		land.polygon = _outline(area.vertices)
		land.color = SCENERY
		land.z_index = 0
		land.z_as_relative = false
		add_child(land)
	_coast_lines = coast_lines(map, _extras.get("scenery", []))
	var shallows := Node2D.new()
	shallows.z_index = -5
	shallows.z_as_relative = false
	shallows.draw.connect(func():
		for line in _coast_lines:
			shallows.draw_polyline(line, Color(SHALLOWS, 0.55), 26.0, true)
			shallows.draw_polyline(line, Color(SHALLOWS.lightened(0.15), 0.5), 10.0, true))
	add_child(shallows)


func _outline(vertex_ids: Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for i in vertex_ids.size():
		var edge := state.map.edge_points(vertex_ids[i], vertex_ids[(i + 1) % vertex_ids.size()])
		edge.remove_at(edge.size() - 1)
		polygon.append_array(edge)
	return polygon


## The coastline as long lines: every edge used by only one area (a region or
## scenery) that isn't on the edge of the map.
static func coast_lines(map: MapData, scenery: Array) -> Array[PackedVector2Array]:
	var outlines: Array = []
	for region in map.province_order:
		outlines.append(map.provinces[region].vertices)
	for area in scenery:
		outlines.append(area.vertices)
	var uses := {}
	for ids in outlines:
		for i in ids.size():
			var key := MapData.border_key(ids[i], ids[(i + 1) % ids.size()])
			uses[key] = uses.get(key, 0) + 1
	var next := {}
	for ids in outlines:
		for i in ids.size():
			var a: String = ids[i]
			var b: String = ids[(i + 1) % ids.size()]
			if uses[MapData.border_key(a, b)] == 1:
				var ends := map.edge_points(a, b)
				var p := ends[0]
				var q := ends[ends.size() - 1]
				var on_frame := (p.x == 0 and q.x == 0) or (p.y == 0 and q.y == 0) \
					or (p.x == map.size.x and q.x == map.size.x) or (p.y == map.size.y and q.y == map.size.y)
				if not on_frame:
					next[a] = b
	var lines: Array[PackedVector2Array] = []
	var done := {}
	for start in next:
		if done.has(start):
			continue
		var line := PackedVector2Array()
		var at: String = start
		while next.has(at) and not done.has(at):
			done[at] = true
			var points := map.edge_points(at, next[at])
			if not line.is_empty():
				points.remove_at(0)
			line.append_array(points)
			at = next[at]
		lines.append(line)
	return lines


func _draw() -> void:
	var map := state.map
	if is_real_map():
		for line in _coast_lines:
			draw_polyline(line, Color(INK, 0.75), 2.0, true)
		draw_polyline(PackedVector2Array([Vector2.ZERO, Vector2(map.size.x, 0), map.size, Vector2(0, map.size.y), Vector2.ZERO]),
			Color(INK, 0.9), 3.0, true)
		_draw_sea_names()
	else:
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

	if is_real_map():
		_draw_ports()
	else:
		_draw_ships()

	for region in map.province_order:
		_draw_label(region)


## The box a region's name fills, with its outline; the unit token stays above it.
static func label_rect(centroid: Vector2) -> Rect2:
	var top := centroid.y + LABEL_BASELINE - LABEL_SIZE * 0.85
	return Rect2(Vector2(centroid.x - 100.0, top), Vector2(200.0, LABEL_SIZE * 1.1))


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


## Sea names in italic across the water (and a few land names, like deserts, in ink).
func _draw_sea_names() -> void:
	for label in _extras.get("sea_labels", []):
		var size := int(label.get("size", 30))
		var text: String = label.text
		var width := _italic.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var color := Color(INK, 0.45) if label.get("land", false) else SEA_NAME
		draw_set_transform(Vector2(label.at[0], label.at[1]), deg_to_rad(label.get("angle", 0.0)))
		draw_string(_italic, Vector2(-width / 2.0, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		draw_set_transform(Vector2.ZERO)


## Dashed sea links between ports, then a boat off each port.
func _draw_ports() -> void:
	var map := state.map
	for link in _extras.get("sea_links", []):
		var a: Dictionary = map.provinces[link[0]]
		var b: Dictionary = map.provinces[link[1]]
		var from := Vector2(a.port_at[0], a.port_at[1])
		var to := Vector2(b.port_at[0], b.port_at[1])
		var gap := (to - from).normalized() * 16.0
		draw_line(from + gap, to - gap, Color("#9fc4d0", 0.35), 6.0, true)
		draw_dashed_line(from + gap, to - gap, SEA_LINK, 3.0, 12.0)
	for region in map.province_order:
		var province: Dictionary = map.provinces[region]
		if province.has("port_at"):
			var at := Vector2(province.port_at[0], province.port_at[1])
			draw_circle(at, 17.0, Color("#9fc4d0", 0.3))
			draw_texture_rect(_icons.map_ship, Rect2(at - Vector2(15, 16), Vector2(30, 30)), false, Color("#1a1008", 0.9))


func _draw_label(region: String) -> void:
	var map := state.map
	var centre: Vector2 = map.provinces[region].centroid
	var name: String = map.region_name(region)
	var at := centre + Vector2(0, LABEL_BASELINE)
	draw_string_outline(_font, at - Vector2(100, 0), name, HORIZONTAL_ALIGNMENT_CENTER, 200, LABEL_SIZE, 4, Color(1, 0.96, 0.85, 0.35))
	draw_string(_font, at - Vector2(100, 0), name, HORIZONTAL_ALIGNMENT_CENTER, 200, LABEL_SIZE, INK)

	# Gold income: a coin stack and the number, in italic.
	var income := roundi(Economy.region_income(state, region))
	if state.factions.has(state.owners[region]):
		var coin_at := centre + Vector2(-18, 37)
		draw_texture_rect(_icons.ui_coins, Rect2(coin_at, Vector2(15, 15)), false, Color("#3a2410", 0.9))
		draw_string(_italic, coin_at + Vector2(17, 13), str(income), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#3a2410"))

	# Little icons beside the name: crown for a capital, tower for walls, tent or houses where reinforcements arrive.
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
