class_name Resolver
extends RefCounted
## Carries out every faction's orders together when the hourglass is pressed
## (PRD 8.3, 8.4), always in the same order, with the game's seeded dice:
##   0. units with several orders, or an order for only some soldiers, split
##      into detachments: the soldiers with no order stay home as the unit;
##      if everyone goes, the unit itself leads the
##      largest detachment. HP is shared out per soldier;
##   1. ranged volleys;
##   2. head-on attacks (A attacks B while B attacks A) become one field battle;
##   3. moves into empty or friendly regions, with swaps and merges; units of
##      different factions moving into the same empty region fight for it;
##   4. sieges, then attacks on occupied regions; several attackers on one
##      region fight one after another, strongest first;
##   5. detachments that end the turn back home (failed, blocked or only
##      shooting) rejoin their unit; then captures: a region a unit of another
##      faction entered this turn, and still holds (or rode through, empty),
##      changes hands;
##   6. the economy and end-of-turn upkeep.
## Steps 1-4 run once for every detachment's first step and again for
## cavalry's second step. A detachment that moves into an empty region, or
## wins an attack and finds the region empty, stays there as a new unit.
## Returns the events in the order they happened, for the animations.


static func resolve(state: GameState) -> Array:
	var events := []
	var plan := {}
	# group: each detachment -> the unit it split from; homes: region -> that unit.
	var ctx := {"plan": plan, "stopped": {}, "came_from": {}, "entered": [], "group": {}, "homes": {}}
	events.append_array(_split(state, ctx))
	for wave in Orders.CAVALRY_STEPS:
		var steps := {}
		for unit in _by_id(plan.keys()):
			if state.units.has(unit) and not ctx.stopped.has(unit) and plan[unit].steps.size() > wave:
				steps[unit] = plan[unit].steps[wave]
		if steps.is_empty():
			break
		events.append_array(_volleys(state, steps, ctx))
		events.append_array(_head_on(state, steps, ctx))
		events.append_array(_moves(state, steps, ctx))
		events.append_array(_attacks(state, steps, ctx))
	events.append_array(_reunite(state, ctx))
	events.append_array(_one_per_region(state))
	events.append_array(_captures(state, ctx))
	events.append_array(_end_of_turn(state))
	return events


# --- 0. Detachments ------------------------------------------------------------------

## Turns each unit's orders into detachments, each a unit with one order.
## A unit whose single order sends everyone simply carries it out itself.
static func _split(state: GameState, ctx: Dictionary) -> Array:
	var events := []
	for unit in _by_id(state.orders.keys()):
		if not state.units.has(unit):
			continue
		var list: Array = state.orders[unit]
		var total := unit.soldiers()
		var sizes := []
		var left := total
		for order in list:
			var size := clampi(int(order.get("size", total)), 0, left)
			sizes.append(size)
			left -= size
		if list.is_empty() or total <= 0:
			continue
		if list.size() == 1 and sizes[0] >= total:
			ctx.plan[unit] = _plan_entry(list[0], total)
			continue
		# If nobody stays home, the unit itself leads the largest detachment.
		var leader := -1
		if left <= 0:
			for i in sizes.size():
				if leader < 0 or sizes[i] > sizes[leader]:
					leader = i
		var per_soldier := unit.hp / total
		var floor_hp := _floor_hp(unit)
		var parts := []
		var hp := {}
		var given := 0.0
		for i in list.size():
			if i == leader or sizes[i] <= 0:
				continue
			var part := state.add_unit(unit.type_id, unit.owner, unit.province)
			part.hp = maxf(per_soldier * sizes[i], floor_hp)
			part.coastal_moves = unit.coastal_moves
			given += part.hp
			ctx.group[part] = unit
			ctx.plan[part] = _plan_entry(list[i], sizes[i])
			parts.append(part)
			hp[part] = part.hp
		if parts.is_empty() and leader >= 0:
			ctx.plan[unit] = _plan_entry(list[leader], total)
			continue
		unit.hp = maxf(unit.hp - given, floor_hp)
		unit.moved = true  # Reorganising: a unit that splits doesn't also rest and heal this turn.
		ctx.group[unit] = unit
		ctx.homes[unit.province] = unit
		if leader >= 0:
			ctx.plan[unit] = _plan_entry(list[leader], sizes[leader])
		hp[unit] = unit.hp
		events.append({"type": "split", "unit": unit, "parts": parts, "province": unit.province, "hp": hp})
	return events


