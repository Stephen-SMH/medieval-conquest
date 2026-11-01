class_name Bonuses
extends RefCounted
## Bonuses from civilizations (PRD 8.5) and research (8.7). Everything that
## asks "does this faction get something extra?" comes through here.

const ANGLISH_HOME_DEFENSE := 1.15
const FRANKISH_CAVALRY_COST := 0.8
const BYZANTINE_MARKETS := 1.25
const SARACEN_MERCENARIES := 0.75
const CRUSADER_HEALING := 2  # Extra soldiers a resting unit regains each turn.


static func civ(state: GameState, faction: String) -> String:
	return state.factions[faction].civ if state.factions.has(faction) else ""


## Multiplier for a kind of income: "gold" (all of it) or "market".
static func income(state: GameState, faction: String, kind: String) -> float:
	var multiplier := Research.income(state, faction, kind)
	if kind == "market" and civ(state, faction) == "byzantine":
		multiplier *= BYZANTINE_MARKETS
	return multiplier


## Multiplier on a unit type's gold cost.
static func recruit_cost(state: GameState, faction: String, unit_type: UnitType) -> float:
	if unit_type.is_cavalry() and civ(state, faction) == "frankish":
		return FRANKISH_CAVALRY_COST
	return 1.0


## Multiplier on what mercenaries cost.
static func mercenary_cost(state: GameState, faction: String) -> float:
	return SARACEN_MERCENARIES if civ(state, faction) == "saracen" else 1.0


## Crusader hospitals: extra soldiers a resting unit heals each turn.
static func extra_healing(state: GameState, faction: String) -> int:
	return CRUSADER_HEALING if civ(state, faction) == "crusader" else 0


## Experience new recruits start with.
static func starting_xp(state: GameState, faction: String) -> int:
	return Research.starting_xp(state, faction)


## Norse raiding: moves 2 regions along the coast.
static func coastal_moves(state: GameState, faction: String) -> int:
	return 1 if civ(state, faction) == "norse" else 0


## Adds civilization and research bonuses to a unit's battle multipliers.
static func battle(state: GameState, unit: Unit, defending: bool, region: String) -> void:
	if defending and civ(state, unit.owner) == "anglish" and state.owners.get(region) == unit.owner:
		unit.defense_mod *= ANGLISH_HOME_DEFENSE
	Research.battle(state, unit)
