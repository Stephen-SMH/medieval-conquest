class_name Economy
extends RefCounted
## The gold economy (PRD 8.9, which replaces 3.3, 3.4 and 3.12): every region
## earns gold each turn (10, more for towns, capitals and markets), and gold
## pays for recruiting, mercenaries, healing, buildings, research and upkeep.
## If gold would run out, units desert. Income is worked out by breakdown(),
## which the treasury shows and the end of the turn applies.

const REGION_INCOME := 10.0
const TOWN_INCOME := 5.0
const CAPITAL_INCOME := 10.0
const DESERTION_LOSS := 0.05         # Units lose soldiers when there's no gold to pay them.
const LOGISTICS_UPKEEP_SAVING := 0.05  # Per point of a general's logistics, for his unit.

const HEAL_SOLDIERS := 2             # UT-7: soldiers a resting unit regains in a friendly region...
const HEAL_SOLDIERS_BARRACKS := 4    # ...or with Barracks.
## Gold per soldier healed, as a share of a soldier's recruiting cost.
const HEAL_COST_SHARE := 1.0

const SLOTS := 4                     # PV-1
const CAPITAL_SLOTS := 6
const MAX_RECRUITS_PER_TURN := 1     # One unit per region, so one recruit at a time.
## Mercenaries at towns and camps: what each offers, how many to start with, and the price in gold.
const MERCENARY_OFFERS := {
	"town": ["spearmen", "crossbowmen", "swordsmen"],
	"camp": ["militia", "archers", "light_cavalry"],
}
const MERCENARY_START := 2
const MERCENARY_RESTOCK_TURNS := 3  # One more of each offered type every this many turns, up to MERCENARY_MAX.
const MERCENARY_MAX := 4
const MERCENARY_PRICE := 1.5  # Times the unit's gold cost.
const GENERAL_COST := {"gold": 100.0}

const START_RESOURCES := {"gold": 300.0}


# --- Income ----------------------------------------------------------------------------

## Enemy units in a region stop it paying its owner.
static func blockaded(state: GameState, region: String) -> bool:
	return not state.enemy_units_in(region, state.owners[region]).is_empty()


static func building_bonus(state: GameState, region: String, field: String) -> float:
	var total := 0.0
	var province: ProvinceState = state.provinces[region]
	for building_id in province.buildings:
		total += province.buildings[building_id] * Rules.building(building_id).get(field)
	return total


## "town", "camp" or "" for a region.
static func site(state: GameState, region: String) -> String:
	return state.map.provinces[region].get("site", "")


## The gold a region pays its owner each turn: the number on the map.
static func region_income(state: GameState, region: String) -> float:
	var owner: String = state.owners[region]
	var income := REGION_INCOME + Research.region_bonus(state, owner, region)
	if site(state, region) == "town":
		income += TOWN_INCOME
	if state.is_capital(region):
		income += CAPITAL_INCOME
	income += building_bonus(state, region, "gold") * Bonuses.income(state, owner, "market")
	return roundf(income * Bonuses.income(state, owner, "gold"))


## The lines that add up to the gold change this turn: {"gold": [["Regions", 60.0], ...]}.
static func breakdown(state: GameState, faction_id: String) -> Dictionary:
	var totals := {}
	for region in state.map.province_order:
		if state.owners[region] != faction_id or blockaded(state, region):
			continue
		var label := "Capital" if state.is_capital(region) else ("Towns" if site(state, region) == "town" else "Regions")
		if state.provinces[region].level("market") > 0:
			label = "Market regions"
		totals[label] = totals.get(label, 0.0) + region_income(state, region)
	for unit in state.units_of(faction_id):
		totals["Unit upkeep"] = totals.get("Unit upkeep", 0.0) - unit_upkeep(state, unit)
	var lines := []
	for label in totals:
		lines.append([label, totals[label]])
	return {"gold": lines}


## The change to the treasury this turn: {"gold": 42.0}.
static func deltas(state: GameState, faction_id: String) -> Dictionary:
	var total := 0.0
	for line in breakdown(state, faction_id).gold:
		total += line[1]
	return {"gold": total}


static func unit_upkeep(state: GameState, unit: Unit) -> float:
	var logistics := unit.general.logistics if unit.general != null else 0
	return unit.type().upkeep_gold * unit.strength() * (1.0 - LOGISTICS_UPKEEP_SAVING * logistics) * Research.upkeep_mod(state, unit.owner)


# --- Buildings (3.11) -------------------------------------------------------------

## The cost of building `building` up to `level`.
static func building_cost(building: BuildingType, level := 1) -> Dictionary:
	var scale := 1.0
	if level - 1 < building.level_cost_multipliers.size():
		scale = building.level_cost_multipliers[level - 1]
	return {"gold": building.cost_gold * scale}


static func slots(state: GameState, region: String) -> int:
	return CAPITAL_SLOTS if state.is_capital(region) else SLOTS


static func used_slots(state: GameState, region: String) -> int:
	var province: ProvinceState = state.provinces[region]
	var used := province.buildings.size()
	if province.construction != "" and province.level(province.construction) == 0:
		used += 1
	return used