static func _plan_entry(order: Dictionary, size: int) -> Dictionary:
	return {"steps": order.steps.duplicate(true), "soldiers": mini(int(order.get("soldiers", size)), size),
		"shoot": mini(int(order.get("shoot", 0)), size)}


# --- 1. Volleys --------------------------------------------------------------------

static func _volleys(state: GameState, steps: Dictionary, ctx: Dictionary) -> Array:
	var events := []
	for unit: Unit in _by_id(steps.keys()):
		var step: Dictionary = steps[unit]
		var shoot: int = ctx.plan[unit].get("shoot", 0)
		if step.type != "attack" or not unit.type().is_ranged() or shoot <= 0 or not state.units.has(unit):
			continue
		var target: String = step.target
		var defender := state.unit_in(target)
		if defender == null or not state.is_enemy(unit.owner, defender.owner):
			events.append({"type": "volley_missed", "unit": unit, "origin": unit.province, "province": target})
			continue
		var shooters := _detach(state, unit, shoot)
		var forces := state.forces([shooters] as Array[Unit], [defender] as Array[Unit], target, false)
		forces[0].hit_and_run = unit.type().skirmisher
		var battle := Battle.new(forces[0], forces[1], state.map.terrain(target), false, state.rng.randi())
		battle.resolve()
		state.record_losses(battle)
		unit.attacked = true
		events.append({"type": "volley", "battle": battle, "unit": unit, "origin": unit.province, "province": target, "shooters": shoot,
			"hp": _hp_after([[unit, shooters], [defender, defender]])})
		events.append_array(_remove_destroyed(state, [shooters, defender]))
		_rejoin(state, unit, shooters, events)
		if int(ctx.plan[unit].get("soldiers", 0)) <= 0 or not state.map.are_neighbours(unit.province, target):
			ctx.stopped[unit] = true
	return events


# --- 2. Head-on attacks ---------------------------------------------------------------

static func _head_on(state: GameState, steps: Dictionary, ctx: Dictionary) -> Array:
	var events := []
	for a: Unit in _by_id(steps.keys()):
		if not _melee_attack(state, a, steps, ctx):
			continue
		var target: String = steps[a].target
		var b: Unit = null
		for other in state.units_in(target):
			if steps.has(other) and _melee_attack(state, other, steps, ctx) and steps[other].target == a.province:
				b = other
				break
		if b == null:
			continue
		var origin_a := a.province
		var origin_b := b.province
		var part_a := _detach(state, a, int(ctx.plan[a].soldiers))
		var part_b := _detach(state, b, int(ctx.plan[b].soldiers))
		var forces := state.forces([part_a] as Array[Unit], [part_b] as Array[Unit], target, false, true)
		var battle := Battle.new(forces[0], forces[1], Rules.terrains.plains, false, state.rng.randi())
		battle.resolve()
		state.record_losses(battle)
		a.attacked = true
		b.attacked = true
		ctx.stopped[a] = true
		ctx.stopped[b] = true
		events.append({"type": "battle", "kind": "head_on", "battle": battle, "unit": a, "other": b,
			"origin": origin_a, "province": origin_b, "hp": _hp_after([[a, part_a], [b, part_b]])})
		events.append_array(_remove_destroyed(state, [part_a, part_b]))
		# The winner moves into the loser's region only if the loser is gone from it.
		var winner := part_a if battle.attacker_won() else (part_b if battle.winner == "defender" and battle.ending != "held" else null)
		for pair in [[part_a, a, origin_a, origin_b], [part_b, b, origin_b, origin_a]]:
			var part: Unit = pair[0]
			if not state.units.has(part):
				continue
			if part == winner and state.unit_in(pair[3]) == null:
				_enter(state, part, pair[3], ctx, events, "advance")
			else:
				_rejoin(state, pair[1], part, events)
	return events


