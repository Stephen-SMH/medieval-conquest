class_name Orders
extends RefCounted
## Planning orders (PRD 8.3). A unit can split its soldiers across several
## orders in the same turn: each order is a **detachment** with its own arrow,
## a blue one to move into a neighbouring region or a red one to attack.
## Soldiers not given to any order stay home. A unit sends at most one
## detachment to each region, and two of its detachments never head for the
## same region. Cavalry detachments may take two steps: a move and then a move
## or an attack. Ranged units split an attack between shooting and melee. A
## siege takes the whole unit. Nothing happens until the hourglass: then the
## Resolver carries out everyone's orders together.
##
## state.orders[unit] is an Array of orders, each
##   {"steps": [{"type": "move"/"attack"/"besiege", "target": region}, ...],
##    "size": soldiers in the detachment,
##    "soldiers": soldiers of the detachment who go into melee when it attacks,
##    "shoot": soldiers of the detachment who shoot when it attacks}.

const CAVALRY_STEPS := 2


static func orders_of(state: GameState, unit: Unit) -> Array:
	return state.orders.get(unit, [])


static func max_steps(unit: Unit) -> int:
	return CAVALRY_STEPS if unit.type().is_cavalry() else 1


## Soldiers given to orders.
static func assigned(state: GameState, unit: Unit) -> int:
	var total := 0
	for order in orders_of(state, unit):
		total += int(order.size)
	return total


## Soldiers with no order: they stay home.
static func unassigned(state: GameState, unit: Unit) -> int:
	return maxi(unit.soldiers() - assigned(state, unit), 0)


## The order whose first arrow points at `target`, or -1.
static func index_to(state: GameState, unit: Unit, target: String) -> int:
	var list := orders_of(state, unit)
	for i in list.size():
		if list[i].steps[0].target == target:
			return i
	return -1


## Whether some order of the unit, other than order `except`, passes through `region`.
static func uses_region(state: GameState, unit: Unit, region: String, except := -1) -> bool:
	var list := orders_of(state, unit)
	for i in list.size():
		if i != except and list[i].steps.any(func(s): return s.target == region):
			return true
	return false


## The order that can take a second step (the latest, if it's a cavalry move), or -1.
static func chain_index(state: GameState, unit: Unit) -> int:
	var list := orders_of(state, unit)
	if list.is_empty():
		return -1
	var last: Dictionary = list.back()
	if last.steps.size() < max_steps(unit) and last.steps.back().type == "move":
		return list.size() - 1
	return -1


## True when the unit's only order sends every soldier: a new arrow replaces it
## (so a quick second click still changes a whole unit's mind, as it always did).
static func _replaceable(state: GameState, unit: Unit) -> bool:
	var list := orders_of(state, unit)
	return list.size() == 1 and int(list[0].size) >= unit.soldiers() and list[0].steps[0].type != "besiege"


## The unit has used everything it can this turn: every soldier has an order
## and no detachment can take another step. The map shows a red X.
static func is_spent(state: GameState, unit: Unit) -> bool:
	return state.orders.has(unit) and unassigned(state, unit) == 0 and chain_index(state, unit) < 0


## How many soldiers an order to `target` could have: the unassigned ones,
## plus those of the order being changed or replaced. A cavalry second step
## carries on with its detachment.
static func available(state: GameState, unit: Unit, target: String) -> int:
	var plan := intent(state, unit, target)
	if plan.is_empty():
		return unassigned(state, unit)
	if plan.order >= 0:
		var order: Dictionary = orders_of(state, unit)[plan.order]
		return int(order.size) if plan.step > 0 else unassigned(state, unit) + int(order.size)
	return unit.soldiers() if _replaceable(state, unit) else unassigned(state, unit)


