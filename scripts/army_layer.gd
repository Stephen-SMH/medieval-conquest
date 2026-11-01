class_name ArmyLayer
extends Node2D
## Draws every visible army as a banner on its province and finds the army
## under the mouse. Garrisons (no general) are drawn as a small shield.

const TOKEN_SPACING := 30.0
const BASE_OFFSET := Vector2(0, 46)  # From the province centre to the foot of the banner pole.
const FLAG_SIZE := Vector2(24, 16)
const POLE_HEIGHT := 30.0
const SELECTED_COLOR := Color(1.0, 0.85, 0.3)

var state: GameState
var selected_army: Army
## Provinces whose armies the player can see; null shows everything.
var visible_provinces = null


func _ready() -> void:
	z_index = 5


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for army in visible_armies():
		var base := token_position(army)
		var color: Color = state.map.factions[army.owner].color
		var outline := SELECTED_COLOR if army == selected_army else Color(0.1, 0.08, 0.06)
		var outline_width := 3.0 if army == selected_army else 1.5
		var count := str(army.regiments.size())
		if army.is_garrison():
			var shield := Rect2(base + Vector2(-9, -20), Vector2(18, 18))
			draw_rect(shield, color.darkened(0.25))
			draw_rect(shield, outline, false, outline_width)
			draw_string(font, shield.position + Vector2(0, 14), count, HORIZONTAL_ALIGNMENT_CENTER, shield.size.x, 12, Color.WHITE)
		else:
			draw_line(base, base + Vector2(0, -POLE_HEIGHT), Color(0.2, 0.15, 0.1), 2.0)
			var flag := Rect2(base + Vector2(1, -POLE_HEIGHT), FLAG_SIZE)
			draw_rect(flag, color)
			draw_rect(flag, outline, false, outline_width)
			draw_string(font, flag.position + Vector2(0, 13), count, HORIZONTAL_ALIGNMENT_CENTER, FLAG_SIZE.x, 12, Color.WHITE)
			if army.movement_left == 0 and army.owner == state.player:
				draw_circle(base, 3.0, Color(0.6, 0.1, 0.1))  # Out of movement this turn.
			else:
				draw_circle(base, 3.0, Color(0.2, 0.15, 0.1))


func visible_armies() -> Array[Army]:
	var shown: Array[Army] = []
	for army in state.armies:
		if visible_provinces == null or army.owner == state.player or visible_provinces.has(army.province):
			shown.append(army)
	return shown


func token_position(army: Army) -> Vector2:
	var here: Array[Army] = []
	for other in visible_armies():
		if other.province == army.province:
			here.append(other)
	var index := here.find(army)
	var centre: Vector2 = state.map.provinces[army.province].centroid + BASE_OFFSET
	return centre + Vector2((index - (here.size() - 1) / 2.0) * TOKEN_SPACING, 0)


## The army whose banner is under `point` (map coordinates), or null.
func army_at(point: Vector2) -> Army:
	for army in visible_armies():
		var base := token_position(army)
		var hit := Rect2(base + Vector2(-10, -POLE_HEIGHT - 2), Vector2(FLAG_SIZE.x + 14, POLE_HEIGHT + 6))
		if hit.has_point(point):
			return army
	return null
