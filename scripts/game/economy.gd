class_name Economy
extends RefCounted
## Resources, food and supply, buildings, recruiting, healing, taxes and
## happiness (PRD 3.3, 3.4, 3.11, 3.12, UT-7). Income is worked out by
## breakdown(), which the resource bar shows and the end of the turn applies,
## so the two always agree.

const SEASON_FOOD := {"Spring": 1.0, "Summer": 1.25, "Autumn": 1.5, "Winter": 0.25}  # FD-2
const TAX_RATES := {"low": 0.6, "normal": 1.0, "high": 1.5}
const TAX_HAPPINESS := {"low": 15.0, "normal": 0.0, "high": -20.0}
const GOLD_PER_1000 := 1.5           # Taxes per 1,000 people at normal tax and full happiness.
const POPULATION_FOOD_PER_1000 := 1.0  # FD-1
## Soldiers gained per person each turn: a 15,000-person capital adds 15 soldiers a turn.
const MANPOWER_RATE := 0.001
const LOGISTICS_FOOD_SAVING := 0.05  # Per point of the general's logistics.

const FOOD_CAP := 500.0              # ST-1
const FOOD_CAP_PER_GRANARY := 500.0
const MATERIAL_CAP := 1000.0         # ST-2: wood and iron.
const MATERIAL_CAP_PER_CAPITAL := 500.0

const STARVATION_LOSS := 0.10        # FD-3
const FORAGE_LOSS := 0.05            # FD-4
const SUPPLY_RANGE := 2
const WINTER_LOSS := 0.05            # FD-5
const WINTER_MOUNTAIN_LOSS := 0.10
const DESERTION_LOSS := 0.05         # Units lose soldiers when there's no gold to pay them.

const HEAL_SOLDIERS := 2             # UT-7: soldiers a resting unit regains in a friendly region...
const HEAL_SOLDIERS_BARRACKS := 4    # ...or with Barracks.
## Gold per soldier healed, as a share of a soldier's recruiting cost.
const HEAL_COST_SHARE := 1.0

const BASE_HAPPINESS := 50.0
const CAPITAL_HAPPINESS := 10.0
const GARRISON_HAPPINESS := 10.0
const STARVING_HAPPINESS := -20.0
const CONQUERED_HAPPINESS := 15.0    # Happiness right after a region changes hands.
const HAPPINESS_STEP := 10.0         # Happiness moves this far towards its target each turn.
const REVOLT_BELOW := 20.0           # PV-3
const REVOLT_CHANCE := 0.25
const AFTER_REVOLT_HAPPINESS := 40.0

const SLOTS := 4                     # PV-1
const CAPITAL_SLOTS := 6
const MAX_RECRUITS_PER_TURN := 2     # PV-2
const GENERAL_COST := {"gold": 100.0}

const START_RESOURCES := {"gold": 300.0, "food": 300.0, "wood": 100.0, "iron": 50.0, "manpower": 100.0}


# --- Region output ------------------------------------------------------------

## Enemy units in a region stop it producing anything for its owner.
static func blockaded(state: GameState, region: String) -> bool:
	return not state.enemy_units_in(region, state.owners[region]).is_empty()


static func building_bonus(state: GameState, region: String, field: String) -> float:
	var total := 0.0
	var province: ProvinceState = state.provinces[region]
	for building_id in province.buildings:
		total += province.buildings[building_id] * Rules.building(building_id).get(field)
	return total


## Food grown from the land, before farms and the season.
static func land_food(state: GameState, region: String) -> float:
	return state.map.terrain(region).food_output * state.map.provinces[region].population / 10000.0


## Food the region grows this turn, with farms, the season and research.
static func province_food(state: GameState, region: String) -> float:
	var food: float = (land_food(state, region) + building_bonus(state, region, "food")) * SEASON_FOOD[state.season()]
	return food * _bonus(state, state.owners[region], "food")


static func province_taxes(state: GameState, region: String) -> float:
	var owner: String = state.owners[region]
	if not state.factions.has(owner):
		return 0.0
	var happiness: float = state.provinces[region].happiness
	return state.map.provinces[region].population / 1000.0 * GOLD_PER_1000 * TAX_RATES[state.factions[owner].tax] \
		* (0.5 + happiness / 200.0) * _bonus(state, owner, "gold")


