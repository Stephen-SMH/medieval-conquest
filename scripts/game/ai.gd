class_name AI
extends RefCounted
## Plans a computer faction's turn (PRD V2, C) with the same Orders a person
## uses. Like a player in S&T it plays in waves: first the attacks, which it
## carries out with the "!" (plan_attacks); then, knowing how they went, more
## attacks by the armies still fresh, carried out too; then the marches
## (plan_moves), which the hourglass carries out. It recruits soldiers that counter the enemies it can see,
## builds when poor, pulls weak armies back, attacks where the forecast is
## good enough for its personality, besieges walls, guards its threatened
## regions, captures empty regions and masses its armies at the front.
##
## How well it plays depends on the game's difficulty (GameState.difficulty):
##   easy:   plans everything at once before anything happens, attacks with one
##           army at a time (others may join as supports), sometimes hesitates,
##           and earns 15% less gold;
##   normal: gathers several armies against one target (one attacks, the rest
##           support), plays in waves, guards its capital and threatened
##           regions, doesn't leave a region next to an enemy army empty, and
##           merges its armies at the front;
##   hard:   the same, and also starts with a quarter more soldiers in each
##           army (up to Unit.CAP), takes a close fight when several armies
##           join, forecasts more carefully, earns 40% more gold, keeps less
##           of it back and buys reinforcements further from the front.

const DIFFICULTIES := ["easy", "normal", "hard"]
const SKILL := {
	"easy": {"waves": false, "gather": false, "hesitate": 0.3, "runs": 6, "bolder": false, "reserve": 1.4, "income": 0.85, "muster": 2, "start": 1.0},
	"normal": {"waves": true, "gather": true, "hesitate": 0.0, "runs": 8, "bolder": false, "reserve": 1.0, "income": 1.0, "muster": 2, "start": 1.0},
	"hard": {"waves": true, "gather": true, "hesitate": 0.0, "runs": 12, "bolder": true, "reserve": 0.4, "income": 1.4, "muster": 4, "start": 1.25},
}
const RETREAT_BELOW := 0.35  # Armies with less health than this pull back from the front...
const RETREAT_SOLDIERS := 4  # ...as do armies this small.
## Forecast ratings each personality is willing to attack on.
const ACCEPT := {
	"aggressive": ["Decisive win", "Win", "Close"],
	"balanced": ["Decisive win", "Win"],
	"defensive": ["Decisive win"],
}
const GOLD_RESERVE := {"aggressive": 40.0, "balanced": 80.0, "defensive": 120.0}
## A unit splits off a garrison only when it has this many soldiers or more.
const GARRISON_FROM := 14
## The most armies gathered against one target.
const MOST_GATHERED := 4


static func skill(state: GameState) -> Dictionary:
	return SKILL.get(state.difficulty, SKILL.normal)


## The difficulty's gold multiplier for a computer faction (Bonuses.income).
static func income_multiplier(state: GameState, faction: String) -> float:
	if not state.factions.has(faction) or state.factions[faction].human:
		return 1.0
	return float(skill(state).income)


## Hard: the computer's armies start the game a quarter stronger (Unit.CAP at most).
static func strengthen_start(state: GameState, faction: String) -> void:
	var share: float = float(skill(state).start) - 1.0
	if share <= 0.0:
		return
	for unit in state.units_of(faction):
		var extra := Orders.pick(unit.composition(), mini(roundi(unit.soldiers() * share), Unit.CAP - unit.soldiers()))
		for type_id in extra:
			unit.add(type_id, int(extra[type_id]))


## How many waves of attacks the computer plans and carries out before its
## marches: 1 on easy (and then nothing happens until the hourglass), 2 else.
static func attack_waves(state: GameState) -> int:
	return 2 if skill(state).waves else 1


static func plays_in_waves(state: GameState) -> bool:
	return skill(state).waves


