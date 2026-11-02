class_name Battle
extends RefCounted
## An auto-resolved battle between the troops attacking a region (one army's
## detachment, plus any armies supporting the attack) and the troops of the
## army defending it (PRD 3.9, A, B). Every soldier type fights with its own
## stats and the counter table, in three phases:
##   1. Ranged: archers, crossbowmen and catapults shoot RANGED_VOLLEYS times.
##   2. Charge: cavalry strikes first. Infantry meets the charge: units that
##      counter cavalry (spearmen) strike back in full, the rest at half strength.
##   3. Melee: everyone fights, for up to 6 rounds, until one side's morale breaks.
## Attacking ranged troops shoot from their own region (OR-4): only enemy ranged
## troops can hit them, and an attack by ranged troops alone is just the volleys.
## Fire only wounds (PRD D): it wears health down and never takes a troop's
## last soldier, so only melee destroys an army.
## Damage = attack × counter multiplier × terrain × modifiers × morale × random(0.85–1.15)
##          − defense / 2, with attack scaled by the soldiers left in the unit.
## The same seed always gives the same battle.

const MELEE_ROUNDS := 6
const RANGED_VOLLEYS := 2
const ROUT_MORALE := 30.0
const DAMAGE_SCALE := 2.5        # Turns the PRD's stat numbers into HP lost per hit.
const MIN_DAMAGE_SHARE := 0.2    # Defense can't cut a hit below this share of its raw damage.
const MORALE_PER_LOSS := 150.0   # Morale lost for losing 100% of the side's starting strength.
const MORALE_PER_UNIT_LOST := 8.0
const MORALE_OUTNUMBERED := 5.0  # Lost each exchange while below OUTNUMBERED_RATIO of the enemy.
const OUTNUMBERED_RATIO := 0.67
const RIVER_PENALTY := 0.75      # Attacker's attack across a river (PRD 3.1).
const ROUT_LOSS := 0.2           # Extra HP a routed side loses while fleeing (BT-4).
const RANGED_IN_MELEE := 0.5     # Ranged units fight at half strength once the melee starts.
const SIEGE_IN_FIELD := 0.5      # Catapults are weak against troops in the field.
const MEET_CHARGE := 0.5         # Infantry that doesn't counter cavalry strikes back at this strength.
const NOTABLE_HIGH := 1.5        # Counter multipliers at or above this are reported.
const NOTABLE_LOW := 0.6         # ...and at or below this.
const FORECAST_RUNS := 20


## One side of the battle: troops of one or more armies.
class Force:
	var faction := ""
	var attacking := false
	var units: Array[Troop] = []
	## Attacking ranged troops shooting from their own region.
	var standoff := {}  # Troop -> true
	## Walls: damage taken by this side is divided by 1 + wall_bonus (3.10).
	var wall_bonus := 0.0
	## Horse archers shoot and ride off: nobody can shoot back at them.
	var hit_and_run := false
	var morale := 100.0
	var routed := false
	var start_strength := 0.0
	var before := []  # [type_id, soldiers] for each unit at the start, for the report.

	func _init(faction_id: String, is_attacker: bool, troops: Array[Troop]) -> void:
		faction = faction_id
		attacking = is_attacker
		units = troops
		for unit in units:
			if attacking and unit.type().is_ranged():
				standoff[unit] = true
			start_strength += unit.strength()
			before.append([unit.type_id, unit.soldiers])

	func alive() -> Array[Troop]:
		var standing: Array[Troop] = []
		for unit in units:
			if not unit.is_destroyed():
				standing.append(unit)
		return standing

	## Troops in the fight itself, not shooting from another region.
	func engaged() -> Array[Troop]:
		var found: Array[Troop] = []
		for unit in alive():
			if not standoff.has(unit):
				found.append(unit)
		return found

	func strength() -> float:
		var total := 0.0
		for unit in alive():
			total += unit.strength()
		return total

	func all_berserkers() -> bool:
		var standing := engaged()
		if standing.is_empty():
			return false
		for unit in standing:
			if not unit.type().berserker:
				return false
		return true