## A faction's multiplier for a kind of income, from civilization and research.
static func _bonus(state: GameState, faction: String, kind: String) -> float:
	return Bonuses.income(state, faction, kind)


# --- Income and upkeep (PRD 3.3, RS-2, RS-3) --------------------------------------

## For each resource, the lines that add up to its change this turn:
## {"gold": [["Taxes (normal)", 30.0], ["Unit upkeep", -18.0]], ...}.
static func breakdown(state: GameState, faction_id: String) -> Dictionary:
	var faction: FactionState = state.factions[faction_id]
	var lines := {}
	for resource in FactionState.RESOURCES:
		lines[resource] = []
	var totals := {}
	for region in state.map.province_order:
		if state.owners[region] != faction_id or blockaded(state, region):
			continue
		var season_mod: float = SEASON_FOOD[state.season()] * _bonus(state, faction_id, "food")
		_add(totals, "gold", "Taxes (%s)" % faction.tax, province_taxes(state, region))
		_add(totals, "gold", "Markets", building_bonus(state, region, "gold") * Bonuses.income(state, faction_id, "market"))
		_add(totals, "food", "Farmland (%s ×%.2f)" % [state.season(), season_mod], land_food(state, region) * season_mod)
		_add(totals, "food", "Farms", building_bonus(state, region, "food") * season_mod)
		_add(totals, "food", "Population eats", -state.map.provinces[region].population / 1000.0 * POPULATION_FOOD_PER_1000)
		_add(totals, "wood", "Land", state.map.terrain(region).wood_output)
		_add(totals, "wood", "Lumber camps", building_bonus(state, region, "wood"))
		_add(totals, "iron", "Land", state.map.terrain(region).iron_output * _bonus(state, faction_id, "iron"))
		_add(totals, "iron", "Mines", building_bonus(state, region, "iron") * _bonus(state, faction_id, "iron"))
		_add(totals, "manpower", "New recruits", state.map.provinces[region].population * MANPOWER_RATE)
	for unit in state.units_of(faction_id):
		_add(totals, "gold", "Unit upkeep", -unit_gold_upkeep(unit))
		if is_supplied(state, unit):
			_add(totals, "food", "Units eat", -unit_food_upkeep(unit))
	for key in totals:
		var parts: PackedStringArray = key.split("/", true, 1)
		lines[parts[0]].append([parts[1], totals[key]])
	return lines


## The change to each resource this turn: {"gold": 12.5, ...}.
static func deltas(state: GameState, faction_id: String) -> Dictionary:
	var lines := breakdown(state, faction_id)
	var result := {}
	for resource in lines:
		var total := 0.0
		for line in lines[resource]:
			total += line[1]
		result[resource] = total
	return result


static func unit_gold_upkeep(unit: Unit) -> float:
	return unit.type().upkeep_gold * unit.strength()


static func unit_food_upkeep(unit: Unit) -> float:
	var logistics := unit.general.logistics if unit.general != null else 0
	return unit.type().upkeep_food * unit.strength() * (1.0 - LOGISTICS_FOOD_SAVING * logistics)


static func _add(totals: Dictionary, resource: String, label: String, amount: float) -> void:
	if amount != 0.0:
		var key := resource + "/" + label
		totals[key] = totals.get(key, 0.0) + amount


# --- Supply (FD-4) ------------------------------------------------------------------

## Steps from each region to the nearest region the faction owns.
static func distance_from_territory(state: GameState, faction_id: String) -> Dictionary:
	var distance := {}
	var frontier := []
	for region in state.map.province_order:
		if state.owners[region] == faction_id:
			distance[region] = 0
			frontier.append(region)
	while not frontier.is_empty():
		var region: String = frontier.pop_front()
		for neighbour in state.map.neighbours(region):
			if not distance.has(neighbour):
				distance[neighbour] = distance[region] + 1
				frontier.append(neighbour)
	return distance


static func supply_range(state: GameState, unit: Unit) -> int:
	var bonus := 1 if unit.general != null and unit.general.logistics >= 3 else 0
	return SUPPLY_RANGE + bonus + Bonuses.supply_range(state, unit.owner)


## A unit is supplied from its faction's stockpile within its supply range of
## its own territory; otherwise it lives off the land.
static func is_supplied(state: GameState, unit: Unit) -> bool:
	var distance := distance_from_territory(state, unit.owner)
	return distance.get(unit.province, 1 << 30) <= supply_range(state, unit)


