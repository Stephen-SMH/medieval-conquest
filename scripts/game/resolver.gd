class_name Resolver
extends RefCounted
## Carries out one faction's orders (PRD C, 8.4): when it presses the "!" in
## the middle of its turn (carry_out), and whatever is left when it ends the
## turn with the hourglass (resolve). Always in the same order, with the
## game's seeded dice:
##   0. armies with several orders, or an order for only some soldiers, split
##      into detachments: the soldiers with no order stay home as the army;
##      if everyone goes, the army itself leads the largest detachment. Each
##      type's health is shared out per soldier;
##   1. sieges, then attacks. The attacks on one region are grouped: each
##      plain attack, with every support order that joins it (PRD B), is one
##      battle. Attacks of ranged soldiers only are volleys and go first;
##      then the others, strongest first, and later ones face whatever is left.
##      Supporters fight from home and never move in (as in S&T);
##   2. moves into empty or friendly regions (merges add the compositions, up
##      to Unit.CAP; two armies or detachments, each alone in its region,
##      trading places swap). Attacks go first
##      so that beaten attackers are home before others march in: a march
##      that no longer fits only partly merges, and the rest stay put;
##   3. detachments that end the turn in their home region (failed, blocked
##      or only shooting) rejoin their army; then captures;
##   4. the faction's end of turn (resolve only): income, upkeep, healing and sieges.
## The soldiers given orders are tired from then on: they can't be given
## another order until the faction's next turn (Troop.tired).
## Steps 1-2 run once for every detachment's first step and again for a
## cavalry detachment's second step. No region ends the turn with more than
## Unit.CAP soldiers. A detachment that moves into an empty
## region, or wins an attack and finds the region empty, stays there as an
## army of its own. Returns the events in the order they happened.


## The hourglass: the orders still waiting, then the end of the turn.
static func resolve(state: GameState, faction: String) -> Array:
	var events := carry_out(state, faction)
	events.append_array(_end_of_turn(state, faction))
	return events


## The "!": carries out the faction's orders now, and clears them.
static func carry_out(state: GameState, faction: String) -> Array:
	var events := []
	_tire(state, faction)
	# group: each detachment -> the army it split from.
	var ctx := {"plan": {}, "stopped": {}, "entered": [], "group": {}, "faction": faction}
	events.append_array(_split(state, faction, ctx))
	for wave in Orders.CAVALRY_STEPS:
		var steps := {}
		for unit in _by_id(ctx.plan.keys()):
			if state.units.has(unit) and not ctx.stopped.has(unit) and ctx.plan[unit].steps.size() > wave:
				steps[unit] = ctx.plan[unit].steps[wave]
		if steps.is_empty():
			break
		events.append_array(_attacks(state, steps, ctx, wave))
		events.append_array(_moves(state, steps, ctx))
	events.append_array(_reunite(state, ctx))
	events.append_array(_one_per_region(state))
	events.append_array(_captures(state, ctx))
	for unit in state.orders.keys():
		if unit.owner == faction or not state.units.has(unit):
			state.orders.erase(unit)
	return events


## Every soldier given an order is tired; detachments take the tired with them.
static func _tire(state: GameState, faction: String) -> void:
	for unit: Unit in state.orders:
		if unit.owner == faction and state.units.has(unit):
			unit.tire(Orders.assigned_by_type(state, unit))


## What an army looks like right now, for the animations: {soldiers, hp, full}.
static func look(unit: Unit) -> Dictionary:
	return {"soldiers": unit.soldiers(), "hp": unit.hp, "full": unit.full_hp(), "troops": unit.composition()}


# --- 0. Detachments ------------------------------------------------------------------

