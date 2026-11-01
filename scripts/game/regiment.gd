class_name Regiment
extends RefCounted
## A regiment of up to 100 men of one unit type. HP and attack scale with men.

const FULL_STRENGTH := 100.0

var type_id := ""
var men := FULL_STRENGTH


func _init(unit_type_id := "", starting_men := FULL_STRENGTH) -> void:
	type_id = unit_type_id
	men = starting_men


func type() -> UnitType:
	return Rules.unit(type_id)


func strength() -> float:
	return men / FULL_STRENGTH


func hp() -> float:
	return type().hp * strength()


func copy() -> Regiment:
	return Regiment.new(type_id, men)
