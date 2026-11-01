class_name ProvinceState
extends RefCounted
## What changes in a province during a campaign (PRD 3.11): buildings,
## construction, recruits waiting, happiness and food left to forage.
## The owner is kept in GameState.owners.

var buildings := {}  # building id -> level
var construction := ""  # Building being built or upgraded; "" for none.
var construction_turns := 0
var recruits: Array[String] = []  # Unit types that join the garrison at the end of the turn.
var happiness := 60.0
var forage := 0.0  # Food an army living off the land can still take here.


func level(building_id: String) -> int:
	return buildings.get(building_id, 0)