static func _split(state: GameState, faction: String, ctx: Dictionary) -> Array:
	var events := []
	for unit in _by_id(state.orders.keys()):
		if not state.units.has(unit) or unit.owner != faction:
			continue
		var list: Array = state.orders[unit]
		if list.is_empty() or unit.soldiers() <= 0:
			continue
		# Clamp the orders to the soldiers really there.
		var left := unit.composition()
		var wanted := []
		for order in list:
			var troops := {}
			for type_id in order.troops:
				var count := mini(int(order.troops[type_id]), int(left.get(type_id, 0)))
				if count > 0:
					troops[type_id] = count
					left[type_id] -= count
			wanted.append(troops)
		var home_left := Orders.total(left)
		if list.size() == 1 and home_left == 0:
			ctx.plan[unit] = _plan_entry(list[0], wanted[0])
			continue
		# If nobody stays home, the army itself leads the largest detachment.
		var leader := -1
		if home_left == 0:
			for i in wanted.size():
				if leader < 0 or Orders.total(wanted[i]) > Orders.total(wanted[leader]):
					leader = i
		var parts := []
		var looks := {}
		for i in list.size():
			if i == leader or Orders.total(wanted[i]) <= 0:
				continue
			var part := unit.split(wanted[i])
			state.register(part)
			part.reset_turn()
			ctx.group[part] = unit
			ctx.plan[part] = _plan_entry(list[i], wanted[i])
			parts.append(part)
			looks[part] = look(part)
		if parts.is_empty() and leader >= 0:
			ctx.plan[unit] = _plan_entry(list[leader], wanted[leader])
			continue
		unit.moved = true  # Reorganising: an army that splits doesn't also rest and heal this turn.
		ctx.group[unit] = unit
		if leader >= 0:
			ctx.plan[unit] = _plan_entry(list[leader], wanted[leader])
		looks[unit] = look(unit)
		events.append({"type": "split", "unit": unit, "parts": parts, "province": unit.province, "hp": looks})
	return events


static func _plan_entry(order: Dictionary, troops: Dictionary) -> Dictionary:
	var entry := {"steps": order.steps.duplicate(true), "support": order.get("support", false)}
	if order.has("attackers"):
		var attackers := {}
		for type_id in order.attackers:
			var count := mini(int(order.attackers[type_id]), int(troops.get(type_id, 0)))
			if count > 0:
				attackers[type_id] = count
		entry["attackers"] = attackers
	return entry


# --- 1. Moves ----------------------------------------------------------------------------

static func _moves(state: GameState, steps: Dictionary, ctx: Dictionary) -> Array:
	var events := []
	var pending: Array[Unit] = []
	for unit: Unit in _by_strength(steps.keys()):
		if steps[unit].type == "move" and state.units.has(unit) and not ctx.stopped.has(unit):
			pending.append(unit)
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		# Swaps: two armies (or detachments) each alone in its region trade places.
		for unit in pending.duplicate():
			if not pending.has(unit):
				continue
			var other := state.unit_in(steps[unit].target)
			if other != null and other.owner == unit.owner and pending.has(other) and steps[other].target == unit.province \
					and state.units_in(unit.province).size() == 1 and state.units_in(other.province).size() == 1:
				var here: String = unit.province
				unit.province = other.province
				other.province = here
				for moved in [unit, other]:
					moved.moved = true
					ctx.entered.append({"region": moved.province, "faction": moved.owner, "from": other.province if moved == unit else unit.province})
					pending.erase(moved)
				events.append({"type": "swapped", "unit": unit, "other": other, "province": unit.province, "from": other.province})
				progress = true
		# Moves into empty regions, or into an army of ours that stays.
		for unit in pending.duplicate():
			var target: String = steps[unit].target
			var occupant := state.unit_in(target)
			if occupant == null:
				pending.erase(unit)
				_enter(state, unit, target, ctx, events, "move")
				progress = true
			elif occupant.owner == unit.owner and not pending.has(occupant) and _may_merge(state, occupant, unit, ctx):
				pending.erase(unit)
				_merge_in(state, occupant, unit, events, ctx)
				progress = true
	for unit in pending:
		events.append({"type": "blocked", "unit": unit, "province": steps[unit].target, "reason": "the region was not free"})
		ctx.stopped[unit] = true
	return events


# --- 2. Sieges and attacks ------------------------------------------------------------------

