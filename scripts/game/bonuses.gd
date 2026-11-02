class_name Bonuses
extends RefCounted
## Bonuses from civilizations (PRD 8.5) and the Forge (G). Everything that
## asks "does this faction get something extra?" comes through here.

const ANGLISH_HOME_DEFENSE := 1.15
const NORSE_SHORE_ATTACK := 1.15  # Sea-wolves: attacks on coastal regions.
const FRANKISH_CAVALRY_COST := 0.8
const BYZANTINE_MARKETS := 1.25
const SARACEN_REINFORCEMENTS := 0.85



static func civ(state: GameState, faction: String) -> String:
	return state.factions[faction].civ if state.factions.has(faction) else ""


## Multiplier for a kind of income: "gold" (all of it) or "market".
static func income(state: GameState, faction: String, kind: String) -> float:
	var multiplier := 1.0
	if kind == "market" and civ(state, faction) == "byzantine":
		multiplier *= BYZANTINE_MARKETS
	return multiplier


## Multiplier on a soldier type's price: Frankish cavalry 20% cheaper,
## Saracen reinforcements 15% cheaper.
static func recruit_cost(state: GameState, faction: String, unit_type: UnitType) -> float:
	if unit_type.is_cavalry() and civ(state, faction) == "frankish":
		return FRANKISH_CAVALRY_COST
	if civ(state, faction) == "saracen":
		return SARACEN_REINFORCEMENTS
	return 1.0


## Crusader hospitals: armies in their own regions heal even after marching or fighting.
static func heals_on_the_move(state: GameState, faction: String) -> bool:
	return civ(state, faction) == "crusader"


## Adds civilization bonuses and Forge upgrades to a troop's battle multipliers.
static func battle(state: GameState, troop: Troop, owner: String, defending: bool, region: String, _from := "") -> void:
	if defending and civ(state, owner) == "anglish" and state.owners.get(region) == owner:
		troop.defense_mod *= ANGLISH_HOME_DEFENSE
	if not defending and civ(state, owner) == "norse" and state.map.is_coastal(region):
		troop.attack_mod *= NORSE_SHORE_ATTACK
	Forge.apply(state.upgrades.get(owner, {}), troop)