## "" if the unit may take this step, else the reason why not. Step 0 starts
## from the unit's region; a later step from `from` (by default the waypoint
## of the order that can take a second step).
static func problem(state: GameState, unit: Unit, type: String, target: String, step_index := 0, from := "") -> String:
	if state.is_over():
		return "the game is over"
	if unit.owner != state.current_faction():
		return "not your unit to command"
	var chained := chain_index(state, unit)
	if step_index > 0:
		if step_index >= max_steps(unit):
			return "only cavalry can take two steps"
		if from == "":
			if chained < 0:
				return "no march to carry on from"
			from = orders_of(state, unit)[chained].steps.back().target
		if uses_region(state, unit, target, chained):
			return "another detachment already goes there"
	var origin := from if step_index > 0 else unit.province
	if target == origin:
		return "already there"
	var editing := step_index == 0 and index_to(state, unit, target) >= 0
	if step_index == 0 and type != "besiege" and not editing:
		var replacing := _replaceable(state, unit)
		if not replacing and unassigned(state, unit) == 0:
			return "every soldier already has orders"
		if not replacing and uses_region(state, unit, target):
			return "another detachment already goes there"
	var occupant := state.unit_in(target)
	match type:
		"move":
			if not state.map.are_neighbours(origin, target) and not (step_index == 0 and _coastal_reach(state, unit, target)):
				return "not next to it"
			if occupant == null or occupant == unit:
				return ""
			if state.is_enemy(unit.owner, occupant.owner):
				return "an enemy unit is there: attack instead"
			# Your own unit there: the same type merges. Otherwise only a whole unit
			# may go, and only if that unit leaves or swaps places (settled when the
			# turn resolves); a detachment can't squeeze in beside it.
			if step_index == 0 and occupant.type_id != unit.type_id and not orders_of(state, unit).is_empty() \
					and not _replaceable(state, unit) and not (editing and orders_of(state, unit).size() == 1):
				return "your %s are there; only the whole unit can swap" % occupant.type().display_name.to_lower()
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


## Whether only the whole unit may move to `target` (a friendly unit of another type is there).
static func whole_unit_only(state: GameState, unit: Unit, target: String) -> bool:
	var occupant := state.unit_in(target)
	return occupant != null and occupant != unit and occupant.owner == unit.owner and occupant.type_id != unit.type_id


## Norse raiding: a move 2 regions along the coast, through an empty coastal region.
static func _coastal_reach(state: GameState, unit: Unit, target: String) -> bool:
	if Bonuses.coastal_moves(state, unit.owner) == 0 or not state.map.is_coastal(unit.province) or not state.map.is_coastal(target):
		return false
	for middle in state.map.neighbours(unit.province):
		if state.map.is_coastal(middle) and state.map.are_neighbours(middle, target) and state.unit_in(middle) == null:
			return true
	return false


## What clicking `target` would do with the unit, or {} if nothing:
## {"type": "move"/"attack", "order": index of the order it changes or extends
## (-1 for a new detachment), "step": the step's index, "from": where the arrow starts}.
## Re-drawing to an order's target edits it; then a cavalry detachment's second
## step; else a new detachment from home.
static func intent(state: GameState, unit: Unit, target: String) -> Dictionary:
	var existing := index_to(state, unit, target)
	if existing >= 0:
		var first: Dictionary = orders_of(state, unit)[existing].steps[0]
		if first.type != "besiege":
			return {"type": first.type, "order": existing, "step": 0, "from": unit.province}
	var chained := chain_index(state, unit)
	if chained >= 0:
		var order: Dictionary = orders_of(state, unit)[chained]
		var waypoint: String = order.steps.back().target
		for type in ["attack", "move"]:
			if problem(state, unit, type, target, order.steps.size(), waypoint) == "":
				return {"type": type, "order": chained, "step": order.steps.size(), "from": waypoint}
	for type in ["attack", "move"]:
		if problem(state, unit, type, target, 0) == "":
			return {"type": type, "order": -1, "step": 0, "from": unit.province}
	return {}


## Plans a step: edits the order already aimed at `target`, adds a cavalry
## detachment's second step, or sends a new detachment from home. `amounts`
## may hold "soldiers" (soldiers sent; for a ranged attack, those going into
## melee) and "shoot" (soldiers shooting); by default every soldier still free
## goes. Returns "" or the reason it can't be done.
static func give(state: GameState, unit: Unit, type: String, target: String, amounts := {}) -> String:
	if type == "besiege":
		var siege := problem(state, unit, "besiege", target)
		if siege != "":
			return siege
		state.orders[unit] = [{"steps": [{"type": "besiege", "target": target}], "size": unit.soldiers(), "soldiers": unit.soldiers(), "shoot": 0}]
		return ""
	var plan := intent(state, unit, target)
	if not plan.is_empty() and plan.type == type and plan.order >= 0:
		var order: Dictionary = orders_of(state, unit)[plan.order]
		if plan.step == 0:
			var room := unassigned(state, unit) + int(order.size)
			if type == "move" and whole_unit_only(state, unit, target):
				amounts = {"soldiers": room}
			if order.steps.size() > 1 and order.steps.back().type == "attack":
				# The detachment's size changes; its attack after the march sends all of it.
				_set_size(order, unit, type, amounts, room)
				order.soldiers = order.size if not unit.type().is_ranged() else 0
				order.shoot = order.size if unit.type().is_ranged() else 0
			else:
				_set_size(order, unit, type, amounts, room)
			return ""
		order.steps.append({"type": type, "target": target})
		if type == "attack":
			_set_attack(order, unit, amounts)
		return ""
	var fresh := problem(state, unit, type, target, 0)
	if fresh != "":
		return fresh
	if _replaceable(state, unit) or (not state.orders.has(unit)):
		state.orders[unit] = []
	var order := {"steps": [{"type": type, "target": target}], "size": 0, "soldiers": 0, "shoot": 0}
	var room := unassigned(state, unit)
	if type == "move" and whole_unit_only(state, unit, target):
		amounts = {"soldiers": room}
	_set_size(order, unit, type, amounts, room)
	state.orders[unit].append(order)
	return ""