var attacker: Force
var defender: Force
var terrain: TerrainType
var river_crossing := false
## "attacker", "defender", or "" after a ranged-only attack.
var winner := ""
## "rout", "destroyed", "held" (the defender lasted all melee rounds) or "ranged".
var ending := ""
var rounds_fought := 0
## Phase or melee round in which the battle was decided, for the report.
var rout_moment := ""
## "attacker_type>defender_type" -> {attacker, defender, multiplier, damage, attacking}.
var counter_damage := {}

var _rng := RandomNumberGenerator.new()


func _init(attacking_side: Force, defending_side: Force, battle_terrain: TerrainType, crossing_river: bool, battle_seed: int) -> void:
	attacker = attacking_side
	defender = defending_side
	terrain = battle_terrain
	river_crossing = crossing_river
	_rng.seed = battle_seed


func ranged_only() -> bool:
	return attacker.engaged().is_empty()


## Fights the battle, changing the units' HP in place.
func resolve() -> void:
	var melee_attack := not ranged_only()
	var decided := false
	for volley in RANGED_VOLLEYS:
		var replies: Array[Troop] = []
		if not attacker.hit_and_run:
			replies = _shooters(defender)
		_exchange(_shooters(attacker), replies, "ranged")
		if melee_attack and _finished("the ranged phase"):
			decided = true
			break
	if not melee_attack:
		ending = "ranged"
		return
	if not decided:
		_exchange(_cavalry(attacker) + _bracing(attacker, defender), _cavalry(defender) + _bracing(defender, attacker), "charge")
		if not _finished("the charge"):
			for round_number in range(1, MELEE_ROUNDS + 1):
				rounds_fought = round_number
				_exchange(_fighters(attacker), _fighters(defender), "melee")
				if _finished("melee round %d" % round_number):
					break
	if winner == "":
		winner = "defender"
		ending = "held"
	if ending == "rout":
		var loser := attacker if winner == "defender" else defender
		for unit in loser.engaged():
			if not unit.type().berserker:
				unit.lose_share(ROUT_LOSS)


func attacker_won() -> bool:
	return winner == "attacker"


## Share of a side's starting strength still standing.
func survival(side: Force) -> float:
	return side.strength() / side.start_strength if side.start_strength > 0 else 0.0


## Counter matchups worth mentioning: strong or weak multipliers that actually
## dealt damage, biggest first.
func notable_counters() -> Array:
	var notable := []
	for entry in counter_damage.values():
		if entry.multiplier >= NOTABLE_HIGH or entry.multiplier <= NOTABLE_LOW:
			notable.append(entry)
	notable.sort_custom(func(a, b): return a.damage > b.damage)
	return notable


## Plain-language reasons for the result, from the point of view of `viewer`.
func explain(viewer: String, faction_names: Dictionary) -> PackedStringArray:
	var reasons := PackedStringArray()
	var loser := defender if winner == "attacker" else attacker
	var loser_name: String = "Your army" if loser.faction == viewer else faction_names.get(loser.faction, loser.faction)
	match ending:
		"rout":
			reasons.append("%s broke and fled in %s when its morale fell to %d." % [
				loser_name, rout_moment, roundi(loser.morale)])
		"destroyed":
			reasons.append("%s was wiped out in %s." % [loser_name, rout_moment])
		"held":
			reasons.append("The defenders held for all %d melee rounds, so the attack failed." % MELEE_ROUNDS)
		"ranged":
			reasons.append("A ranged attack: the archers shot from their own region. Fire only wounds: it can't destroy an army or take a region.")
	reasons.append("Strength at the start: %d attacking soldiers against %d defending." % [
		_soldiers_before(attacker), _soldiers_before(defender)])
	for entry in notable_counters().slice(0, 3):
		var whose := "Attacking" if entry.attacking else "Defending"
		if (entry.attacking and attacker.faction == viewer) or (not entry.attacking and defender.faction == viewer):
			whose = "Your"
		var verdict := "a strong counter" if entry.multiplier >= NOTABLE_HIGH else "a poor matchup"
		reasons.append("%s %s against %s: ×%.2f, %s (%d HP of damage)." % [
			whose, Rules.unit(entry.attacker).display_name.to_lower(), Rules.unit(entry.defender).display_name.to_lower(),
			entry.multiplier, verdict, roundi(entry.damage)])
	if terrain.battle_text != "":
		reasons.append("Fought on %s: %s." % [terrain.display_name.to_lower(), terrain.battle_text])
	if river_crossing:
		reasons.append("The attackers crossed a river: −25% attack.")
	if defender.wall_bonus > 0.0:
		reasons.append("Walls: the defenders took %d%% less damage." % roundi(100.0 - 100.0 / (1.0 + defender.wall_bonus)))
	return reasons


