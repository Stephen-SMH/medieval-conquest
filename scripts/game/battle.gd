class_name Battle
extends RefCounted
## An auto-resolved field battle (PRD 3.9), fought in three phases:
##   1. Ranged: archers, crossbowmen and catapults shoot RANGED_VOLLEYS times.
##   2. Charge: cavalry strikes first. Units that counter cavalry (spearmen)
##      brace and strike back at the chargers in the same moment.
##   3. Melee: everyone fights, for up to 6 rounds, until one side's morale breaks.
## Damage = attack × counter multiplier × terrain × general × morale × random(0.85–1.15)
##          − defense / 2, with attack scaled by the men left in the regiment.
## The same seed always gives the same battle.

const MELEE_ROUNDS := 6
const RANGED_VOLLEYS := 2
const ROUT_MORALE := 30.0
const DAMAGE_SCALE := 2.5        # Turns the PRD's stat numbers into casualties per hit.
const MIN_DAMAGE_SHARE := 0.2    # Defense can't cut a hit below this share of its raw damage.
const MORALE_PER_LOSS := 150.0   # Morale lost for losing 100% of the side's starting men.
const MORALE_PER_REGIMENT_LOST := 8.0
const MORALE_OUTNUMBERED := 5.0  # Lost each exchange while below OUTNUMBERED_RATIO of the enemy.
const OUTNUMBERED_RATIO := 0.67
const RIVER_PENALTY := 0.75      # Attacker's attack the turn it crosses a river (PRD 3.1).
const ROUT_LOSS := 0.2           # Extra men a routed side loses while fleeing (BT-4).
const DESTROYED_BELOW := 5.0     # A regiment with fewer men is destroyed.
const RANGED_IN_MELEE := 0.5     # Ranged units fight at half strength hand to hand.
const SIEGE_IN_FIELD := 0.5      # Catapults are weak against troops in the field.
const NOTABLE_HIGH := 1.5        # Counter multipliers at or above this are reported.
const NOTABLE_LOW := 0.6         # ...and at or below this.
const FORECAST_RUNS := 20


## One side of the battle.
class Force:
	var faction := ""
	var attacking := false
	var regiments: Array[Regiment] = []
	var general_mod := 1.0
	var morale := 100.0
	var routed := false
	var start_men := 0.0
	var before := []  # [type_id, men] for each regiment at the start, for the report.

	func _init(faction_id: String, is_attacker: bool, troops: Array[Regiment], command_mod: float) -> void:
		faction = faction_id
		attacking = is_attacker
		regiments = troops
		general_mod = command_mod
		for regiment in regiments:
			start_men += regiment.men
			before.append([regiment.type_id, regiment.men])

	func alive() -> Array[Regiment]:
		var standing: Array[Regiment] = []
		for regiment in regiments:
			if regiment.men >= DESTROYED_BELOW:
				standing.append(regiment)
		return standing

	func men() -> float:
		var total := 0.0
		for regiment in alive():
			total += regiment.men
		return total


var attacker: Force
var defender: Force
var terrain: TerrainType
var river_crossing := false
## "attacker" or "defender".
var winner := ""
## "rout", "destroyed" or "held" (the defender lasted all melee rounds).
var ending := ""
var rounds_fought := 0
## Melee round (or phase name) in which a side routed, for the report.
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


## Fights the battle, changing the regiments' men in place.
func resolve() -> void:
	var shot_out := false
	for volley in RANGED_VOLLEYS:
		_exchange(_shooters(attacker), _shooters(defender), "ranged")
		if _finished("the ranged phase"):
			shot_out = true
			break
	if not shot_out:
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
		for regiment in loser.alive():
			regiment.men *= 1.0 - ROUT_LOSS


func attacker_won() -> bool:
	return winner == "attacker"


