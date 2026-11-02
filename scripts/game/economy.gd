class_name Economy
extends RefCounted
## The gold economy (PRD 8.9, E): every region earns gold each turn (10, more
## for towns, capitals and markets; a real map sets 5, 10 or 15 itself), and
## gold pays for reinforcement bundles, buildings and upkeep.
## If gold would run out, units desert. Income is worked out by breakdown(),
## which the treasury shows and the end of the turn applies.

const REGION_INCOME := 10.0
const TOWN_INCOME := 5.0
const CAPITAL_INCOME := 10.0
const DESERTION_LOSS := 0.05         # Units lose soldiers when there's no gold to pay them.

## UT-7: an army resting in its own region regains this share of its lost
## health each turn (Barracks: all of it). Healing restores health, not
## soldiers: new soldiers come from reinforcements.
const HEAL_SHARE := 0.5
const HEAL_SHARE_BARRACKS := 1.0

const SLOTS := 4                     # PV-1
const CAPITAL_SLOTS := 6

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


## A region's own worth before markets: the map's "income"
## (5, 10 or 15 on the real maps), else 10, +5 for a town, +10 for a capital.
static func base_income(state: GameState, region: String) -> float:
	var data: Dictionary = state.map.provinces[region]
	if data.has("income"):
		return float(data.income)
	var income := REGION_INCOME
	if site(state, region) == "town":
		income += TOWN_INCOME
	if state.is_capital(region):
		income += CAPITAL_INCOME
	return income


## The gold a region pays its owner each turn: the number on the map.
static func region_income(state: GameState, region: String) -> float:
	var owner: String = state.owners[region]
	var income := base_income(state, region)
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
	var total := 0.0
	for troop in unit.troops:
		total += troop.type().upkeep_gold * troop.soldiers / float(UnitType.SOLDIERS)
	return total


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


# --- Reinforcements (PRD E) ---------------------------------------------------------

## Reinforcements come in fixed bundles bought for gold: so many soldiers of a
## type for a price, worked out from the type's cost. Each type has a small
## and a large bundle; the large one is cheaper per soldier. A bundle is sent
## to one of your provinces with a town or camp (or your capital), one bundle
## per province per turn, and arrives at the start of your next turn, joining
## the army there (up to Unit.CAP soldiers).
const SOLDIER_PRICE := 0.1  # Gold per soldier, as a share of the type's cost (a 20-soldier unit's price).
const SMALL_BUNDLE_GOLD := 40.0  # About what a small bundle costs.
const LARGE_BUNDLE_SCALE := 3  # A large bundle has this many times the soldiers...
const LARGE_BUNDLE_DISCOUNT := 0.9  # ...at this share of the price.
const MAX_BUNDLE := 10  # So a large bundle fits an army of half Unit.CAP (20).


## Gold for one soldier of a type, for a faction (civilization bonuses included).
static func soldier_price(state: GameState, faction_id: String, unit_type: UnitType) -> float:
	return unit_type.cost_gold * SOLDIER_PRICE * Bonuses.recruit_cost(state, faction_id, unit_type)


## The old whole-unit price, still used for scoring: {"gold": price of 20 soldiers}.
static func unit_cost(state: GameState, faction_id: String, unit_type: UnitType) -> Dictionary:
	return {"gold": roundf(unit_type.cost_gold * Bonuses.recruit_cost(state, faction_id, unit_type))}


## Soldier types a faction may ever recruit: the base roster plus its civilization's own.
static func roster(state: GameState, faction_id: String) -> Array[String]:
	var civ: String = state.factions[faction_id].civ
	var ids: Array[String] = []
	for unit_id in Rules.units:
		var unit_type := Rules.unit(unit_id)
		if unit_type.civilization == "" or unit_type.civilization == civ:
			ids.append(unit_id)
	return ids


## The bundles a faction can buy, in display order: [{"type", "soldiers", "price"}, ...].
static func bundles(state: GameState, faction_id: String) -> Array:
	var list := []
	for unit_id in roster(state, faction_id):
		var per := soldier_price(state, faction_id, Rules.unit(unit_id))
		var small := clampi(roundi(SMALL_BUNDLE_GOLD / per), 1, 6)
		var large := mini(small * LARGE_BUNDLE_SCALE, MAX_BUNDLE)
		list.append({"type": unit_id, "soldiers": small, "price": _round_price(per * small)})
		if large > small:
			list.append({"type": unit_id, "soldiers": large, "price": _round_price(per * large * LARGE_BUNDLE_DISCOUNT)})
	return list


static func _round_price(gold: float) -> int:
	return maxi(5, roundi(gold / 5.0) * 5)


## Whether a province can take reinforcements: yours, with a town or camp, or your capital.
static func recruit_point(state: GameState, region: String, faction_id: String) -> bool:
	return state.owners.get(region) == faction_id and (site(state, region) != "" or state.capitals.get(faction_id) == region)