static func _attacks(state: GameState, steps: Dictionary, ctx: Dictionary, wave: int) -> Array:
	var events := []
	for unit: Unit in _by_id(steps.keys()):
		if steps[unit].type == "besiege" and state.units.has(unit) and not ctx.stopped.has(unit):
			if Sieges.besiege(state, [unit], steps[unit].target):
				events.append({"type": "besieged", "unit": unit, "province": steps[unit].target})
			ctx.stopped[unit] = true
	# Each plain attack with the supports that join it is one battle (PRD B).
	var groups := {}  # leader -> [attackers]
	var by_target := {}
	for unit: Unit in _by_id(steps.keys()):
		if steps[unit].type != "attack" or not state.units.has(unit) or ctx.stopped.has(unit):
			continue
		by_target.get_or_add(steps[unit].target, []).append(unit)
	var battles := []
	for target in _sorted_keys(by_target):
		var mains: Array = by_target[target].filter(func(u): return not ctx.plan[u].support)
		var supports: Array = by_target[target].filter(func(u): return ctx.plan[u].support)
		if mains.is_empty():
			mains = [supports.pop_front()]
		for main in mains:
			groups[main] = [main]
		for support in supports:
			groups[mains[0]].append(support)
		for main in mains:
			battles.append([target, groups[main]])
	# Volleys first, then the strongest attacks.
	battles.sort_custom(func(a, b):
		var ranged_a := _ranged_only(a[1], ctx)
		var ranged_b := _ranged_only(b[1], ctx)
		if ranged_a != ranged_b:
			return ranged_a
		var power_a := _group_power(a[1])
		var power_b := _group_power(b[1])
		return power_a > power_b or (power_a == power_b and a[1][0].id < b[1][0].id))
	for entry in battles:
		events.append_array(_battle(state, entry[0], entry[1], ctx))
	return events


static func _ranged_only(group: Array, ctx: Dictionary) -> bool:
	return group.all(func(u: Unit): return Orders.all_ranged(ctx.plan[u].get("attackers", u.composition())))


static func _group_power(group: Array) -> float:
	var total := 0.0
	for unit: Unit in group:
		total += unit.power()
	return total


## One battle: `group` attacks `target` together.
static func _battle(state: GameState, target: String, group: Array, ctx: Dictionary) -> Array:
	var events := []
	var faction: String = ctx.faction
	var attackers: Array[Unit] = []  # The soldiers actually fighting.
	var homes := {}  # fighting part -> the army it came from
	var supporting := {}  # parts that fight from home and never move in
	for unit: Unit in group:
		if not state.units.has(unit):
			continue
		ctx.stopped[unit] = true
		unit.attacked = true
		var part := unit
		var wanted: Dictionary = ctx.plan[unit].get("attackers", {})
		if not wanted.is_empty() and Orders.total(wanted) < unit.soldiers():
			part = unit.split(wanted)
			state.register(part)
			part.attacked = true
		homes[part] = unit
		attackers.append(part)
		if unit != group[0] and ctx.plan[unit].support:
			supporting[part] = true
	if attackers.is_empty():
		return events
	var occupant := state.unit_in(target)
	if occupant == null or occupant.owner == faction:
		# The defenders are gone: the melee soldiers walk in.
		for part in attackers:
			if supporting.has(part):
				_rejoin(state, homes[part], part, events)
			elif occupant == null and part.has_melee():
				_enter(state, part, target, ctx, events, "advance")
				occupant = part
			elif occupant != null and occupant.owner == faction and part != occupant and part.has_melee() and _may_merge(state, occupant, part, ctx):
				_merge_in(state, occupant, part, events, ctx)
			else:
				_rejoin(state, homes[part], part, events)
		return events
	var ranged_only := attackers.all(func(u: Unit): return u.all_ranged())
	var sent: int = attackers.reduce(func(sum, u): return sum + u.soldiers(), 0)
	var forces := state.forces(attackers, [occupant] as Array[Unit], target, false)
	forces[0].hit_and_run = attackers.all(func(u: Unit): return u.troops.all(func(t: Troop): return t.type().skirmisher))
	var battle := Battle.new(forces[0], forces[1], state.map.terrain(target), state.crosses_river(attackers, target), state.rng.randi())
	battle.resolve()
	state.record_losses(battle)
	var origin: String = group[0].province
	var looks := {}
	for part in attackers:
		part.cleanup()
	occupant.cleanup()
	for part in attackers:
		var home: Unit = homes[part]
		var both := look(part)
		if home != part and state.units.has(home):
			var at_home := look(home)
			both = {"soldiers": both.soldiers + at_home.soldiers, "hp": both.hp + at_home.hp, "full": both.full + at_home.full}
		looks[home] = both
	looks[occupant] = look(occupant)
	var supports := []
	for unit in group.slice(1):
		supports.append({"unit": unit, "origin": unit.province})
	events.append({"type": "volley" if ranged_only else "battle", "kind": "volley" if ranged_only else "assault", "battle": battle,
		"unit": group[0], "other": occupant, "origin": origin, "province": target, "supports": supports,
		"soldiers": sent, "hp": looks})
	for part in attackers:
		if part.is_destroyed():
			events.append_array(state.destroy(part, "was destroyed", occupant.owner))
	if occupant.is_destroyed():
		events.append_array(state.destroy(occupant, "was destroyed", faction))
	elif battle.attacker_won():
		var refuge := state.retreat_region(occupant, target)
		if refuge == "":
			events.append_array(state.destroy(occupant, "had nowhere to retreat", faction))
		else:
			events.append({"type": "retreated", "unit": occupant, "from": target, "province": refuge})
			occupant.province = refuge
	var holder: Unit = null
	for part in _by_size(attackers):
		if not state.units.has(part):
			continue
		var home: Unit = homes[part]
		if supporting.has(part):
			_rejoin(state, home, part, events)
		elif battle.attacker_won() and part.has_melee() and state.unit_in(target) == null:
			_enter(state, part, target, ctx, events, "advance")
			events.back()["main"] = home
			holder = part
		elif battle.attacker_won() and holder != null and part.has_melee() and _may_merge(state, holder, part, ctx):
			_merge_in(state, holder, part, events, ctx)
			if state.units.has(part):
				_rejoin(state, home, part, events)
		else:
			if not ranged_only and not battle.attacker_won():
				events.append({"type": "repulsed", "unit": home, "province": home.province, "target": target})
			_rejoin(state, home, part, events)
	return events