## Share of a side's starting men still standing.
func survival(side: Force) -> float:
	return side.men() / side.start_men if side.start_men > 0 else 0.0


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
	reasons.append("Started with %d attacking men against %d defending." % [roundi(attacker.start_men), roundi(defender.start_men)])
	for entry in notable_counters().slice(0, 3):
		var whose := "Attacking" if entry.attacking else "Defending"
		if (entry.attacking and attacker.faction == viewer) or (not entry.attacking and defender.faction == viewer):
			whose = "Your"
		var verdict := "a strong counter" if entry.multiplier >= NOTABLE_HIGH else "a poor matchup"
		reasons.append("%s %s against %s: ×%.2f, %s (%d men killed)." % [
			whose, Rules.unit(entry.attacker).display_name.to_lower(), Rules.unit(entry.defender).display_name.to_lower(),
			entry.multiplier, verdict, roundi(entry.damage)])
	if terrain.battle_text != "":
		reasons.append("Fought on %s: %s." % [terrain.display_name.to_lower(), terrain.battle_text])
	if river_crossing:
		reasons.append("The attackers crossed a river: −25% attack.")
	if attacker.general_mod != defender.general_mod:
		reasons.append("Generals: attackers +%d%%, defenders +%d%% attack from Command." % [
			roundi((attacker.general_mod - 1.0) * 100), roundi((defender.general_mod - 1.0) * 100)])
	return reasons


## Simulates the battle FORECAST_RUNS times on copies of the regiments and
## rates the attacker's chances (BT-7). Returns {rating, wins, runs,
## attacker_survival, defender_survival}.
static func forecast(attacking: Callable, defending: Callable, battle_terrain: TerrainType,
		crossing_river: bool, battle_seed: int) -> Dictionary:
	var wins := 0
	var attacker_left := 0.0
	var defender_left := 0.0
	for run in FORECAST_RUNS:
		var battle := Battle.new(attacking.call(), defending.call(), battle_terrain, crossing_river, battle_seed + run)
		battle.resolve()
		if battle.attacker_won():
			wins += 1
		attacker_left += battle.survival(battle.attacker)
		defender_left += battle.survival(battle.defender)
	var win_rate := float(wins) / FORECAST_RUNS
	var attacker_survival := attacker_left / FORECAST_RUNS
	var rating := "Decisive loss"
	if win_rate >= 0.9 and attacker_survival >= 0.65:
		rating = "Decisive win"
	elif win_rate >= 0.6:
		rating = "Win"
	elif win_rate > 0.4:
		rating = "Close"
	elif win_rate > 0.1:
		rating = "Loss"
	return {"rating": rating, "wins": wins, "runs": FORECAST_RUNS,
		"attacker_survival": attacker_survival, "defender_survival": defender_left / FORECAST_RUNS}


# --- Phases ------------------------------------------------------------------

## Both sides strike at the same time, so the order of regiments doesn't matter.
func _exchange(attacking_units: Array[Regiment], defending_units: Array[Regiment], phase: String) -> void:
	var men_before := {attacker: attacker.men(), defender: defender.men()}
	var alive_before := {attacker: attacker.alive().size(), defender: defender.alive().size()}
	var hits := []
	for regiment in attacking_units:
		hits.append(_strike(regiment, attacker, defender, phase))
	for regiment in defending_units:
		hits.append(_strike(regiment, defender, attacker, phase))
	for hit in hits:
		if hit != null:
			hit.target.men = maxf(hit.target.men - hit.men_lost, 0.0)
	for side: Force in [attacker, defender]:
		var other := defender if side == attacker else attacker
		var lost: float = men_before[side] - side.men()
		side.morale -= MORALE_PER_LOSS * lost / side.start_men
		side.morale -= MORALE_PER_REGIMENT_LOST * (alive_before[side] - side.alive().size())
		if side.men() < OUTNUMBERED_RATIO * other.men():
			side.morale -= MORALE_OUTNUMBERED
		side.morale = clampf(side.morale, 0.0, 100.0)


