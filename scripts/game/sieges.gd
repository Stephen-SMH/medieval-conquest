class_name Sieges
extends RefCounted
## Walls and sieges (PRD 3.10). Walls make defenders take less damage. An
## attacker can assault them at once, or besiege them from a neighbouring
## region: after 2, 4 or 6 turns (palisade, stone walls, castle) the walls are
## breached, the bonus is gone, and the starving defenders lose a quarter of
## their soldiers every turn.

const WALL_NAMES := ["no walls", "Palisade", "Stone walls", "Castle"]
const WALL_BONUS := [0.0, 0.5, 1.0, 1.5]  # Damage taken by defenders ÷ (1 + bonus).
const CATAPULT_CUT := 0.25  # Each attacking catapult takes this off the bonus.
const TURNS_PER_LEVEL := 2
const STARVATION := 0.25


## Wall level of a region: 0 none, 1 palisade, 2 stone walls, 3 castle.
static func walls(state: GameState, region: String) -> int:
	return state.provinces[region].level("walls")


## Turns of siege the walls hold out: 2 per level, 1 less with Siege Engineering.
static func duration(state: GameState, region: String, besieger: String) -> int:
	var turns := walls(state, region) * TURNS_PER_LEVEL
	if state.factions.has(besieger) and state.factions[besieger].has_tech("siege_engineering"):
		turns -= 1
	return maxi(turns, 1)


static func breached(state: GameState, region: String) -> bool:
	var province: ProvinceState = state.provinces[region]
	return province.siege_faction != "" and province.siege_turns >= duration(state, region, province.siege_faction)


## The defenders' wall bonus against an assault by `attacking`.
static func wall_bonus(state: GameState, region: String, attacking: Array[Unit]) -> float:
	var level := walls(state, region)
	if level == 0 or (breached(state, region) and not attacking.is_empty() and state.provinces[region].siege_faction == attacking[0].owner):
		return 0.0
	var catapults := 0.0
	for unit in attacking:
		for troop in unit.troops:
			if troop.type().unit_class == "siege":
				catapults += troop.soldiers / float(UnitType.SOLDIERS)
	return maxf(WALL_BONUS[level] - CATAPULT_CUT * catapults, 0.0)


## "" if these units can besiege `region`, else why not.
static func besiege_problem(state: GameState, stack: Array, region: String) -> String:
	if stack.is_empty():
		return "no units"
	var faction: String = stack[0].owner
	if walls(state, region) == 0:
		return "no walls to besiege"
	if state.owners[region] == faction:
		return "your own region"
	var province: ProvinceState = state.provinces[region]
	if province.siege_faction == faction:
		return "already besieging it"
	for unit: Unit in stack:
		if unit.has_melee() and map_adjacent(state, unit, region) and not unit.attacked:
			return ""
	return "needs an army with melee soldiers next to it that hasn't fought this turn"


static func map_adjacent(state: GameState, unit: Unit, region: String) -> bool:
	return state.map.are_neighbours(unit.province, region)


## Starts a siege: it uses the besieging units' attack this turn.
static func besiege(state: GameState, stack: Array, region: String) -> bool:
	if besiege_problem(state, stack, region) != "":
		return false
	var province: ProvinceState = state.provinces[region]
	province.siege_faction = stack[0].owner
	province.siege_turns = 0
	for unit: Unit in stack:
		if map_adjacent(state, unit, region):
			unit.attacked = true
	return true


## At the end of the besieger's turn: the siege goes on while one of its melee
## units still stands next to the walls, and breached walls starve the defenders.
static func advance(state: GameState, faction: String) -> Array:
	var events := []
	for region in state.map.province_order:
		var province: ProvinceState = state.provinces[region]
		if province.siege_faction != faction:
			continue
		var still_there := false
		for unit in state.units_of(faction):
			if unit.has_melee() and state.map.are_neighbours(unit.province, region):
				still_there = true
		if not still_there or state.owners[region] == faction:
			province.siege_faction = ""
			province.siege_turns = 0
			events.append({"type": "siege_lifted", "province": region, "faction": faction})
			continue
		province.siege_turns += 1
		if breached(state, region):
			for unit in state.units_in(region):
				if unit.owner != faction:
					for troop in unit.troops:
						var before := troop.soldiers
						troop.lose_share(STARVATION)
						state.note_loss(unit.owner, troop.type_id, before - troop.soldiers)
			events.append({"type": "siege_breached", "province": region, "faction": faction})
	return events
