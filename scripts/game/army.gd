class_name Army
extends RefCounted
## A group of up to 12 regiments in one province (PRD 3.7). An army without a
## general is a garrison and can't leave its province (AR-2).

const MAX_REGIMENTS := 12

var id := 0
var owner := ""
var province := ""
var general: General  # null for a garrison.
var regiments: Array[Regiment] = []
var movement_left := 0
## Provinces still to visit, in order, after this turn's movement runs out.
var path: Array[String] = []


func is_garrison() -> bool:
	return general == null


func display_name() -> String:
	return "Garrison" if is_garrison() else "%s's army" % general.name


## Movement points per turn: the lowest speed among the regiments (MV-1).
func max_movement() -> int:
	if regiments.is_empty():
		return 0
	var lowest := 1 << 30
	for regiment in regiments:
		lowest = mini(lowest, regiment.type().speed)
	return lowest


func can_move() -> bool:
	return not is_garrison() and not regiments.is_empty()


func total_men() -> float:
	var total := 0.0
	for regiment in regiments:
		total += regiment.men
	return total


func reset_movement() -> void:
	movement_left = max_movement()