## Plays the current faction's turn up to the hourglass: the waves of
## attacks, each carried out (on normal and hard), then the marches, which
## resolve when the turn ends. Returns the events of the attacks carried out.
static func play_turn(state: GameState) -> Array:
	var events := []
	for wave in attack_waves(state):
		plan_attacks(state, wave)
		if not plays_in_waves(state) or not state.has_orders():
			break
		events.append_array(state.carry_out_orders())
		if state.is_over():
			return events
	plan_moves(state)
	return events


## A wave of attacks. The first also buys and builds and pulls weak armies
## back; a later one is made by the armies still fresh, after the first was
## carried out. Sieges come last.
static func plan_attacks(state: GameState, wave := 0) -> void:
	var faction := state.current_faction()
	if state.factions[faction].ai == "passive" or state.is_over():
		return  # The tutorial's raiders stand and wait.
	var used := {}  # Armies given orders, or that have already fought.
	var claimed := _claimed(state, faction)
	for unit in state.units_of(faction):
		if unit.tired() > 0:
			used[unit] = true
	if wave == 0:
		_manage_economy(state, faction)
		for unit in _strongest_first(state.units_of(faction)):
			if _retreat(state, unit, claimed):
				used[unit] = true
	if skill(state).gather:
		_gathered_attacks(state, faction, used)
	else:
		var doubts := RandomNumberGenerator.new()
		doubts.seed = hash([state.rng.seed, state.turn, faction])
		for unit in _strongest_first(state.units_of(faction)):
			if used.has(unit) or doubts.randf() < float(skill(state).hesitate):
				continue
			if _attack(state, unit):
				_garrison(state, unit, claimed)
				used[unit] = true
		for unit in _strongest_first(state.units_of(faction)):
			if not used.has(unit) and _support(state, unit):
				used[unit] = true
	for unit in _strongest_first(state.units_of(faction)):
		if not used.has(unit) and not state.orders.has(unit):
			_besiege(state, unit)


## The second wave, with the soldiers still fresh: guarding threatened
## regions, capturing empty ones and marching to the front.
static func plan_moves(state: GameState) -> void:
	var faction := state.current_faction()
	if state.factions[faction].ai == "passive" or state.is_over():
		return
	var claimed := _claimed(state, faction)
	var used := {}
	var free: Array[Unit] = []
	for unit in _strongest_first(state.units_of(faction)):
		if not state.orders.has(unit) and Orders.unassigned(state, unit) > 0:
			free.append(unit)
	if skill(state).gather:
		_defend(state, faction, free, used, claimed)
	for unit in free:
		if used.has(unit):
			continue
		if _capture(state, unit, claimed):
			continue
		_advance(state, unit, claimed)


# --- Economy -------------------------------------------------------------------------

static func _manage_economy(state: GameState, faction: String) -> void:
	var me: FactionState = state.factions[faction]
	var change := Economy.deltas(state, faction)
	var reserve: float = GOLD_RESERVE.get(me.ai, GOLD_RESERVE.balanced) * float(skill(state).reserve)

	var capital: String = state.capitals.get(faction, "")
	var wishes := []
	if change.gold < 10.0:
		wishes.append("market")
	wishes.append("barracks")
	if me.ai == "defensive" or _threat(state, faction, capital) > 0.0:
		wishes.append("walls")
	for building in wishes:
		for region in ([capital] if capital != "" and state.owners.get(capital) == faction else []) + _own_regions(state, faction):
			if Economy.build_problem(state, region, building, faction) == "" \
					and me.resources.gold - Economy.building_cost(Rules.building(building), state.provinces[region].level(building) + 1).gold > reserve:
				Economy.start_building(state, region, building)
				break

	# Buy reinforcement bundles for the towns, camps and capital near the front,
	# the most threatened first.
	var points := _own_regions(state, faction).filter(func(r): return Economy.recruit_point(state, r, faction))
	points.sort_custom(func(a, b): return _threat(state, faction, a) > _threat(state, faction, b))
	for region in points:
		if me.resources.gold <= reserve:
			break
		var nearby := _enemies_near(state, faction, region, 2)
		if nearby.is_empty() and _frontier_distance(state, faction, region) > int(skill(state).muster):
			continue
		var bundle := _best_bundle(state, faction, region, nearby, me.resources.gold - reserve)
		if not bundle.is_empty():
			Economy.buy(state, region, bundle)


