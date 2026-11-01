class_name Economy
extends RefCounted
## Resources, food and supply, buildings, recruiting, taxes and happiness
## (PRD 3.3, 3.4, 3.11, 3.12). Income is worked out by breakdown(), which the
## resource bar shows and the end of the turn applies, so the two always agree.

const SEASON_FOOD := {"Spring": 1.0, "Summer": 1.25, "Autumn": 1.5, "Winter": 0.25}  # FD-2
const TAX_RATES := {"low": 0.6, "normal": 1.0, "high": 1.5}
const TAX_HAPPINESS := {"low": 15.0, "normal": 0.0, "high": -20.0}
const GOLD_PER_1000 := 1.5           # Taxes per 1,000 people at normal tax and full happiness.
const POPULATION_FOOD_PER_1000 := 1.0  # FD-1
## Share of the population that becomes manpower each turn. The PRD says 5%,
## but that gives one capital 7 new regiments a turn; 0.5% keeps manpower a real limit.
const MANPOWER_RATE := 0.005
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
const DESERTION_LOSS := 0.05         # Armies lose men when there's no gold to pay them.

const BASE_HAPPINESS := 50.0
const CAPITAL_HAPPINESS := 10.0
const GARRISON_HAPPINESS := 10.0
const STARVING_HAPPINESS := -20.0
const CONQUERED_HAPPINESS := 15.0    # Happiness right after a province changes hands.
const HAPPINESS_STEP := 10.0         # Happiness moves this far towards its target each turn.
const REVOLT_BELOW := 20.0           # PV-3
const REVOLT_CHANCE := 0.25
const AFTER_REVOLT_HAPPINESS := 40.0

const SLOTS := 4                     # PV-1
const CAPITAL_SLOTS := 6
const MAX_RECRUITS_PER_TURN := 2     # PV-2
const GENERAL_COST := {"gold": 100.0}  # Appointing a general, also when splitting an army.

const START_RESOURCES := {"gold": 300.0, "food": 300.0, "wood": 100.0, "iron": 50.0, "manpower": 300.0}


# --- Province output ------------------------------------------------------------

## An enemy army in a province stops it producing anything for its owner.
static func blockaded(state: GameState, id: String) -> bool:
	return not state.enemy_armies_in(id, state.owners[id]).is_empty()


static func building_bonus(state: GameState, id: String, field: String) -> float:
	var total := 0.0
	var province: ProvinceState = state.provinces[id]
	for building_id in province.buildings:
		total += province.buildings[building_id] * Rules.building(building_id).get(field)
	return total


## Food grown from the land, before farms and the season.
static func land_food(state: GameState, id: String) -> float:
	return state.map.terrain(id).food_output * state.map.provinces[id].population / 10000.0


## Food the province grows this turn, with farms and the season.
static func province_food(state: GameState, id: String) -> float:
	return (land_food(state, id) + building_bonus(state, id, "food")) * SEASON_FOOD[state.season()]


static func province_taxes(state: GameState, id: String) -> float:
	var faction: FactionState = state.factions[state.owners[id]]
	var happiness: float = state.provinces[id].happiness
	return state.map.provinces[id].population / 1000.0 * GOLD_PER_1000 * TAX_RATES[faction.tax] * (0.5 + happiness / 200.0)


# --- Income and upkeep (PRD 3.3, RS-2, RS-3) --------------------------------------

