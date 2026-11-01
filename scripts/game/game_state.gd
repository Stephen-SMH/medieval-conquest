class_name GameState
extends RefCounted
## Everything that changes during a game: who owns each region, the regions'
## buildings and happiness, the factions' stockpiles, the unit tokens, whose
## turn it is, and the random number generator. The geography is fixed and
## lives in MapData; the economy rules are in Economy.
##
## Orders follow PRD 8.3: a unit moves into a neighbouring region or attacks
## one; ranged units shoot from where they stand; a unit that fought can still
## retreat into its own regions; the last moves can be undone.

const STACK_LIMIT := 4  # UT-3
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const GENERAL_COMMAND_BONUS := 0.10  # UT-5: per Command level, for units in the general's region.
## Factions that hold regions but never take turns.
const NON_PLAYABLE := {
	"neutral": {"name": "Independent", "color": Color("#8a8478")},
	"rebels": {"name": "Rebels", "color": Color("#4a4a4a")},
}
const GENERAL_NAMES := [
	"Aldric", "Berengar", "Cedric", "Dagny", "Eadwine", "Freya", "Godfrey", "Hilda",
	"Isolde", "Jorund", "Leofric", "Matilda", "Osric", "Rowena", "Sigrun", "Wulfric",
]

var map: MapData
var scenario_id := ""
var turn := 1
var factions := {}  # faction id -> FactionState, playable factions only
var turn_order: Array[String] = []
var current := 0  # Index into turn_order of the faction whose turn it is.
var owners := {}  # region id -> faction id
var provinces := {}  # region id -> ProvinceState
var capitals := {}  # faction id -> region id
var units: Array[Unit] = []
var rng := RandomNumberGenerator.new()
## Moves made this turn, newest last, so they can be undone (OR-7).
var undo_stack := []
## The scenario's mission (objectives, par...); empty for skirmish and hotseat.
var mission := {}
## Turns held for "hold" objectives, by objective index.
var mission_progress := {}
## {} while the game goes on; see Mission.evaluate().
var result := {}

var _next_unit_id := 1


## Builds a game from a scenario (data/scenarios/*.json or a mission): the map,
## factions, owners, capitals, buildings, units and starting resources.
static func from_scenario(scenario: Dictionary, game_seed := 1) -> GameState:
	var state := GameState.new()
	state.map = MapData.load_map(scenario.map)
	state.scenario_id = scenario.get("id", "")
	state.mission = scenario.get("mission", {}).duplicate(true)
	state.rng.seed = game_seed
	for entry in scenario.factions:
		var faction := FactionState.new()
		faction.id = entry.id
		faction.display_name = entry.name
		faction.color = Color(entry.color)
		faction.civ = entry.get("civ", "")
		faction.human = entry.get("human", false)
		faction.ai = entry.get("ai", "balanced")
		faction.resources = Economy.START_RESOURCES.duplicate()
		for resource in scenario.get("resources", {}).get(faction.id, {}):
			faction.resources[resource] = float(scenario.resources[faction.id][resource])
		faction.techs.assign(entry.get("techs", []))
		state.factions[faction.id] = faction
		state.turn_order.append(faction.id)
	state.capitals = scenario.get("capitals", {}).duplicate()
	for region in state.map.province_order:
		state.owners[region] = scenario.get("owners", {}).get(region, "neutral")
		var province := ProvinceState.new()
		for building_id in scenario.get("buildings", {}).get(region, {}):
			province.buildings[building_id] = int(scenario.buildings[region][building_id])
		state.provinces[region] = province
		province.happiness = Economy.BASE_HAPPINESS + (Economy.CAPITAL_HAPPINESS if state.is_capital(region) else 0.0)
		province.forage = Economy.land_food(state, region) * 2.0
	for entry in scenario.get("units", []):
		var unit := state.add_unit(entry.type, entry.owner, entry.region)
		if entry.has("soldiers"):
			unit.set_soldiers(int(entry.soldiers))
		unit.xp = int(entry.get("xp", 0))
		if entry.get("general") != null:
			unit.general = General.new(entry.general.name, int(entry.general.get("command", 1)), int(entry.general.get("logistics", 1)))
	state._start_turn()
	return state


# --- Factions and turns ---------------------------------------------------------

func current_faction() -> String:
	return turn_order[current]


