class_name MapData
extends RefCounted
## A map from data/maps/<id>.json: region shapes, neighbours, coasts, rivers,
## roads, sea links and start slots for skirmish. This is fixed geography; who
## owns what is game state. Regions are called provinces in the code.
## A sea link (PRD J, "sea_links": [[a, b], ...] between two port regions)
## makes the two ports neighbours across a "sea" border: armies sail along
## it to march or attack, and a landing fights like a river crossing.

const MAP_DIR := "res://data/maps"
const TUTORIAL_DIR := "res://data/tutorial"
const EDGE_DETAIL := 3        # Times each border edge is split in half, so borders look hand-drawn.
const EDGE_ROUGHNESS := 0.08  # Largest sideways bend, as a fraction of the edge length.

var id := ""
var display_name := ""
var size := Vector2.ZERO
var provinces := {}      # region id -> data from the map file plus "polygon" and "centroid"
var province_order: Array[String] = []
var borders := {}        # border_key(a, b) -> "river", "road" or "sea"
## Regions where skirmish factions start, in slot order.
var starts: Array[String] = []

var _vertices := {}      # vertex id -> Vector2
var _bounds := {}        # region id -> Rect2 around its polygon, made on first use

static var _cache := {}


## Loads a map once and shares it; maps never change during a game.
static func load_map(map_id: String) -> MapData:
	if not _cache.has(map_id):
		var map := MapData.new()
		var path := MAP_DIR.path_join(map_id + ".json")
		if not FileAccess.file_exists(path):
			path = TUTORIAL_DIR.path_join(map_id + ".json")  # The tutorial's map isn't offered for skirmish.
		var error := map.load_file(path)
		if error != OK:
			push_error("Could not load map %s: %s" % [map_id, error_string(error)])
		_cache[map_id] = map
	return _cache[map_id]


static func list_maps() -> Array[String]:
	var ids: Array[String] = []
	for file in DirAccess.get_files_at(MAP_DIR):
		if file.ends_with(".json"):
			ids.append(file.get_basename())
	ids.sort()
	return ids


func load_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		return ERR_PARSE_ERROR

	Rules.ensure_loaded()
	id = data.id
	display_name = data.name
	size = Vector2(data.size[0], data.size[1])
	for vertex in data.vertices:
		_vertices[vertex] = Vector2(data.vertices[vertex][0], data.vertices[vertex][1])
	for region in data.regions:
		region["population"] = int(region.population)
		region["coastal"] = region.get("coastal", false)
		region["polygon"] = _build_polygon(region.vertices)
		region["centroid"] = polygon_centroid(region.polygon)
		provinces[region.id] = region
		province_order.append(region.id)
	for border in data.get("borders", []):
		borders[border_key(border.between[0], border.between[1])] = border.type
	for link in data.get("sea_links", []):
		for pair in [[link[0], link[1]], [link[1], link[0]]]:
			if not (pair[1] in provinces[pair[0]].neighbours):
				provinces[pair[0]].neighbours.append(pair[1])
		borders[border_key(link[0], link[1])] = "sea"
	starts.assign(data.get("starts", []))
	return OK


static func border_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func neighbours(region: String) -> Array:
	return provinces[region].neighbours


func are_neighbours(a: String, b: String) -> bool:
	return b in provinces[a].neighbours


func terrain(region: String) -> TerrainType:
	return Rules.terrains[provinces[region].terrain]


func is_coastal(region: String) -> bool:
	return provinces[region].coastal


func region_name(region: String) -> String:
	return provinces[region].name


## "river", "road", "sea" or "" for the border between two neighbouring regions.
func border_type(a: String, b: String) -> String:
	return borders.get(border_key(a, b), "")


## The ports a region's sea links reach (PRD J).
func sea_links(region: String) -> Array:
	return neighbours(region).filter(func(other): return border_type(region, other) == "sea")


## Steps between two regions over the neighbour graph (breadth-first).
func distance(from: String, to: String) -> int:
	return distances_from(from).get(to, 1 << 30)