## For each resource, the lines that add up to its change this turn:
## {"gold": [["Taxes", 30.0], ["Army upkeep", -18.0]], ...}.
static func breakdown(state: GameState, faction_id: String) -> Dictionary:
	var faction: FactionState = state.factions[faction_id]
	var totals := {}
	for id in state.map.province_order:
		if state.owners[id] != faction_id or blockaded(state, id):
			continue
		var season_mod: float = SEASON_FOOD[state.season()]
		_add(totals, "Taxes (%s)" % faction.tax, province_taxes(state, id))
		_add(totals, "Markets", building_bonus(state, id, "gold"))
		_add(totals, "Farmland (%s ×%.2f)" % [state.season(), season_mod], land_food(state, id) * season_mod)
		_add(totals, "Farms", building_bonus(state, id, "food") * season_mod)
		_add(totals, "Population eats", -state.map.provinces[id].population / 1000.0 * POPULATION_FOOD_PER_1000)
		_add(totals, "Land (wood)", state.map.terrain(id).wood_output)
		_add(totals, "Lumber camps", building_bonus(state, id, "wood"))
		_add(totals, "Land (iron)", state.map.terrain(id).iron_output)
		_add(totals, "Mines", building_bonus(state, id, "iron"))
		_add(totals, "New recruits", state.map.provinces[id].population * MANPOWER_RATE)
	for army in state.armies:
		if army.owner != faction_id:
			continue
		_add(totals, "Army upkeep", -army_gold_upkeep(army))
		if is_supplied(state, army):
			_add(totals, "Armies eat", -army_food_upkeep(army))

	var lines := {}
	var resource_of := {
		"Markets": "gold", "Army upkeep": "gold",
		"Farms": "food", "Population eats": "food", "Armies eat": "food",
		"Land (wood)": "wood", "Lumber camps": "wood", "Land (iron)": "iron", "Mines": "iron",
		"New recruits": "manpower",
	}
	for resource in FactionState.RESOURCES:
		lines[resource] = []
	for label in totals:
		var resource: String = resource_of.get(label, "gold" if label.begins_with("Taxes") else "food")
		lines[resource].append([label, totals[label]])
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


static func army_gold_upkeep(army: Army) -> float:
	var total := 0.0
	for regiment in army.regiments:
		total += regiment.type().upkeep_gold * regiment.strength()
	return total


static func army_food_upkeep(army: Army) -> float:
	var total := 0.0
	for regiment in army.regiments:
		total += regiment.type().upkeep_food * regiment.strength()
	var logistics := army.general.logistics if army.general != null else 0
	return total * (1.0 - LOGISTICS_FOOD_SAVING * logistics)


static func _add(totals: Dictionary, label: String, amount: float) -> void:
	if amount != 0.0:
		totals[label] = totals.get(label, 0.0) + amount


# --- Supply (FD-4) ------------------------------------------------------------------

## Steps from each province to the nearest province the faction owns.
static func distance_from_territory(state: GameState, faction_id: String) -> Dictionary:
	var distance := {}
	var frontier := []
	for id in state.map.province_order:
		if state.owners[id] == faction_id:
			distance[id] = 0
			frontier.append(id)
	while not frontier.is_empty():
		var id: String = frontier.pop_front()
		for neighbour in state.map.neighbours(id):
			if not distance.has(neighbour):
				distance[neighbour] = distance[id] + 1
				frontier.append(neighbour)
	return distance


static func supply_range(army: Army) -> int:
	return SUPPLY_RANGE + (1 if army.general != null and army.general.logistics >= 3 else 0)


## An army is supplied from its faction's stockpile when it is within its supply
## range of its own territory; otherwise it lives off the land.
static func is_supplied(state: GameState, army: Army) -> bool:
	var distance := distance_from_territory(state, army.owner)
	return distance.get(army.province, 1 << 30) <= supply_range(army)


# --- Storage (3.12) ---------------------------------------------------------------

static func food_cap(state: GameState, faction_id: String) -> float:
	var cap := FOOD_CAP
	for id in state.map.province_order:
		if state.owners[id] == faction_id:
			cap += building_bonus(state, id, "food_storage")
	return cap


static func material_cap(state: GameState, faction_id: String) -> float:
	var cap := MATERIAL_CAP
	for id in state.map.province_order:
		if state.owners[id] == faction_id and state.map.provinces[id].capital:
			cap += MATERIAL_CAP_PER_CAPITAL
	return cap


# --- Buildings (3.11) -------------------------------------------------------------

static func building_cost(building: BuildingType) -> Dictionary:
	return {"gold": float(building.cost_gold), "wood": float(building.cost_wood), "iron": float(building.cost_iron)}


static func slots(state: GameState, id: String) -> int:
	return CAPITAL_SLOTS if state.map.provinces[id].capital else SLOTS


static func used_slots(state: GameState, id: String) -> int:
	var province: ProvinceState = state.provinces[id]
	var used := province.buildings.size()
	if province.construction != "" and province.level(province.construction) == 0:
		used += 1
	return used


