class_name BorderLayer
extends Node2D
## Draws rivers along province borders, roads between provinces, and capital markers.

const RIVER_COLOR := Color("#3f7fc9")
const ROAD_COLOR := Color("#5a3d22")
const CAPITAL_OFFSET := Vector2(0, 8)

var map: MapData
## Faction colour for each capital marker; set by the owner of this layer.
var capital_colors := {}


func _ready() -> void:
	z_index = 4  # Above province outlines and selection highlights.


func _draw() -> void:
	for key in map.borders:
		var pair: PackedStringArray = key.split("|")
		match map.borders[key]:
			"river":
				for edge in map.shared_edges(pair[0], pair[1]):
					draw_polyline(map.edge_points(edge[0], edge[1]), RIVER_COLOR, 5.0, true)
			"road":
				draw_dashed_line(map.provinces[pair[0]].centroid, map.provinces[pair[1]].centroid,
						ROAD_COLOR, 3.0, 10.0)

	for id in map.province_order:
		var province: Dictionary = map.provinces[id]
		if province.capital:
			var at: Vector2 = province.centroid + CAPITAL_OFFSET
			draw_circle(at, 7.0, Color.WHITE)
			draw_circle(at, 5.0, capital_colors.get(id, Color.BLACK).darkened(0.5))