## One regiment hits its best target. Returns {target, men_lost} or null.
## In the charge, non-cavalry units (bracing spearmen) only hit cavalry.
func _strike(regiment: Regiment, side: Force, enemy: Force, phase: String):
	var targets := enemy.alive()
	if phase == "charge" and regiment.type().unit_class != "cavalry":
		targets = _cavalry(enemy)
	if targets.is_empty() or regiment.men < DESTROYED_BELOW:
		return null
	var unit := regiment.type()
	var target := _best_target(unit.id, targets)
	var multiplier := Rules.counters.multiplier(unit.id, target.type_id)

	var phase_mod := 1.0
	if unit.unit_class == "siege":
		phase_mod = SIEGE_IN_FIELD
	elif phase == "melee" and unit.ranged:
		phase_mod = RANGED_IN_MELEE
	var raw := unit.attack * regiment.strength() * multiplier * _terrain_mod(unit, side) \
		* side.general_mod * (0.5 + side.morale / 200.0) * _rng.randf_range(0.85, 1.15) * phase_mod
	var damage := maxf(raw - target.type().defense / 2.0, raw * MIN_DAMAGE_SHARE) * DAMAGE_SCALE
	var men_lost := damage / (target.type().hp / Regiment.FULL_STRENGTH)

	var key := "%s>%s" % [unit.id, target.type_id]
	if not counter_damage.has(key):
		counter_damage[key] = {"attacker": unit.id, "defender": target.type_id,
			"multiplier": multiplier, "damage": 0.0, "attacking": side.attacking}
	counter_damage[key].damage += men_lost
	return {"target": target, "men_lost": men_lost}


## The enemy regiment this unit type does best against; ties go to the larger one (BT-2).
func _best_target(type_id: String, targets: Array[Regiment]) -> Regiment:
	var best := targets[0]
	var best_multiplier := Rules.counters.multiplier(type_id, best.type_id)
	for target in targets:
		var multiplier := Rules.counters.multiplier(type_id, target.type_id)
		if multiplier > best_multiplier or (multiplier == best_multiplier and target.men > best.men):
			best = target
			best_multiplier = multiplier
	return best


func _terrain_mod(unit: UnitType, side: Force) -> float:
	var mod: float = terrain.attack_mods.get(unit.unit_class, 1.0)
	if unit.heavy:
		mod *= terrain.heavy_mod
	if side.attacking:
		mod *= terrain.attacker_mod
		if river_crossing:
			mod *= RIVER_PENALTY
	else:
		mod *= terrain.defender_mod * terrain.defending_class_mods.get(unit.unit_class, 1.0)
	return mod


## Checks for a destroyed or routed side. A side routs when its morale falls to
## 30; if both do, the one with less morale routs (the attacker on a tie).
func _finished(moment: String) -> bool:
	if defender.alive().is_empty() or attacker.alive().is_empty():
		winner = "attacker" if defender.alive().is_empty() else "defender"
		ending = "destroyed"
		rout_moment = moment
		return true
	var attacker_breaks := attacker.morale <= ROUT_MORALE
	var defender_breaks := defender.morale <= ROUT_MORALE
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


func _shooters(side: Force) -> Array[Regiment]:
	return _where(side, func(r: Regiment): return r.type().ranged)


func _cavalry(side: Force) -> Array[Regiment]:
	return _where(side, func(r: Regiment): return r.type().unit_class == "cavalry")


## Non-cavalry regiments that hard-counter one of the enemy's cavalry units.
func _bracing(side: Force, enemy: Force) -> Array[Regiment]:
	var enemy_cavalry := _cavalry(enemy)
	return _where(side, func(r: Regiment):
		if r.type().unit_class == "cavalry":
			return false
		for rider in enemy_cavalry:
			if Rules.counters.multiplier(r.type_id, rider.type_id) >= NOTABLE_HIGH:
				return true
		return false)


func _fighters(side: Force) -> Array[Regiment]:
	return _where(side, func(r: Regiment): return r.type().unit_class != "siege")


func _where(side: Force, predicate: Callable) -> Array[Regiment]:
	var found: Array[Regiment] = []
	found.assign(side.alive().filter(predicate))
	return found