static func _melee_attack(state: GameState, unit: Unit, steps: Dictionary, ctx: Dictionary) -> bool:
	if not state.units.has(unit) or ctx.stopped.has(unit) or steps[unit].type != "attack":
		return false
	if unit.type().is_ranged():
		return int(ctx.plan[unit].get("soldiers", 0)) > 0 and state.map.are_neighbours(unit.province, steps[unit].target)
	return true


# --- 3. Moves ----------------------------------------------------------------------------

static func _moves(state: GameState, steps: Dictionary, ctx: Dictionary) -> Array:
	var events := []
	var pending: Array[Unit] = []
	for unit: Unit in _by_strength(steps.keys()):
		if steps[unit].type == "move" and state.units.has(unit) and not ctx.stopped.has(unit):
			pending.append(unit)
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		# Swaps: two of a faction's units trade places.
		for unit in pending.duplicate():
			if not pending.has(unit):
				continue
			var other := state.unit_in(steps[unit].target)
			# A unit that split this turn shares its region with its detachments: it can't swap.
			if other != null and other.owner == unit.owner and pending.has(other) and steps[other].target == unit.province \
					and not ctx.group.has(unit) and not ctx.group.has(other):
				var here: String = unit.province
				unit.province = other.province
				other.province = here
				for moved in [unit, other]:
					moved.moved = true
					ctx.came_from[moved] = other.province if moved == unit else unit.province
					ctx.entered.append({"region": moved.province, "faction": moved.owner, "from": ctx.came_from[moved]})
					pending.erase(moved)
				events.append({"type": "swapped", "unit": unit, "other": other, "province": unit.province, "from": other.province})
				progress = true
		# Moves into empty regions, with contests between factions.
		var by_target := {}
		for unit in pending:
			var target: String = steps[unit].target
			if state.unit_in(target) == null:
				by_target.get_or_add(target, []).append(unit)
		for target in _sorted_keys(by_target):
			var contenders: Array = by_target[target]
			var champion: Unit = contenders[0]
			for other: Unit in contenders.slice(1):
				if other.owner == champion.owner:
					continue
				events.append_array(_contest(state, champion, other, target, ctx))
				if not state.units.has(champion) or ctx.stopped.has(champion):
					champion = other if state.units.has(other) and not ctx.stopped.has(other) else null
				if champion == null:
					break
			for unit: Unit in contenders:
				pending.erase(unit)
				if not state.units.has(unit) or ctx.stopped.has(unit) and unit != champion:
					continue
				if unit == champion:
					_enter(state, unit, target, ctx, events, "move")
				elif champion != null and unit.owner == champion.owner and _may_merge(state, champion, unit, ctx):
					_merge_in(state, champion, unit, events)
				else:
					events.append({"type": "blocked", "unit": unit, "province": target, "reason": "the region was taken first"})
					ctx.stopped[unit] = true
			progress = true
		# Moves into a region held by the same unit type: merge.
		for unit in pending.duplicate():
			var occupant := state.unit_in(steps[unit].target)
			if occupant != null and occupant.owner == unit.owner and not pending.has(occupant) and _may_merge(state, occupant, unit, ctx):
				pending.erase(unit)
				_merge_in(state, occupant, unit, events)
				progress = true
	for unit in pending:
		events.append({"type": "blocked", "unit": unit, "province": steps[unit].target, "reason": "the region was not free"})
		ctx.stopped[unit] = true
	return events


## Two units of different factions moving into the same empty region fight for
## it in the field. The loser stays where it came from.
static func _contest(state: GameState, champion: Unit, rival: Unit, region: String, ctx: Dictionary) -> Array:
	var events := []
	var forces := state.forces([rival] as Array[Unit], [champion] as Array[Unit], region, false, true)
	var battle := Battle.new(forces[0], forces[1], state.map.terrain(region), false, state.rng.randi())
	battle.resolve()
	state.record_losses(battle)
	champion.attacked = true
	rival.attacked = true
	events.append({"type": "battle", "kind": "contest", "battle": battle, "unit": rival, "other": champion,
		"origin": rival.province, "province": region, "hp": _hp_after([[rival, rival], [champion, champion]])})
	events.append_array(_remove_destroyed(state, [rival, champion]))
	var loser := champion if battle.attacker_won() else rival
	if state.units.has(loser):
		ctx.stopped[loser] = true
		events.append({"type": "repulsed", "unit": loser, "province": loser.province, "target": region})
	return events


