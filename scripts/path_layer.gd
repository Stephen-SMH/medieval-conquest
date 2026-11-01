class_name PathLayer
extends Node2D
## Draws the planned or previewed path of the selected army: a line through
## the province centres, a dot per step coloured by the turn it is reached on,
## and the number of turns at the end (PRD MV-3).

const THIS_TURN_COLOR := Color(0.35, 0.9, 0.4)
const LATER_TURN_COLOR := Color(1.0, 0.65, 0.2)
const ATTACK_COLOR := Color(0.95, 0.25, 0.2)

var state: GameState
var army: Army
var path: Array[String] = []
## True when the path ends on an enemy army.
var attack := false


## Shows `new_path`, cut short at the first enemy army the player can see,
## because the march stops there for a battle.
func show_path(for_army: Army, new_path: Array[String], visible_provinces: Dictionary) -> void:
	army = for_army
	path = []
	attack = false
	for step in new_path:
		path.append(step)
		if visible_provinces.has(step) and not state.enemy_armies_in(step, army.owner).is_empty():
			attack = true
			break
	queue_redraw()


func clear() -> void:
	army = null
	path = []
	queue_redraw()


func _ready() -> void:
	z_index = 5


func _draw() -> void:
	if army == null or path.is_empty():
		return
	var turns := state.path_turns(army, path)
	var points := PackedVector2Array([state.map.provinces[army.province].centroid])
	for step in path:
		points.append(state.map.provinces[step].centroid)
	draw_polyline(points, Color(0, 0, 0, 0.6), 7.0, true)
	draw_polyline(points, Color(1, 1, 1, 0.9), 3.0, true)
	for i in path.size():
		var color := THIS_TURN_COLOR if turns[i] == 0 else LATER_TURN_COLOR
		if attack and i == path.size() - 1:
			color = ATTACK_COLOR
		draw_circle(points[i + 1], 8.0, Color(0, 0, 0, 0.7))
		draw_circle(points[i + 1], 6.0, color)

	var total := turns[turns.size() - 1] + 1
	var text := "This turn" if total == 1 else "%d turns" % total
	if attack:
		text = "Attack! " + text
	var font := ThemeDB.fallback_font
	var at := points[points.size() - 1] + Vector2(-60, 28)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, 5, Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color.WHITE)