## The bundle whose soldier type does best against `enemies`, for its gold,
## within `budget`: the large bundle when it can, else the small one.
static func _best_bundle(state: GameState, faction: String, region: String, enemies: Array, budget: float) -> Dictionary:
	var choice := _best_recruit(state, faction, region, enemies, budget)
	if choice == "":
		return {}
	for large in [true, false]:
		var bundle := Economy.bundle_of(state, faction, choice, large)
		if not bundle.is_empty() and float(bundle.price) <= budget and Economy.bundle_problem(state, region, bundle, faction) == "":
			return bundle
	return {}


## The soldier type that does best against `enemies`, for its gold.
static func _best_recruit(state: GameState, faction: String, region: String, enemies: Array, budget := INF) -> String:
	var best := ""
	var best_score := -1.0
	for unit_id in Economy.roster(state, faction):
		var small := Economy.bundle_of(state, faction, unit_id)
		if small.is_empty() or float(small.price) > budget or Economy.bundle_problem(state, region, small, faction) != "":
			continue
		var unit_type := Rules.unit(unit_id)
		var score := 1.0
		if not enemies.is_empty():
			score = 0.0
			var weight := 0
			for enemy: Unit in enemies:
				for troop in enemy.troops:
					score += troop.soldiers * Rules.counters.multiplier(unit_id, troop.type_id) / maxf(Rules.counters.multiplier(troop.type_id, unit_id), 0.25)
					weight += troop.soldiers
			score /= maxi(weight, 1)
		score *= (unit_type.attack + unit_type.defense) * unit_type.hp / 100.0 / sqrt(maxf(unit_type.cost_gold, 1.0))
		if score > best_score:
			best_score = score
			best = unit_id
	return best


# --- Attacks ---------------------------------------------------------------------------

## Normal and hard: for every enemy army in reach, the fewest armies that
## together win against it; then the best of these attacks, one after another,
## each army in one at most. One army attacks and moves in, the others support.
static func _gathered_attacks(state: GameState, faction: String, used: Dictionary) -> void:
	var plans := []
	for target in _enemy_targets(state, faction):
		var plan := _best_group(state, faction, target, used)
		if not plan.is_empty():
			plans.append(plan)
	while not plans.is_empty():
		plans.sort_custom(func(a, b): return a.score > b.score)
		var plan: Dictionary = plans.pop_front()
		if plan.group.any(func(u): return used.has(u)):
			var again := _best_group(state, faction, plan.target, used)
			if not again.is_empty():
				plans.append(again)
			continue
		if _order_group(state, plan):
			for unit in plan.group:
				used[unit] = true


## The smallest group of free armies, strongest first and the one that will
## move in leading, whose attack on `target` the forecast approves of; {} if
## none. {"target", "group", "forecast", "score"}.
static func _best_group(state: GameState, faction: String, target: String, used: Dictionary) -> Dictionary:
	var accept := _accept(state, faction)
	var distances := state.map.distances_from(target)
	var candidates: Array[Unit] = []
	for unit in state.units_of(faction):
		if not used.has(unit) and not state.orders.has(unit) and distances.get(unit.province, 99) <= 2 \
				and Orders.problem(state, unit, "attack", target) == "":
			candidates.append(unit)
	candidates.sort_custom(func(a: Unit, b: Unit):
		if a.has_melee() != b.has_melee():
			return a.has_melee()
		return a.power() > b.power() or (a.power() == b.power() and a.id < b.id))
	var group: Array[Unit] = []
	for unit in candidates:
		group.append(unit)
		var forecast := state.forecast_attack(group, target, int(skill(state).runs))
		if forecast.is_empty():
			return {}
		if forecast.rating in accept or (skill(state).bolder and group.size() > 1 and forecast.rating == "Close"):
			return {"target": target, "group": group.duplicate(), "forecast": forecast,
				"score": _attack_value(state, target, forecast) - 0.15 * (group.size() - 1)}
		if group.size() >= MOST_GATHERED:
			break
	return {}


