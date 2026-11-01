class_name Orders
extends RefCounted
## Planning orders (PRD 8.3). Each unit gets at most one order: a blue arrow to
## move into a neighbouring region, a red arrow to attack one, or a siege.
## Cavalry may plan two steps: a move and then a move or an attack. An attack
## can send only part of the unit (a slider); ranged units can split their
## soldiers between shooting and going into melee. Nothing happens until the
## hourglass: then the Resolver carries out everyone's orders together.
##
## An order is {"steps": [{"type": "move"/"attack"/"besiege", "target": region}],
##              "soldiers": melee soldiers sent, "shoot": soldiers shooting}.

const CAVALRY_STEPS := 2


static func order_of(state: GameState, unit: Unit) -> Dictionary:
	return state.orders.get(unit, {})


static func max_steps(unit: Unit) -> int:
	return CAVALRY_STEPS if unit.type().is_cavalry() else 1


## Where a step would start from: the unit's region, or where its previous step ends.
static func step_origin(state: GameState, unit: Unit, step_index: int) -> String:
	if step_index == 0:
		return unit.province
	return order_of(state, unit).steps[step_index - 1].target


## The index the unit's next step would have, or -1 if it can't take another.
static func next_step_index(state: GameState, unit: Unit) -> int:
	var order := order_of(state, unit)
	if order.is_empty():
		return 0
	var steps: Array = order.steps
	if steps.size() < max_steps(unit) and steps.back().type == "move":
		return steps.size()
	return -1


## "" if the unit may take this step, else the reason why not.
static func problem(state: GameState, unit: Unit, type: String, target: String, step_index := 0) -> String:
	if state.is_over():
		return "the game is over"
	if unit.owner != state.current_faction():
		return "not your unit to command"
	if step_index > 0 and step_index >= max_steps(unit):
		return "only cavalry can take two steps"
	var origin := step_origin(state, unit, step_index)
	if target == origin:
		return "already there"
	var occupant := state.unit_in(target)
	match type:
		"move":
			if not state.map.are_neighbours(origin, target) and not (step_index == 0 and _coastal_reach(state, unit, target)):
				return "not next to it"
			if occupant == null or occupant == unit:
				return ""
			if state.is_enemy(unit.owner, occupant.owner):
				return "an enemy unit is there: attack instead"
			# Your own unit there: the same type merges; otherwise this works only if
			# that unit leaves or swaps places, which is settled when the turn resolves.
			return ""
		"attack":
			if occupant == null or not state.is_enemy(unit.owner, occupant.owner):
				return "no enemy unit there"
			if unit.type().is_ranged():
				if state.map.distance(origin, target) > state.attack_range(unit):
					return "out of range"
			elif not state.map.are_neighbours(origin, target):
				return "not next to it"
			return ""
		"besiege":
			if step_index > 0:
				return "a siege must be the unit's only order"
			return Sieges.besiege_problem(state, [unit], target)
	return "unknown order"


## Norse raiding: a move 2 regions along the coast, through an empty coastal region.
static func _coastal_reach(state: GameState, unit: Unit, target: String) -> bool:
	if Bonuses.coastal_moves(state, unit.owner) == 0 or not state.map.is_coastal(unit.province) or not state.map.is_coastal(target):
		return false
	for middle in state.map.neighbours(unit.province):
		if state.map.is_coastal(middle) and state.map.are_neighbours(middle, target) and state.unit_in(middle) == null:
			return true
	return false


## Plans a step. Cavalry with a move planned adds a second step from where the
## first ends; any other order replaces the unit's plan. `amounts` may hold
## "soldiers" (melee soldiers sent) and "shoot" (soldiers shooting).
## Returns "" or the reason it can't be done.
static func give(state: GameState, unit: Unit, type: String, target: String, amounts := {}) -> String:
	var index := next_step_index(state, unit)
	if index > 0:
		var chained := problem(state, unit, type, target, index)
		if chained == "":
			state.orders[unit].steps.append({"type": type, "target": target})
			_set_amounts(state, unit, type, amounts)
			return ""
	var fresh := problem(state, unit, type, target, 0)
	if fresh != "":
		return fresh
	state.orders[unit] = {"steps": [{"type": type, "target": target}], "soldiers": unit.soldiers(),
		"shoot": unit.soldiers() if unit.type().is_ranged() else 0}
	if unit.type().is_ranged() and type == "attack":
		state.orders[unit].soldiers = 0  # Archers shoot unless told to also send soldiers into melee.
	_set_amounts(state, unit, type, amounts)
	return ""


static func _set_amounts(state: GameState, unit: Unit, type: String, amounts: Dictionary) -> void:
	if type != "attack":
		return
	var order: Dictionary = state.orders[unit]
	var total := unit.soldiers()
	if amounts.has("shoot"):
		order.shoot = clampi(int(amounts.shoot), 0, total) if unit.type().is_ranged() else 0
	if amounts.has("soldiers"):
		order.soldiers = clampi(int(amounts.soldiers), 0, total - int(order.shoot))
	if not unit.type().is_ranged():
		order.soldiers = maxi(int(order.soldiers), 1)


## How many soldiers can go into melee, at most, for this attack.
static func melee_allowed(state: GameState, unit: Unit, target: String) -> bool:
	return state.map.are_neighbours(unit.province, target)


static func cancel(state: GameState, unit: Unit) -> void:
	state.orders.erase(unit)


## What clicking each nearby region would do for this unit's next step:
## "move", "attack" or "blocked".
static func reachable(state: GameState, unit: Unit) -> Dictionary:
	var result := {}
	var index := next_step_index(state, unit)
	if index < 0:
		index = 0
	var origin := step_origin(state, unit, index)
	var reach: int = maxi(1, state.attack_range(unit)) if index == 0 else 1
	var distance := state.map.distances_from(origin)
	for region in distance:
		var steps: int = distance[region]
		if steps == 0 or steps > maxi(reach, 2):
			continue
		if problem(state, unit, "attack", region, index) == "":
			result[region] = "attack"
		elif problem(state, unit, "move", region, index) == "":
			result[region] = "move"
		elif steps == 1:
			result[region] = "blocked"
	return result