## "" if the faction can build (or upgrade) the building here now, else the reason why not.
static func build_problem(state: GameState, id: String, building_id: String, faction_id: String) -> String:
	var province: ProvinceState = state.provinces[id]
	var building := Rules.building(building_id)
	if state.owners[id] != faction_id:
		return "not your province"
	if blockaded(state, id):
		return "an enemy army is here"
	if province.construction != "":
		return "already building: %s" % Rules.building(province.construction).display_name.to_lower()
	if province.level(building_id) >= building.max_level:
		return "fully built"
	if not building.allowed_terrains.is_empty() and not (state.map.provinces[id].terrain in building.allowed_terrains):
		return "needs %s" % " or ".join(building.allowed_terrains)
	if province.level(building_id) == 0 and used_slots(state, id) >= slots(state, id):
		return "no free building slots"
	if not state.factions[faction_id].can_afford(building_cost(building)):
		return "not enough resources"
	return ""


static func start_building(state: GameState, id: String, building_id: String) -> bool:
	var faction_id: String = state.owners[id]
	if build_problem(state, id, building_id, faction_id) != "":
		return false
	var building := Rules.building(building_id)
	state.factions[faction_id].pay(building_cost(building))
	state.provinces[id].construction = building_id
	state.provinces[id].construction_turns = building.build_turns
	return true


# --- Recruiting (PV-2) ------------------------------------------------------------

static func unit_cost(unit: UnitType) -> Dictionary:
	return {"gold": float(unit.cost_gold), "wood": float(unit.cost_wood), "iron": float(unit.cost_iron),
		"manpower": float(unit.cost_manpower)}


## "" if the faction can recruit the unit here now, else the reason why not.
static func recruit_problem(state: GameState, id: String, unit_id: String, faction_id: String) -> String:
	var unit := Rules.unit(unit_id)
	if state.owners[id] != faction_id:
		return "not your province"
	if blockaded(state, id):
		return "an enemy army is here"
	if unit.required_building != "" and state.provinces[id].level(unit.required_building) == 0:
		return "needs: %s" % Rules.building(unit.required_building).display_name.to_lower()
	if state.provinces[id].recruits.size() >= MAX_RECRUITS_PER_TURN:
		return "%d recruits a turn at most" % MAX_RECRUITS_PER_TURN
	if not state.factions[faction_id].can_afford(unit_cost(unit)):
		return "not enough resources"
	return ""


## Pays for the unit now; it joins the province's garrison at the end of the turn.
static func recruit(state: GameState, id: String, unit_id: String) -> bool:
	var faction_id: String = state.owners[id]
	if recruit_problem(state, id, unit_id, faction_id) != "":
		return false
	state.factions[faction_id].pay(unit_cost(Rules.unit(unit_id)))
	state.provinces[id].recruits.append(unit_id)
	return true


# --- Happiness (PV-3) ---------------------------------------------------------------

static func target_happiness(state: GameState, id: String, starving: bool) -> float:
	var owner: String = state.owners[id]
	var target: float = BASE_HAPPINESS + TAX_HAPPINESS[state.factions[owner].tax] + building_bonus(state, id, "happiness")
	if state.map.provinces[id].capital:
		target += CAPITAL_HAPPINESS
	if _has_own_army(state, id):
		target += GARRISON_HAPPINESS
	if starving:
		target += STARVING_HAPPINESS
	return clampf(target, 0.0, 100.0)


static func _has_own_army(state: GameState, id: String) -> bool:
	for army in state.armies_in(id):
		if army.owner == state.owners[id]:
			return true
	return false


# --- End of turn ----------------------------------------------------------------------

## Runs the economy for every faction at the end of a turn, in the season that
## is ending. Returns events {"type": "economy", "faction", "text", "kind"} for the UI.
static func process_turn(state: GameState) -> Array:
	var events := []
	for faction_id in state.map.playable_factions():
		events.append_array(_process_faction(state, faction_id))
	for id in state.map.province_order:
		var province: ProvinceState = state.provinces[id]
		var full := land_food(state, id) * 2.0
		province.forage = minf(province.forage + land_food(state, id), full)
	for army in state.armies.duplicate():
		state.remove_destroyed_regiments(army)
	return events