## Gives a gathered attack its orders: the first army attacks and moves in,
## the others support it. If another enemy army could walk into the first
## army's home, a guard stays behind when the attack still wins without it;
## else, with a decisive forecast, it may leave a garrison next door.
static func _order_group(state: GameState, plan: Dictionary) -> bool:
	var main: Unit = plan.group[0]
	var guard := _home_guard(state, plan)
	if Orders.give(state, main, "attack", plan.target, {"soldiers": main.soldiers() - guard} if guard > 0 else {}) != "":
		return false
	if guard == 0 and plan.forecast.rating == "Decisive win":
		_garrison(state, main, _claimed(state, main.owner))
	for support: Unit in plan.group.slice(1):
		Orders.give(state, support, "attack", plan.target, {"support": true})
	return true


## Soldiers the attack's leader should leave at home: 0 unless an enemy army
## other than the one attacked borders its own region and the attack still
## gets an acceptable forecast without them.
static func _home_guard(state: GameState, plan: Dictionary) -> int:
	var main: Unit = plan.group[0]
	if state.owners[main.province] != main.owner or main.all_ranged() or main.soldiers() < 6:
		return 0
	var others := _enemies_near(state, main.owner, main.province, 1).filter(func(u: Unit): return u.province != plan.target)
	if others.is_empty():
		return 0
	var guard := maxi(2, main.soldiers() / (3 if _worth(state, main.province) >= 3 else 5))
	var lighter := main.copy()
	lighter.split(Orders.pick(lighter.composition(), guard))
	var stack: Array = [lighter]
	stack.append_array(plan.group.slice(1))
	var forecast := state.forecast_attack(stack, plan.target, int(skill(state).runs))
	if forecast.is_empty() or not (forecast.rating in _accept(state, main.owner) or forecast.rating == plan.forecast.rating):
		return 0
	return guard


## How much an attack is worth: what it does to the enemy less what it costs,
## more for taking a region, its capital, walls and gold.
static func _attack_value(state: GameState, target: String, forecast: Dictionary) -> float:
	var value: float = (1.0 - forecast.defender_survival) - (1.0 - forecast.attacker_survival) * 0.7
	if not forecast.ranged:
		value += 1.0 + (0.8 if state.is_capital(target) else 0.0) + Sieges.walls(state, target) * 0.2 \
			+ Economy.region_income(state, target) / 40.0
		value *= 0.5 + 0.5 * float(forecast.wins) / maxf(float(forecast.runs), 1.0)
	return value


## The forecast ratings the faction attacks on.
static func _accept(state: GameState, faction: String) -> Array:
	return ACCEPT.get(state.factions[faction].ai, ACCEPT.balanced)


## Easy: attacks the best target its forecast approves of, alone.
static func _attack(state: GameState, unit: Unit) -> bool:
	var accept := _accept(state, unit.owner)
	var best := ""
	var best_value := 0.0
	for target in _targets_near(state, unit):
		if Orders.problem(state, unit, "attack", target) != "":
			continue
		var forecast := state.forecast_attack([unit], target, int(skill(state).runs))
		if forecast.is_empty() or not (forecast.rating in accept):
			continue
		var value := _attack_value(state, target, forecast)
		if value > best_value:
			best_value = value
			best = target
	return best != "" and Orders.give(state, unit, "attack", best) == ""


## A big unit attacking with a decisive forecast leaves a fifth of its
## soldiers (at least 3) to hold an empty region of its own next to it that
## enemies could walk into, and attacks with the rest.
static func _garrison(state: GameState, unit: Unit, claimed: Dictionary) -> void:
	var list := Orders.orders_of(state, unit)
	if list.size() != 1 or list[0].steps[0].type != "attack" or unit.all_ranged() or unit.soldiers() < GARRISON_FROM:
		return
	var target: String = list[0].steps[0].target
	for neighbour in state.map.neighbours(unit.province):
		if neighbour == target or state.owners[neighbour] != unit.owner or state.unit_in(neighbour) != null or claimed.has(neighbour) \
				or _enemies_near(state, unit.owner, neighbour, 1).is_empty():
			continue
		var forecast := state.forecast_attack([unit], target, int(skill(state).runs))
		if forecast.is_empty() or forecast.rating != "Decisive win":
			return
		var guard := maxi(3, unit.soldiers() / 5)
		Orders.give(state, unit, "attack", target, {"soldiers": unit.soldiers() - guard})
		if Orders.give(state, unit, "move", neighbour, {"soldiers": guard}) == "":
			claimed[neighbour] = true
		return