## Sets a first step's detachment: how many go (and for an attack, how many shoot).
static func _set_size(order: Dictionary, unit: Unit, type: String, amounts: Dictionary, room: int) -> void:
	room = maxi(room, 1)
	if type == "attack" and unit.type().is_ranged():
		var shoot := clampi(int(amounts.get("shoot", room if not amounts.has("soldiers") else room - int(amounts.soldiers))), 0, room)
		var melee := clampi(int(amounts.get("soldiers", 0)), 0, room - shoot)
		if shoot + melee == 0:
			shoot = 1
		order.shoot = shoot
		order.soldiers = melee
		order.size = shoot + melee
	else:
		order.size = clampi(int(amounts.get("soldiers", room)), 1, room)
		order.soldiers = order.size
		order.shoot = 0


## A second-step attack: how many of the detachment fight; the rest wait at the waypoint.
static func _set_attack(order: Dictionary, unit: Unit, amounts: Dictionary) -> void:
	var size := int(order.size)
	if unit.type().is_ranged():
		order.shoot = clampi(int(amounts.get("shoot", size)), 0, size)
		order.soldiers = clampi(int(amounts.get("soldiers", 0)), 0, size - int(order.shoot))
		if int(order.shoot) + int(order.soldiers) == 0:
			order.shoot = size
	else:
		order.soldiers = clampi(int(amounts.get("soldiers", size)), 1, size)
		order.shoot = 0


## Whether a ranged unit may also send soldiers into melee at `target` from `from`.
static func melee_allowed(state: GameState, unit: Unit, target: String, from := "") -> bool:
	return state.map.are_neighbours(unit.province if from == "" else from, target)


## Cancels all the unit's orders.
static func cancel(state: GameState, unit: Unit) -> void:
	state.orders.erase(unit)


## Cancels one order; its soldiers are free again.
static func cancel_order(state: GameState, unit: Unit, index: int) -> void:
	var list := orders_of(state, unit)
	if index < 0 or index >= list.size():
		return
	list.remove_at(index)
	if list.is_empty():
		state.orders.erase(unit)


## What clicking each nearby region would do for this unit:
## "move", "attack" or "blocked".
static func reachable(state: GameState, unit: Unit) -> Dictionary:
	var result := {}
	var origins := [unit.province]
	var chained := chain_index(state, unit)
	if chained >= 0:
		origins.append(orders_of(state, unit)[chained].steps.back().target)
	var reach: int = maxi(1, state.attack_range(unit))
	for origin in origins:
		var distance := state.map.distances_from(origin)
		for region in distance:
			var steps: int = distance[region]
			if steps == 0 or steps > maxi(reach, 2) or result.get(region, "blocked") != "blocked":
				continue
			var plan := intent(state, unit, region)
			if not plan.is_empty():
				result[region] = plan.type
			elif steps == 1 and origin == unit.province and region != unit.province:
				result[region] = "blocked"
	result.erase(unit.province)
	return result


## A short description of a unit's orders, e.g. "14 attack Ravensford; 4 march to Fernridge; 2 stay home".
static func describe(state: GameState, unit: Unit) -> String:
	var parts := PackedStringArray()
	for order in orders_of(state, unit):
		var steps := PackedStringArray()
		for step in order.steps:
			var verb: String = {"move": "march to", "attack": "attack", "besiege": "besiege"}.get(step.type, step.type)
			steps.append("%s %s" % [verb, state.map.region_name(step.target)])
		parts.append("%d %s" % [int(order.size), ", then ".join(steps)])
	var home := unassigned(state, unit)
	if home > 0:
		parts.append("%d stay home" % home)
	return "; ".join(parts)
