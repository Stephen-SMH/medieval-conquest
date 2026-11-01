class_name CounterTable
extends Resource
## Damage multipliers between unit types (PRD 3.6): multipliers[attacker][defender].

@export var multipliers := {}


func multiplier(attacker_id: String, defender_id: String) -> float:
	return multipliers.get(attacker_id, {}).get(defender_id, 1.0)