static func _process_faction(state: GameState, faction_id: String) -> Array:
	var events := []
	var faction: FactionState = state.factions[faction_id]
	var note := func(kind: String, text: String): events.append(
		{"type": "economy", "faction": faction_id, "kind": kind, "text": text})
	var own_armies := state.armies.filter(func(a: Army): return a.owner == faction_id)

	# Income and upkeep, exactly as the resource bar shows them.
	var change := deltas(state, faction_id)
	for resource in change:
		faction.resources[resource] += change[resource]

	# Armies beyond the supply range live off the land (FD-4).
	for army: Army in own_armies:
		if is_supplied(state, army):
			continue
		var province: ProvinceState = state.provinces[army.province]
		var need := army_food_upkeep(army)
		if province.forage >= need:
			province.forage -= need
		else:
			province.forage = 0.0
			_lose_men(army, FORAGE_LOSS)
			note.call("bad", "%s found nothing left to forage in %s and lost %d%% of its men." % [
				army.display_name(), state.map.provinces[army.province].name, roundi(FORAGE_LOSS * 100)])

	# Starvation (FD-3) and unpaid troops.
	var starving: bool = faction.resources.food < 0.0
	if starving:
		faction.resources.food = 0.0
		for army: Army in own_armies:
			_lose_men(army, STARVATION_LOSS)
		note.call("bad", "Starvation! Every army lost %d%% of its men and the provinces are unhappy." % roundi(STARVATION_LOSS * 100))
	if faction.resources.gold < 0.0:
		faction.resources.gold = 0.0
		for army: Army in own_armies:
			_lose_men(army, DESERTION_LOSS)
		note.call("bad", "No gold to pay the troops: %d%% of every army deserted." % roundi(DESERTION_LOSS * 100))

	# Winter attrition outside your own territory (FD-5).
	if state.season() == "Winter":
		for army: Army in own_armies:
			if state.owners[army.province] == faction_id:
				continue
			var share := WINTER_MOUNTAIN_LOSS if state.map.provinces[army.province].terrain == "mountains" else WINTER_LOSS
			_lose_men(army, share)
			note.call("bad", "%s lost %d%% of its men to the winter in %s." % [
				army.display_name(), roundi(share * 100), state.map.provinces[army.province].name])

	# Storage limits and spoilage (3.12).
	var spoiled: float = faction.resources.food - food_cap(state, faction_id)
	if spoiled > 0.0:
		faction.resources.food -= spoiled
		note.call("info", "%d food spoiled: build granaries to store more." % roundi(spoiled))
	for resource in ["wood", "iron"]:
		faction.resources[resource] = minf(faction.resources[resource], material_cap(state, faction_id))

	# Construction and recruits.
	for id in state.map.province_order:
		if state.owners[id] != faction_id:
			continue
		var province: ProvinceState = state.provinces[id]
		var where: String = state.map.provinces[id].name
		if province.construction != "" and not blockaded(state, id):
			province.construction_turns -= 1
			if province.construction_turns <= 0:
				province.buildings[province.construction] = province.level(province.construction) + 1
				note.call("good", "%s finished in %s." % [Rules.building(province.construction).display_name, where])
				province.construction = ""
		if not province.recruits.is_empty() and not blockaded(state, id):
			for unit_id in province.recruits:
				state.garrison_for(faction_id, id).regiments.append(Regiment.new(unit_id))
			note.call("good", "%d new regiment%s joined the garrison in %s." % [
				province.recruits.size(), "" if province.recruits.size() == 1 else "s", where])
			province.recruits.clear()

	# Happiness and revolts (PV-3).
	for id in state.map.province_order:
		if state.owners[id] != faction_id:
			continue
		var province: ProvinceState = state.provinces[id]
		province.happiness = move_toward(province.happiness, target_happiness(state, id, starving), HAPPINESS_STEP)
		if province.happiness < REVOLT_BELOW and not _has_own_army(state, id) and state.rng.randf() < REVOLT_CHANCE:
			var militia := []
			for i in 2 + floori(state.map.provinces[id].population / 8000.0):
				militia.append("militia")
			state.add_army("rebels", id, null, militia)
			province.happiness = AFTER_REVOLT_HAPPINESS
			note.call("bad", "Revolt in %s! Rebel militia have risen against you." % state.map.provinces[id].name)
	return events


static func _lose_men(army: Army, share: float) -> void:
	for regiment in army.regiments:
		regiment.men *= 1.0 - share
