class_name ProvinceGraph
extends AStar2D
## A* over the province graph (PRD MV-3). A step costs the move cost into the
## next province (terrain, roads and rivers), not the distance on screen.

var map: MapData
var _point_ids := {}  # province id -> A* point id
var _province_ids: Array[String] = []  # A* point id -> province id
var _longest_step := 1.0  # Longest distance between neighbouring centres.


func _init(game_map: MapData) -> void:
	map = game_map
	for id in map.province_order:
		_point_ids[id] = _province_ids.size()
		add_point(_province_ids.size(), map.provinces[id].centroid)
		_province_ids.append(id)
	for id in map.province_order:
		for other in map.neighbours(id):
			connect_points(_point_ids[id], _point_ids[other], false)
			_longest_step = maxf(_longest_step, map.provinces[id].centroid.distance_to(map.provinces[other].centroid))


## The provinces to walk through to reach `to`, not including `from`.
## Empty when `from` is `to`.
func province_path(from: String, to: String) -> Array[String]:
	var path: Array[String] = []
	var ids := get_id_path(_point_ids[from], _point_ids[to])
	for i in range(1, ids.size()):
		path.append(_province_ids[ids[i]])
	return path


func _compute_cost(from_id: int, to_id: int) -> float:
	return map.move_cost(_province_ids[from_id], _province_ids[to_id])


## Every step costs at least 1 and covers at most the longest step, so this
## never overestimates and A* still finds the cheapest path.
func _estimate_cost(from_id: int, to_id: int) -> float:
	return get_point_position(from_id).distance_to(get_point_position(to_id)) / _longest_step