## The human whose eyes the map is drawn for: the one whose turn it is, or the first human.
func viewer() -> String:
	if factions[current_faction()].human:
		return current_faction()
	for id in turn_order:
		if factions[id].human:
			return id
	return current_faction()


func faction_name(id: String) -> String:
	if factions.has(id):
		return factions[id].display_name
	return NON_PLAYABLE.get(id, {"name": id}).name


func faction_color(id: String) -> Color:
	if factions.has(id):
		return factions[id].color
	return NON_PLAYABLE.get(id, {"color": Color.GRAY}).color


func is_enemy(faction: String, other: String) -> bool:
	return faction != other


func is_capital(region: String) -> bool:
	return capitals.has(owners.get(region, "")) and capitals[owners[region]] == region


func season() -> String:
	return SEASONS[(turn - 1) % 4]


func year() -> int:
	return floori((turn - 1) / 4.0) + 1


func date_text() -> String:
	return "%s, Year %d (turn %d)" % [season(), year(), turn]


## Ends the current faction's turn: its economy runs (income, upkeep, healing,
## recruits, buildings, happiness), then the next living faction starts. After
## the last faction, the turn number and season advance. Returns events.
func end_faction_turn() -> Array:
	var ending := current_faction()
	var events := Economy.process_faction(self, ending)
	events.append_array(Sieges.advance(self, ending))
	undo_stack.clear()
	for unit in units.duplicate():
		if unit.is_destroyed():
			remove_unit(unit)
	Mission.end_of_turn(self, ending)
	_update_alive()
	for step in turn_order.size():
		current += 1
		if current >= turn_order.size():
			current = 0
			turn += 1
		if factions[current_faction()].alive:
			break
	_start_turn()
	update_result()
	return events


## Checks objectives and conquest; once the game is decided, `result` stays set.
func update_result() -> void:
	if not result.is_empty():
		return
	_update_alive()
	result = Mission.evaluate(self)


func is_over() -> bool:
	return not result.is_empty()


func _start_turn() -> void:
	for unit in units_of(current_faction()):
		unit.reset_turn()


func _update_alive() -> void:
	for id in factions:
		var holds_land := owners.values().has(id)
		factions[id].alive = holds_land or not units_of(id).is_empty()


func living_factions() -> Array[String]:
	var alive: Array[String] = []
	for id in turn_order:
		if factions[id].alive:
			alive.append(id)
	return alive


# --- Units ----------------------------------------------------------------------

func add_unit(type_id: String, owner: String, region: String) -> Unit:
	var unit := Unit.new(type_id, owner, region)
	unit.id = _next_unit_id
	_next_unit_id += 1
	unit.reset_turn()
	units.append(unit)
	return unit


func remove_unit(unit: Unit) -> void:
	units.erase(unit)


func unit_by_id(id: int) -> Unit:
	for unit in units:
		if unit.id == id:
			return unit
	return null


func units_in(region: String) -> Array[Unit]:
	var found: Array[Unit] = []
	for unit in units:
		if unit.province == region:
			found.append(unit)
	return found


func units_of(faction: String) -> Array[Unit]:
	var found: Array[Unit] = []
	for unit in units:
		if unit.owner == faction:
			found.append(unit)
	return found


func enemy_units_in(region: String, faction: String) -> Array[Unit]:
	var found: Array[Unit] = []
	for unit in units_in(region):
		if is_enemy(faction, unit.owner):
			found.append(unit)
	return found


## Free places in a region's stack for a faction's units (UT-3).
func space_in(region: String, faction: String) -> int:
	var own := 0
	for unit in units_in(region):
		if unit.owner == faction:
			own += 1
	return STACK_LIMIT - own


## Regions a faction can see units in: its own regions, regions its units
## stand in, and every neighbour of those (MP-5).
func visible_provinces(faction: String) -> Dictionary:
	var seen := {}
	var sources := []
	for region in map.province_order:
		if owners[region] == faction:
			sources.append(region)
	for unit in units_of(faction):
		sources.append(unit.province)
	for region in sources:
		seen[region] = true
		for neighbour in map.neighbours(region):
			seen[neighbour] = true
	return seen


# --- Moving (OR-3, OR-5, OR-7) --------------------------------------------------------

