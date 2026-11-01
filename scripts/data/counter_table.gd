class_name CounterTable
extends Resource
## Damage multipliers between unit types (PRD 3.6): multipliers[attacker][defender].
## Special units use the row and column of the base unit they count as.

@export var multipliers := {}


func multiplier(attacker_id: String, defender_id: String) -> float:
	var attacker := Rules.unit(attacker_id).counter_id()
	var defender := Rules.unit(defender_id).counter_id()
	return multipliers.get(attacker, {}).get(defender, 1.0)
