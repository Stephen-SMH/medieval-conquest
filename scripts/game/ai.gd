class_name AI
extends RefCounted
## Plans a computer faction's orders (PRD V2) with the same Orders a person
## uses: recruit units that counter the enemies it can see, build when poor,
## pull damaged units back, attack where the forecast is good enough for its
## personality, besiege walls, capture empty regions and advance. The orders
## are carried out with everyone else's when the turn resolves.

const FORECAST_RUNS := 8  # Fewer than the player's forecast, to keep AI turns fast.
const RETREAT_BELOW := 0.35  # Units weaker than this pull back from the front.
## Forecast ratings each personality is willing to attack on.
const ACCEPT := {
	"aggressive": ["Decisive win", "Win", "Close"],
	"balanced": ["Decisive win", "Win"],
	"defensive": ["Decisive win"],
}
const GOLD_RESERVE := {"aggressive": 40.0, "balanced": 80.0, "defensive": 120.0}


## Plans the current faction's orders. Returns [] (nothing happens until the turn resolves).
static func play_turn(state: GameState) -> Array:
	var faction := state.current_faction()
	_manage_economy(state, faction)
	var claimed := {}  # Regions some unit already plans to move into.
	for unit in _strongest_first(state.units_of(faction)):
		if _retreat(state, unit, claimed):
			continue
		if _attack(state, unit):
			continue
		if _besiege(state, unit):
			continue
		if _capture(state, unit, claimed):
			continue
		_advance(state, unit, claimed)
	return []


# --- Economy -------------------------------------------------------------------------

static func _manage_economy(state: GameState, faction: String) -> void:
	var me: FactionState = state.factions[faction]
	var change := Economy.deltas(state, faction)
	Research.choose_for_ai(state, faction)

	var capital: String = state.capitals.get(faction, "")
	var wishes := []
	if change.gold < 10.0:
		wishes.append("market")
	wishes.append_array(["barracks", "archery_range", "stable"])
	if me.ai == "defensive" or _threat(state, faction, capital) > 0.0:
		wishes.append("walls")
	for building in wishes:
		for region in ([capital] if capital != "" and state.owners.get(capital) == faction else []) + _own_regions(state, faction):
			if Economy.build_problem(state, region, building, faction) == "" \
					and me.resources.gold - Economy.building_cost(Rules.building(building), state.provinces[region].level(building) + 1).gold > GOLD_RESERVE[me.ai]:
				Economy.start_building(state, region, building)
				break

	# Recruit (or hire mercenaries) where there is room and enemies near.
	for region in _own_regions(state, faction):
		if me.resources.gold <= GOLD_RESERVE[me.ai]:
			break
		var nearby := _enemies_near(state, faction, region, 2)
		if nearby.is_empty() and _frontier_distance(state, faction, region) > 2:
			continue
		var choice := _best_recruit(state, faction, region, nearby)
		if choice != "":
			Economy.recruit(state, region, choice)
		elif Economy.site(state, region) != "":
			for unit_id in state.provinces[region].mercenaries:
				if Economy.hire_problem(state, region, unit_id, faction) == "":
					Economy.hire(state, region, unit_id)
					break


## The unit type that does best against `enemies`, for its gold.
static func _best_recruit(state: GameState, faction: String, region: String, enemies: Array) -> String:
	var best := ""
	var best_score := -1.0
	for unit_id in Economy.roster(state, faction):
		if Economy.recruit_problem(state, region, unit_id, faction) != "":
			continue
		var unit_type := Rules.unit(unit_id)
		var score := 1.0
		if not enemies.is_empty():
			score = 0.0
			for enemy: Unit in enemies:
				score += Rules.counters.multiplier(unit_id, enemy.type_id) / maxf(Rules.counters.multiplier(enemy.type_id, unit_id), 0.25)
			score /= enemies.size()
		score *= (unit_type.attack + unit_type.defense) * unit_type.hp / 100.0 / sqrt(maxf(unit_type.cost_gold, 1.0))
		if score > best_score:
			best_score = score
			best = unit_id
	return best


# --- Orders ----------------------------------------------------------------------------

## A badly hurt unit at the front steps back into a safer free region of its own.
static func _retreat(state: GameState, unit: Unit, claimed: Dictionary) -> bool:
	if unit.strength() >= RETREAT_BELOW or _threat(state, unit.owner, unit.province) == 0.0:
		return false
	var safest := ""
	var lowest := _threat(state, unit.owner, unit.province)
	for neighbour in state.map.neighbours(unit.province):
		if state.owners[neighbour] == unit.owner and not claimed.has(neighbour) and Orders.problem(state, unit, "move", neighbour) == "":
			var threat := _threat(state, unit.owner, neighbour)
			if threat < lowest:
				lowest = threat
				safest = neighbour
	if safest == "":
		return false
	claimed[safest] = true
	return Orders.give(state, unit, "move", safest) == ""


