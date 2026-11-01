class_name BorderLayer
extends Node2D
## Draws coastlines, rivers along region borders, roads between regions and
## capital markers.

const RIVER_COLOR := Color("#3f7fc9")
const COAST_COLOR := Color("#9fd0f0")
const ROAD_COLOR := Color("#5a3d22")
const CAPITAL_OFFSET := Vector2(0, 38)

var state: GameState


func _ready() -> void:
	z_index = 4  # Above region outlines and selection highlights.


func _draw() -> void:
	var map := state.map
	for region in map.province_order:
		if map.is_coastal(region):
			for edge in map.outer_edges(region):
				draw_polyline(map.edge_points(edge[0], edge[1]), COAST_COLOR, 6.0, true)
	for key in map.borders:
		var pair: PackedStringArray = key.split("|")
		match map.borders[key]:
			"river":
				for edge in map.shared_edges(pair[0], pair[1]):
					draw_polyline(map.edge_points(edge[0], edge[1]), RIVER_COLOR, 5.0, true)
			"road":
				draw_dashed_line(map.provinces[pair[0]].centroid, map.provinces[pair[1]].centroid,
						ROAD_COLOR, 3.0, 10.0)
	for faction in state.capitals:
		var region: String = state.capitals[faction]
		if state.owners[region] != faction:
			continue
		var at: Vector2 = map.provinces[region].centroid + CAPITAL_OFFSET
		draw_circle(at, 7.0, Color.WHITE)
		draw_circle(at, 5.0, state.faction_color(faction).darkened(0.5))
