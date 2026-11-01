class_name Bonuses
extends RefCounted
## Bonuses from civilizations (PRD 8.5) and research (8.7). Everything that
## asks "does this faction get something extra?" comes through here.

const ANGLISH_HOME_DEFENSE := 1.15
const FRANKISH_CAVALRY_COST := 0.8
const BYZANTINE_MARKETS := 1.25


static func civ(state: GameState, faction: String) -> String:
	return state.factions[faction].civ if state.factions.has(faction) else ""


## Multiplier for a kind of income: "food", "gold", "iron" or "market".
static func income(state: GameState, faction: String, kind: String) -> float:
	var multiplier := Research.income(state, faction, kind)
	if kind == "market" and civ(state, faction) == "byzantine":
		multiplier *= BYZANTINE_MARKETS
	return multiplier


static func supply_range(state: GameState, faction: String) -> int:
	return Research.supply_range(state, faction)


## Multiplier on a unit type's gold cost.
static func recruit_cost(state: GameState, faction: String, unit_type: UnitType) -> float:
	if unit_type.is_cavalry() and civ(state, faction) == "frankish":
		return FRANKISH_CAVALRY_COST
	return 1.0


static func ignores_attrition(state: GameState, faction: String) -> bool:
	return civ(state, faction) == "saracen"


## Experience new recruits start with.
static func starting_xp(state: GameState, faction: String) -> int:
	return Research.starting_xp(state, faction)


## Free moves along the coast for Norse units (coastal raiding).
static func coastal_moves(state: GameState, faction: String) -> int:
	return 1 if civ(state, faction) == "norse" else 0


## Adds civilization and research bonuses to a unit's battle multipliers.
static func battle(state: GameState, unit: Unit, defending: bool, region: String) -> void:
	if defending and civ(state, unit.owner) == "anglish" and state.owners.get(region) == unit.owner:
		unit.defense_mod *= ANGLISH_HOME_DEFENSE
	Research.battle(state, unit)
