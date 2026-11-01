class_name GameState
extends RefCounted
## Everything that changes during a game: who owns each region, the regions'
## buildings, the factions' treasuries, the units, the orders
## planned this turn, and the random number generator. The geography is fixed
## and lives in MapData; the economy rules are in Economy.
##
## Turns are simultaneous (PRD 8.3): every faction plans its orders in turn
## (Orders), then the Resolver carries them all out together.

const STACK_LIMIT := 1  # UT-3: one unit per region.
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const GENERAL_COMMAND_BONUS := 0.10  # UT-5: per Command level, for the general's unit.
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
## Index into turn_order of the faction planning its orders now.
var current := 0
var owners := {}  # region id -> faction id
var provinces := {}  # region id -> ProvinceState
var capitals := {}  # faction id -> region id
var units: Array[Unit] = []
var rng := RandomNumberGenerator.new()
## Orders planned this turn: Unit -> {"type": "move"/"attack"/"besiege", "target": region}.
var orders := {}
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
	if scenario.has("campaign") and not state.mission.is_empty():
		state.mission["campaign"] = scenario.campaign
		state.mission["mission_index"] = scenario.mission_index
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
	Economy.stock_mercenaries(state)
	for entry in scenario.get("units", []):
		if state.unit_in(entry.region) != null:
			push_error("Scenario %s puts two units in %s" % [state.scenario_id, entry.region])
			continue
		var unit := state.add_unit(entry.type, entry.owner, entry.region)
		if entry.has("soldiers"):
			unit.set_soldiers(int(entry.soldiers))
		unit.xp = int(entry.get("xp", 0))
		if entry.get("general") != null:
			unit.general = General.new(entry.general.name, int(entry.general.get("command", 1)), int(entry.general.get("logistics", 1)))
	state.update_alive()
	state.begin_turn()
	return state


# --- Factions and turns ---------------------------------------------------------

## The faction planning its orders now.
func current_faction() -> String:
	return turn_order[current]


## The human whose eyes the map is drawn for: the one planning, or the first human.
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


## Starts a turn: units are fresh, nobody has orders, the first faction plans.
func begin_turn() -> void:
	orders.clear()
	for unit in units:
		unit.reset_turn()
	current = 0
	_skip_fallen()


## Ends the current faction's planning. When every living faction has planned,
## the orders are resolved together (PRD 8.3) and the next turn begins.
## Returns the resolution events, or [] if another faction still has to plan.
func end_faction_turn() -> Array:
	if is_over():
		return []
	for step in turn_order.size():
		current += 1
		if current >= turn_order.size():
			break
		if factions[current_faction()].alive:
			return []
	current = turn_order.size() - 1
	var events := Resolver.resolve(self)
	turn += 1
	begin_turn()
	update_result()
	return events


func _skip_fallen() -> void:
	while current < turn_order.size() - 1 and not factions[current_faction()].alive:
		current += 1


## Checks objectives and conquest; once the game is decided, `result` stays set.
func update_result() -> void:
	if not result.is_empty():
		return
	update_alive()
	result = Mission.evaluate(self)


func is_over() -> bool:
	return not result.is_empty()


func update_alive() -> void:
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
	orders.erase(unit)


func unit_by_id(id: int) -> Unit:
	for unit in units:
		if unit.id == id:
			return unit
	return null


## The unit in a region, or null (one unit per region, UT-3).
func unit_in(region: String) -> Unit:
	for unit in units:
		if unit.province == region:
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


## Free places in a region for a faction's units: 1 if empty, else 0.
func space_in(region: String, _faction := "") -> int:
	return STACK_LIMIT - units_in(region).size()


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


func attack_range(unit: Unit) -> int:
	return unit.type().attack_range


# --- Battles ----------------------------------------------------------------------

## Rates an attack by a unit on the unit in `region` without changing anything (OR-6).
func forecast_attack(stack: Array, region: String, runs := Battle.FORECAST_RUNS) -> Dictionary:
	if stack.is_empty() or enemy_units_in(region, stack[0].owner).is_empty():
		return {}
	var attacker: Unit = stack[0]
	var defender: Unit = enemy_units_in(region, attacker.owner)[0]
	var attacking: Array[Unit] = [attacker]
	var defending: Array[Unit] = [defender]
	return Battle.forecast(
		func(): return forces(attacking, defending, region, true)[0],
		func(): return forces(attacking, defending, region, true)[1],
		map.terrain(region), crosses_river(attacking, region),
		hash([attacker.id, region, turn]), runs)


