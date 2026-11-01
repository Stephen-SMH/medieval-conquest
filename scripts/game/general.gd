class_name General
extends RefCounted
## The leader of an army (PRD AR-3). Command raises the army's attack;
## logistics lowers its food upkeep and extends its supply range.

var name := ""
var command := 1    # Each point: +5% attack for the army.
var logistics := 1  # Each point: −5% food upkeep for the army.


func _init(general_name := "", command_points := 1, logistics_points := 1) -> void:
	name = general_name
	command = command_points
	logistics = logistics_points


func attack_mod() -> float:
	return 1.0 + command * 0.05