## "" if the unit can move into `region` now, else the reason why not.
func move_problem(unit: Unit, region: String) -> String:
	if is_over():
		return "the game is over"
	if unit.owner != current_faction():
		return "not your turn"
	if not map.are_neighbours(unit.province, region):
		return "not next to it"
	if unit.move_points_left < 1:
		return "no move points left"
	if not enemy_units_in(region, unit.owner).is_empty():
		return "enemy units there: attack instead"
	if unit.attacked and owners[region] != unit.owner:
		return "after fighting it can only retreat into your own regions"
	if space_in(region, unit.owner) <= 0:
		return "full: %d units at most" % STACK_LIMIT
	return ""


## Moves a unit into a neighbouring region, capturing it if it is an empty
## enemy or neutral region. Returns events; the move can be undone.
func move_unit(unit: Unit, region: String) -> Array:
	if move_problem(unit, region) != "":
		return []
	undo_stack.append({"unit": unit, "from": unit.province, "move_points": unit.move_points_left,
		"moved": unit.moved, "region": region, "owner": owners[region],
		"happiness": provinces[region].happiness})
	unit.province = region
	unit.move_points_left -= 1
	unit.moved = true
	var events := [{"type": "moved", "unit": unit, "province": region}]
	events.append_array(_capture(unit.owner, region))
	update_result()
	return events


## Moves every unit of a stack that can go (OR-2), as long as there is room.
func move_stack(stack: Array, region: String) -> Array:
	var events := []
	for unit: Unit in stack:
		events.append_array(move_unit(unit, region))
	return events


## Undoes the last move this turn, including any capture it made (OR-7).
func undo_last_move() -> bool:
	if undo_stack.is_empty() or is_over():
		return false
	var step: Dictionary = undo_stack.pop_back()
	var unit: Unit = step.unit
	unit.province = step.from
	unit.move_points_left = step.move_points
	unit.moved = step.moved
	owners[step.region] = step.owner
	provinces[step.region].happiness = step.happiness
	return true


func _capture(faction: String, region: String) -> Array:
	if owners[region] == faction:
		return []
	var previous: String = owners[region]
	owners[region] = faction
	var province: ProvinceState = provinces[region]
	province.happiness = Economy.CONQUERED_HAPPINESS
	province.construction = ""
	province.recruits.clear()
	province.siege_faction = ""
	province.siege_turns = 0
	return [{"type": "captured", "province": region, "faction": faction, "previous_owner": previous}]


# --- Attacking (OR-4, OR-6, BR-1..BR-5) ------------------------------------------------

## "" if the unit can take part in an attack on `region` now, else why not.
func attack_problem(unit: Unit, region: String) -> String:
	if is_over():
		return "the game is over"
	if unit.owner != current_faction():
		return "not your turn"
	if enemy_units_in(region, unit.owner).is_empty():
		return "no enemy units there"
	if unit.attacked:
		return "already fought this turn"
	var unit_type := unit.type()
	if unit_type.is_ranged():
		if map.distance(unit.province, region) > attack_range(unit):
			return "out of range"
		if unit.moved and not unit_type.skirmisher:
			return "moved this turn"
		return ""
	if not map.are_neighbours(unit.province, region):
		return "not next to it"
	if unit.moved and not unit_type.is_cavalry():
		return "moved this turn"
	if unit.move_points_left < 1:
		return "no move points left"
	return ""


func attack_range(unit: Unit) -> int:
	return unit.type().attack_range


## The units of `stack` that can join an attack on `region`. Attacks come from
## one region at a time, so only units in the first able unit's region join.
func attackers_for(stack: Array, region: String) -> Array[Unit]:
	var able: Array[Unit] = []
	var origin := ""
	for unit: Unit in stack:
		if attack_problem(unit, region) != "":
			continue
		if origin == "":
			origin = unit.province
		if unit.province == origin:
			able.append(unit)
	return able


## Rates an attack without changing anything (OR-6).
func forecast_attack(stack: Array, region: String, runs := Battle.FORECAST_RUNS) -> Dictionary:
	var attacking := attackers_for(stack, region)
	if attacking.is_empty():
		return {}
	var defenders := enemy_units_in(region, attacking[0].owner)
	return Battle.forecast(
		func(): return _forces(attacking, defenders, region, true)[0],
		func(): return _forces(attacking, defenders, region, true)[1],
		map.terrain(region), _crosses_river(attacking, region),
		hash([attacking[0].id, region, turn]), runs)