## Easy: joins another army's attack next to it when together the forecast is better.
static func _support(state: GameState, unit: Unit) -> bool:
	var accept := _accept(state, unit.owner)
	for target in _targets_near(state, unit):
		var main := Orders.main_attack(state, unit.owner, target, unit)
		if main == null or Orders.problem(state, unit, "attack", target) != "":
			continue
		var forecast := state.forecast_attack([main, unit], target, int(skill(state).runs))
		if not forecast.is_empty() and forecast.rating in accept + ["Close"]:
			return Orders.give(state, unit, "attack", target, {"support": true}) == ""
	return false


static func _besiege(state: GameState, unit: Unit) -> bool:
	if state.factions[unit.owner].ai == "defensive":
		return false
	for target in state.map.neighbours(unit.province):
		if state.is_enemy(unit.owner, state.owners[target]) and Orders.problem(state, unit, "besiege", target) == "":
			return Orders.give(state, unit, "besiege", target) == ""
	return false


# --- Marches ---------------------------------------------------------------------------

## A badly hurt unit at the front steps back into a safer free region of its own.
static func _retreat(state: GameState, unit: Unit, claimed: Dictionary) -> bool:
	if (unit.health() >= RETREAT_BELOW and unit.soldiers() > RETREAT_SOLDIERS) or _threat(state, unit.owner, unit.province) == 0.0:
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


## Normal and hard: fresh armies next to a threatened region worth guarding
## (the capital, or one with walls or buildings) march in to hold it, from
## regions that are safer or matter less.
static func _defend(state: GameState, faction: String, free: Array[Unit], used: Dictionary, claimed: Dictionary) -> void:
	var regions := _own_regions(state, faction).filter(func(r): return _worth(state, r) >= 2 and _threat(state, faction, r) > 0.0)
	regions.sort_custom(func(a, b): return _worth(state, a) > _worth(state, b) or (_worth(state, a) == _worth(state, b) and a < b))
	for region in regions:
		var need := _threat(state, faction, region)  # Less the strength already marching in.
		for neighbour in state.map.neighbours(region):
			if need <= 0.0:
				break
			var helper := state.unit_in(neighbour)
			if helper == null or helper.owner != faction or not free.has(helper) or used.has(helper):
				continue
			if _threat(state, faction, neighbour) > 0.0 and _worth(state, neighbour) >= _worth(state, region):
				continue
			if Orders.problem(state, helper, "move", region) == "" and Orders.give(state, helper, "move", region) == "":
				used[helper] = true
				claimed[region] = true
				need -= helper.power() * Orders.assigned(state, helper) / maxf(helper.soldiers(), 1.0)


## Walks into the best empty enemy or neutral region next to it. Normal and
## hard split the army to take every one it can at once: a soldier for each
## extra region no enemy army borders (three for one that one does), the
## rest into the best; they leave half behind (or stay) when an enemy army
## could walk into a home worth guarding.
static func _capture(state: GameState, unit: Unit, claimed: Dictionary) -> bool:
	if _leaves_exposed(state, unit):
		return false
	var options := []
	for neighbour in state.map.neighbours(unit.province):
		if state.owners[neighbour] != unit.owner and state.unit_in(neighbour) == null and not claimed.has(neighbour) \
				and Orders.problem(state, unit, "move", neighbour) == "":
			options.append(neighbour)
	if options.is_empty():
		return false
	var value := func(r): return _worth(state, r) * 100 + Economy.region_income(state, r)
	options.sort_custom(func(a, b): return value.call(a) > value.call(b) or (value.call(a) == value.call(b) and a < b))
	if not skill(state).gather:
		claimed[options[0]] = true
		return Orders.give(state, unit, "move", options[0]) == ""
	var spare := Orders.unassigned(state, unit)
	if _would_be_exposed(state, unit):
		if spare < 6:
			return false
		spare -= spare / 2
	for region in options.slice(1):
		var need := 1 if _enemies_near(state, unit.owner, region, 1).is_empty() else 3
		if spare - need < 2:
			break
		if Orders.give(state, unit, "move", region, {"soldiers": need}) == "":
			claimed[region] = true
			spare -= need
	claimed[options[0]] = true
	return Orders.give(state, unit, "move", options[0], {"soldiers": spare}) == ""