# --- 3. Captures and 4. end of turn -----------------------------------------------------------

static func _captures(state: GameState, ctx: Dictionary) -> Array:
	var events := []
	for entry in ctx.entered:
		var region: String = entry.region
		var holder := state.unit_in(region)
		if state.factions.has(entry.faction) and state.owners[region] != entry.faction \
				and (holder == null or holder.owner == entry.faction):
			events.append_array(state.capture(entry.faction, region, entry.from))
	return events


static func _end_of_turn(state: GameState, faction: String) -> Array:
	var events := []
	events.append_array(Economy.process_faction(state, faction))
	events.append_array(Sieges.advance(state, faction))
	Mission.end_of_turn(state, faction)
	for unit in state.units.duplicate():
		unit.cleanup()
		if unit.is_destroyed():
			state.remove_unit(unit)
	state.update_alive()
	return events


# --- Helpers ------------------------------------------------------------------------------------

## A detachment goes back to its army and merges with it again.
static func _rejoin(state: GameState, unit: Unit, part: Unit, events: Array) -> void:
	if part == unit or not state.units.has(part):
		return
	if state.units.has(unit) and unit.province == part.province:
		_join(state, unit, part)
		events.append({"type": "rejoined", "unit": unit, "part": part, "province": unit.province, "hp": look(unit)})


## Merges a detachment back into its army, up to Unit.CAP. If the army took
## others in meanwhile, those who don't fit are left to _one_per_region.
static func _join(state: GameState, unit: Unit, part: Unit) -> void:
	unit.attacked = unit.attacked or part.attacked
	unit.moved = unit.moved or part.moved
	if unit.soldiers() + part.soldiers() <= Unit.CAP:
		unit.absorb(part)
		state.remove_unit(part)
	else:
		state.merge(unit, part)


## Whether `unit` may merge into `target`: the same faction, with room left.
## Orders.room planned for it, counting the soldiers who left.
static func _may_merge(state: GameState, target: Unit, unit: Unit, _ctx: Dictionary) -> bool:
	return state.merge_problem(target, unit) == ""


