class_name AI
extends RefCounted
## Plays a whole turn for a computer faction (PRD V2) using the same orders as
## a person: recruit units that counter the enemies it can see, build when
## poor, pull damaged units back, attack where the forecast is good enough for
## its personality, besiege walls, defend threatened regions, and advance.

const FORECAST_RUNS := 8  # Fewer than the player's forecast, to keep AI turns fast.
const RETREAT_BELOW := 0.35  # Units weaker than this pull back from the front.
## Forecast ratings each personality is willing to attack on.
const ACCEPT := {
	"aggressive": ["Decisive win", "Win", "Close"],
	"balanced": ["Decisive win", "Win"],
	"defensive": ["Decisive win"],
}
const GOLD_RESERVE := {"aggressive": 40.0, "balanced": 80.0, "defensive": 120.0}


static func play_turn(state: GameState) -> Array:
	var faction := state.current_faction()
	var events := []
	_manage_economy(state, faction)
	_retreat_damaged(state, faction)
	events.append_array(_attack(state, faction))
	_besiege(state, faction)
	events.append_array(_capture_empty(state, faction))
	_reinforce(state, faction)
	events.append_array(_advance(state, faction))
	return events


# --- Economy -------------------------------------------------------------------------

static func _manage_economy(state: GameState, faction: String) -> void:
	var me: FactionState = state.factions[faction]
	var change := Economy.deltas(state, faction)
	var unhappy := 0
	for region in _own_regions(state, faction):
		if state.provinces[region].happiness < Economy.REVOLT_BELOW + 10.0:
			unhappy += 1
	me.tax = "low" if unhappy > 0 else ("high" if me.ai == "aggressive" and change.gold < 0.0 else "normal")
	Research.choose_for_ai(state, faction)

	# Build: food first if it's running out, then recruiting buildings, then gold.
	var capital: String = state.capitals.get(faction, "")
	var wishes := []
	if change.food < 0.0:
		wishes.append("farm")
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

	# Recruit units that counter the enemies near each region.
	for region in _own_regions(state, faction):
		var nearby := _enemies_near(state, faction, region, 2)
		if nearby.is_empty() and _frontier_distance(state, faction, region) > 2:
			continue
		while me.resources.gold > GOLD_RESERVE[me.ai]:
			var choice := _best_recruit(state, faction, region, nearby)
			if choice == "" or not Economy.recruit(state, region, choice):
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

## Units that are badly hurt step back to a friendly region away from the front.
static func _retreat_damaged(state: GameState, faction: String) -> void:
	for unit in state.units_of(faction):
		if unit.strength() >= RETREAT_BELOW or _threat(state, faction, unit.province) == 0.0:
			continue
		var safest := ""
		var lowest := _threat(state, faction, unit.province)
		for neighbour in state.map.neighbours(unit.province):
			if state.owners[neighbour] == faction and state.move_problem(unit, neighbour) == "":
				var threat := _threat(state, faction, neighbour)
				if threat < lowest:
					lowest = threat
					safest = neighbour
		if safest != "":
			state.move_unit(unit, safest)


## Attacks, best first, while the forecast is good enough.
static func _attack(state: GameState, faction: String) -> Array:
	var events := []
	var accept: Array = ACCEPT.get(state.factions[faction].ai, ACCEPT.balanced)
	for attempt in 12:
		var best := {}
		var best_value := 0.0
		for region in _regions_with_units(state, faction):
			var stack := state.units_in(region).filter(func(u: Unit): return u.owner == faction)
			for target in _targets_near(state, faction, region):
				var attackers := state.attackers_for(stack, target)
				if attackers.is_empty():
					continue
				var forecast := state.forecast_attack(attackers, target, FORECAST_RUNS)
				if not (forecast.rating in accept):
					continue
				var value: float = (1.0 - forecast.defender_survival) - (1.0 - forecast.attacker_survival) * 0.7
				if not forecast.ranged:
					value += 1.0 + (0.5 if state.is_capital(target) else 0.0)
				if value > best_value:
					best_value = value
					best = {"units": attackers, "region": target}
		if best.is_empty():
			break
		var result := state.attack(best.units, best.region)
		if result.is_empty():
			break
		events.append_array(result.events)
		if not state.result.is_empty():
			break
	return events