## "" if the faction can build (or upgrade) the building here now, else the reason why not.
static func build_problem(state: GameState, region: String, building_id: String, faction_id: String) -> String:
	var province: ProvinceState = state.provinces[region]
	var building := Rules.building(building_id)
	if state.owners[region] != faction_id:
		return "not your region"
	if blockaded(state, region):
		return "enemy units are here"
	if province.construction != "":
		return "already building: %s" % Rules.building(province.construction).display_name.to_lower()
	if province.level(building_id) >= building.max_level:
		return "fully built"
	if not building.allowed_terrains.is_empty() and not (state.map.provinces[region].terrain in building.allowed_terrains):
		return "needs %s" % " or ".join(building.allowed_terrains)
	if province.level(building_id) == 0 and used_slots(state, region) >= slots(state, region):
		return "no free building slots"
	if not state.factions[faction_id].can_afford(building_cost(building, province.level(building_id) + 1)):
		return "not enough gold"
	return ""


static func start_building(state: GameState, region: String, building_id: String) -> bool:
	var faction_id: String = state.owners[region]
	if not state.factions.has(faction_id) or build_problem(state, region, building_id, faction_id) != "":
		return false
	var building := Rules.building(building_id)
	state.factions[faction_id].pay(building_cost(building, state.provinces[region].level(building_id) + 1))
	state.provinces[region].construction = building_id
	state.provinces[region].construction_turns = building.build_turns
	return true


# --- Recruiting ---------------------------------------------------------------------

static func unit_cost(state: GameState, faction_id: String, unit_type: UnitType) -> Dictionary:
	return {"gold": roundf(unit_type.cost_gold * Bonuses.recruit_cost(state, faction_id, unit_type))}


## Unit types a faction may ever recruit: the base roster plus its civilization's own.
static func roster(state: GameState, faction_id: String) -> Array[String]:
	var civ: String = state.factions[faction_id].civ
	var ids: Array[String] = []
	for unit_id in Rules.units:
		var unit_type := Rules.unit(unit_id)
		if unit_type.civilization == "" or unit_type.civilization == civ:
			ids.append(unit_id)
	return ids


## "" if the faction can recruit the unit here now, else the reason why not.
static func recruit_problem(state: GameState, region: String, unit_id: String, faction_id: String) -> String:
	var unit_type := Rules.unit(unit_id)
	if state.owners[region] != faction_id:
		return "not your region"
	if not (unit_id in roster(state, faction_id)):
		return "only the %s can recruit it" % unit_type.civilization.capitalize()
	if unit_type.required_tech != "" and not state.factions[faction_id].has_tech(unit_type.required_tech):
		return "needs research: %s" % Rules.tech_name(unit_type.required_tech)
	if blockaded(state, region):
		return "enemy units are here"
	if unit_type.required_building != "" and state.provinces[region].level(unit_type.required_building) == 0:
		return "needs: %s" % Rules.building(unit_type.required_building).display_name.to_lower()
	var room := _room_problem(state, region, unit_id)
	if room != "":
		return room
	if not state.factions[faction_id].can_afford(unit_cost(state, faction_id, unit_type)):
		return "not enough gold"
	return ""


## Recruits need an empty region, or a unit of the same type there to reinforce.
static func _room_problem(state: GameState, region: String, unit_id: String) -> String:
	if state.provinces[region].recruits.size() >= MAX_RECRUITS_PER_TURN:
		return "one recruit per region per turn"
	var occupant := state.unit_in(region)
	if occupant != null and (occupant.type_id != unit_id or occupant.soldiers() >= UnitType.SOLDIERS):
		return "no room: one unit per region (a %s can only be reinforced)" % occupant.type().display_name.to_lower() \
			if occupant.owner == state.owners[region] else "enemy units are here"
	return ""


## Pays for the unit now; it appears in the region at the end of the turn.
static func recruit(state: GameState, region: String, unit_id: String) -> bool:
	var faction_id: String = state.owners[region]
	if not state.factions.has(faction_id) or recruit_problem(state, region, unit_id, faction_id) != "":
		return false
	state.factions[faction_id].pay(unit_cost(state, faction_id, Rules.unit(unit_id)))
	state.provinces[region].recruits.append(unit_id)
	return true


# --- Mercenaries ----------------------------------------------------------------------

static func mercenary_price(unit_type: UnitType, state: GameState = null, faction_id := "") -> float:
	var price := unit_type.cost_gold * MERCENARY_PRICE
	if state != null:
		price *= Bonuses.mercenary_cost(state, faction_id)
	return roundf(price)


## "" if the faction can hire this mercenary here now, else why not.
static func hire_problem(state: GameState, region: String, unit_id: String, faction_id: String) -> String:
	if state.owners[region] != faction_id:
		return "not your region"
	if site(state, region) == "":
		return "mercenaries are only hired in towns and camps"
	if int(state.provinces[region].mercenaries.get(unit_id, 0)) <= 0:
		return "none available here"
	if blockaded(state, region):
		return "enemy units are here"
	var room := _room_problem(state, region, unit_id)
	if room != "":
		return room
	if state.factions[faction_id].resources.gold < mercenary_price(Rules.unit(unit_id), state, faction_id):
		return "not enough gold"
	return ""