## "" if the faction can send this bundle to the province now, else why not.
static func bundle_problem(state: GameState, region: String, bundle: Dictionary, faction_id: String) -> String:
	if not recruit_point(state, region, faction_id):
		return "reinforcements go to your provinces with a town or camp"
	if not state.provinces[region].recruits.is_empty():
		return "this province already has reinforcements coming this turn"
	if blockaded(state, region):
		return "enemy units are here"
	var army := state.unit_in(region)
	if army != null and army.soldiers() + int(bundle.soldiers) > Unit.CAP:
		return "no room: the army here would pass %d soldiers" % Unit.CAP
	if state.factions[faction_id].resources.gold < float(bundle.price):
		return "not enough gold"
	return ""


## The provinces this bundle could go to now.
static func bundle_targets(state: GameState, bundle: Dictionary, faction_id: String) -> Array[String]:
	var found: Array[String] = []
	for region in state.map.province_order:
		if bundle_problem(state, region, bundle, faction_id) == "":
			found.append(region)
	return found


## Pays for the bundle; it arrives in the province at the start of the next turn.
static func buy(state: GameState, region: String, bundle: Dictionary) -> bool:
	var faction_id: String = state.owners.get(region, "")
	if not state.factions.has(faction_id) or bundle_problem(state, region, bundle, faction_id) != "":
		return false
	state.factions[faction_id].resources.gold -= float(bundle.price)
	state.provinces[region].recruits.append({"type": bundle.type, "soldiers": int(bundle.soldiers), "price": int(bundle.price)})
	return true


## A province of yours with a town, camp or capital that can't take any
## reinforcements now (some are already coming, enemies are there, or its
## army is full): the map shows a red no-sign over its icon.
static func recruit_closed(state: GameState, region: String, faction_id: String) -> bool:
	if not recruit_point(state, region, faction_id):
		return false
	var army := state.unit_in(region)
	return not state.provinces[region].recruits.is_empty() or blockaded(state, region) or (army != null and army.soldiers() >= Unit.CAP)


## The cheapest bundle of a type (for tests and simple callers).
static func bundle_of(state: GameState, faction_id: String, unit_id: String, large := false) -> Dictionary:
	var found := bundles(state, faction_id).filter(func(b): return b.type == unit_id)
	if found.is_empty():
		return {}
	return found.back() if large else found[0]


# --- Healing (UT-7) ---------------------------------------------------------------

## The share of its lost health an army would regain at the end of this turn.
static func heal_share(state: GameState, unit: Unit) -> float:
	if state.owners.get(unit.province) != unit.owner:
		return 0.0
	if (unit.moved or unit.attacked) and not Bonuses.heals_on_the_move(state, unit.owner):
		return 0.0
	return HEAL_SHARE_BARRACKS if state.provinces[unit.province].level("barracks") > 0 else HEAL_SHARE


# --- Arrivals --------------------------------------------------------------------

## Reinforcements ordered last turn arrive at the start of the owner's turn,
## joining the army there (up to Unit.CAP; the gold for any soldiers who
## don't fit is paid back). While enemies hold the province they wait.
static func arrivals(state: GameState, faction_id: String) -> Array:
	var events := []
	for region in state.map.province_order:
		var province: ProvinceState = state.provinces[region]
		if state.owners[region] != faction_id or province.recruits.is_empty():
			continue
		var army := state.unit_in(region)
		if army != null and army.owner != faction_id:
			continue
		var where := state.map.region_name(region)
		for bundle in province.recruits:
			if army == null:
				army = state.add_unit("", faction_id, region)
			var soldiers := int(bundle.soldiers)
			var count := mini(soldiers, Unit.CAP - army.soldiers())
			if count < soldiers:
				var refund := roundf(float(bundle.get("price", 0)) * (soldiers - count) / soldiers)
				state.factions[faction_id].resources.gold += refund
				events.append({"type": "economy", "faction": faction_id, "kind": "bad",
					"text": "%d reinforcements had no room in %s's army: %d gold paid back." % [soldiers - count, where, roundi(refund)]})
			if count <= 0:
				continue
			army.add(bundle.type, count)
			army.reset_turn()
			events.append({"type": "arrived", "faction": faction_id, "province": region, "unit": army, "bundle": bundle,
				"text": "Reinforcements arrived in %s: %s – %d." % [where, Rules.unit(bundle.type).display_name, count]})
		province.recruits.clear()
		if army != null and army.soldiers() == 0:
			state.remove_unit(army)
	return events


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
			for troop in unit.troops:
				var before := troop.soldiers
				troop.lose_share(DESERTION_LOSS)
				state.note_loss(faction_id, troop.type_id, before - troop.soldiers)
		note.call("bad", "No gold to pay the troops: %d%% of every unit deserted." % roundi(DESERTION_LOSS * 100))

	# Armies that rested in their own regions heal (UT-7).
	for unit in own_units:
		var share := heal_share(state, unit)
		if share > 0.0:
			for troop in unit.troops:
				troop.heal(share)

	# Construction.
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
	return events