## Starts sieges on walled enemy regions it wouldn't assault.
static func _besiege(state: GameState, faction: String) -> void:
	if state.factions[faction].ai == "defensive":
		return
	for region in _regions_with_units(state, faction):
		var stack := state.units_in(region).filter(func(u: Unit): return u.owner == faction)
		for target in state.map.neighbours(region):
			if state.is_enemy(faction, state.owners[target]) and Sieges.besiege_problem(state, stack, target) == "":
				Sieges.besiege(state, stack, target)


## Walks into empty enemy and neutral regions next to its units.
static func _capture_empty(state: GameState, faction: String) -> Array:
	var events := []
	for unit in _fastest_first(state.units_of(faction)):
		for neighbour in state.map.neighbours(unit.province):
			if state.owners[neighbour] != faction and state.enemy_units_in(neighbour, faction).is_empty() \
					and state.move_problem(unit, neighbour) == "" and not _leaves_exposed(state, faction, unit):
				events.append_array(state.move_unit(unit, neighbour))
				break
	return events


## Moves idle units into neighbouring regions that are more threatened.
static func _reinforce(state: GameState, faction: String) -> void:
	for unit in state.units_of(faction):
		if unit.moved or unit.attacked or _leaves_exposed(state, faction, unit):
			continue
		var here := _threat(state, faction, unit.province)
		for neighbour in state.map.neighbours(unit.province):
			if state.owners[neighbour] == faction and _threat(state, faction, neighbour) > here + 1.0 \
					and state.move_problem(unit, neighbour) == "":
				state.move_unit(unit, neighbour)
				break


## Idle units behind the front step towards the nearest enemy region.
static func _advance(state: GameState, faction: String) -> Array:
	var events := []
	if state.factions[faction].ai == "defensive" and state.turn < 6:
		return events
	var targets := []
	for region in state.map.province_order:
		if state.is_enemy(faction, state.owners[region]) and state.owners[region] != "rebels":
			targets.append(region)
	if targets.is_empty():
		return events
	for unit in state.units_of(faction):
		if unit.moved or unit.attacked or unit.move_points_left < 1 or _leaves_exposed(state, faction, unit):
			continue
		var distances := state.map.distances_from(unit.province)
		var here := _nearest(targets, distances)
		var best := ""
		var best_distance := here
		for neighbour in state.map.neighbours(unit.province):
			if state.move_problem(unit, neighbour) != "":
				continue
			var there := _nearest(targets, state.map.distances_from(neighbour))
			if there < best_distance:
				best_distance = there
				best = neighbour
		if best != "":
			events.append_array(state.move_unit(unit, best))
	return events


# --- Helpers -------------------------------------------------------------------------

static func _own_regions(state: GameState, faction: String) -> Array:
	return state.map.province_order.filter(func(r): return state.owners[r] == faction)


static func _regions_with_units(state: GameState, faction: String) -> Array:
	var regions := {}
	for unit in state.units_of(faction):
		regions[unit.province] = true
	return regions.keys()


## Enemy regions within reach of a region's units (2 for longbows).
static func _targets_near(state: GameState, faction: String, region: String) -> Array:
	var distances := state.map.distances_from(region)
	var targets := []
	for other in distances:
		if distances[other] >= 1 and distances[other] <= 2 and not state.enemy_units_in(other, faction).is_empty():
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
		enemy += _power(unit)
	var own := 0.0
	for unit in state.units_in(region):
		if unit.owner == faction:
			own += _power(unit)
	return maxf(enemy - own, 0.0) if enemy > 0.0 else 0.0


static func _power(unit: Unit) -> float:
	var unit_type := unit.type()
	return unit.strength() * (unit_type.attack + unit_type.defense) * unit_type.hp / 100.0


## True if moving this unit would leave its region empty next to enemies.
static func _leaves_exposed(state: GameState, faction: String, unit: Unit) -> bool:
	var others := state.units_in(unit.province).filter(func(u: Unit): return u.owner == faction and u != unit)
	return others.is_empty() and state.owners[unit.province] == faction and not _enemies_near(state, faction, unit.province, 1).is_empty()


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


static func _fastest_first(units: Array[Unit]) -> Array[Unit]:
	var sorted := units.duplicate()
	sorted.sort_custom(func(a: Unit, b: Unit): return a.move_points_left > b.move_points_left)
	return sorted
