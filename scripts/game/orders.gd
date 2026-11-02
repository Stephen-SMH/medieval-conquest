class_name Orders
extends RefCounted
## Planning orders (PRD 8.3, A, B). An army can split its soldiers across
## several orders in the same turn: each order is a **detachment** with its
## own arrow, a blue one to move into a neighbouring region (or along a sea
## route) or a red one to attack. A detachment takes so many soldiers of each
## type the army holds (one slider per type in the window). Soldiers not
## given to any order stay home. An army sends at most one detachment to each
## region, and two of its detachments never head for the same region. A
## detachment of cavalry only may take two steps: a move and then a move or
## an attack. In an attack the ranged soldiers shoot and the rest go into
## melee; ranged soldiers alone only shoot (and may reach 2 regions with
## longbows). A **support** order adds a detachment to another army's attack
## on the same region, so they fight as one battle. A siege takes the whole
## army. Nothing happens until the hourglass: then the Resolver carries out
## the current faction's orders.
##
## state.orders[unit] is an Array of orders, each
##   {"steps": [{"type": "move"/"attack"/"besiege", "target": region}, ...],
##    "troops": {type id: soldiers}, "size": soldiers in the detachment,
##    "support": true for a support order}.

const CAVALRY_STEPS := 2


static func orders_of(state: GameState, unit: Unit) -> Array:
	return state.orders.get(unit, [])


## Soldiers of each type given to orders.
static func assigned_by_type(state: GameState, unit: Unit) -> Dictionary:
	var result := {}
	for order in orders_of(state, unit):
		for type_id in order.troops:
			result[type_id] = int(result.get(type_id, 0)) + int(order.troops[type_id])
	return result


static func assigned(state: GameState, unit: Unit) -> int:
	var total := 0
	for order in orders_of(state, unit):
		total += int(order.size)
	return total


## Soldiers with no order: they stay home.
static func unassigned(state: GameState, unit: Unit) -> int:
	return maxi(unit.soldiers() - assigned(state, unit), 0)


## Soldiers of each type with no order.
static func free_troops(state: GameState, unit: Unit) -> Dictionary:
	var given := assigned_by_type(state, unit)
	var result := {}
	for type_id in unit.composition():
		var left: int = unit.composition()[type_id] - int(given.get(type_id, 0))
		if left > 0:
			result[type_id] = left
	return result


## Takes `count` soldiers from `pool` ({type: soldiers}), spread over the
## types in proportion (largest remainders first, ties in display order).
static func pick(pool: Dictionary, count: int) -> Dictionary:
	var total := 0
	for type_id in pool:
		total += int(pool[type_id])
	count = clampi(count, 0, total)
	if count >= total:
		return pool.duplicate()
	var result := {}
	var remainders := []
	var given := 0
	for type_id in pool:
		var exact := float(pool[type_id]) * count / total
		result[type_id] = floori(exact)
		given += floori(exact)
		remainders.append([exact - floori(exact), type_id])
	remainders.sort_custom(func(a, b): return a[0] > b[0])
	for entry in remainders:
		if given >= count:
			break
		result[entry[1]] += 1
		given += 1
	for type_id in result.keys():
		if result[type_id] <= 0:
			result.erase(type_id)
	return result


static func total(troops: Dictionary) -> int:
	var sum := 0
	for type_id in troops:
		sum += int(troops[type_id])
	return sum


static func all_cavalry(troops: Dictionary) -> bool:
	return not troops.is_empty() and troops.keys().all(func(t): return Rules.unit(t).is_cavalry())


static func all_ranged(troops: Dictionary) -> bool:
	return not troops.is_empty() and troops.keys().all(func(t): return Rules.unit(t).is_ranged())


## The order whose first arrow points at `target`, or -1.
static func index_to(state: GameState, unit: Unit, target: String) -> int:
	var list := orders_of(state, unit)
	for i in list.size():
		if list[i].steps[0].target == target:
			return i
	return -1


## Whether some order of the army, other than order `except`, passes through `region`.
static func uses_region(state: GameState, unit: Unit, region: String, except := -1) -> bool:
	var list := orders_of(state, unit)
	for i in list.size():
		if i != except and list[i].steps.any(func(s): return s.target == region):
			return true
	return false


## The order that can take a second step (the latest, if it's a march of
## cavalry only), or -1.
static func chain_index(state: GameState, unit: Unit) -> int:
	var list := orders_of(state, unit)
	if list.is_empty():
		return -1
	var last: Dictionary = list.back()
	if last.steps.size() < CAVALRY_STEPS and last.steps.back().type == "move" and all_cavalry(last.troops):
		return list.size() - 1
	return -1