## Detachments of the same army that end the turn in the same region join up.
static func _reunite(state: GameState, ctx: Dictionary) -> Array:
	var events := []
	var by_place := {}
	for unit: Unit in _by_id(ctx.group.keys()):
		if state.units.has(unit):
			var key := "%d/%s" % [ctx.group[unit].id, unit.province]
			by_place.get_or_add(key, []).append(unit)
	for key in _sorted_keys(by_place):
		var members: Array = by_place[key]
		if members.size() < 2:
			continue
		var origin: Unit = null
		for member: Unit in members:
			if ctx.group[member] == member:
				origin = member
		var keeper: Unit = origin if origin != null else members[0]
		for member: Unit in members:
			if member == keeper or not state.units.has(member):
				continue
			_join(state, keeper, member)
			events.append({"type": "rejoined", "unit": keeper, "part": member, "province": keeper.province, "hp": look(keeper)})
	return events


## A last guard for UT-3: if two armies ever end in one region, the same
## faction's merge (up to the cap); otherwise, or with soldiers left over, the
## newer army falls back to a free region of its own, or is lost.
static func _one_per_region(state: GameState) -> Array:
	var events := []
	var seen := {}
	for unit: Unit in _by_id(state.units.duplicate()):
		if not state.units.has(unit):
			continue
		var first: Unit = seen.get(unit.province)
		if first == null:
			seen[unit.province] = unit
			continue
		if first.owner == unit.owner and state.merge_problem(first, unit) == "":
			state.merge(first, unit)
			events.append({"type": "rejoined", "unit": first, "part": unit, "province": first.province, "hp": look(first), "crowded": true})
			if not state.units.has(unit):
				continue
		var refuge := state.retreat_region(unit, unit.province)
		if refuge == "":
			events.append_array(state.destroy(unit, "had no room"))
		else:
			events.append({"type": "retreated", "unit": unit, "from": unit.province, "province": refuge, "crowded": true})
			unit.province = refuge
			seen[refuge] = unit
	return events


static func _enter(state: GameState, unit: Unit, region: String, ctx: Dictionary, events: Array, how: String) -> void:
	var from := unit.province
	ctx.entered.append({"region": region, "faction": unit.owner, "from": from})
	unit.province = region
	unit.moved = true
	events.append({"type": "moved", "unit": unit, "from": from, "province": region, "how": how})


## Merges `unit` into `target` (compositions add up to Unit.CAP). Soldiers
## that don't fit stay where they were.
static func _merge_in(state: GameState, target: Unit, unit: Unit, events: Array, ctx: Dictionary) -> void:
	var from := unit.province
	var moved := state.merge(target, unit)
	unit.moved = true
	target.moved = true  # Reorganising: the merged army doesn't also rest and heal this turn.
	ctx.entered.append({"region": target.province, "faction": unit.owner, "from": from})
	events.append({"type": "merged", "unit": unit, "into": target, "from": from, "province": target.province, "soldiers": moved,
		"hp": look(target)})
	if state.units.has(unit):
		events.append({"type": "blocked", "unit": unit, "province": target.province, "reason": "only %d soldiers fitted" % moved})
		ctx.stopped[unit] = true


static func _by_id(units: Array) -> Array[Unit]:
	var sorted: Array[Unit] = []
	sorted.assign(units)
	sorted.sort_custom(func(a: Unit, b: Unit): return a.id < b.id)
	return sorted


## Largest first, ties by id.
static func _by_size(units: Array) -> Array[Unit]:
	var sorted: Array[Unit] = []
	sorted.assign(units)
	sorted.sort_custom(func(a: Unit, b: Unit): return a.soldiers() > b.soldiers() or (a.soldiers() == b.soldiers() and a.id < b.id))
	return sorted


## Strongest first, ties by id, so resolution never depends on dictionary order.
static func _by_strength(units: Array) -> Array[Unit]:
	var sorted: Array[Unit] = []
	sorted.assign(units)
	sorted.sort_custom(func(a: Unit, b: Unit): return a.power() > b.power() or (a.power() == b.power() and a.id < b.id))
	return sorted


static func _sorted_keys(dictionary: Dictionary) -> Array:
	var keys := dictionary.keys()
	keys.sort()
	return keys
