class_name FactionState
extends RefCounted
## A faction's shared stockpile (PRD 3.3, 3.12) and tax level (PV-4).

const RESOURCES := ["gold", "food", "wood", "iron", "manpower"]
const TAX_LEVELS := ["low", "normal", "high"]

var id := ""
var resources := {"gold": 0.0, "food": 0.0, "wood": 0.0, "iron": 0.0, "manpower": 0.0}
var tax := "normal"


func can_afford(cost: Dictionary) -> bool:
	for resource in cost:
		if resources[resource] < cost[resource]:
			return false
	return true


func pay(cost: Dictionary) -> void:
	for resource in cost:
		resources[resource] -= cost[resource]
