class_name FactionState
extends RefCounted
## A faction in a game: who plays it, its civilization and its treasury
## (gold, PRD 8.9).

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


func can_afford(cost: Dictionary) -> bool:
	for resource in cost:
		if resources[resource] < cost[resource]:
			return false
	return true


func pay(cost: Dictionary) -> void:
	for resource in cost:
		resources[resource] -= cost[resource]