# --- 4. Sieges and attacks ------------------------------------------------------------------

static func _attacks(state: GameState, steps: Dictionary, ctx: Dictionary) -> Array:
	var events := []
	for unit: Unit in _by_id(steps.keys()):
		if steps[unit].type == "besiege" and state.units.has(unit) and not ctx.stopped.has(unit):
			if Sieges.besiege(state, [unit], steps[unit].target):
				events.append({"type": "besieged", "unit": unit, "province": steps[unit].target})
			ctx.stopped[unit] = true
	var by_target := {}
	for unit: Unit in _by_strength(steps.keys()):
		if _melee_attack(state, unit, steps, ctx):
			by_target.get_or_add(steps[unit].target, []).append(unit)
	for target in _sorted_keys(by_target):
		for attacker: Unit in by_target[target]:
			if not state.units.has(attacker):
				continue
			ctx.stopped[attacker] = true
			attacker.attacked = true
			var origin := attacker.province
			var occupant := state.unit_in(target)
			if occupant != null and occupant.owner == attacker.owner:
				continue
			var part := _detach(state, attacker, int(ctx.plan[attacker].get("soldiers", attacker.soldiers())))
			if occupant == null:
				_enter(state, part, target, ctx, events, "advance")
				continue
			var forces := state.forces([part] as Array[Unit], [occupant] as Array[Unit], target, false)
			var battle := Battle.new(forces[0], forces[1], state.map.terrain(target), state.crosses_river([part] as Array[Unit], target), state.rng.randi())
			battle.resolve()
			state.record_losses(battle)
			events.append({"type": "battle", "kind": "assault", "battle": battle, "unit": attacker, "other": occupant,
				"origin": origin, "province": target, "soldiers": part.soldiers(), "hp": _hp_after([[attacker, part], [occupant, occupant]])})
			events.append_array(_remove_destroyed(state, [part, occupant]))
			if battle.attacker_won() and state.units.has(occupant):
				var refuge := state.retreat_region(occupant, target)
				if refuge == "":
					events.append_array(state.destroy(occupant, "had nowhere to retreat"))
				else:
					events.append({"type": "retreated", "unit": occupant, "from": target, "province": refuge})
					occupant.province = refuge
			if not state.units.has(part):
				continue
			if battle.attacker_won() and state.unit_in(target) == null:
				_enter(state, part, target, ctx, events, "advance")
				events.back()["main"] = attacker
			else:
				events.append({"type": "repulsed", "unit": attacker, "province": origin, "target": target})
				_rejoin(state, attacker, part, events)
	return events


# --- 5. Captures and 6. end of turn -----------------------------------------------------------

static func _captures(state: GameState, ctx: Dictionary) -> Array:
	var events := []
	for entry in ctx.entered:
		var region: String = entry.region
		var holder := state.unit_in(region)
		if state.factions.has(entry.faction) and state.owners[region] != entry.faction \
				and (holder == null or holder.owner == entry.faction):
			events.append_array(state.capture(entry.faction, region, entry.from))
	return events


static func _end_of_turn(state: GameState) -> Array:
	var events := []
	for faction in state.living_factions():
		events.append_array(Economy.process_faction(state, faction))
		events.append_array(Sieges.advance(state, faction))
		Mission.end_of_turn(state, faction)
	for unit in state.units.duplicate():
		if unit.is_destroyed():
			state.remove_unit(unit)
	state.update_alive()
	return events


# --- Helpers ------------------------------------------------------------------------------------

## Splits `soldiers` off a unit into a detachment in the same region, or returns
## the unit itself when it sends everyone. HP is shared out per soldier.
static func _detach(state: GameState, unit: Unit, soldiers: int) -> Unit:
	if soldiers >= unit.soldiers() or soldiers <= 0:
		return unit
	var part := state.add_unit(unit.type_id, unit.owner, unit.province)
	var floor_hp := _floor_hp(unit)
	part.hp = maxf(unit.hp * soldiers / unit.soldiers(), floor_hp)
	part.attacked = true
	unit.hp = maxf(unit.hp - part.hp, floor_hp)
	return part


