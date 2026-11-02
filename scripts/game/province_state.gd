class_name ProvinceState
extends RefCounted
## What changes in a region during a game (PRD 3.11, 3.10): buildings,
## construction, reinforcements on the way and any siege.
## The owner is kept in GameState.owners.

var buildings := {}  # building id -> level
var construction := ""  # Building being built or upgraded; "" for none.
var construction_turns := 0
## Reinforcement bundles that arrive here at the start of the owner's next turn: [{"type", "soldiers"}].
var recruits: Array = []
## The faction besieging this region's walls, and for how many of its turns.
var siege_faction := ""
var siege_turns := 0


func level(building_id: String) -> int:
	return buildings.get(building_id, 0)