## Attacks the best target its forecast approves of.
static func _attack(state: GameState, unit: Unit) -> bool:
	var accept: Array = ACCEPT.get(state.factions[unit.owner].ai, ACCEPT.balanced)
	var best := ""
	var best_value := 0.0
	for target in _targets_near(state, unit):
		if Orders.problem(state, unit, "attack", target) != "":
			continue
		var forecast := state.forecast_attack([unit], target, FORECAST_RUNS)
		if forecast.is_empty() or not (forecast.rating in accept):
			continue
		var value: float = (1.0 - forecast.defender_survival) - (1.0 - forecast.attacker_survival) * 0.7
		if not forecast.ranged:
			value += 1.0 + (0.5 if state.is_capital(target) else 0.0)
		if value > best_value:
			best_value = value
			best = target
	return best != "" and Orders.give(state, unit, "attack", best) == ""


static func _besiege(state: GameState, unit: Unit) -> bool:
	if state.factions[unit.owner].ai == "defensive":
		return false
	for target in state.map.neighbours(unit.province):
		if state.is_enemy(unit.owner, state.owners[target]) and Orders.problem(state, unit, "besiege", target) == "":
			return Orders.give(state, unit, "besiege", target) == ""
	return false


## Walks into an empty enemy or neutral region next to it.
static func _capture(state: GameState, unit: Unit, claimed: Dictionary) -> bool:
	if _leaves_exposed(state, unit):
		return false
	for neighbour in state.map.neighbours(unit.province):
		if state.owners[neighbour] != unit.owner and state.unit_in(neighbour) == null and not claimed.has(neighbour) \
				and Orders.problem(state, unit, "move", neighbour) == "":
			claimed[neighbour] = true
			return Orders.give(state, unit, "move", neighbour) == ""
	return false


## Units behind the front step towards the nearest enemy region.
static func _advance(state: GameState, unit: Unit, claimed: Dictionary) -> void:
	if (state.factions[unit.owner].ai == "defensive" and state.turn < 6) or _leaves_exposed(state, unit):
		return
	var targets := state.map.province_order.filter(func(r): return state.is_enemy(unit.owner, state.owners[r]) and state.owners[r] != "rebels")
	if targets.is_empty():
		return
	var here := _nearest(targets, state.map.distances_from(unit.province))
	var best := ""
	for neighbour in state.map.neighbours(unit.province):
		if claimed.has(neighbour) or state.unit_in(neighbour) != null or Orders.problem(state, unit, "move", neighbour) != "":
			continue
		var there := _nearest(targets, state.map.distances_from(neighbour))
		if there < here:
			here = there
			best = neighbour
	if best != "":
		claimed[best] = true
		Orders.give(state, unit, "move", best)


# --- Helpers -------------------------------------------------------------------------

static func _own_regions(state: GameState, faction: String) -> Array:
	return state.map.province_order.filter(func(r): return state.owners[r] == faction)


## Enemy-held regions within reach of a unit (2 for longbows).
static func _targets_near(state: GameState, unit: Unit) -> Array:
	var distances := state.map.distances_from(unit.province)
	var targets := []
	for other in distances:
		if distances[other] >= 1 and distances[other] <= 2 and not state.enemy_units_in(other, unit.owner).is_empty():
			targets.append(other)
	return targets


static func _enemies_near(state: GameState, faction: String, region: String, steps: int) -> Array:
	var distances := state.map.distances_from(region)
	var found := []
	for unit in state.units:
		if state.is_enemy(faction, unit.owner) and distances.get(unit.province, 99) <= steps:
			found.append(unit)
	return found


## Enemy strength next to a region minus our own strength in it.
static func _threat(state: GameState, faction: String, region: String) -> float:
	if region == "":
		return 0.0
	var enemy := 0.0
	for unit in _enemies_near(state, faction, region, 1):
		enemy += unit.power()
	var own := 0.0
	for unit in state.units_in(region):
		if unit.owner == faction:
			own += unit.power()
	return maxf(enemy - own, 0.0) if enemy > 0.0 else 0.0


## True if moving this unit would leave its own region empty next to enemies.
static func _leaves_exposed(state: GameState, unit: Unit) -> bool:
	return state.owners[unit.province] == unit.owner and not _enemies_near(state, unit.owner, unit.province, 1).is_empty() \
		and state.is_capital(unit.province)


static func _frontier_distance(state: GameState, faction: String, region: String) -> int:
	var distances := state.map.distances_from(region)
	var nearest := 99
	for other in distances:
		if state.is_enemy(faction, state.owners[other]):
			nearest = mini(nearest, distances[other])
	return nearest


static func _nearest(targets: Array, distances: Dictionary) -> int:
	var nearest := 1 << 30
	for target in targets:
		nearest = mini(nearest, distances.get(target, 1 << 30))
	return nearest


static func _strongest_first(units: Array[Unit]) -> Array[Unit]:
	var sorted := units.duplicate()
	sorted.sort_custom(func(a: Unit, b: Unit): return a.power() > b.power() or (a.power() == b.power() and a.id < b.id))
	return sorted