## Pays in gold; the mercenaries arrive at the end of the turn.
static func hire(state: GameState, region: String, unit_id: String) -> bool:
	var faction_id: String = state.owners[region]
	if not state.factions.has(faction_id) or hire_problem(state, region, unit_id, faction_id) != "":
		return false
	state.factions[faction_id].resources.gold -= mercenary_price(Rules.unit(unit_id), state, faction_id)
	state.provinces[region].mercenaries[unit_id] = int(state.provinces[region].mercenaries[unit_id]) - 1
	state.provinces[region].recruits.append(unit_id)
	return true


## Fills a town's or camp's stock at the start of the game.
static func stock_mercenaries(state: GameState) -> void:
	for region in state.map.province_order:
		for unit_id in MERCENARY_OFFERS.get(site(state, region), []):
			state.provinces[region].mercenaries[unit_id] = MERCENARY_START


static func _restock(state: GameState) -> void:
	if state.turn % MERCENARY_RESTOCK_TURNS != 0:
		return
	for region in state.map.province_order:
		for unit_id in state.provinces[region].mercenaries:
			state.provinces[region].mercenaries[unit_id] = mini(int(state.provinces[region].mercenaries[unit_id]) + 1, MERCENARY_MAX)


# --- Healing (UT-7) ---------------------------------------------------------------

## Gold to heal one soldier of this type.
static func heal_cost(unit_type: UnitType) -> float:
	return unit_type.cost_gold / float(UnitType.SOLDIERS) * HEAL_COST_SHARE


## Soldiers a unit would heal at the end of this turn if the gold allows.
static func heal_amount(state: GameState, unit: Unit) -> int:
	if unit.moved or unit.attacked or state.owners[unit.province] != unit.owner:
		return 0
	var rate := HEAL_SOLDIERS_BARRACKS if state.provinces[unit.province].level("barracks") > 0 else HEAL_SOLDIERS
	return mini(rate, UnitType.SOLDIERS - unit.soldiers())


# --- End of turn --------------------------------------------------------------------

## Runs the economy for one faction at the end of the turn. Returns events
## {"type": "economy", "faction", "kind", "text"}.
static func process_faction(state: GameState, faction_id: String) -> Array:
	var events := []
	var faction: FactionState = state.factions[faction_id]
	var note := func(kind: String, text: String): events.append(
		{"type": "economy", "faction": faction_id, "kind": kind, "text": text})
	var own_units := state.units_of(faction_id)

	faction.resources.gold += deltas(state, faction_id).gold
	if faction.resources.gold < 0.0:
		faction.resources.gold = 0.0
		for unit in own_units:
			unit.hp *= 1.0 - DESERTION_LOSS
		note.call("bad", "No gold to pay the troops: %d%% of every unit deserted." % roundi(DESERTION_LOSS * 100))

	# Healing units that rested in a friendly region (UT-7).
	var healed := 0
	for unit in own_units:
		var amount := heal_amount(state, unit)
		var cost := heal_cost(unit.type())
		amount = mini(amount, floori(faction.resources.gold / cost) if cost > 0.0 else amount)
		if amount > 0 and not unit.is_destroyed():
			unit.set_soldiers(unit.soldiers() + amount)
			faction.resources.gold -= amount * cost
			healed += amount
	if healed > 0:
		note.call("good", "%d soldiers healed in resting units." % healed)

	# Construction, research and recruits.
	for region in state.map.province_order:
		if state.owners[region] != faction_id:
			continue
		var province: ProvinceState = state.provinces[region]
		var where := state.map.region_name(region)
		if province.construction != "" and not blockaded(state, region):
			province.construction_turns -= 1
			if province.construction_turns <= 0:
				province.buildings[province.construction] = province.level(province.construction) + 1
				note.call("good", "%s finished in %s." % [Rules.building(province.construction).display_name, where])
				province.construction = ""
		if not province.recruits.is_empty() and not blockaded(state, region):
			var waiting: Array[String] = []
			for unit_id in province.recruits:
				var occupant := state.unit_in(region)
				if occupant == null:
					var recruit := state.add_unit(unit_id, faction_id, region)
					recruit.xp = Bonuses.starting_xp(state, faction_id)
					note.call("good", "New %s ready in %s." % [Rules.unit(unit_id).display_name.to_lower(), where])
				elif occupant.owner == faction_id and occupant.type_id == unit_id and occupant.soldiers() < UnitType.SOLDIERS:
					occupant.set_soldiers(UnitType.SOLDIERS)
					note.call("good", "The %s in %s were reinforced." % [Rules.unit(unit_id).display_name.to_lower(), where])
				else:
					waiting.append(unit_id)
			province.recruits = waiting
	events.append_array(Research.advance(state, faction_id))
	if faction_id == state.living_factions()[0]:
		_restock(state)
	return events