## [attacking Force, defending Force] for units fighting over `region`. With
## `copy`, the forces fight copies so a forecast leaves the real ones untouched.
## A `field` battle (head-on or contested move) has no walls.
func forces(attacking: Array[Unit], defenders: Array[Unit], region: String, copy: bool, field := false) -> Array:
	var attack_units: Array[Unit] = []
	for unit in attacking:
		prepare_for_battle(unit, false, region)
		attack_units.append(unit.copy() if copy else unit)
	var defend_units: Array[Unit] = []
	for unit in defenders:
		prepare_for_battle(unit, not field, region)
		defend_units.append(unit.copy() if copy else unit)
	var attacking_force := Battle.Force.new(attacking[0].owner, true, attack_units, command_mod(attacking))
	var defending_force := Battle.Force.new(defenders[0].owner, false, defend_units, command_mod(defenders))
	if not field:
		defending_force.wall_bonus = Sieges.wall_bonus(self, region, attacking)
	return [attacking_force, defending_force]


## Works out a unit's battle multipliers from its rank (UT-6), civilization and research.
func prepare_for_battle(unit: Unit, defending: bool, region: String) -> void:
	var rank_bonus: float = Unit.RANK_BONUS[unit.rank()]
	unit.attack_mod = 1.0 + rank_bonus
	unit.defense_mod = 1.0 + rank_bonus
	unit.charge_mod = 1.0
	Bonuses.battle(self, unit, defending, region)


## +10% attack per Command level of a general among these units (UT-5).
func command_mod(side: Array[Unit]) -> float:
	var best := 0
	for unit in side:
		if unit.general != null:
			best = maxi(best, unit.general.command)
	return 1.0 + GENERAL_COMMAND_BONUS * best


func crosses_river(attacking: Array[Unit], region: String) -> bool:
	for unit in attacking:
		if not unit.type().is_ranged() and map.border_type(unit.province, region) == "river":
			return true
	return false


## A free neighbouring region the unit's faction owns, or "" if there is none.
func retreat_region(unit: Unit, from: String) -> String:
	for neighbour in map.neighbours(from):
		if owners[neighbour] == unit.owner and unit_in(neighbour) == null:
			return neighbour
	return ""


## Removes a unit. Its general is killed or captured with it (UT-5).
func destroy(unit: Unit, how: String) -> Array:
	remove_unit(unit)
	var events := [{"type": "destroyed", "unit": unit, "province": unit.province, "how": how}]
	if unit.general != null:
		var fate := "captured" if rng.randf() < 0.5 else "killed"
		events.append({"type": "general_lost", "unit": unit, "general": unit.general, "fate": fate})
	return events


## Takes a region for a faction. Returns the event, or [] if nothing changed.
func capture(faction: String, region: String, from := "") -> Array:
	if owners[region] == faction:
		return []
	var previous: String = owners[region]
	owners[region] = faction
	var province: ProvinceState = provinces[region]
	province.construction = ""
	province.recruits.clear()
	province.siege_faction = ""
	province.siege_turns = 0
	return [{"type": "captured", "province": region, "faction": faction, "previous_owner": previous, "from": from}]


# --- Merging (UT-8) ----------------------------------------------------------------

## "" if `source` can join `target`, else why not.
func merge_problem(target: Unit, source: Unit) -> String:
	if target == source:
		return "the same unit"
	if target.owner != source.owner:
		return "not the same faction"
	if target.type_id != source.type_id:
		return "different unit types"
	if target.soldiers() >= UnitType.SOLDIERS:
		return "already %d soldiers" % UnitType.SOLDIERS
	if target.general != null and source.general != null:
		return "both have a general"
	return ""


## Moves soldiers from `source` into `target`, up to 20 (UT-8). The rank is the
## soldier-weighted average, rounded down. Soldiers that don't fit stay in
## `source`; if none are left, `source` is removed. Returns the soldiers moved.
func merge(target: Unit, source: Unit) -> int:
	if merge_problem(target, source) != "":
		return 0
	var moving := mini(source.soldiers(), UnitType.SOLDIERS - target.soldiers())
	var soldiers_t := target.soldiers()
	var rank := floori(float(target.rank() * soldiers_t + source.rank() * moving) / (soldiers_t + moving))
	var xp: int = Unit.RANK_XP[rank]
	if target.rank() == rank and source.rank() == rank:
		xp = mini(target.xp, source.xp)
	target.set_soldiers(soldiers_t + moving)
	target.xp = xp
	if target.general == null and moving == source.soldiers():
		target.general = source.general
	if moving >= source.soldiers():
		remove_unit(source)
	else:
		source.set_soldiers(source.soldiers() - moving)
	return moving


func new_general() -> General:
	return General.new(GENERAL_NAMES[rng.randi() % GENERAL_NAMES.size()], rng.randi_range(1, 3), rng.randi_range(0, 3))


## Attaches a new general to a unit for gold (UT-5).
func hire_general(unit: Unit) -> bool:
	if unit.general != null or not factions[unit.owner].can_afford(Economy.GENERAL_COST):
		return false
	factions[unit.owner].pay(Economy.GENERAL_COST)
	unit.general = new_general()
	return true