## Simulates the battle FORECAST_RUNS times on copies of the units and rates
## the attacker's chances (BT-7, OR-6). `attacking` and `defending` must
## return fresh Forces of copied units. Returns {rating, wins, runs,
## attacker_survival, defender_survival, ranged}.
static func forecast(attacking: Callable, defending: Callable, battle_terrain: TerrainType,
		crossing_river: bool, battle_seed: int, runs := FORECAST_RUNS) -> Dictionary:
	var wins := 0
	var attacker_left := 0.0
	var defender_left := 0.0
	var ranged := false
	for run in runs:
		var battle := Battle.new(attacking.call(), defending.call(), battle_terrain, crossing_river, battle_seed + run)
		ranged = battle.ranged_only()
		battle.resolve()
		if battle.attacker_won():
			wins += 1
		attacker_left += battle.survival(battle.attacker)
		defender_left += battle.survival(battle.defender)
	var win_rate := float(wins) / runs
	var attacker_survival := attacker_left / runs
	var defender_survival := defender_left / runs
	var rating := "Decisive loss"
	if ranged:
		# A ranged attack can't win or lose; rate it by the damage traded.
		var dealt := 1.0 - defender_survival
		var taken := 1.0 - attacker_survival
		rating = "Win" if dealt > taken * 1.5 else ("Close" if dealt >= taken else "Loss")
	elif win_rate >= 0.9 and attacker_survival >= 0.65:
		rating = "Decisive win"
	elif win_rate >= 0.6:
		rating = "Win"
	elif win_rate > 0.4:
		rating = "Close"
	elif win_rate > 0.1:
		rating = "Loss"
	return {"rating": rating, "wins": wins, "runs": runs, "ranged": ranged,
		"attacker_survival": attacker_survival, "defender_survival": defender_survival}


func _soldiers_before(side: Force) -> int:
	var total := 0
	for entry in side.before:
		total += entry[1]
	return total


# --- Phases ------------------------------------------------------------------

## Both sides strike at the same time, so the order of units doesn't matter.
func _exchange(attacking_units: Array[Troop], defending_units: Array[Troop], phase: String) -> void:
	var strength_before := {attacker: attacker.strength(), defender: defender.strength()}
	var alive_before := {attacker: attacker.alive().size(), defender: defender.alive().size()}
	var hits := []
	for unit in attacking_units:
		hits.append(_strike(unit, attacker, defender, phase))
	for unit in defending_units:
		hits.append(_strike(unit, defender, attacker, phase))
	for hit in hits:
		if hit != null:
			if hit.ranged:
				hit.target.wound(hit.damage)
			else:
				hit.target.hit(hit.damage)
	for side: Force in [attacker, defender]:
		var other := defender if side == attacker else attacker
		var lost: float = strength_before[side] - side.strength()
		side.morale -= MORALE_PER_LOSS * lost / maxf(side.start_strength, 0.01)
		side.morale -= MORALE_PER_UNIT_LOST * (alive_before[side] - side.alive().size())
		if side.strength() < OUTNUMBERED_RATIO * other.strength():
			side.morale -= MORALE_OUTNUMBERED
		side.morale = clampf(side.morale, 0.0, 100.0)


