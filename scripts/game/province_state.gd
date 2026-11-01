class_name ProvinceState
extends RefCounted
## What changes in a region during a game (PRD 3.11, 3.10): buildings,
## construction, recruits waiting, any siege and mercenaries for hire.
## The owner is kept in GameState.owners.

var buildings := {}  # building id -> level
var construction := ""  # Building being built or upgraded; "" for none.
var construction_turns := 0
var recruits: Array[String] = []  # Unit types that appear here at the end of the owner's turn.
## The faction besieging this region's walls, and for how many of its turns.
var siege_faction := ""
var siege_turns := 0
## Mercenaries for hire in a town or camp region: unit type -> how many are available.
var mercenaries := {}


func level(building_id: String) -> int:
	return buildings.get(building_id, 0)