## Units behind the front step towards the nearest enemy region; normal and
## hard join an army of theirs that is ahead.
static func _advance(state: GameState, unit: Unit, claimed: Dictionary) -> void:
	if (state.factions[unit.owner].ai == "defensive" and state.turn < 6) or _leaves_exposed(state, unit):
		return
	if skill(state).gather and _would_be_exposed(state, unit):
		return
	var targets := state.map.province_order.filter(func(r): return state.is_enemy(unit.owner, state.owners[r]) and state.owners[r] != "rebels")
	if targets.is_empty():
		return
	var here := _nearest(targets, state.map.distances_from(unit.province))
	var best := ""
	for neighbour in state.map.neighbours(unit.province):
		if claimed.has(neighbour) or Orders.problem(state, unit, "move", neighbour) != "":
			continue
		var ahead := state.unit_in(neighbour)
		if ahead != null and not (skill(state).gather and ahead.owner == unit.owner):
			continue
		var there := _nearest(targets, state.map.distances_from(neighbour))
		if there < here:
			here = there
			best = neighbour
	if best != "":
		if state.unit_in(best) == null:
			claimed[best] = true
		Orders.give(state, unit, "move", best)


# --- Helpers -------------------------------------------------------------------------

static func _own_regions(state: GameState, faction: String) -> Array:
	return state.map.province_order.filter(func(r): return state.owners[r] == faction)


## Regions with an enemy army that some army of the faction can reach.
static func _enemy_targets(state: GameState, faction: String) -> Array:
	var found := {}
	for unit in state.units_of(faction):
		for target in _targets_near(state, unit):
			found[target] = true
	var targets := found.keys()
	targets.sort()
	return targets


## Enemy-held regions within reach of a unit (2 for longbows).
static func _targets_near(state: GameState, unit: Unit) -> Array:
	var distances := state.map.distances_from(unit.province)
	var targets := []
	for other in distances:
		if distances[other] >= 1 and distances[other] <= 2 and not state.enemy_units_in(other, unit.owner).is_empty():
			targets.append(other)
	return targets


## Regions the faction's orders already send soldiers into.
static func _claimed(state: GameState, faction: String) -> Dictionary:
	var claimed := {}
	for unit: Unit in state.orders:
		if unit.owner == faction:
			for order in state.orders[unit]:
				for arrival in Orders.arrivals(order):
					if arrival[0] != "":
						claimed[arrival[0]] = true
	return claimed


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


## How much a region matters: 3 a capital, 2 walls or buildings, else 1.
static func _worth(state: GameState, region: String) -> int:
	if state.is_capital(region):
		return 3
	if Sieges.walls(state, region) > 0 or not state.provinces[region].buildings.is_empty():
		return 2
	return 1


## True if moving this unit would leave its capital empty next to enemies.
static func _leaves_exposed(state: GameState, unit: Unit) -> bool:
	return state.owners[unit.province] == unit.owner and not _enemies_near(state, unit.owner, unit.province, 1).is_empty() \
		and state.is_capital(unit.province)


## True if an enemy army next to the unit's own region, one worth guarding
## (_worth 2 or more), could walk in were it to leave.
static func _would_be_exposed(state: GameState, unit: Unit) -> bool:
	return state.owners[unit.province] == unit.owner and _worth(state, unit.province) >= 2 \
		and not _enemies_near(state, unit.owner, unit.province, 1).is_empty()


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