## True when the army's only order sends every soldier: a new arrow replaces it.
static func _replaceable(state: GameState, unit: Unit) -> bool:
	var list := orders_of(state, unit)
	return list.size() == 1 and int(list[0].size) >= unit.soldiers() and list[0].steps[0].type != "besiege"


## Every soldier has an order and no detachment can take another step: a red X.
static func is_spent(state: GameState, unit: Unit) -> bool:
	return state.orders.has(unit) and unassigned(state, unit) == 0 and chain_index(state, unit) < 0


## Soldier types that can take part in a step of this kind over `distance`
## regions: an attack 2 regions away is for longbows only.
static func eligible(type_id: String, type: String, distance: int) -> bool:
	if type == "attack" and distance > 1:
		return Rules.unit(type_id).attack_range >= distance
	return true


## The soldiers of each type an order to `target` could take: the free ones,
## plus those of the order being changed or replaced. A cavalry second step
## carries on with its detachment.
static func available(state: GameState, unit: Unit, target: String, type := "") -> Dictionary:
	var plan := intent(state, unit, target)
	if type == "":
		type = plan.get("type", "move")
	var pool := free_troops(state, unit)
	var from := unit.province
	if not plan.is_empty() and plan.order >= 0:
		var order: Dictionary = orders_of(state, unit)[plan.order]
		if plan.step > 0:
			pool = order.troops.duplicate()
			from = plan.from
		else:
			for type_id in order.troops:
				pool[type_id] = int(pool.get(type_id, 0)) + int(order.troops[type_id])
	elif _replaceable(state, unit):
		pool = unit.composition()
	var distance := state.map.distance(from, target)
	var result := {}
	for type_id in unit.composition():
		if pool.has(type_id) and eligible(type_id, type, distance):
			result[type_id] = int(pool[type_id])
	return result


## Another army of the same faction already has an attack (not a support)
## ordered on `target`: a support order can join it (PRD B).
static func can_support(state: GameState, unit: Unit, target: String) -> bool:
	return main_attack(state, unit.owner, target, unit) != null


## The army whose plain attack on `target` supports would join, or null.
static func main_attack(state: GameState, faction: String, target: String, except: Unit = null) -> Unit:
	var found: Unit = null
	for other: Unit in state.orders:
		if other == except or other.owner != faction or not state.units.has(other):
			continue
		for order in state.orders[other]:
			if not order.get("support", false) and order.steps.back().type == "attack" and order.steps.back().target == target:
				if found == null or other.id < found.id:
					found = other
	return found


## "" if the army may take this step, else the reason why not. Step 0 starts
## from the army's region; a later step from `from` (by default the waypoint
## of the order that can take a second step).
static func problem(state: GameState, unit: Unit, type: String, target: String, step_index := 0, from := "") -> String:
	if state.is_over():
		return "the game is over"
	if unit.owner != state.current_faction():
		return "not your army to command"
	var chained := chain_index(state, unit)
	if step_index > 0:
		if step_index >= CAVALRY_STEPS:
			return "only two steps"
		if from == "":
			if chained < 0:
				return "no cavalry march to carry on from"
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
			if not state.map.are_neighbours(origin, target):
				return "not next to it"
			if occupant == null or occupant == unit:
				return ""
			if state.is_enemy(unit.owner, occupant.owner):
				return "an enemy army is there: attack instead"
			if occupant.soldiers() >= Unit.CAP and not state.orders.has(occupant):
				return "that army already has %d soldiers" % Unit.CAP
			return ""
		"attack":
			if occupant == null or not state.is_enemy(unit.owner, occupant.owner):
				return "no enemy army there"
			var distance := state.map.distance(origin, target)
			if distance > 1:
				var reach := 0
				for type_id in (orders_of(state, unit)[chained].troops if step_index > 0 else unit.composition()):
					reach = maxi(reach, Rules.unit(type_id).attack_range)
				if distance > reach:
					return "out of range"
			return ""
		"besiege":
			if step_index > 0:
				return "a siege must be the army's only order"
			return Sieges.besiege_problem(state, [unit], target)
	return "unknown order"