## Attacks `region` with the units of `stack` that can (BR-1) and applies the
## result. If the attackers lose, the survivors stay in the region they attacked
## from (BR-2). If the defenders lose, each retreats to a neighbouring friendly
## region with room or is destroyed, and the melee attackers move in and take
## the region (BR-3). Ranged-only attacks never take a region (BR-5).
## Returns {"battle": Battle, "events": [...]} or {} if nobody could attack.
func attack(stack: Array, region: String) -> Dictionary:
	var attacking := attackers_for(stack, region)
	if attacking.is_empty():
		return {}
	var origin := attacking[0].province
	var faction := attacking[0].owner
	var defenders := enemy_units_in(region, faction)
	var forces := _forces(attacking, defenders, region, false)
	var battle := Battle.new(forces[0], forces[1], map.terrain(region), _crosses_river(attacking, region), rng.randi())
	battle.resolve()
	undo_stack.clear()

	var events := [{"type": "battle", "battle": battle, "province": region, "origin": origin, "faction": faction}]
	for unit in attacking:
		unit.attacked = true
	for unit in attacking + defenders:
		if not unit.is_destroyed():
			unit.xp += 1
	if battle.attacker_won():
		for unit in attacking:
			unit.xp += 1
	else:
		for unit in defenders:
			unit.xp += 1
	events.append_array(_remove_destroyed(attacking + defenders))

	if battle.attacker_won():
		for defender in defenders:
			if not units.has(defender):
				continue
			var refuge := _retreat_region(defender, region)
			if refuge == "":
				events.append_array(_destroy(defender, "had nowhere to retreat"))
			else:
				defender.province = refuge
				events.append({"type": "retreated", "unit": defender, "province": refuge})
		var movers := attacking.filter(func(u: Unit): return units.has(u) and not u.type().is_ranged())
		for unit: Unit in movers:
			unit.province = region
			unit.moved = true
		if not movers.is_empty():
			events.append_array(_capture(faction, region))
	elif not battle.ranged_only():
		events.append({"type": "repulsed", "province": origin, "faction": faction})
	update_result()
	return {"battle": battle, "events": events}


## [attacking Force, defending Force]. With `copy`, the forces fight copies
## of the units so a forecast leaves the real ones untouched.
func _forces(attacking: Array[Unit], defenders: Array[Unit], region: String, copy: bool) -> Array:
	var attack_units: Array[Unit] = []
	for unit in attacking:
		prepare_for_battle(unit, false, region)
		attack_units.append(unit.copy() if copy else unit)
	var defend_units: Array[Unit] = []
	for unit in defenders:
		prepare_for_battle(unit, true, region)
		defend_units.append(unit.copy() if copy else unit)
	var defender_faction: String = defenders[0].owner if not defenders.is_empty() else owners[region]
	var attacking_force := Battle.Force.new(attacking[0].owner, true, attack_units, _command_mod(attacking[0].owner, attacking[0].province))
	var defending_force := Battle.Force.new(defender_faction, false, defend_units, _command_mod(defender_faction, region))
	defending_force.wall_bonus = wall_bonus(region, attacking)
	return [attacking_force, defending_force]


## Works out a unit's battle multipliers from its rank (UT-6). Civilizations
## and research add to these.
func prepare_for_battle(unit: Unit, defending: bool, region: String) -> void:
	var rank_bonus: float = Unit.RANK_BONUS[unit.rank()]
	unit.attack_mod = 1.0 + rank_bonus
	unit.defense_mod = 1.0 + rank_bonus
	unit.charge_mod = 1.0
	Bonuses.battle(self, unit, defending, region)


## +10% attack per Command level of the best general among a faction's units in a region (UT-5).
func _command_mod(faction: String, region: String) -> float:
	var best := 0
	for unit in units_in(region):
		if unit.owner == faction and unit.general != null:
			best = maxi(best, unit.general.command)
	return 1.0 + GENERAL_COMMAND_BONUS * best


## Walls make defenders take less damage; each attacking catapult cuts the
## bonus by 25 points, and a finished siege removes it (3.10).
func wall_bonus(region: String, attacking: Array[Unit]) -> float:
	return Sieges.wall_bonus(self, region, attacking)