# --- Storage (3.12) ---------------------------------------------------------------

static func food_cap(state: GameState, faction_id: String) -> float:
	var cap := FOOD_CAP
	for region in state.map.province_order:
		if state.owners[region] == faction_id:
			cap += building_bonus(state, region, "food_storage")
	return cap


static func material_cap(state: GameState, faction_id: String) -> float:
	var cap := MATERIAL_CAP
	for region in state.map.province_order:
		if state.owners[region] == faction_id and state.is_capital(region):
			cap += MATERIAL_CAP_PER_CAPITAL
	return cap


# --- Buildings (3.11) -------------------------------------------------------------

static func building_cost(building: BuildingType) -> Dictionary:
	return {"gold": float(building.cost_gold), "wood": float(building.cost_wood), "iron": float(building.cost_iron)}


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
	if not state.factions[faction_id].can_afford(building_cost(building)):
		return "not enough resources"
	return ""


static func start_building(state: GameState, region: String, building_id: String) -> bool:
	var faction_id: String = state.owners[region]
	if not state.factions.has(faction_id) or build_problem(state, region, building_id, faction_id) != "":
		return false
	var building := Rules.building(building_id)
	state.factions[faction_id].pay(building_cost(building))
	state.provinces[region].construction = building_id
	state.provinces[region].construction_turns = building.build_turns
	return true


# --- Recruiting (PV-2) ------------------------------------------------------------

static func unit_cost(state: GameState, faction_id: String, unit_type: UnitType) -> Dictionary:
	var cost := {"gold": float(unit_type.cost_gold), "wood": float(unit_type.cost_wood),
		"iron": float(unit_type.cost_iron), "manpower": float(unit_type.cost_manpower)}
	cost.gold *= Bonuses.recruit_cost(state, faction_id, unit_type)
	return cost


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
	var waiting: int = state.provinces[region].recruits.size()
	if waiting >= MAX_RECRUITS_PER_TURN:
		return "%d recruits a turn at most" % MAX_RECRUITS_PER_TURN
	if state.space_in(region, faction_id) - waiting <= 0:
		return "no room: %d units at most" % GameState.STACK_LIMIT
	if not state.factions[faction_id].can_afford(unit_cost(state, faction_id, unit_type)):
		return "not enough resources"
	return ""


## Pays for the unit now; it appears in the region at the end of the turn.
static func recruit(state: GameState, region: String, unit_id: String) -> bool:
	var faction_id: String = state.owners[region]
	if not state.factions.has(faction_id) or recruit_problem(state, region, unit_id, faction_id) != "":
		return false
	state.factions[faction_id].pay(unit_cost(state, faction_id, Rules.unit(unit_id)))
	state.provinces[region].recruits.append(unit_id)
	return true


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


# --- Happiness (PV-3) ---------------------------------------------------------------

static func target_happiness(state: GameState, region: String, starving: bool) -> float:
	var owner: String = state.owners[region]
	var tax: String = state.factions[owner].tax if state.factions.has(owner) else "normal"
	var target: float = BASE_HAPPINESS + TAX_HAPPINESS[tax] + building_bonus(state, region, "happiness")
	if state.is_capital(region):
		target += CAPITAL_HAPPINESS
	if _has_own_units(state, region):
		target += GARRISON_HAPPINESS
	if starving:
		target += STARVING_HAPPINESS
	return clampf(target, 0.0, 100.0)


static func _has_own_units(state: GameState, region: String) -> bool:
	for unit in state.units_in(region):
		if unit.owner == state.owners[region]:
			return true
	return false


# --- End of a faction's turn --------------------------------------------------------

