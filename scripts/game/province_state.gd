class_name ProvinceState
extends RefCounted
## What changes in a region during a game (PRD 3.11, 3.10): buildings,
## construction, recruits waiting, happiness, food left to forage and any siege.
## The owner is kept in GameState.owners.

var buildings := {}  # building id -> level
var construction := ""  # Building being built or upgraded; "" for none.
var construction_turns := 0
var recruits: Array[String] = []  # Unit types that appear here at the end of the owner's turn.
var happiness := 60.0
var forage := 0.0  # Food a unit living off the land can still take here.
## The faction besieging this region's walls, and for how many of its turns.
var siege_faction := ""
var siege_turns := 0


func level(building_id: String) -> int:
	return buildings.get(building_id, 0)