func _crosses_river(attacking: Array[Unit], region: String) -> bool:
	for unit in attacking:
		if not unit.type().is_ranged() and map.border_type(unit.province, region) == "river":
			return true
	return false


## A neighbouring region the unit's faction owns, with room and no enemy units.
func _retreat_region(unit: Unit, from: String) -> String:
	for neighbour in map.neighbours(from):
		if owners[neighbour] == unit.owner and space_in(neighbour, unit.owner) > 0 \
				and enemy_units_in(neighbour, unit.owner).is_empty():
			return neighbour
	return ""


func _remove_destroyed(involved: Array) -> Array:
	var events := []
	for unit: Unit in involved:
		if units.has(unit) and unit.is_destroyed():
			events.append_array(_destroy(unit, "was destroyed"))
	return events


## Removes a unit. Its general is killed or captured with it (UT-5).
func _destroy(unit: Unit, how: String) -> Array:
	remove_unit(unit)
	var events := [{"type": "destroyed", "unit": unit, "province": unit.province, "how": how}]
	if unit.general != null:
		var fate := "captured" if rng.randf() < 0.5 else "killed"
		events.append({"type": "general_lost", "unit": unit, "general": unit.general, "fate": fate})
	return events


# --- Merging (UT-8) ----------------------------------------------------------------

## "" if `source` can merge into `target`, else why not.
func merge_problem(target: Unit, source: Unit) -> String:
	if target == source:
		return "the same unit"
	if target.owner != source.owner or target.province != source.province:
		return "not in the same region"
	if target.type_id != source.type_id:
		return "different unit types"
	if target.soldiers() + source.soldiers() > UnitType.SOLDIERS:
		return "more than %d soldiers" % UnitType.SOLDIERS
	if target.general != null and source.general != null:
		return "both have a general"
	return ""


## Merges `source` into `target`. The rank is the soldier-weighted average,
## rounded down; the merged unit keeps the lower move points of the two.
func merge(target: Unit, source: Unit) -> bool:
	if merge_problem(target, source) != "":
		return false
	var soldiers_t := target.soldiers()
	var soldiers_s := source.soldiers()
	var rank := floori(float(target.rank() * soldiers_t + source.rank() * soldiers_s) / (soldiers_t + soldiers_s))
	var xp: int = Unit.RANK_XP[rank]
	if target.rank() == rank and source.rank() == rank:
		xp = mini(target.xp, source.xp)
	target.hp = minf(target.hp + source.hp, target.max_hp())
	target.xp = xp
	if target.general == null:
		target.general = source.general
	target.move_points_left = mini(target.move_points_left, source.move_points_left)
	target.attacked = target.attacked or source.attacked
	target.moved = target.moved or source.moved
	remove_unit(source)
	undo_stack.clear()
	return true


func new_general() -> General:
	return General.new(GENERAL_NAMES[rng.randi() % GENERAL_NAMES.size()], rng.randi_range(1, 3), rng.randi_range(0, 3))


## Attaches a new general to a unit for gold (UT-5).
func hire_general(unit: Unit) -> bool:
	if unit.general != null or not factions[unit.owner].can_afford(Economy.GENERAL_COST):
		return false
	factions[unit.owner].pay(Economy.GENERAL_COST)
	unit.general = new_general()
	return true


# --- Highlights (OR-1) ---------------------------------------------------------------

## For the selected units, what clicking each nearby region would do:
## "move", "attack" or "blocked".
func reachable(stack: Array) -> Dictionary:
	var result := {}
	var origins := {}
	for unit: Unit in stack:
		origins[unit.province] = true
		var reach: int = maxi(1, attack_range(unit))
		var distance := map.distances_from(unit.province)
		for region in distance:
			var steps: int = distance[region]
			if steps == 0 or steps > reach:
				continue
			var status := ""
			if attack_problem(unit, region) == "":
				status = "attack"
			elif steps == 1:
				status = "move" if move_problem(unit, region) == "" else "blocked"
			else:
				continue
			if not result.has(region) or _rank_status(status) > _rank_status(result[region]):
				result[region] = status
	for origin in origins:
		result.erase(origin)
	return result


func _rank_status(status: String) -> int:
	return {"blocked": 0, "move": 1, "attack": 2}[status]