## The least HP a detachment gets: just one soldier, so it isn't destroyed
## (Unit.DESTROYED_BELOW) and doesn't count as two.
static func _floor_hp(unit: Unit) -> float:
	return unit.max_hp() * Unit.DESTROYED_BELOW * (1.0 + 1e-5)


## A detachment goes back to its unit and merges with it again.
static func _rejoin(state: GameState, unit: Unit, part: Unit, events: Array) -> void:
	if part == unit or not state.units.has(part):
		return
	if state.units.has(unit):
		_join(state, unit, part)
		events.append({"type": "rejoined", "unit": unit, "part": part, "province": unit.province, "hp": unit.hp})
	elif state.unit_in(part.province) != part:
		events.append_array(state.destroy(part, "was cut off"))


## Merges a detachment back into its unit, keeping their HP (a merge of two
## different units rounds up to whole soldiers instead, UT-8).
## They always fit: both came out of one unit and HP never grows in a turn.
static func _join(state: GameState, unit: Unit, part: Unit) -> void:
	unit.attacked = unit.attacked or part.attacked
	unit.moved = unit.moved or part.moved
	var hp := unit.hp + part.hp
	if hp > unit.max_hp() * 1.0001 or unit.owner != part.owner or unit.type_id != part.type_id:
		state.merge(unit, part)  # Not one unit's soldiers after all: a normal merge, up to 20.
		return
	unit.hp = minf(hp, unit.max_hp())
	state.remove_unit(part)


## Whether `unit` may merge into `target`. A unit that split this turn takes in
## only its own detachments, so they always fit when they come home.
static func _may_merge(state: GameState, target: Unit, unit: Unit, ctx: Dictionary) -> bool:
	if state.merge_problem(target, unit) != "":
		return false
	if ctx.group.has(target) and ctx.homes.get(target.province) == ctx.group[target]:
		return ctx.group.get(unit) == ctx.group[target]
	return true


## Detachments of the same unit that end the turn in the same region (back
## home after a failed attack, a blocked march, or a volley) join up again.
## If the unit itself is gone, the first of them becomes the unit there.
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
			events.append({"type": "rejoined", "unit": keeper, "part": member, "province": keeper.province, "hp": keeper.hp})
	return events


## A last guard for UT-3: if two units ever end in one region, the same type
## merges; otherwise the newer unit falls back to a free region of its own,
## or is lost.
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
		if first.owner == unit.owner and state.merge_problem(first, unit) == "" and first.soldiers() + unit.soldiers() <= UnitType.SOLDIERS:
			_join(state, first, unit)
			events.append({"type": "rejoined", "unit": first, "part": unit, "province": first.province, "hp": first.hp, "crowded": true})
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
	ctx.came_from[unit] = from
	ctx.entered.append({"region": region, "faction": unit.owner, "from": from})
	unit.province = region
	unit.moved = true
	events.append({"type": "moved", "unit": unit, "from": from, "province": region, "how": how})


static func _merge_in(state: GameState, target: Unit, unit: Unit, events: Array) -> void:
	var from := unit.province
	var moved := state.merge(target, unit)
	unit.moved = true
	target.moved = true  # Reorganising: the merged unit doesn't also rest and heal this turn.
	events.append({"type": "merged", "unit": unit, "into": target, "from": from, "province": target.province, "soldiers": moved})


## Each unit's HP right after a fight, counting a detachment with its unit,
## so the animation can drain the bars to the right place: {Unit: hp}.
static func _hp_after(pairs: Array) -> Dictionary:
	var hp := {}
	for pair in pairs:
		var unit: Unit = pair[0]
		var part: Unit = pair[1]
		hp[unit] = maxf(unit.hp, 0.0) + (maxf(part.hp, 0.0) if part != unit else 0.0)
	return hp


static func _remove_destroyed(state: GameState, units: Array) -> Array:
	var events := []
	for unit: Unit in units:
		if state.units.has(unit) and unit.is_destroyed():
			events.append_array(state.destroy(unit, "was destroyed"))
	return events


static func _by_id(units: Array) -> Array[Unit]:
	var sorted: Array[Unit] = []
	sorted.assign(units)
	sorted.sort_custom(func(a: Unit, b: Unit): return a.id < b.id)
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
