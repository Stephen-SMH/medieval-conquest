class_name General
extends RefCounted
## The leader attached to a unit (PRD UT-5). Command raises the unit's attack;
## logistics lowers its gold upkeep.

var name := ""
var command := 1    # Each point: +5% attack for the army.
var logistics := 1  # Each point: −5% gold upkeep for the unit.


func _init(general_name := "", command_points := 1, logistics_points := 1) -> void:
	name = general_name
	command = command_points
	logistics = logistics_points


func attack_mod() -> float:
	return 1.0 + command * 0.05
