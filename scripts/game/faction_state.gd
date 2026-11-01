class_name FactionState
extends RefCounted
## A faction in a game: who plays it, its civilization, its treasury (gold,
## PRD 8.9) and its research (8.7).

const RESOURCES := ["gold"]

var id := ""
var display_name := ""
var color := Color.WHITE
var civ := ""
## Played by a person (hotseat can have several); otherwise by the AI.
var human := false
## AI personality: "aggressive", "balanced" or "defensive".
var ai := "balanced"
var alive := true
var resources := {"gold": 0.0}
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
