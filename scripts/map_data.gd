class_name MapData
extends RefCounted
## The campaign map from data/map.json: factions, province shapes, neighbours,
## rivers and roads. This is the fixed geography; who owns what is game state.

const DATA_PATH := "res://data/map.json"
const EDGE_DETAIL := 3        # Times each border edge is split in half, so borders look hand-drawn.
const EDGE_ROUGHNESS := 0.08  # Largest sideways bend, as a fraction of the edge length.

var size := Vector2.ZERO
var factions := {}       # faction id -> {name, color}
var provinces := {}      # province id -> data from map.json plus "polygon" and "centroid"
var province_order: Array[String] = []
var borders := {}        # border_key(a, b) -> "river" or "road"
var start_armies := []   # {owner, province, general (or null for a garrison), regiments}

var _vertices := {}      # vertex id -> Vector2


static func load_default() -> MapData:
	var map := MapData.new()
	var error := map.load_file(DATA_PATH)
	if error != OK:
		push_error("Could not load %s: %s" % [DATA_PATH, error_string(error)])
	return map


func load_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		return ERR_PARSE_ERROR

	Rules.ensure_loaded()
	size = Vector2(data.map_size[0], data.map_size[1])
	for id in data.vertices:
		_vertices[id] = Vector2(data.vertices[id][0], data.vertices[id][1])
	for id in data.factions:
		factions[id] = data.factions[id]
		factions[id]["color"] = Color(data.factions[id].color)
	for province in data.provinces:
		province["population"] = int(province.population)
		province["polygon"] = _build_polygon(province.vertices)
		province["centroid"] = polygon_centroid(province.polygon)
		provinces[province.id] = province
		province_order.append(province.id)
	for border in data.borders:
		borders[border_key(border.between[0], border.between[1])] = border.type
	start_armies = data.get("start_armies", [])
	return OK


static func border_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


## Factions that own provinces and play turns (not the rebels).
func playable_factions() -> Array:
	return factions.keys().filter(func(id): return not factions[id].get("rebel", false))


func neighbours(id: String) -> Array:
	return provinces[id].neighbours


func are_neighbours(a: String, b: String) -> bool:
	return b in provinces[a].neighbours


func terrain(id: String) -> TerrainType:
	return Rules.terrains[provinces[id].terrain]


## "river", "road" or "" for the border between two neighbouring provinces.
func border_type(a: String, b: String) -> String:
	return borders.get(border_key(a, b), "")


## Cost for an army to move from a province into its neighbour (PRD 3.1 and MV-2).
func move_cost(from_id: String, to_id: String) -> int:
	var cost := terrain(to_id).move_cost
	match border_type(from_id, to_id):
		"river":
			cost += 1
		"road":
			cost = maxi(cost - 1, 1)
	return cost


## The province under a point on the map, or "" for none.
func province_at(point: Vector2) -> String:
	for id in province_order:
		if Geometry2D.is_point_in_polygon(point, provinces[id].polygon):
			return id
	return ""


## Vertex-id pairs that two provinces share as a border.
func shared_edges(a: String, b: String) -> Array:
	var edges_of_b := {}
	for edge in _edges(b):
		edges_of_b[border_key(edge[0], edge[1])] = true
	var shared := []
	for edge in _edges(a):
		if edges_of_b.has(border_key(edge[0], edge[1])):
			shared.append(edge)
	return shared


## The points of the border line between two vertices. Both provinces that share
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


func _edges(id: String) -> Array:
	var ids: Array = provinces[id].vertices
	var edges := []
	for i in ids.size():
		edges.append([ids[i], ids[(i + 1) % ids.size()]])
	return edges


## Edges along the outside of the map stay straight.
func _on_map_edge(a: Vector2, b: Vector2) -> bool:
	return (a.x == 0 and b.x == 0) or (a.y == 0 and b.y == 0) \
		or (a.x == size.x and b.x == size.x) or (a.y == size.y and b.y == size.y)
