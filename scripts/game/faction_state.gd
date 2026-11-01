class_name FactionState
extends RefCounted
## A faction in a game: who plays it, its civilization, its shared stockpile
## (PRD 3.3, 3.12), tax level (PV-4) and research (8.7).

const RESOURCES := ["gold", "food", "wood", "iron", "manpower"]
const TAX_LEVELS := ["low", "normal", "high"]

var id := ""
var display_name := ""
var color := Color.WHITE
var civ := ""
## Played by a person (hotseat can have several); otherwise by the AI.
var human := false
## AI personality: "aggressive", "balanced" or "defensive".
var ai := "balanced"
var alive := true
var resources := {"gold": 0.0, "food": 0.0, "wood": 0.0, "iron": 0.0, "manpower": 0.0}
var tax := "normal"
var techs: Array[String] = []
var researching := ""
var research_turns_left := 0


func can_afford(cost: Dictionary) -> bool:
	for resource in cost:
		if resources[resource] < cost[resource]:
			return false
	return true


func pay(cost: Dictionary) -> void:
	for resource in cost:
		resources[resource] -= cost[resource]


func has_tech(tech_id: String) -> bool:
	return tech_id in techs