func distances_from(from: String) -> Dictionary:
	var result := {from: 0}
	var frontier := [from]
	while not frontier.is_empty():
		var current: String = frontier.pop_front()
		for next in neighbours(current):
			if not result.has(next):
				result[next] = result[current] + 1
				frontier.append(next)
	return result


## The region under a point on the map, or "" for none.
## The bounding box check comes first: Geometry2D.is_point_in_polygon can
## wrongly answer true for points far outside a long, detailed coastline.
func province_at(point: Vector2) -> String:
	if _bounds.is_empty():
		for region in province_order:
			var polygon: PackedVector2Array = provinces[region].polygon
			var box := Rect2(polygon[0], Vector2.ZERO)
			for p in polygon:
				box = box.expand(p)
			_bounds[region] = box
	for region in province_order:
		if _bounds[region].has_point(point) and Geometry2D.is_point_in_polygon(point, provinces[region].polygon):
			return region
	return ""


## Vertex-id pairs that two regions share as a border.
func shared_edges(a: String, b: String) -> Array:
	var edges_of_b := {}
	for edge in _edges(b):
		edges_of_b[border_key(edge[0], edge[1])] = true
	var shared := []
	for edge in _edges(a):
		if edges_of_b.has(border_key(edge[0], edge[1])):
			shared.append(edge)
	return shared


## Edges of a region that lie on the outside of the map.
func outer_edges(region: String) -> Array:
	var found := []
	for edge in _edges(region):
		if _on_map_edge(_vertices[edge[0]], _vertices[edge[1]]):
			found.append(edge)
	return found


## The points of the border line between two vertices. Both regions that share
## an edge get exactly the same points, so there are no gaps between them.
func edge_points(from_id: String, to_id: String) -> PackedVector2Array:
	var flip := from_id > to_id
	var a: Vector2 = _vertices[to_id if flip else from_id]
	var b: Vector2 = _vertices[from_id if flip else to_id]
	var points := PackedVector2Array([a, b])
	if not _on_map_edge(a, b):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(border_key(from_id, to_id))
		var bend := a.distance_to(b) * EDGE_ROUGHNESS
		for level in EDGE_DETAIL:
			var refined := PackedVector2Array()
			for i in points.size() - 1:
				var p := points[i]
				var q := points[i + 1]
				var normal := (q - p).orthogonal().normalized()
				refined.append(p)
				refined.append((p + q) / 2.0 + normal * rng.randf_range(-bend, bend))
			refined.append(points[points.size() - 1])
			points = refined
			bend /= 2.0
	if flip:
		points.reverse()
	return points


static func polygon_area(polygon: PackedVector2Array) -> float:
	var twice_area := 0.0
	for i in polygon.size():
		twice_area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(twice_area) / 2.0


static func polygon_centroid(polygon: PackedVector2Array) -> Vector2:
	var twice_area := 0.0
	var sum := Vector2.ZERO
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		var cross := p.cross(q)
		twice_area += cross
		sum += (p + q) * cross
	return sum / (3.0 * twice_area)


func _build_polygon(vertex_ids: Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for i in vertex_ids.size():
		var edge := edge_points(vertex_ids[i], vertex_ids[(i + 1) % vertex_ids.size()])
		edge.remove_at(edge.size() - 1)  # The next edge starts with this point.
		polygon.append_array(edge)
	return polygon


func _edges(region: String) -> Array:
	var ids: Array = provinces[region].vertices
	var edges := []
	for i in ids.size():
		edges.append([ids[i], ids[(i + 1) % ids.size()]])
	return edges


## Edges along the outside of the map stay straight.
func _on_map_edge(a: Vector2, b: Vector2) -> bool:
	return (a.x == 0 and b.x == 0) or (a.y == 0 and b.y == 0) \
		or (a.x == size.x and b.x == size.x) or (a.y == size.y and b.y == size.y)
