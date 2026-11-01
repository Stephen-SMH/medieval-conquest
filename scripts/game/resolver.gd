class_name Resolver
extends RefCounted
## Carries out every faction's orders together when the hourglass is pressed
## (PRD 8.3, 8.4), always in the same order, with the game's seeded dice:
##   1. ranged volleys;
##   2. head-on attacks (A attacks B while B attacks A) become one field battle;
##   3. moves into empty or friendly regions, with swaps and merges; units of
##      different factions moving into the same empty region fight for it;
##   4. sieges, then attacks on occupied regions; several attackers on one
##      region fight one after another, strongest first;
##   5. captures: a region a unit of another faction entered this turn, and
##      still holds (or rode through, empty), changes hands;
##   6. the economy and end-of-turn upkeep.
## Steps 1-4 run once for every unit's first step and again for cavalry's
## second step. An attack that sends only part of a unit fights with a
## detachment, which rejoins its unit afterwards unless it took the region.
## Returns the events in the order they happened, for the animations.


static func resolve(state: GameState) -> Array:
	var events := []
	var plan := {}
	for unit in state.orders:
		if state.units.has(unit):
			plan[unit] = state.orders[unit].duplicate(true)
	var ctx := {"plan": plan, "stopped": {}, "came_from": {}, "entered": []}
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
	events.append_array(_captures(state, ctx))
	events.append_array(_end_of_turn(state))
	return events


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
		unit.attacked = true
		events.append({"type": "volley", "battle": battle, "unit": unit, "origin": unit.province, "province": target, "shooters": shoot,
			"hp": _hp_after([[unit, shooters], [defender, defender]])})
		_award_xp([shooters, defender], battle)
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
		var b := state.unit_in(target)
		if b == null or not steps.has(b) or not _melee_attack(state, b, steps, ctx) or steps[b].target != a.province:
			continue
		var origin_a := a.province
		var origin_b := b.province
		var part_a := _detach(state, a, int(ctx.plan[a].soldiers))
		var part_b := _detach(state, b, int(ctx.plan[b].soldiers))
		var forces := state.forces([part_a] as Array[Unit], [part_b] as Array[Unit], target, false, true)
		var battle := Battle.new(forces[0], forces[1], Rules.terrains.plains, false, state.rng.randi())
		battle.resolve()
		a.attacked = true
		b.attacked = true
		ctx.stopped[a] = true
		ctx.stopped[b] = true
		events.append({"type": "battle", "kind": "head_on", "battle": battle, "unit": a, "other": b,
			"origin": origin_a, "province": origin_b, "hp": _hp_after([[a, part_a], [b, part_b]])})
		_award_xp([part_a, part_b], battle)
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
			if other != null and other.owner == unit.owner and pending.has(other) and steps[other].target == unit.province:
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
				elif champion != null and unit.owner == champion.owner and state.merge_problem(champion, unit) == "":
					_merge_in(state, champion, unit, events)
				else:
					events.append({"type": "blocked", "unit": unit, "province": target, "reason": "the region was taken first"})
					ctx.stopped[unit] = true
			progress = true
		# Moves into a region held by the same unit type: merge.
		for unit in pending.duplicate():
			var occupant := state.unit_in(steps[unit].target)
			if occupant != null and occupant.owner == unit.owner and not pending.has(occupant) and state.merge_problem(occupant, unit) == "":
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
	champion.attacked = true
	rival.attacked = true
	events.append({"type": "battle", "kind": "contest", "battle": battle, "unit": rival, "other": champion,
		"origin": rival.province, "province": region, "hp": _hp_after([[rival, rival], [champion, champion]])})
	_award_xp([rival, champion], battle)
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
			events.append({"type": "battle", "kind": "assault", "battle": battle, "unit": attacker, "other": occupant,
				"origin": origin, "province": target, "soldiers": part.soldiers(), "hp": _hp_after([[attacker, part], [occupant, occupant]])})
			_award_xp([part, occupant], battle)
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
## the unit itself when it sends everyone.
static func _detach(state: GameState, unit: Unit, soldiers: int) -> Unit:
	if soldiers >= unit.soldiers() or soldiers <= 0:
		return unit
	var part := state.add_unit(unit.type_id, unit.owner, unit.province)
	part.set_soldiers(soldiers)
	part.xp = unit.xp
	part.attacked = true
	unit.set_soldiers(unit.soldiers() - soldiers)
	return part


## A detachment goes back to its unit and merges with it again.
static func _rejoin(state: GameState, unit: Unit, part: Unit, events: Array) -> void:
	if part == unit or not state.units.has(part):
		return
	if state.units.has(unit):
		state.merge(unit, part)
		events.append({"type": "rejoined", "unit": unit, "part": part, "province": unit.province})
	elif state.unit_in(part.province) != part:
		events.append_array(state.destroy(part, "was cut off"))


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


static func _award_xp(units: Array, battle: Battle) -> void:
	for unit: Unit in units:
		if not unit.is_destroyed():
			unit.xp += 1
	var winners := battle.attacker if battle.attacker_won() else battle.defender
	if battle.ending != "ranged" and battle.ending != "held":
		for unit in winners.units:
			if not unit.is_destroyed():
				unit.xp += 1


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