## What clicking `target` would do with the army, or {} if nothing:
## {"type": "move"/"attack", "order": index of the order it changes or extends
## (-1 for a new detachment), "step": the step's index, "from": where the arrow starts}.
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
## may hold "troops" ({type: soldiers}), or "soldiers" (a count spread over
## the types), and "support" (true to join another army's attack). By default
## every soldier still free goes. Returns "" or the reason it can't be done.
static func give(state: GameState, unit: Unit, type: String, target: String, amounts := {}) -> String:
	if type == "besiege":
		var siege := problem(state, unit, "besiege", target)
		if siege != "":
			return siege
		state.orders[unit] = [{"steps": [{"type": "besiege", "target": target}], "troops": unit.composition(), "size": unit.soldiers(), "support": false}]
		return ""
	var support: bool = amounts.get("support", false) and type == "attack"
	if support and not can_support(state, unit, target):
		return "no attack of yours to support there"
	var plan := intent(state, unit, target)
	if not plan.is_empty() and plan.type == type and plan.order >= 0:
		var order: Dictionary = orders_of(state, unit)[plan.order]
		if plan.step == 0:
			_set_troops(order, _wanted(available(state, unit, target, type), amounts))
			order.support = support
			return ""
		var going: Dictionary = _wanted(order.troops, amounts) if type == "attack" else order.troops.duplicate()
		order.steps.append({"type": type, "target": target})
		if type == "attack":
			order["attackers"] = going  # Those who attack after the march; the rest wait at the waypoint.
			order.support = support
		return ""
	var fresh := problem(state, unit, type, target, 0)
	if fresh != "":
		return fresh
	var pool := available(state, unit, target, type)
	if _replaceable(state, unit) or not state.orders.has(unit):
		state.orders[unit] = []
	var wanted := _wanted(pool, amounts)
	if total(wanted) <= 0:
		return "no soldiers can go there"
	var order := {"steps": [{"type": type, "target": target}], "troops": {}, "size": 0, "support": support}
	_set_troops(order, wanted)
	state.orders[unit].append(order)
	return ""


## The soldiers asked for, within `pool`: "troops" per type, or "soldiers"
## spread over the types, or everyone.
static func _wanted(pool: Dictionary, amounts: Dictionary) -> Dictionary:
	if amounts.has("troops"):
		var result := {}
		for type_id in amounts.troops:
			var count := clampi(int(amounts.troops[type_id]), 0, int(pool.get(type_id, 0)))
			if count > 0:
				result[type_id] = count
		if result.is_empty():
			return pick(pool, 1)
		return result
	if amounts.has("soldiers"):
		return pick(pool, maxi(int(amounts.soldiers), 1))
	return pool.duplicate()


static func _set_troops(order: Dictionary, troops: Dictionary) -> void:
	order.troops = troops
	order.size = total(troops)


## Cancels all the army's orders.
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


## What clicking each nearby region would do for this army:
## "move", "attack" or "blocked".
static func reachable(state: GameState, unit: Unit) -> Dictionary:
	var result := {}
	var origins := [unit.province]
	var chained := chain_index(state, unit)
	if chained >= 0:
		origins.append(orders_of(state, unit)[chained].steps.back().target)
	for origin in origins:
		var distance := state.map.distances_from(origin)
		for region in distance:
			var steps: int = distance[region]
			if steps == 0 or steps > 2 or result.get(region, "blocked") != "blocked":
				continue
			var plan := intent(state, unit, region)
			if not plan.is_empty():
				result[region] = plan.type
			elif steps == 1 and origin == unit.province and region != unit.province:
				result[region] = "blocked"
	result.erase(unit.province)
	return result


## "8 militia, 2 archers".
static func troops_text(troops: Dictionary) -> String:
	var parts := PackedStringArray()
	for type_id in troops:
		parts.append("%d %s" % [int(troops[type_id]), Rules.unit(type_id).plural_name().to_lower()])
	return ", ".join(parts)


## A short description of an army's orders, e.g. "14 attack Ravensford; 4 march to Fernridge; 2 stay home".
static func describe(state: GameState, unit: Unit) -> String:
	var parts := PackedStringArray()
	for order in orders_of(state, unit):
		var steps := PackedStringArray()
		for step in order.steps:
			var verb: String = {"move": "march to", "attack": "support the attack on" if order.get("support", false) else "attack",
				"besiege": "besiege"}.get(step.type, step.type)
			steps.append("%s %s" % [verb, state.map.region_name(step.target)])
		parts.append("%d %s" % [int(order.size), ", then ".join(steps)])
	var home := unassigned(state, unit)
	if home > 0:
		parts.append("%d stay home" % home)
	return "; ".join(parts)