## One troop hits its best target. Returns {target, damage, ranged} or null. Melee
## blows can't reach attackers shooting from another region, and in the
## charge, non-cavalry units (bracing spearmen) only hit cavalry.
func _strike(unit: Troop, side: Force, enemy: Force, phase: String):
	var shooting := unit.type().is_ranged() and (phase == "ranged" or side.standoff.has(unit))
	var targets := enemy.alive() if shooting else enemy.engaged()
	if phase == "charge" and not unit.type().is_cavalry():
		targets = _cavalry(enemy)
	if targets.is_empty() or unit.is_destroyed():
		return null
	var unit_type := unit.type()
	var target := _best_target(unit.type_id, targets)
	var multiplier := Rules.counters.multiplier(unit.type_id, target.type_id)

	var phase_mod := 1.0
	if unit_type.unit_class == "siege":
		phase_mod = SIEGE_IN_FIELD
	elif phase == "melee" and unit_type.is_ranged():
		phase_mod = RANGED_IN_MELEE
	if phase == "charge":
		if unit_type.is_cavalry():
			phase_mod *= unit_type.charge_bonus * unit.charge_mod
		elif multiplier < NOTABLE_HIGH:
			phase_mod *= MEET_CHARGE
	var fury := 2.0 - unit.health() if unit_type.berserker else 1.0  # Berserkers hit harder as they bleed.
	var raw := unit_type.attack * unit.strength() * multiplier * _terrain_mod(unit_type, side) * fury \
		* unit.attack_mod * (0.5 + side.morale / 200.0) * _rng.randf_range(0.85, 1.15) * phase_mod
	var damage := maxf(raw - target.type().defense / 2.0, raw * MIN_DAMAGE_SHARE) * DAMAGE_SCALE
	damage /= target.defense_mod * (1.0 + enemy.wall_bonus)

	var key := "%s>%s" % [unit.type_id, target.type_id]
	if not counter_damage.has(key):
		counter_damage[key] = {"attacker": unit.type_id, "defender": target.type_id,
			"multiplier": multiplier, "damage": 0.0, "attacking": side.attacking}
	counter_damage[key].damage += damage
	return {"target": target, "damage": damage, "ranged": shooting}


## The enemy unit this unit type does best against; ties go to the stronger one (BT-2).
func _best_target(type_id: String, targets: Array[Troop]) -> Troop:
	var best := targets[0]
	var best_multiplier := Rules.counters.multiplier(type_id, best.type_id)
	for target in targets:
		var multiplier := Rules.counters.multiplier(type_id, target.type_id)
		if multiplier > best_multiplier or (multiplier == best_multiplier and target.hp > best.hp):
			best = target
			best_multiplier = multiplier
	return best


func _terrain_mod(unit_type: UnitType, side: Force) -> float:
	var mod: float = terrain.attack_mods.get(unit_type.unit_class, 1.0)
	if unit_type.heavy:
		mod *= terrain.heavy_mod
	if side.attacking:
		mod *= terrain.attacker_mod
		if river_crossing:
			mod *= RIVER_PENALTY
	else:
		mod *= terrain.defender_mod * terrain.defending_class_mods.get(unit_type.unit_class, 1.0)
	return mod


## Checks for a destroyed or routed side. A side routs when its morale falls to
## 30, unless it's all berserkers; if both rout, the one with less morale does
## (the attacker on a tie).
func _finished(moment: String) -> bool:
	if defender.alive().is_empty() or attacker.engaged().is_empty():
		winner = "attacker" if defender.alive().is_empty() else "defender"
		ending = "destroyed"
		rout_moment = moment
		return true
	var attacker_breaks := attacker.morale <= ROUT_MORALE and not attacker.all_berserkers()
	var defender_breaks := defender.morale <= ROUT_MORALE and not defender.all_berserkers()
	if not attacker_breaks and not defender_breaks:
		return false
	var loser := attacker
	if defender_breaks and (not attacker_breaks or defender.morale < attacker.morale):
		loser = defender
	loser.routed = true
	winner = "defender" if loser == attacker else "attacker"
	ending = "rout"
	rout_moment = moment
	return true


func _shooters(side: Force) -> Array[Troop]:
	return _where(side.alive(), func(u: Troop): return u.type().is_ranged())


func _cavalry(side: Force) -> Array[Troop]:
	return _where(side.engaged(), func(u: Troop): return u.type().is_cavalry())


## Non-cavalry units that meet the enemy's charge, if the enemy has cavalry.
func _bracing(side: Force, enemy: Force) -> Array[Troop]:
	if _cavalry(enemy).is_empty():
		return []
	return _where(side.engaged(), func(u: Troop): return not u.type().is_cavalry() and u.type().unit_class != "siege")


## Everyone fights in the melee except catapults; attackers' archers keep shooting from their region.
func _fighters(side: Force) -> Array[Troop]:
	return _where(side.alive(), func(u: Troop): return u.type().unit_class != "siege")


func _where(pool: Array[Troop], predicate: Callable) -> Array[Troop]:
	var found: Array[Troop] = []
	found.assign(pool.filter(predicate))
	return found
