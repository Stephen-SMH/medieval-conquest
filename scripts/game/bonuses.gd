class_name Bonuses
extends RefCounted
## Bonuses from civilizations (PRD 8.5) and research (8.7). Everything that
## asks "does this faction get something extra?" comes through here.


## Multiplier for a kind of income: "food", "gold", "iron" or "market".
static func income(_state: GameState, _faction: String, _kind: String) -> float:
	return 1.0


static func supply_range(_state: GameState, _faction: String) -> int:
	return 0


## Multiplier on a unit type's gold cost.
static func recruit_cost(_state: GameState, _faction: String, _unit_type: UnitType) -> float:
	return 1.0


static func ignores_attrition(_state: GameState, _faction: String) -> bool:
	return false


## Experience new recruits start with.
static func starting_xp(_state: GameState, _faction: String) -> int:
	return 0


## Adds civilization and research bonuses to a unit's battle multipliers.
static func battle(_state: GameState, _unit: Unit, _defending: bool, _region: String) -> void:
	pass