## Runs the economy for one faction at the end of its turn, in the current
## season. Returns events {"type": "economy", "faction", "kind", "text"}.
static func process_faction(state: GameState, faction_id: String) -> Array:
	var events := []
	var faction: FactionState = state.factions[faction_id]
	var note := func(kind: String, text: String): events.append(
		{"type": "economy", "faction": faction_id, "kind": kind, "text": text})
	var own_units := state.units_of(faction_id)

	# Income and upkeep, exactly as the resource bar shows them.
	var change := deltas(state, faction_id)
	for resource in change:
		faction.resources[resource] += change[resource]

	# Units beyond the supply range live off the land (FD-4).
	for unit in own_units:
		if is_supplied(state, unit):
			continue
		var province: ProvinceState = state.provinces[unit.province]
		var need := unit_food_upkeep(unit)
		if province.forage >= need:
			province.forage -= need
		else:
			province.forage = 0.0
			_lose(unit, FORAGE_LOSS)
			note.call("bad", "%s found nothing to forage in %s and lost soldiers." % [
				unit.type().display_name, state.map.region_name(unit.province)])

	# Starvation (FD-3) and unpaid troops.
	var starving: bool = faction.resources.food < 0.0
	if starving:
		faction.resources.food = 0.0
		for unit in own_units:
			_lose(unit, STARVATION_LOSS)
		note.call("bad", "Starvation! Every unit lost %d%% of its soldiers and the regions are unhappy." % roundi(STARVATION_LOSS * 100))
	if faction.resources.gold < 0.0:
		faction.resources.gold = 0.0
		for unit in own_units:
			_lose(unit, DESERTION_LOSS)
		note.call("bad", "No gold to pay the troops: %d%% of every unit deserted." % roundi(DESERTION_LOSS * 100))

	# Winter attrition outside your own territory (FD-5).
	if state.season() == "Winter" and not Bonuses.ignores_attrition(state, faction_id):
		for unit in own_units:
			if state.owners[unit.province] == faction_id:
				continue
			var share := WINTER_MOUNTAIN_LOSS if state.map.provinces[unit.province].terrain == "mountains" else WINTER_LOSS
			_lose(unit, share)
			note.call("bad", "%s lost %d%% of its soldiers to the winter in %s." % [
				unit.type().display_name, roundi(share * 100), state.map.region_name(unit.province)])

	# Healing units that rested in a friendly region (UT-7); not while starving.
	var healed := 0
	for unit in own_units if not starving else []:
		var amount := heal_amount(state, unit)
		var cost := heal_cost(unit.type())
		amount = mini(amount, floori(faction.resources.gold / cost) if cost > 0.0 else amount)
		if amount > 0 and not unit.is_destroyed():
			unit.set_soldiers(unit.soldiers() + amount)
			faction.resources.gold -= amount * cost
			healed += amount
	if healed > 0:
		note.call("good", "%d soldiers healed in resting units." % healed)

	# Storage limits and spoilage (3.12).
	var spoiled: float = faction.resources.food - food_cap(state, faction_id)
	if spoiled > 0.0:
		faction.resources.food -= spoiled
		note.call("info", "%d food spoiled: build granaries to store more." % roundi(spoiled))
	for resource in ["wood", "iron"]:
		faction.resources[resource] = minf(faction.resources[resource], material_cap(state, faction_id))

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
				if state.space_in(region, faction_id) > 0:
					var recruit := state.add_unit(unit_id, faction_id, region)
					recruit.xp = Bonuses.starting_xp(state, faction_id)
					note.call("good", "New %s ready in %s." % [Rules.unit(unit_id).display_name.to_lower(), where])
				else:
					waiting.append(unit_id)
			province.recruits = waiting
	events.append_array(Research.advance(state, faction_id))

	# Happiness and revolts (PV-3).
	for region in state.map.province_order:
		if state.owners[region] != faction_id:
			continue
		var province: ProvinceState = state.provinces[region]
		province.happiness = move_toward(province.happiness, target_happiness(state, region, starving), HAPPINESS_STEP)
		if province.happiness < REVOLT_BELOW and not _has_own_units(state, region) and state.rng.randf() < REVOLT_CHANCE:
			for i in mini(1 + floori(state.map.provinces[region].population / 8000.0), GameState.STACK_LIMIT):
				state.add_unit("militia", "rebels", region)
			province.happiness = AFTER_REVOLT_HAPPINESS
			note.call("bad", "Revolt in %s! Rebel militia have risen against you." % state.map.region_name(region))

	# Forage grows back.
	for region in state.map.province_order:
		var province: ProvinceState = state.provinces[region]
		province.forage = minf(province.forage + land_food(state, region) / state.turn_order.size(), land_food(state, region) * 2.0)
	return events


static func _lose(unit: Unit, share: float) -> void:
	unit.hp *= 1.0 - share
